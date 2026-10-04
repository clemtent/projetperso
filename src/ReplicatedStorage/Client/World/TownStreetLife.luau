--[[
	TownStreetLife (ModuleScript)
	Emplacement : ReplicatedStorage > Client > World > TownStreetLife

	🏙️ Dopamine Town (v9.8, CITY98) : les rues PLEINES DE VIE, construites
	côté CLIENT, en flux autour de l'avatar (0 pièce serveur). Le serveur
	(TownStreets / TownEntrance / TownNature / TownPlaza, via
	TownKit.LifeSpot) publie les emplacements dans DopamineTown > StreetLife
	(une Configuration par case de 64 studs, attribut "Data" : lignes
	"kind;x;y;z;yaw;seed"). Ici on construit, près de l'avatar :
	  - poubelles, bacs de tri, bancs, jardinières, pots, bornes, boîtes aux
	    lettres jaunes, distributeurs de journaux, cabines téléphoniques,
	    distributeurs de boissons, panneaux "30", distributeurs de sacs pour
	    chiens, horodateurs, fontaine à boire ;
	  - abribus vitrés (banc, affiche, poteau d'arrêt), colonnes Morris,
	    kiosque à journaux, étals de fleuriste / bouquiniste, terrasse de
	    café (tables, chaises, parasols) ;
	  - passages piétons (bandes + dalles podotactiles), balises clignotantes,
	    FEUX TRICOLORES animés (voitures + piétons, synchronisés sur l'heure
	    du serveur), plaques d'égout, avaloirs, pistes cyclables peintes,
	    oriflammes, plaques de noms de rue, poteau indicateur, lampadaires ;
	  - grands panneaux publicitaires (affiches drôles), statues en bronze
	    (personnages NPCModels), tables d'échecs, petit MARCHÉ (étals de
	    fruits et légumes sous auvents rayés), COLLINE AU MOULIN À VENT (les
	    ailes tournent), ÉOLIENNES sur les collines lointaines.
	Tout est ancré ; CanQuery / CanTouch false ; seuls les gros objets
	gênent le passage (collision locale). Aucune lumière (les verres de
	lanterne sont "NightGlow" : Neon la nuit, via TownAtmosphere), aucun son.
	Flux : construit à < 190 studs (gros objets : 320, éoliennes : toujours),
	détruit au-delà de +50 ; 6 constructions par passe au plus. Animation
	(feux, balises, moulin, éoliennes, oriflammes) à 20 Hz au plus, et
	seulement pour ce qui est construit.

	API (TownClient, via optionalModule) :
	  TownStreetLife.Start()                 à l'entrée en ville
	  TownStreetLife.Step(position: Vector3) flux (4 fois / s)
	  TownStreetLife.Stop()                  à la sortie
	  TownStreetLife.Spots(kind) -> { {CF, Seed} } (TownPeople : bancs, terrasses…)
	  TownStreetLife.Debug() -> table
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Locale = require(ReplicatedStorage.Shared.Locale)
local NPCModels = require(ReplicatedStorage.Shared.NPCModels)
local Greenery = require(ReplicatedStorage.Shared.Greenery) -- (v9.9, CITY99) arbres construits côté client
local TownRoads = require(script.Parent.TownRoads) -- (v9.9, CITY99) routes, trottoirs, allées, poteaux indicateurs
local TownDistricts = require(script.Parent.TownDistricts) -- (v9.9, CITY99) skatepark, jardins partagés, coin sport
-- (v10, CITY10) la grande ville : quartiers, autoroute, parcs, marquages
-- (plan calculé côté client depuis WorldLayout : CityPlan ; kits CityKit /
-- TownHighway / District*) ; imposteurs de loin
local okCity, CityPlan = pcall(require, script.Parent.CityPlan)
local okKit, CityKit = pcall(require, script.Parent.CityKit)
local okST, StreetTrees = pcall(require, script.Parent.StreetTrees) -- (v11, CITY11) arbres d'alignement
-- (v9.8, REALISM98) réglage "Graphismes > Détail" : distances de flux x 0,65 / 1 / 1,35
local okGQ, GraphicsQuality = pcall(require, ReplicatedStorage.Shared.GraphicsQuality)
local function detailScale(): number
	if okGQ and type(GraphicsQuality) == "table" and GraphicsQuality.DetailScale then
		local ok, v = pcall(GraphicsQuality.DetailScale)
		if ok and type(v) == "number" then
			return v
		end
	end
	return 1
end

local TownStreetLife = {}

TownStreetLife.FOLDER_NAME = "TownStreetLife"
-- (v9.9, CITY99 -> NPC99) dessus des sièges du mobilier (TownPeople y pose
-- les passants assis) : chaises de terrasse, tabourets des tables d'échecs
TownStreetLife.SEAT_TOPS = { Terrace = 1.85, Chess = 1.85, Bench = 1.85 } -- (v11, SCALE11 : échelle Roblox)
local BUILD_IN, BUILD_OUT = 190, 240
local BIG_IN, BIG_OUT = 320, 380
local IMP_IN, IMP_OUT = 640, 720 -- (v10) imposteurs (silhouettes) des gros lieux
local FAR_IN, FAR_OUT = 2400, 2600
local BUILDS_PER_STEP = 12 -- (v9.9 : 6 -> 12, les tronçons de route sont petits)
local ANIM_STEP = 1 / 20
local ANIM_RANGE = 260

local M = Enum.Material
local rgb = Color3.fromRGB
local UPRIGHT = CFrame.Angles(0, 0, math.rad(90)) -- cylindre debout (axe X -> Y)
local FLAT_X = CFrame.Angles(0, math.rad(90), 0) -- cylindre couché le long de Z

-- Palette "mobilier urbain" réaliste
local GREEN = rgb(38, 78, 62) -- vert municipal
local GRAPHITE = rgb(52, 54, 60)
local STEEL = rgb(170, 174, 182)
local CONCRETE = rgb(206, 202, 196)
local WOOD = rgb(176, 124, 84)
local WHITE = rgb(250, 250, 248)
local YELLOW = rgb(255, 204, 40)
local GLASS = rgb(190, 222, 236)
local INK = rgb(40, 36, 44)
local FLOWERS = {
	rgb(255, 120, 170),
	rgb(255, 200, 70),
	rgb(190, 140, 255),
	rgb(255, 150, 100),
	rgb(250, 250, 250),
	rgb(255, 90, 110),
	rgb(120, 170, 255),
}

-- Types d'objets "gros" (vus de plus loin) et "lointains"
local BIG = { Paint = true, Billboard = true, WindmillHill = true, MarketSquare = true, Statue = true, Kiosk = true, BikeLane = true, BusShelter = true }
local FAR = { Turbine = true }
-- Emplacements qui ne sont PAS du mobilier (ancres des passants : TownPeople)
local ANCHORS = { SitBench = true, Chat = true, Wait = true, Dest = true }

type Spot = {
	Kind: string,
	CF: CFrame,
	Seed: number,
	Pos: Vector3,
	Size: Vector3?,
	Model: Model?,
	Anim: any?,
	Data: any?, -- (v10, CITY10) paramètres du plan (CityPlan)
	Snap: boolean?, -- (v10) recaler au sol (rayon) à la construction
	Imp: Model?, -- (v10) imposteur construit
	Nudged: boolean?, -- (v11) recalé une fois (trottoir jamais pincé)
}

local state: any = nil

----------------------------------------------------------------------
-- Hasard déterministe + fabrique de pièces
----------------------------------------------------------------------

local function hash(a: number, b: number): number
	local x = math.sin(a * 12.9898 + b * 78.233) * 43758.5453
	return x - math.floor(x)
end

local partCount = 0

-- `solid` : l'avatar s'y cogne (collision locale)
local function newPart(parent: Instance, name: string, size: Vector3, cf: CFrame, color: Color3, material: Enum.Material?, shape: string?, solid: boolean?): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored = true
	p.CanCollide = solid == true
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = solid == true and size.Y > 2
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Material = material or M.SmoothPlastic
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	if shape == "Ball" then
		p.Shape = Enum.PartType.Ball
	elseif shape == "Cyl" then
		p.Shape = Enum.PartType.Cylinder
	elseif shape == "Egg" then
		local mesh = Instance.new("SpecialMesh")
		mesh.MeshType = Enum.MeshType.Sphere
		mesh.Parent = p
	end
	p.Parent = parent
	partCount += 1
	return p
end

local function wedge(parent: Instance, name: string, size: Vector3, cf: CFrame, color: Color3, material: Enum.Material?): WedgePart
	local p = Instance.new("WedgePart")
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
	p.Parent = parent
	partCount += 1
	return p
end

-- boîte par ses bornes (repère `F`)
local function box(parent: Instance, name: string, F: CFrame, x0: number, x1: number, y0: number, y1: number, z0: number, z1: number, color: Color3, material: Enum.Material?, solid: boolean?): Part
	return newPart(parent, name, Vector3.new(x1 - x0, y1 - y0, z1 - z0), F * CFrame.new((x0 + x1) / 2, (y0 + y1) / 2, (z0 + z1) / 2), color, material, nil, solid)
end

-- cylindre debout : bas à y0, haut à y1
local function column(parent: Instance, name: string, F: CFrame, x: number, z: number, y0: number, y1: number, d: number, color: Color3, material: Enum.Material?, solid: boolean?): Part
	return newPart(parent, name, Vector3.new(y1 - y0, d, d), F * CFrame.new(x, (y0 + y1) / 2, z) * UPRIGHT, color, material, "Cyl", solid)
end

local function ball(parent: Instance, name: string, F: CFrame, x: number, y: number, z: number, d: number, color: Color3, material: Enum.Material?): Part
	return newPart(parent, name, Vector3.new(d, d, d), F * CFrame.new(x, y, z), color, material, "Ball")
end

local function egg(parent: Instance, name: string, cf: CFrame, size: Vector3, color: Color3, material: Enum.Material?): Part
	return newPart(parent, name, size, cf, color, material, "Egg")
end

-- tige entre deux points (cylindre)
local function rod(parent: Instance, name: string, a: Vector3, b: Vector3, d: number, color: Color3, material: Enum.Material?): Part
	local axis = (b - a)
	local up = math.abs(axis.Unit.Y) > 0.98 and Vector3.new(1, 0, 0) or Vector3.new(0, 1, 0)
	return newPart(parent, name, Vector3.new(axis.Magnitude, d, d), CFrame.lookAt((a + b) / 2, b, up) * CFrame.Angles(0, math.pi / 2, 0), color, material, "Cyl")
end

-- Texte sur une face (SurfaceGui ; LightInfluence douce, pas d'éblouissement)
local function surfaceText(host: BasePart, face: Enum.NormalId, text: string, color: Color3, bg: Color3?, font: Enum.Font?, maxDistance: number?): TextLabel
	local gui = Instance.new("SurfaceGui")
	gui.Name = "Text"
	gui.Face = face
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 40
	gui.LightInfluence = 0.6
	gui.Brightness = 1
	gui.MaxDistance = maxDistance or 90
	gui.Parent = host
	local label = Instance.new("TextLabel")
	label.Name = "Label"
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = bg and 0 or 1
	label.BackgroundColor3 = bg or WHITE
	label.BorderSizePixel = 0
	label.TextScaled = true
	label.Font = font or Enum.Font.GothamBold
	label.TextColor3 = color
	label.Text = text
	label.Parent = gui
	return label
end

-- Verre de lanterne : mat le jour, Neon la nuit (TownAtmosphere, sous DopamineTown)
local function glow(p: BasePart): BasePart
	p.Material = M.SmoothPlastic
	p:SetAttribute("NightGlow", true)
	return p
end

----------------------------------------------------------------------
-- Petit mobilier
----------------------------------------------------------------------

-- Poubelle municipale (corps vert, anneau, couvercle, fente, socle)
local function buildBin(m: Model, F: CFrame, seed: number)
	local body = hash(seed, 1) < 0.7 and GREEN or rgb(70, 90, 130)
	column(m, "BinFoot", F, 0, 0, -0.05, 0.25, 1.15, GRAPHITE, M.Metal, true)
	column(m, "BinBody", F, 0, 0, 0.2, 2.3, 1.05, body, M.Metal, true)
	column(m, "BinBand", F, 0, 0, 1.55, 1.75, 1.12, body:Lerp(WHITE, 0.3), M.Metal)
	column(m, "BinLid", F, 0, 0, 2.25, 2.6, 1.14, GRAPHITE, M.Metal)
	box(m, "BinSlot", F, -0.3, 0.3, 2.0, 2.2, -0.62, -0.5, INK, M.SmoothPlastic)
end

-- Bacs de tri (verre / papier / emballages)
local function buildRecycle(m: Model, F: CFrame, _seed: number)
	local colors = { rgb(60, 140, 80), rgb(236, 196, 40), rgb(60, 110, 200) }
	for i, c in ipairs(colors) do
		local x = (i - 2) * 1.35
		box(m, "RecycleBody", F, x - 0.6, x + 0.6, -0.05, 2.4, -0.55, 0.55, GRAPHITE, M.Metal, true)
		box(m, "RecycleLid", F, x - 0.65, x + 0.65, 2.35, 2.6, -0.6, 0.6, c, M.SmoothPlastic)
		box(m, "RecycleTag", F, x - 0.4, x + 0.4, 1.3, 1.9, -0.6, -0.5, c, M.SmoothPlastic)
		column(m, "RecycleHole", F, x, -0.1, 2.58, 2.66, 0.5, INK, M.SmoothPlastic)
	end
end

-- Banc de rue (lattes bois, flasques en fonte) ; avant = -Z
local function buildBench(m: Model, F: CFrame, _seed: number)
	local iron = rgb(58, 54, 66)
	-- (v11, SCALE11 : échelle Roblox) assise à 1,85, profondeur 2,0, 2,8 par
	-- place (5,6), dossier jusqu'à 3,8 ; mêmes repères que TownKit.BENCH
	for _, sx in ipairs({ -1, 1 }) do
		local x = sx * 2.93
		box(m, "BenchLeg", F, x - 0.1, x + 0.1, -0.05, 1.75, -1.05, -0.85, iron, M.Metal)
		box(m, "BenchLeg", F, x - 0.1, x + 0.1, -0.05, 3.85, 0.65, 0.85, iron, M.Metal)
		box(m, "BenchArm", F, x - 0.14, x + 0.14, 2.55, 2.69, -1.2, 0.8, iron, M.Metal)
		box(m, "BenchArmPost", F, x - 0.1, x + 0.1, 1.75, 2.55, -1.05, -0.85, iron, M.Metal)
	end
	box(m, "BenchSeat", F, -2.8, 2.8, 1.67, 1.85, -1.15, -0.2, WOOD, M.Wood, true)
	box(m, "BenchSeat", F, -2.8, 2.8, 1.67, 1.85, -0.1, 0.65, WOOD, M.Wood, true)
	for i, y in ipairs({ 2.2, 2.75, 3.3 }) do
		box(m, "BenchBack", F, -2.8, 2.8, y, y + 0.42, 0.62 + i * 0.04, 0.78 + i * 0.04, WOOD, M.Wood)
	end
end

-- Jardinière longue (bac béton, arbustes, fleurs)
local function buildPlanter(m: Model, F: CFrame, seed: number)
	box(m, "PlanterBox", F, -2.6, 2.6, -0.05, 1.5, -0.8, 0.8, CONCRETE, M.Concrete, true)
	box(m, "PlanterSoil", F, -2.35, 2.35, 1.3, 1.55, -0.55, 0.55, rgb(96, 70, 52), M.Ground)
	for i = 0, 1 do
		egg(m, "Shrub", F * CFrame.new(-1.3 + i * 2.6, 2.0, 0), Vector3.new(2.3, 1.3, 1.2), rgb(84, 150, 84):Lerp(rgb(110, 176, 96), i), M.Grass)
	end
	for i = 0, 2 do
		local dz = ({ -0.12, 0.1, 0 })[(seed + i) % 3 + 1]
		egg(m, "Flowers", F * CFrame.new(-1.8 + i * 1.8, 2.55, dz), Vector3.new(1.1, 0.55, 0.8), FLOWERS[(seed + i) % #FLOWERS + 1], M.SmoothPlastic)
	end
end

-- Grand pot rond + boule taillée
local function buildPlanterSmall(m: Model, F: CFrame, seed: number)
	column(m, "PotBody", F, 0, 0, -0.05, 1.4, 1.6, rgb(190, 120, 90), M.Slate, true)
	column(m, "PotRim", F, 0, 0, 1.3, 1.55, 1.8, rgb(170, 106, 80), M.Slate)
	ball(m, "Topiary", F, 0, 2.5, 0, 2.0, rgb(84, 150, 84), M.Grass)
	ball(m, "TopiaryFlower", F, 0.55, 3.2, -0.55, 0.5, FLOWERS[seed % #FLOWERS + 1], M.SmoothPlastic)
end

-- Boîte aux lettres jaune (pied, caisson, dessus arrondi, fente, plaque)
local function buildMailbox(m: Model, F: CFrame, _seed: number)
	box(m, "MailFoot", F, -0.25, 0.25, -0.05, 1.8, -0.2, 0.3, GRAPHITE, M.Metal)
	box(m, "MailBody", F, -0.55, 0.55, 1.75, 3.2, -0.45, 0.45, YELLOW, M.Metal, true)
	newPart(m, "MailTop", Vector3.new(1.1, 0.9, 0.9), F * CFrame.new(0, 3.2, 0), YELLOW, M.Metal, "Cyl")
	box(m, "MailSlot", F, -0.3, 0.3, 2.9, 3.0, -0.5, -0.43, INK, M.SmoothPlastic)
	box(m, "MailPlate", F, -0.35, 0.35, 2.05, 2.55, -0.5, -0.43, rgb(40, 70, 150), M.SmoothPlastic)
end

-- Distributeur de journaux (caisse bleue, vitre avec le journal du jour)
local function buildNewsBox(m: Model, F: CFrame, seed: number)
	local c = hash(seed, 3) < 0.5 and rgb(60, 110, 200) or rgb(200, 60, 70)
	box(m, "NewsLegs", F, -0.45, 0.45, -0.05, 0.9, -0.3, 0.3, GRAPHITE, M.Metal)
	box(m, "NewsBody", F, -0.6, 0.6, 0.85, 2.5, -0.5, 0.5, c, M.Metal, true)
	box(m, "NewsWindow", F, -0.45, 0.45, 1.5, 2.3, -0.54, -0.46, GLASS, M.Glass).Transparency = 0.3
	box(m, "NewsPaper", F, -0.35, 0.35, 1.55, 2.2, -0.47, -0.43, rgb(236, 232, 222), M.SmoothPlastic)
	box(m, "NewsTop", F, -0.65, 0.65, 2.45, 2.62, -0.55, 0.55, c:Lerp(INK, 0.3), M.Metal)
end

-- 3 potelets (bande réfléchissante)
local function buildBollards(m: Model, F: CFrame, _seed: number)
	for i = -1, 1 do
		column(m, "Bollard", F, i * 1.3, 0, -0.05, 2.0, 0.42, GRAPHITE, M.Metal, true)
		column(m, "BollardBand", F, i * 1.3, 0, 1.55, 1.75, 0.46, WHITE, M.SmoothPlastic)
		ball(m, "BollardCap", F, i * 1.3, 2.0, 0, 0.42, GRAPHITE, M.Metal)
	end
end

-- Cabine téléphonique (v11, CITY11, refaite "20x") : vraie CABINE à
-- l'échelle Roblox (porte 2,9 x 8,3 : on y entre), 4 montants laqués,
-- vitrages à traverses, soubassements pleins, toit débordant avec CAISSON
-- LUMINEUX "TÉLÉPHONE" sur les 4 faces (verre "NightGlow" : allumé la
-- nuit), plafonnier, sol en caoutchouc ; au fond : publiphone (boîtier
-- inox, écran, clavier, fente à carte, combiné sur son crochet et cordon
-- spiralé), tablette et ANNUAIRE sur sa chaîne ; affiche sur le côté ;
-- PORTE vitrée à charnière (poignée-barre) qui S'OUVRE quand l'avatar
-- approche et se referme après. Avant (porte) = -Z local ; centrée 0,4
-- vers l'arrière du trottoir (côté pelouse).
local BOOTH_W, BOOTH_H = 3.6, 9.3
local function buildPhoneBooth(m: Model, F0: CFrame, seed: number)
	local F = F0 * CFrame.new(0, 0, 0.4)
	local hw = BOOTH_W / 2
	local lacquer = ({ rgb(196, 36, 44), rgb(34, 66, 120), rgb(36, 92, 74) })[seed % 3 + 1]
	local dark = lacquer:Lerp(INK, 0.45)
	local steel = rgb(196, 200, 206)
	-- socle + sol caoutchouc
	box(m, "BoothPlinth", F, -hw - 0.15, hw + 0.15, -0.05, 0.22, -hw - 0.15, hw + 0.15, rgb(150, 148, 144), M.Concrete, true)
	box(m, "BoothFloor", F, -hw + 0.2, hw - 0.2, 0.2, 0.27, -hw + 0.2, hw - 0.2, rgb(48, 50, 56), M.Rubber)
	-- montants d'angle
	for _, x in ipairs({ -hw + 0.13, hw - 0.13 }) do
		for _, z in ipairs({ -hw + 0.13, hw - 0.13 }) do
			box(m, "BoothPost", F, x - 0.13, x + 0.13, 0.22, BOOTH_H - 0.8, z - 0.13, z + 0.13, lacquer, M.SmoothPlastic, true)
		end
	end
	-- trois côtés : soubassement plein, vitrage, traverses
	local sides = {
		{ "Back", CFrame.identity },
		{ "Left", CFrame.Angles(0, math.pi / 2, 0) },
		{ "Right", CFrame.Angles(0, -math.pi / 2, 0) },
	}
	for i, sd in ipairs(sides) do
		-- repère du côté : face extérieure vers +Z local (le fond est à +Z)
		local S = F * (sd[2] :: CFrame)
		local z0, z1 = hw - 0.2, hw - 0.08
		box(m, "BoothPanel", S, -hw + 0.26, hw - 0.26, 0.22, 1.5, z0 - 0.02, z1 + 0.02, dark, M.SmoothPlastic, true)
		local g = box(m, "BoothGlass", S, -hw + 0.26, hw - 0.26, 1.5, BOOTH_H - 0.8, z0, z1, GLASS, M.Glass, true)
		g.Transparency = 0.6
		g.Reflectance = 0.15
		for _, y in ipairs({ 1.5, 3.4, 6.6 }) do
			box(m, "BoothRail", S, -hw + 0.26, hw - 0.26, y - 0.07, y + 0.07, z0 - 0.04, z1 + 0.04, lacquer, M.SmoothPlastic)
		end
		if i == 2 then
			-- affiche dans le soubassement gauche (côté rue)
			local ad = box(m, "BoothAd", S, -hw + 0.5, hw - 0.5, 0.35, 1.38, z1 + 0.025, z1 + 0.04, WHITE, M.SmoothPlastic)
			surfaceText(ad, Enum.NormalId.Back, "📱 " .. Locale.T("Call a friend!"), lacquer, WHITE, Enum.Font.FredokaOne, 40)
		end
	end
	-- toit : chapeau débordant + caisson lumineux "TÉLÉPHONE"
	box(m, "BoothHeader", F, -hw - 0.02, hw + 0.02, BOOTH_H - 0.8, BOOTH_H - 0.05, -hw - 0.02, hw + 0.02, lacquer, M.SmoothPlastic)
	local caption = "📞 " .. string.upper(Locale.T("Telephone"))
	for k = 0, 3 do
		local R = F * CFrame.Angles(0, k * math.pi / 2, 0)
		local sign = glow(box(m, "BoothSign", R, -hw + 0.3, hw - 0.3, BOOTH_H - 0.68, BOOTH_H - 0.17, -hw - 0.09, -hw - 0.03, rgb(250, 248, 236), M.SmoothPlastic))
		surfaceText(sign, Enum.NormalId.Front, caption, dark, rgb(250, 248, 236), Enum.Font.GothamBlack, 80)
	end
	box(m, "BoothRoof", F, -hw - 0.3, hw + 0.3, BOOTH_H - 0.05, BOOTH_H + 0.25, -hw - 0.3, hw + 0.3, dark, M.Metal)
	box(m, "BoothRoofTop", F, -hw + 0.1, hw - 0.1, BOOTH_H + 0.25, BOOTH_H + 0.45, -hw + 0.1, hw - 0.1, lacquer, M.SmoothPlastic)
	glow(box(m, "BoothLamp", F, -0.6, 0.6, BOOTH_H - 0.9, BOOTH_H - 0.84, -0.6, 0.6, rgb(255, 240, 210), M.SmoothPlastic))
	-- publiphone au fond (face -Z vers l'intérieur)
	local zb = hw - 0.2
	box(m, "PhoneBack", F, -0.75, 0.75, 3.3, 6.4, zb - 0.08, zb - 0.02, steel, M.Metal)
	box(m, "PhoneBody", F, -0.62, 0.62, 3.6, 6.1, zb - 0.5, zb - 0.08, rgb(150, 156, 166), M.Metal)
	local screen = glow(box(m, "PhoneScreen", F, -0.42, 0.42, 5.35, 5.85, zb - 0.53, zb - 0.5, rgb(170, 220, 190), M.SmoothPlastic))
	surfaceText(screen, Enum.NormalId.Front, Locale.T("INSERT CARD"), rgb(30, 70, 50), rgb(170, 220, 190), Enum.Font.Code, 25)
	local pad = box(m, "PhoneKeypad", F, -0.36, 0.36, 4.2, 5.15, zb - 0.53, zb - 0.5, rgb(64, 68, 78), M.SmoothPlastic)
	do
		local gui = Instance.new("SurfaceGui")
		gui.Face = Enum.NormalId.Front
		gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
		gui.PixelsPerStud = 60
		gui.MaxDistance = 25
		gui.LightInfluence = 0.7
		gui.Parent = pad
		local keys = { "1", "2", "3", "4", "5", "6", "7", "8", "9", "*", "0", "#" }
		for i, key in ipairs(keys) do
			local col, row = (i - 1) % 3, math.floor((i - 1) / 3)
			local b = Instance.new("TextLabel")
			b.BackgroundColor3 = rgb(222, 226, 232)
			b.BorderSizePixel = 0
			b.Position = UDim2.fromScale(0.06 + col * 0.31, 0.04 + row * 0.24)
			b.Size = UDim2.fromScale(0.26, 0.2)
			b.TextScaled = true
			b.Font = Enum.Font.GothamBold
			b.TextColor3 = rgb(40, 44, 52)
			b.Text = key
			b.Parent = gui
			local c = Instance.new("UICorner")
			c.CornerRadius = UDim.new(0.3, 0)
			c.Parent = b
		end
	end
	box(m, "PhoneSlot", F, -0.3, 0.3, 3.85, 3.95, zb - 0.56, zb - 0.5, INK, M.SmoothPlastic)
	-- combiné sur son crochet (côté gauche) + cordon spiralé
	box(m, "PhoneHook", F, -0.92, -0.62, 5.4, 5.55, zb - 0.45, zb - 0.2, steel, M.Metal)
	box(m, "Handset", F, -1.02, -0.74, 4.3, 5.75, zb - 0.62, zb - 0.32, INK, M.SmoothPlastic)
	for _, y in ipairs({ 4.25, 5.8 }) do
		ball(m, "HandsetCup", F, -0.88, y, zb - 0.47, 0.42, INK, M.SmoothPlastic)
	end
	for k = 0, 3 do
		local y = 4.0 - k * 0.28
		newPart(m, "PhoneCord", Vector3.new(0.12, 0.2, 0.2), F * CFrame.new(-0.84 + k * 0.05, y, zb - 0.4) * UPRIGHT, INK, M.SmoothPlastic, "Cyl")
	end
	-- tablette + annuaire (sur sa chaîne)
	box(m, "PhoneShelf", F, -0.95, 0.95, 3.0, 3.12, zb - 1.0, zb - 0.02, steel, M.Metal)
	local book = box(m, "Directory", F, -0.2, 0.75, 3.12, 3.42, zb - 0.95, zb - 0.3, rgb(250, 214, 60), M.SmoothPlastic)
	surfaceText(book, Enum.NormalId.Top, Locale.T("DIRECTORY"), rgb(60, 50, 30), rgb(250, 214, 60), Enum.Font.GothamBlack, 25)
	box(m, "DirectoryChain", F, 0.6, 0.66, 3.12, 3.7, zb - 0.12, zb - 0.06, steel, M.Metal)
	-- PORTE à charnière (montant gauche), poignée-barre ; s'ouvre vers l'extérieur
	local hinge = F * CFrame.new(-hw + 0.26, 0, -hw + 0.14)
	local door = {}
	local function dpart(p: BasePart)
		table.insert(door, { p, hinge:ToObjectSpace(p.CFrame) })
	end
	local dz0, dz1 = -0.06, 0.06
	local dw = BOOTH_W - 0.52
	dpart(box(m, "DoorFrame", hinge, 0, 0.14, 0.32, BOOTH_H - 0.85, dz0, dz1, lacquer, M.SmoothPlastic))
	dpart(box(m, "DoorFrame", hinge, dw - 0.14, dw, 0.32, BOOTH_H - 0.85, dz0, dz1, lacquer, M.SmoothPlastic))
	for _, y in ipairs({ 0.32, 3.4, BOOTH_H - 0.99 }) do
		dpart(box(m, "DoorRail", hinge, 0.14, dw - 0.14, y, y + 0.14, dz0, dz1, lacquer, M.SmoothPlastic))
	end
	local dg = box(m, "DoorGlass", hinge, 0.14, dw - 0.14, 0.46, BOOTH_H - 0.99, -0.03, 0.03, GLASS, M.Glass)
	dg.Transparency = 0.6
	dpart(dg)
	dpart(box(m, "DoorPull", hinge, dw - 0.45, dw - 0.33, 3.0, 5.4, -0.22, -0.1, steel, M.Metal))
	dpart(box(m, "DoorPullFoot", hinge, dw - 0.45, dw - 0.33, 4.15, 4.25, -0.13, -0.06, steel, M.Metal))
	if okKit and type(CityKit) == "table" then
		local angle = 0
		local parts, frames = {}, {}
		for i, d in ipairs(door) do
			parts[i] = d[1]
		end
		local front = (F * CFrame.new(0, 0, -hw - 1.5)).Position
		CityKit.Actor(m, F.Position, function(_t: number, dt: number)
			local character = Players.LocalPlayer.Character
			local root = character and character:FindFirstChild("HumanoidRootPart")
			local want = 0
			if root and root:IsA("BasePart") then
				local p = root.Position
				local dFront = Vector3.new(p.X - front.X, 0, p.Z - front.Z).Magnitude
				local dIn = Vector3.new(p.X - F.Position.X, 0, p.Z - F.Position.Z).Magnitude
				if dFront < 4.5 or dIn < hw then
					want = math.rad(95)
				end
			end
			local new = angle + math.clamp(want - angle, -dt * 3.2, dt * 3.2)
			if math.abs(new - angle) < 1e-4 then
				return
			end
			angle = new
			local rot = hinge * CFrame.Angles(0, angle, 0)
			for i, d in ipairs(door) do
				frames[i] = rot * d[2]
			end
			workspace:BulkMoveTo(parts, frames, Enum.BulkMoveMode.FireCFrameChanged)
		end, seed)
	end
end

-- Distributeur de boissons (vitrine à canettes)
local function buildVending(m: Model, F: CFrame, seed: number)
	local brand = ({ rgb(210, 40, 60), rgb(40, 110, 210), rgb(236, 72, 140) })[seed % 3 + 1]
	-- caisson (creux derrière la vitrine : on voit les canettes)
	box(m, "VendBody", F, -1.1, 1.1, -0.05, 5.6, -0.3, 0.8, brand, M.SmoothPlastic, true)
	box(m, "VendFrame", F, -1.1, -0.95, -0.05, 5.6, -0.8, -0.3, brand, M.SmoothPlastic, true)
	box(m, "VendFrame", F, 0.35, 1.1, -0.05, 5.6, -0.8, -0.3, brand, M.SmoothPlastic, true)
	box(m, "VendFrame", F, -0.95, 0.35, -0.05, 1.6, -0.8, -0.3, brand, M.SmoothPlastic, true)
	box(m, "VendFrame", F, -0.95, 0.35, 5.2, 5.6, -0.8, -0.3, brand, M.SmoothPlastic, true)
	box(m, "VendTop", F, -1.15, 1.15, 5.55, 5.9, -0.85, 0.85, brand:Lerp(INK, 0.35), M.SmoothPlastic)
	local glass = box(m, "VendGlass", F, -0.95, 0.35, 1.6, 5.2, -0.86, -0.78, GLASS, M.Glass)
	glass.Transparency = 0.5
	local cans = { rgb(220, 50, 60), rgb(60, 160, 230), rgb(255, 200, 60), rgb(120, 200, 90) }
	for row = 0, 3 do
		local y = 1.9 + row * 0.85
		box(m, "Cans", F, -0.85, 0.25, y, y + 0.55, -0.7, -0.4, cans[(row + seed) % #cans + 1], M.Metal)
		box(m, "VendShelf", F, -0.9, 0.3, y - 0.08, y + 0.02, -0.76, -0.32, STEEL, M.Metal)
	end
	box(m, "VendPanel", F, 0.5, 0.95, 2.6, 4.2, -0.86, -0.78, INK, M.SmoothPlastic)
	box(m, "VendButtons", F, 0.58, 0.87, 3.0, 3.9, -0.9, -0.84, STEEL, M.Metal)
	box(m, "VendTray", F, -0.7, 0.2, 0.6, 1.1, -0.86, -0.78, INK, M.SmoothPlastic)
	local logo = box(m, "VendLogo", F, -0.95, 0.95, 5.25, 5.55, -0.87, -0.79, WHITE, M.SmoothPlastic)
	surfaceText(logo, Enum.NormalId.Front, "🧠 Dopa Cola", brand, WHITE, Enum.Font.FredokaOne, 50)
end

-- Panneau "30" (zone 30)
local function buildSpeedSign(m: Model, F: CFrame, _seed: number)
	column(m, "SignPole", F, 0, 0.1, -0.05, 6.6, 0.22, STEEL, M.Metal)
	newPart(m, "SignPlate", Vector3.new(0.1, 1.9, 1.9), F * CFrame.new(0, 6.2, -0.02) * FLAT_X, rgb(210, 40, 50), M.Metal, "Cyl")
	newPart(m, "SignInner", Vector3.new(0.16, 1.45, 1.45), F * CFrame.new(0, 6.2, -0.02) * FLAT_X, WHITE, M.SmoothPlastic, "Cyl")
	local face = box(m, "SignFace", F, -0.5, 0.5, 5.8, 6.6, -0.15, -0.13, WHITE, M.SmoothPlastic)
	face.Transparency = 1
	surfaceText(face, Enum.NormalId.Front, "30", INK, nil, Enum.Font.GothamBlack, 60)
end

-- Distributeur de sacs pour chiens + petite poubelle
local function buildDogStation(m: Model, F: CFrame, _seed: number)
	column(m, "DogPole", F, 0, 0, -0.05, 4.2, 0.24, GREEN, M.Metal)
	box(m, "DogBox", F, -0.45, 0.45, 3.0, 4.0, -0.35, 0.05, GREEN, M.Metal)
	local icon = box(m, "DogIcon", F, -0.3, 0.3, 3.3, 3.8, -0.39, -0.33, WHITE, M.SmoothPlastic)
	surfaceText(icon, Enum.NormalId.Front, "🐕", GREEN, WHITE, nil, 40)
	box(m, "DogBin", F, -0.4, 0.4, 1.0, 2.0, -0.35, 0.3, GREEN, M.Metal)
end

-- Horodateur (borne de paiement)
local function buildParkMeter(m: Model, F: CFrame, _seed: number)
	box(m, "MeterFoot", F, -0.3, 0.3, -0.05, 1.2, -0.25, 0.25, GRAPHITE, M.Metal)
	box(m, "MeterBody", F, -0.45, 0.45, 1.15, 4.2, -0.35, 0.35, rgb(40, 90, 160), M.Metal, true)
	box(m, "MeterScreen", F, -0.3, 0.3, 3.3, 3.8, -0.39, -0.33, rgb(150, 210, 190), M.Glass)
	box(m, "MeterKeys", F, -0.3, 0.3, 2.5, 3.1, -0.39, -0.33, STEEL, M.Metal)
	local sign = box(m, "MeterSign", F, -0.35, 0.35, 4.15, 4.95, -0.1, 0.1, rgb(40, 90, 160), M.SmoothPlastic)
	surfaceText(sign, Enum.NormalId.Front, "P", WHITE, rgb(40, 90, 160), Enum.Font.GothamBlack, 60)
end

-- Fontaine à boire (colonne + vasque + bec)
local function buildDrinkFountain(m: Model, F: CFrame, _seed: number)
	column(m, "DrinkBase", F, 0, 0, -0.05, 0.3, 1.4, CONCRETE, M.Concrete, true)
	column(m, "DrinkColumn", F, 0, 0, 0.25, 3.2, 0.9, GREEN, M.Metal, true)
	column(m, "DrinkBowl", F, 0, -0.5, 2.9, 3.3, 1.2, GREEN, M.Metal)
	column(m, "DrinkWater", F, 0, -0.5, 3.1, 3.34, 0.95, rgb(120, 190, 240), M.Glass)
	ball(m, "DrinkTop", F, 0, 3.35, 0.1, 0.9, GREEN, M.Metal)
	rod(m, "DrinkSpout", (F * CFrame.new(0, 3.5, -0.3)).Position, (F * CFrame.new(0, 3.55, -0.6)).Position, 0.14, STEEL, M.Metal)
end

----------------------------------------------------------------------
-- Rue : peinture au sol, balises, feux, plaques
----------------------------------------------------------------------

-- Passage piéton : `F` au milieu, sur la chaussée ; Z local = à travers la
-- route (largeur `seed` / 10), X = sens des voitures. Bandes posées 0,06
-- au-dessus de l'asphalte (0,04 sous les lignes existantes).
local function buildZebra(m: Model, F: CFrame, seed: number)
	local width = seed / 10
	local span = width - 3.2
	local len = width >= 12 and 9 or 5
	local n = math.max(3, math.floor(span / 2 + 0.5))
	for i = 0, n - 1 do
		local z = -span / 2 + 0.55 + i * (span - 1.1) / math.max(1, n - 1)
		newPart(m, "ZebraStripe", Vector3.new(len, 0.4, 1.1), F * CFrame.new(0, 0.15 - 0.2, z), WHITE, M.SmoothPlastic) -- (v9.9 : dessus à +0,15)
	end
	-- dalles podotactiles sur les trottoirs (derrière les bordures)
	for _, sz in ipairs({ -1, 1 }) do
		local z0 = width / 2 + 0.9
		newPart(m, "Tactile", Vector3.new(len - 1, 0.3, 0.8), F * CFrame.new(0, 0.5 + 0.12 - 0.15, sz * (z0 + 0.4)), rgb(236, 206, 90), M.DiamondPlate) -- (v9.9 : +0,12 au-dessus du trottoir)
	end
end

-- Balise clignotante (poteau zébré + globe orange) ; animée
local function buildBeacon(m: Model, F: CFrame, _seed: number): any
	column(m, "BeaconPole", F, 0, 0, -0.05, 6.4, 0.3, INK, M.Metal)
	for i = 0, 3 do
		column(m, "BeaconStripe", F, 0, 0, 1 + i * 1.3, 1.6 + i * 1.3, 0.34, WHITE, M.SmoothPlastic)
	end
	local globe = ball(m, "BeaconGlobe", F, 0, 6.9, 0, 1.1, rgb(255, 170, 40), M.SmoothPlastic)
	return { Kind = "Beacon", Globe = globe }
end

-- Feu tricolore (voitures) + feu piétons + bouton ; `F` au pied, avant = -Z
-- (face aux voitures) ; `seed` = groupe (1/2, 3/4 : même phase)
local function buildTrafficLight(m: Model, F: CFrame, seed: number): any
	column(m, "LightPole", F, 0, 0, -0.05, 8.6, 0.36, GRAPHITE, M.Metal, true)
	box(m, "LightHousing", F, -0.5, 0.5, 6.1, 8.9, -0.55, 0.05, INK, M.Metal)
	box(m, "LightBackplate", F, -0.8, 0.8, 5.9, 9.1, 0.05, 0.15, INK, M.Metal)
	local lamps = {}
	for i, c in ipairs({ rgb(230, 40, 40), rgb(255, 170, 30), rgb(40, 220, 90) }) do
		local y = 8.4 - (i - 1) * 0.9
		local lamp = newPart(m, "Lamp", Vector3.new(0.12, 0.62, 0.62), F * CFrame.new(0, y, -0.58) * FLAT_X, c, M.SmoothPlastic, "Cyl")
		box(m, "Visor", F, -0.38, 0.38, y + 0.3, y + 0.38, -0.95, -0.55, INK, M.Metal)
		lamps[i] = { Part = lamp, On = c, Off = c:Lerp(INK, 0.78) }
		lamp.Color = lamps[i].Off
	end
	-- feu piétons (tourné vers le passage : côté +X local)
	box(m, "PedHousing", F, 0.18, 0.62, 3.6, 5.2, -0.3, 0.3, INK, M.Metal)
	local ped = {}
	for i, c in ipairs({ rgb(230, 40, 40), rgb(40, 220, 90) }) do
		local y = 4.85 - (i - 1) * 0.72
		local p = box(m, "PedLamp", F, 0.58, 0.68, y - 0.28, y + 0.28, -0.24, 0.24, c, M.SmoothPlastic)
		ped[i] = { Part = p, On = c, Off = c:Lerp(INK, 0.78) }
		p.Color = ped[i].Off
	end
	box(m, "PushButton", F, -0.22, 0.22, 3.0, 3.5, -0.33, -0.18, YELLOW, M.SmoothPlastic)
	return { Kind = "TrafficLight", Lamps = lamps, Ped = ped, Group = seed <= 2 and 0 or 7, State = -1 }
end

local function buildManhole(m: Model, F: CFrame, _seed: number)
	-- (dessus à +0,09 : au-dessus des pointillés (+0,05), sous les lignes de rive (+0,1))
	-- (v9.9 : dessus à +0,16, au-dessus de la peinture relevée)
	newPart(m, "Manhole", Vector3.new(0.36, 2.1, 2.1), F * CFrame.new(0, 0.16 - 0.18, 0) * UPRIGHT, rgb(70, 68, 72), M.DiamondPlate, "Cyl")
end

local function buildDrain(m: Model, F: CFrame, _seed: number)
	box(m, "Drain", F, -0.8, 0.8, -0.2, 0.07, -0.25, 0.25, rgb(58, 56, 62), M.DiamondPlate) -- (v9.9 : sur le caniveau, dessus +0,07)
end

-- Piste cyclable : bande verte (longueur `seed`) + pictogrammes vélo
local function buildBikeLane(m: Model, F: CFrame, seed: number)
	local len = seed
	newPart(m, "BikeLane", Vector3.new(1.9, 0.36, len), F * CFrame.new(0, 0.1 - 0.18, 0), rgb(76, 150, 100), M.SmoothPlastic) -- (v9.9 : dessus à +0,10)
	local n = math.max(1, math.floor(len / 28))
	for i = 0, n - 1 do
		local z = -len / 2 + (i + 0.5) * len / n
		for _, dz in ipairs({ -0.55, 0.55 }) do
			newPart(m, "BikeWheel", Vector3.new(0.2, 0.8, 0.8), F * CFrame.new(0, 0.055, z + dz) * UPRIGHT, WHITE, M.SmoothPlastic, "Cyl")
		end
		newPart(m, "BikeFrame", Vector3.new(0.14, 0.2, 1.1), F * CFrame.new(0, 0.055, z), WHITE, M.SmoothPlastic)
		newPart(m, "BikeBar", Vector3.new(0.5, 0.2, 0.12), F * CFrame.new(0, 0.055, z - 0.45), WHITE, M.SmoothPlastic)
	end
end

-- Oriflamme sur un lampadaire (2 potences + drapeau vertical)
local BANNER_COLORS = { rgb(236, 72, 140), rgb(126, 196, 255), rgb(186, 150, 246), rgb(255, 196, 90) }
local function buildBanner(m: Model, F: CFrame, seed: number): any
	local c = BANNER_COLORS[seed % #BANNER_COLORS + 1]
	for _, y in ipairs({ 7.1, 9.7 }) do
		box(m, "BannerArm", F, -0.08, 0.08, y - 0.06, y + 0.06, -1.5, -0.22, rgb(56, 52, 70), M.Metal)
	end
	local flag = box(m, "BannerFlag", F, -0.05, 0.05, 7.0, 9.8, -1.45, -0.35, c, M.Fabric)
	local mark = box(m, "BannerMark", F, -0.09, 0.09, 8.0, 8.8, -1.2, -0.6, WHITE, M.SmoothPlastic)
	surfaceText(mark, Enum.NormalId.Right, "🧠", c, WHITE, nil, 60)
	return { Kind = "Banner", Parts = { flag, mark }, Base = { flag.CFrame, mark.CFrame }, Pivot = F * CFrame.new(0, 9.7, -0.3), Phase = seed }
end

-- Plaques de rue (2 lames bleues perpendiculaires) ; `seed` = n° de rue
local STREET_NAMES = { "Dopamine Avenue", "Neuron Street", "Serotonin Street" }
local function buildStreetName(m: Model, F: CFrame, seed: number)
	column(m, "NamePole", F, 0, 0, -0.05, 9.4, 0.24, GRAPHITE, M.Metal)
	ball(m, "NameCap", F, 0, 9.45, 0, 0.32, GRAPHITE, M.Metal)
	local names = { STREET_NAMES[seed] or STREET_NAMES[1], "Brain Boulevard" }
	for i, name in ipairs(names) do
		local y = 8.9 - (i - 1) * 0.85
		local rot = i == 1 and CFrame.identity or CFrame.Angles(0, math.pi / 2, 0)
		local blade = newPart(m, "NameBlade", Vector3.new(3.6, 0.7, 0.1), F * rot * CFrame.new(0, y, 0), rgb(30, 70, 150), M.Metal)
		surfaceText(blade, Enum.NormalId.Front, Locale.T(name), WHITE, rgb(30, 70, 150), Enum.Font.GothamBold, 70)
		surfaceText(blade, Enum.NormalId.Back, Locale.T(name), WHITE, rgb(30, 70, 150), Enum.Font.GothamBold, 70)
	end
end

-- Poteau indicateur (3 flèches en bois)
local function buildSignpost(m: Model, F: CFrame, _seed: number)
	column(m, "PostPole", F, 0, 0, -0.05, 9, 0.5, rgb(120, 86, 60), M.Wood, true)
	local arrows = {
		{ "🏰 Dopamine Town", -1, 7.8 },
		{ "🛒 MégaDopa", 1, 6.8 },
		{ "🎡 Fun fair", -1, 5.8 },
	}
	for _, a in ipairs(arrows) do
		local dir = a[2] :: number
		local y = a[3] :: number
		local board = box(m, "PostBoard", F, dir < 0 and -4.2 or 0.3, dir < 0 and -0.3 or 4.2, y - 0.4, y + 0.4, -0.12, 0.12, rgb(236, 220, 190), M.Wood)
		wedge(m, "PostTip", Vector3.new(0.24, 0.8, 0.6), F * CFrame.new(dir * 4.5, y, 0) * CFrame.Angles(0, dir * math.pi / 2, 0) * CFrame.Angles(0, 0, 0), rgb(236, 220, 190), M.Wood)
		surfaceText(board, Enum.NormalId.Front, Locale.T(a[1] :: string), rgb(90, 60, 40), rgb(236, 220, 190), Enum.Font.GothamBold, 80)
		surfaceText(board, Enum.NormalId.Back, Locale.T(a[1] :: string), rgb(90, 60, 40), rgb(236, 220, 190), Enum.Font.GothamBold, 80)
	end
end

-- Lampadaire de décor (verre "NightGlow")
local function buildLamppost(m: Model, F: CFrame, _seed: number)
	local iron = rgb(56, 52, 70)
	column(m, "LampFoot", F, 0, 0, -0.05, 1, 1.3, iron, M.Metal, true)
	column(m, "LampPole", F, 0, 0, 0.95, 11.4, 0.42, iron, M.Metal, true)
	box(m, "LampArm", F, -0.1, 0.1, 11.2, 11.45, -2.3, 0, iron, M.Metal)
	box(m, "LampHood", F, -0.8, 0.8, 11.1, 11.5, -2.9, -1.3, iron, M.Metal)
	glow(box(m, "LampGlass", F, -0.45, 0.45, 10.3, 11.1, -2.55, -1.65, rgb(255, 232, 180), M.SmoothPlastic))
end

----------------------------------------------------------------------
-- Gros mobilier
----------------------------------------------------------------------

-- Abribus vitré : avant ouvert vers la route (-Z)
local ADS = {
	{ "🧠 Dopa Cola", "Fresh ideas in every can!", rgb(236, 72, 100), rgb(255, 196, 120) },
	{ "🛒 MégaDopa", "Everything. Always. Cheaper.", rgb(60, 110, 220), rgb(140, 220, 255) },
	{ "🎡 Fun fair", "Tonight: rides & candy floss!", rgb(186, 90, 230), rgb(255, 170, 220) },
	{ "🏠 Dream house", "Your mansion is waiting.", rgb(40, 150, 120), rgb(190, 250, 200) },
	{ "🍦 Brain freeze?", "Our ice creams are the cure.", rgb(255, 120, 150), rgb(255, 236, 170) },
	{ "🚗 Dopa Motors", "Test drive the new Bubble!", rgb(220, 60, 60), rgb(255, 220, 120) },
}

local function poster(host: BasePart, face: Enum.NormalId, ad: { any }, maxDistance: number)
	local gui = Instance.new("SurfaceGui")
	gui.Name = "Poster"
	gui.Face = face
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 24
	gui.LightInfluence = 0.5
	gui.Brightness = 1
	gui.MaxDistance = maxDistance
	gui.Parent = host
	local bg = Instance.new("Frame")
	bg.Size = UDim2.fromScale(1, 1)
	bg.BorderSizePixel = 0
	bg.BackgroundColor3 = WHITE
	bg.Parent = gui
	local grad = Instance.new("UIGradient")
	grad.Color = ColorSequence.new(ad[3] :: Color3, ad[4] :: Color3)
	grad.Rotation = 90
	grad.Parent = bg
	local title = Instance.new("TextLabel")
	title.BackgroundTransparency = 1
	title.Size = UDim2.fromScale(0.9, 0.42)
	title.Position = UDim2.fromScale(0.05, 0.1)
	title.TextScaled = true
	title.Font = Enum.Font.FredokaOne
	title.TextColor3 = WHITE
	title.Text = Locale.T(ad[1] :: string)
	title.Parent = bg
	local sub = Instance.new("TextLabel")
	sub.BackgroundTransparency = 1
	sub.Size = UDim2.fromScale(0.9, 0.28)
	sub.Position = UDim2.fromScale(0.05, 0.6)
	sub.TextScaled = true
	sub.Font = Enum.Font.GothamBold
	sub.TextColor3 = WHITE
	sub.Text = Locale.T(ad[2] :: string)
	sub.Parent = bg
end

local function buildBusShelter(m: Model, F: CFrame, seed: number)
	local frame = rgb(60, 66, 80)
	for _, x in ipairs({ -3.4, 3.4 }) do
		box(m, "ShelterPost", F, x - 0.15, x + 0.15, -0.05, 7.65, 1.55, 1.85, frame, M.Metal, true)
		box(m, "ShelterPost", F, x - 0.15, x + 0.15, -0.05, 7.65, -1.25, -0.95, frame, M.Metal, true)
	end
	box(m, "ShelterRoof", F, -3.8, 3.8, 7.6, 7.9, -1.9, 2.1, frame, M.Metal)
	local roofGlass = box(m, "ShelterRoofGlass", F, -3.6, 3.6, 7.87, 8.0, -1.7, 1.9, GLASS, M.Glass)
	roofGlass.Transparency = 0.4
	local back = box(m, "ShelterBack", F, -3.22, 3.22, 0.8, 7.2, 1.62, 1.78, GLASS, M.Glass, true)
	back.Transparency = 0.6
	local side = box(m, "ShelterSide", F, -3.32, -3.18, 0.8, 7.2, -0.9, 1.5, GLASS, M.Glass, true)
	side.Transparency = 0.6
	-- panneau publicitaire (caisson à l'autre bout)
	local adBox = box(m, "ShelterAdBox", F, 3.25, 3.55, 0.6, 7.2, -0.9, 1.5, frame, M.Metal, true)
	local adFace = box(m, "ShelterAd", F, 3.1, 3.27, 1.2, 6.8, -0.75, 1.35, WHITE, M.SmoothPlastic)
	poster(adFace, Enum.NormalId.Left, ADS[seed % #ADS + 1], 90)
	local _ = adBox
	-- banc
	box(m, "ShelterBench", F, -2.8, 2.6, 1.2, 1.45, 0.6, 1.5, WOOD, M.Wood, true)
	for _, x in ipairs({ -2.2, 2.0 }) do
		box(m, "ShelterBenchLeg", F, x - 0.1, x + 0.1, -0.05, 1.25, 1.2, 1.5, frame, M.Metal)
	end
	-- nom de l'arrêt sur le bandeau du toit
	local strip = box(m, "ShelterName", F, -3.0, 3.0, 7.0, 7.62, -1.35, -1.25, WHITE, M.SmoothPlastic)
	surfaceText(strip, Enum.NormalId.Front, "🚌 " .. Locale.T("Bus stop"), rgb(30, 70, 150), WHITE, Enum.Font.GothamBold, 90)
	-- poteau d'arrêt avec plan de ligne
	column(m, "StopPole", F, -4.8, -1.2, -0.05, 8.2, 0.24, STEEL, M.Metal)
	local flag = box(m, "StopFlag", F, -5.5, -4.1, 7.0, 8.4, -1.26, -1.14, rgb(30, 70, 150), M.Metal)
	surfaceText(flag, Enum.NormalId.Front, "🚌", WHITE, rgb(30, 70, 150), nil, 90)
	box(m, "StopTimetable", F, -5.3, -4.3, 4.2, 5.6, -1.26, -1.14, WHITE, M.SmoothPlastic)
end

-- Colonne Morris (affiches en anneaux colorés, dôme vert)
local function buildMorris(m: Model, F: CFrame, seed: number)
	column(m, "MorrisBase", F, 0, 0, -0.05, 0.6, 2.9, GREEN, M.Metal, true)
	column(m, "MorrisColumn", F, 0, 0, 0.55, 7.25, 2.4, rgb(236, 226, 206), M.SmoothPlastic, true)
	local bands = { rgb(236, 72, 140), rgb(60, 110, 220), rgb(255, 196, 70), rgb(120, 200, 150), rgb(186, 120, 240) }
	for i = 0, 2 do
		local y0 = 1.2 + i * 1.9
		column(m, "MorrisPoster", F, 0, 0, y0, y0 + 1.6, 2.5, bands[(seed + i) % #bands + 1], M.SmoothPlastic)
	end
	column(m, "MorrisCornice", F, 0, 0, 7.2, 7.6, 2.9, GREEN, M.Metal)
	egg(m, "MorrisDome", F * CFrame.new(0, 7.9, 0), Vector3.new(2.6, 1.6, 2.6), GREEN, M.Metal)
	ball(m, "MorrisFinial", F, 0, 8.9, 0, 0.5, rgb(210, 180, 90), M.Metal)
	-- une affiche lisible (plaque courbe approchée, côté -Z)
	local plate = box(m, "MorrisBill", F, -0.7, 0.7, 3.3, 4.6, -1.3, -1.24, WHITE, M.SmoothPlastic)
	poster(plate, Enum.NormalId.Front, ADS[(seed + 2) % #ADS + 1], 60)
end

-- Grand panneau publicitaire sur pieds (avant = -Z)
local function buildBillboard(m: Model, F: CFrame, seed: number)
	local steel = rgb(90, 94, 104)
	for _, x in ipairs({ -4.5, 4.5 }) do
		box(m, "BillLeg", F, x - 0.4, x + 0.4, -0.05, 9, 0.2, 1.0, steel, M.Metal, true)
	end
	box(m, "BillBeam", F, -6, 6, 8.6, 9.2, 0.25, 0.95, steel, M.Metal)
	box(m, "BillFrame", F, -8.2, 8.2, 9, 17.4, -0.1, 0.4, WHITE, M.SmoothPlastic)
	local face = box(m, "BillFace", F, -7.9, 7.9, 9.3, 17.1, -0.22, -0.05, WHITE, M.SmoothPlastic)
	poster(face, Enum.NormalId.Front, ADS[seed % #ADS + 1], 400)
	box(m, "BillWalk", F, -7.6, 7.6, 8.7, 8.85, -1.8, -0.1, steel, M.DiamondPlate)
	for _, x in ipairs({ -4, 4 }) do
		box(m, "BillLampArm", F, x - 0.08, x + 0.08, 17.3, 17.45, -1.9, 0.2, steel, M.Metal)
		glow(box(m, "BillLamp", F, x - 0.45, x + 0.45, 17.0, 17.35, -2.3, -1.6, rgb(255, 236, 200), M.SmoothPlastic))
	end
	-- (panneau double face : une autre affiche au dos)
	local back = box(m, "BillBack", F, -8.1, 8.1, 9.1, 17.3, 0.35, 0.55, steel, M.Metal)
	local backFace = box(m, "BillFaceBack", F, -7.9, 7.9, 9.3, 17.1, 0.5, 0.67, WHITE, M.SmoothPlastic)
	poster(backFace, Enum.NormalId.Back, ADS[(seed + 3) % #ADS + 1], 400)
	local _ = back
end

-- Kiosque à journaux (vert, toit en dôme, comptoir, revues)
local function buildKiosk(m: Model, F: CFrame, _seed: number)
	box(m, "KioskBody", F, -2.4, 2.4, -0.05, 3.2, -1.6, 2, GREEN, M.Metal, true)
	box(m, "KioskCounter", F, -2.1, 2.1, 3.15, 3.45, -1.95, -1.4, rgb(120, 86, 60), M.Wood)
	-- (fenêtre ouverte : on voit le marchand ; parois intérieures sombres)
	box(m, "KioskBackWall", F, -2.3, 2.3, 3.15, 6.25, 1.5, 1.95, rgb(70, 60, 56), M.SmoothPlastic)
	for _, sx in ipairs({ -1, 1 }) do
		box(m, "KioskSideWall", F, sx < 0 and -2.4 or 2.05, sx < 0 and -2.05 or 2.4, 3.15, 6.25, -1.2, 1.55, GREEN, M.Metal)
	end
	box(m, "KioskShelf", F, -1.9, 1.9, 4.6, 4.75, 1.0, 1.5, rgb(120, 86, 60), M.Wood)
	for i = 0, 5 do
		box(m, "ShelfMagazine", F, -1.7 + i * 0.6, -1.25 + i * 0.6, 4.75, 5.4, 1.2, 1.35, ({ rgb(236, 72, 140), rgb(60, 110, 220), rgb(255, 200, 60) })[i % 3 + 1], M.SmoothPlastic)
	end
	for _, x in ipairs({ -2.35, 2.35 }) do
		box(m, "KioskPost", F, x - 0.15, x + 0.15, 3.2, 6.4, -1.75, -1.45, GREEN, M.Metal)
	end
	box(m, "KioskHeader", F, -2.6, 2.6, 6.2, 7.2, -1.8, 2.2, GREEN, M.Metal, true)
	local sign = box(m, "KioskSign", F, -2.3, 2.3, 6.35, 7.05, -1.86, -1.78, rgb(250, 240, 210), M.SmoothPlastic)
	surfaceText(sign, Enum.NormalId.Front, "📰 " .. Locale.T("Newspapers"), GREEN, rgb(250, 240, 210), Enum.Font.GothamBlack, 90)
	egg(m, "KioskDome", F * CFrame.new(0, 7.3, 0.2), Vector3.new(5.6, 2.4, 4.4), GREEN, M.Metal)
	ball(m, "KioskFinial", F, 0, 8.6, 0.2, 0.6, rgb(210, 180, 90), M.Metal)
	-- revues exposées (rangées colorées sur les flancs)
	local covers = { rgb(236, 72, 140), rgb(60, 110, 220), rgb(255, 200, 60), rgb(120, 200, 150), rgb(250, 250, 250) }
	for row = 0, 2 do
		for _, sx in ipairs({ -1, 1 }) do
			box(m, "Magazines", F, sx < 0 and -2.5 or 2.38, sx < 0 and -2.38 or 2.5, 0.6 + row * 0.8, 1.2 + row * 0.8, -1.2, 1.2, covers[(row * 2 + (sx > 0 and 1 or 0)) % #covers + 1], M.SmoothPlastic)
		end
	end
	box(m, "KioskPapers", F, -1.8, 1.8, 3.43, 3.6, -1.9, -1.5, rgb(236, 232, 222), M.SmoothPlastic)
end

-- Terrasse de café : 3 tables rondes, chaises, 2 parasols (le long de X)
local function buildTerrace(m: Model, F: CFrame, seed: number)
	local parasol = hash(seed, 5) < 0.5 and rgb(200, 50, 60) or rgb(40, 120, 110)
	for i = -1, 1 do
		local x = i * 3.4
		column(m, "TableFoot", F, x, 0, -0.05, 0.12, 1.1, GRAPHITE, M.Metal)
		-- (v11, SCALE11 : échelle Roblox) plateau à 3,1, chaises à 1,85 (= SEAT_TOPS.Terrace)
		column(m, "TableLeg", F, x, 0, 0.1, 2.98, 0.2, GRAPHITE, M.Metal)
		column(m, "TableTop", F, x, 0, 2.98, 3.1, 1.9, rgb(236, 232, 226), M.Marble, true)
		for _, sz in ipairs({ -1, 1 }) do
			local c = F * CFrame.new(x, 0, sz * 1.6) * CFrame.Angles(0, sz < 0 and math.pi or 0, 0)
			box(m, "ChairSeat", c, -0.75, 0.75, 1.68, 1.85, -0.7, 0.7, rgb(160, 110, 70), M.Wood)
			box(m, "ChairBack", c, -0.75, 0.75, 1.81, 4.1, 0.6, 0.74, rgb(160, 110, 70), M.Wood)
			for _, lx in ipairs({ -0.62, 0.62 }) do
				box(m, "ChairFrame", c, lx - 0.05, lx + 0.05, -0.05, 1.7, -0.62, 0.62, GRAPHITE, M.Metal)
			end
		end
		if i ~= 0 then
			column(m, "ParasolPole", F, x * 0.5, 0, 0.25, 8.2, 0.14, WHITE, M.Metal)
			egg(m, "Parasol", F * CFrame.new(x * 0.5, 8.0, 0), Vector3.new(5.6, 1.6, 4.2), parasol, M.Fabric)
		end
	end
	column(m, "ParasolBase", F, -1.6, 0, -0.05, 0.3, 1, GRAPHITE, M.Concrete)
	column(m, "ParasolBase", F, 1.6, 0, -0.05, 0.3, 1, GRAPHITE, M.Concrete)
	-- ardoise "menu"
	local slate = box(m, "MenuSlate", F, 4.9, 6.1, 0.35, 2.6, -0.1, 0.02, rgb(50, 54, 58), M.Slate)
	surfaceText(slate, Enum.NormalId.Front, Locale.T("Café ☕ Croissant 🥐"), WHITE, nil, Enum.Font.FredokaOne, 50)
	box(m, "MenuFoot", F, 5.2, 5.8, -0.05, 0.4, -0.3, 0.3, WOOD, M.Wood)
end

-- Étal de fleuriste / bouquiniste (avant = -Z)
local function buildStall(m: Model, F: CFrame, seed: number, flowers: boolean)
	local awning = flowers and rgb(255, 140, 180) or rgb(40, 100, 70)
	box(m, "StallTable", F, -2.6, 2.6, 2.2, 2.45, -1.2, 1.2, rgb(150, 104, 70), M.Wood, true)
	for _, x in ipairs({ -2.4, 2.4 }) do
		for _, z in ipairs({ -1.0, 1.0 }) do
			box(m, "StallLeg", F, x - 0.1, x + 0.1, -0.05, 2.25, z - 0.1, z + 0.1, rgb(120, 84, 56), M.Wood)
		end
		box(m, "StallPost", F, x - 0.08, x + 0.08, 2.4, 6.4, 0.95, 1.1, GRAPHITE, M.Metal)
	end
	for i = 0, 3 do
		wedge(m, "StallAwning", Vector3.new(1.3, 0.8, 2.8), F * CFrame.new(-1.95 + i * 1.3, 6.6, -0.35) * CFrame.Angles(0, math.pi, 0), i % 2 == 0 and awning or WHITE, M.Fabric)
	end
	if flowers then
		for i = 0, 5 do
			local x = -2.1 + i * 0.84
			column(m, "Bucket", F, x, -0.4, 2.4, 3.2, 0.7, rgb(170, 176, 186), M.Metal)
			egg(m, "BouquetLeaves", F * CFrame.new(x, 3.35, -0.4), Vector3.new(0.72, 0.5, 0.72), rgb(90, 156, 84), M.Grass)
			for j = 0, 2 do
				local a = j / 3 * math.pi * 2 + i
				ball(m, "Bouquet", F, x + math.cos(a) * 0.17, 3.62 + (j % 2) * 0.1, -0.4 + math.sin(a) * 0.17, 0.34, FLOWERS[(i * 3 + j + seed) % #FLOWERS + 1], M.SmoothPlastic)
			end
		end
		box(m, "Greens", F, -2.4, 2.4, 2.4, 2.75, 0.3, 1.0, rgb(84, 150, 84), M.Grass)
	else
		-- boîtes vertes de bouquiniste + livres
		box(m, "BookBox", F, -2.35, 2.35, 2.4, 3.2, -1.1, 0.9, rgb(40, 100, 70), M.Wood)
		local covers = { rgb(170, 60, 60), rgb(60, 90, 160), rgb(220, 190, 110), rgb(90, 140, 90), rgb(120, 80, 140) }
		for i = 0, 9 do
			local x = -2.2 + i * 0.48
			box(m, "Books", F, x - 0.2, x + 0.2, 3.15, 3.2 + 0.55 + hash(seed, i) * 0.3, -0.8, 0.2, covers[i % #covers + 1], M.SmoothPlastic)
		end
	end
end

-- Table d'échecs en pierre + 2 tabourets (×2)
local function buildChessTables(m: Model, F: CFrame, _seed: number)
	for _, x in ipairs({ -3, 3 }) do
		local T = F * CFrame.new(x, 0, 0)
		-- (v11, SCALE11 : échelle Roblox) plateau à 3,1, tabourets à 1,85 (= SEAT_TOPS.Chess)
		column(m, "ChessFoot", T, 0, 0, -0.05, 2.85, 1.0, CONCRETE, M.Concrete, true)
		box(m, "ChessTop", T, -1.4, 1.4, 2.8, 3.1, -1.4, 1.4, rgb(220, 214, 206), M.Marble, true)
		local board = box(m, "ChessBoard", T, -0.9, 0.9, 3.08, 3.14, -0.9, 0.9, WHITE, M.SmoothPlastic)
		local gui = Instance.new("SurfaceGui")
		gui.Face = Enum.NormalId.Top
		gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
		gui.PixelsPerStud = 32
		gui.LightInfluence = 0.8
		gui.MaxDistance = 70
		gui.Parent = board
		for i = 0, 7 do
			for j = 0, 7 do
				if (i + j) % 2 == 1 then
					local sq = Instance.new("Frame")
					sq.BorderSizePixel = 0
					sq.BackgroundColor3 = rgb(60, 50, 50)
					sq.Size = UDim2.fromScale(1 / 8, 1 / 8)
					sq.Position = UDim2.fromScale(i / 8, j / 8)
					sq.Parent = gui
				end
			end
		end
		for _, sz in ipairs({ -1, 1 }) do
			column(m, "ChessStool", T, 0, sz * 2.4, -0.05, 1.85, 1.2, CONCRETE, M.Concrete, true)
		end
		-- quelques pièces
		for k = 0, 3 do
			column(m, "ChessPiece", T, -0.6 + k * 0.4, (k % 2 == 0 and -0.5 or 0.55), 3.12, 3.5, 0.2, k % 2 == 0 and WHITE or INK, M.SmoothPlastic)
		end
	end
end

-- Statue en bronze (personnage NPCModels figé) sur piédestal + plaque
local STATUE_TITLES = { "To the first clicker", "Our town founder", "The dreamer" }
local function buildStatue(m: Model, F: CFrame, seed: number)
	local stone = rgb(214, 208, 200)
	box(m, "PlinthStep", F, -2.6, 2.6, -0.05, 0.6, -2.6, 2.6, rgb(190, 184, 176), M.Granite, true)
	box(m, "Plinth", F, -1.8, 1.8, 0.55, 4.25, -1.8, 1.8, stone, M.Marble, true)
	box(m, "PlinthCap", F, -2.1, 2.1, 4.2, 4.6, -2.1, 2.1, rgb(190, 184, 176), M.Granite, true)
	local plaque = box(m, "Plaque", F, -1.2, 1.2, 1.8, 3.2, -1.9, -1.78, rgb(170, 130, 70), M.Metal)
	surfaceText(plaque, Enum.NormalId.Front, Locale.T(STATUE_TITLES[seed % #STATUE_TITLES + 1]), rgb(60, 40, 20), rgb(196, 156, 92), Enum.Font.Garamond, 50)
	local bronze = hash(seed, 9) < 0.6
	local figure = NPCModels.Build(({ "pedestrian", "elder", "worker", "shopper" })[seed % 4 + 1], { Seed = seed, Scale = 1.5, Prop = "none" })
	figure:PivotTo(F * CFrame.new(0, 4.6, 0))
	NPCModels.Animate(figure, (seed % 2 == 0) and "wave" or "talk", 1.2)
	local tone = bronze and rgb(150, 112, 70) or rgb(236, 232, 226)
	for _, d in ipairs(figure:GetDescendants()) do
		if d:IsA("BasePart") then
			d.Color = tone:Lerp(Color3.new(0, 0, 0), (hash(seed, #d.Name) - 0.5) * 0.12)
			d.Material = bronze and M.Metal or M.Marble
			d.Reflectance = bronze and 0.08 or 0
			partCount += 1
		end
	end
	figure.Parent = m
	-- couronne de fleurs au pied
	for i = 0, 7 do
		local a = i / 8 * math.pi * 2
		ball(m, "StatueFlowers", F, math.sin(a) * 2.35, 0.75, math.cos(a) * 2.35, 0.8, FLOWERS[(i + seed) % #FLOWERS + 1], M.SmoothPlastic)
	end
end

-- Petit marché : pavage + 4 étals de fruits et légumes sous auvents rayés
local function buildMarketSquare(m: Model, F: CFrame, seed: number)
	box(m, "MarketPaving", F, -13, 13, -0.08, 0.12, -11, 11, rgb(214, 196, 180), M.Cobblestone, true)
	local stripes = { rgb(220, 60, 70), rgb(40, 130, 90), rgb(60, 110, 200), rgb(236, 170, 40) }
	local produce = { rgb(236, 60, 50), rgb(255, 170, 40), rgb(130, 200, 70), rgb(255, 220, 70), rgb(150, 70, 150), rgb(236, 120, 40) }
	local stalls = { { -7, -4, 0 }, { 7, -4, 0 }, { -7, 5, math.pi }, { 7, 5, math.pi } }
	for si, s in ipairs(stalls) do
		local S = F * CFrame.new(s[1], 0, s[2]) * CFrame.Angles(0, s[3], 0)
		local c = stripes[(si + seed) % #stripes + 1]
		box(m, "StallTable", S, -3, 3, 2.1, 2.35, -1.3, 1.3, rgb(150, 104, 70), M.Wood, true)
		box(m, "StallSkirt", S, -2.9, 2.9, 0.1, 2.15, -1.2, -1.1, c:Lerp(WHITE, 0.5), M.Fabric)
		for _, x in ipairs({ -2.8, 2.8 }) do
			box(m, "StallPost", S, x - 0.1, x + 0.1, 0.08, 6.6, 1.05, 1.25, GRAPHITE, M.Metal)
		end
		for i = 0, 4 do
			wedge(m, "StallAwning", Vector3.new(1.2, 0.9, 3.2), S * CFrame.new(-2.4 + i * 1.2, 6.8, -0.4) * CFrame.Angles(0, math.pi, 0), i % 2 == 0 and c or WHITE, M.Fabric)
		end
		-- 4 cagettes de fruits (tas bombé = une boule écrasée)
		for k = 0, 3 do
			local x = -2.2 + k * 1.45
			local crate = S * CFrame.new(x, 2.35, -0.3) * CFrame.Angles(math.rad(-12), 0, 0)
			newPart(m, "Crate", Vector3.new(1.3, 0.45, 1.3), crate * CFrame.new(0, 0.225, 0), rgb(200, 160, 110), M.WoodPlanks)
			egg(m, "Produce", crate * CFrame.new(0, 0.5, 0), Vector3.new(1.15, 0.5, 1.15), produce[(k + si * 2 + seed) % #produce + 1], M.SmoothPlastic)
		end
		local sign = box(m, "PriceSign", S, -0.7, 0.7, 2.95, 3.65, -1.36, -1.3, rgb(50, 54, 58), M.Slate)
		surfaceText(sign, Enum.NormalId.Front, ({ "🍎 2€", "🥕 1€", "🍋 3€", "🍇 4€" })[si], WHITE, nil, Enum.Font.FredokaOne, 50)
	end
	-- paniers et caisses au sol, 2 bancs au milieu
	for i = 0, 2 do
		column(m, "Basket", F, -1.5 + i * 1.5, -0.2 + (i % 2) * 0.6, 0.08, 0.9, 1.0, rgb(190, 150, 90), M.Fabric)
	end
end

-- Colline au moulin à vent : dôme d'herbe (collision) + moulin (ailes animées)
local function buildWindmillHill(m: Model, F: CFrame, _seed: number): any
	local r, h = 24, 6.5
	local d = (r * r + h * h) / h
	local hill = newPart(m, "Hill", Vector3.new(d, d, d), F * CFrame.new(0, h - d / 2, 0), rgb(112, 180, 96), M.Grass, "Ball", true)
	hill.CastShadow = false
	local T = F * CFrame.new(0, h - 0.3, 0)
	-- chemin + fleurs sur la pente
	for i = 0, 11 do
		local a = i / 12 * math.pi * 2
		local rr = 9 + hash(i, 3) * 8
		local y = math.sqrt(math.max(0, (d / 2) ^ 2 - rr * rr)) - d / 2 + h
		ball(m, "HillFlowers", F, math.sin(a) * rr, y + 0.1, math.cos(a) * rr, 1.1, FLOWERS[i % #FLOWERS + 1], M.SmoothPlastic)
	end
	local stone = rgb(236, 228, 214)
	column(m, "MillBase", T, 0, 0, -0.2, 2.2, 8.2, rgb(170, 160, 150), M.Cobblestone, true)
	column(m, "MillTower", T, 0, 0, 2.15, 13, 7, stone, M.Plaster, true)
	column(m, "MillTowerTop", T, 0, 0, 12.95, 17, 6, stone, M.Plaster, true)
	column(m, "MillBalcony", T, 0, 0, 12.6, 13.2, 8.4, rgb(120, 86, 60), M.Wood)
	egg(m, "MillCap", T * CFrame.new(0, 17.4, 0), Vector3.new(6.8, 5.4, 7.4), rgb(150, 80, 70), M.WoodPlanks)
	box(m, "MillDoor", T, -1.1, 1.1, 2.2, 6.2, -3.62, -3.38, rgb(120, 70, 50), M.Wood)
	for _, y in ipairs({ 8.5, 14.8 }) do
		box(m, "MillWindow", T, -0.7, 0.7, y, y + 1.4, -(y > 13 and 3.12 or 3.62), -(y > 13 and 2.9 or 3.4), rgb(90, 120, 150), M.Glass)
	end
	-- ailes (4 bras avec toile) : tournent autour de l'axe du moyeu
	local hub = T * CFrame.new(0, 16.2, -4.9)
	newPart(m, "MillHub", Vector3.new(1.2, 1.4, 1.4), hub * FLAT_X, rgb(90, 64, 46), M.Wood, "Cyl")
	newPart(m, "MillAxle", Vector3.new(1.6, 0.6, 0.6), T * CFrame.new(0, 16.2, -3.9) * FLAT_X, rgb(90, 64, 46), M.Wood, "Cyl")
	local parts, locals = {}, {}
	for k = 0, 3 do
		local arm = CFrame.Angles(0, 0, k * math.pi / 2)
		local spar = newPart(m, "MillSpar", Vector3.new(0.45, 11, 0.35), hub * arm * CFrame.new(0, 5.8, -0.3), rgb(110, 80, 56), M.Wood)
		local sail = newPart(m, "MillSail", Vector3.new(2.4, 8.4, 0.12), hub * arm * CFrame.new(1.35, 6.6, -0.35), rgb(246, 240, 226), M.Fabric)
		for _, p in ipairs({ spar, sail }) do
			table.insert(parts, p)
			table.insert(locals, hub:ToObjectSpace(p.CFrame))
		end
	end
	return { Kind = "Windmill", Parts = parts, Locals = locals, Hub = hub, Speed = 0.55, Frames = table.clone(locals) }
end

-- Éolienne lointaine (mât, nacelle, 3 pales) : très grande, peu de pièces
local function buildTurbine(m: Model, F: CFrame, seed: number): any
	local white = rgb(244, 246, 248)
	column(m, "TurbineMast", F, 0, 0, -2, 40, 3.2, white, M.SmoothPlastic)
	column(m, "TurbineMastTop", F, 0, 0, 39.95, 72, 2.2, white, M.SmoothPlastic)
	box(m, "TurbineNacelle", F, -1.8, 1.8, 71, 74.4, -4.5, 3.5, white, M.SmoothPlastic)
	local hub = F * CFrame.new(0, 72.7, -5.3)
	egg(m, "TurbineHub", hub, Vector3.new(2.6, 2.6, 3.2), white, M.SmoothPlastic)
	local parts, locals = {}, {}
	for k = 0, 2 do
		local arm = CFrame.Angles(0, 0, k * math.pi * 2 / 3)
		local blade = newPart(m, "TurbineBlade", Vector3.new(2.2, 30, 0.5), hub * arm * CFrame.new(0.4, 16, -0.4), white, M.SmoothPlastic)
		table.insert(parts, blade)
		table.insert(locals, hub:ToObjectSpace(blade.CFrame))
	end
	return { Kind = "Turbine", Parts = parts, Locals = locals, Hub = hub, Speed = 0.9 + hash(seed, 2) * 0.4, Frames = table.clone(locals), Far = true }
end

----------------------------------------------------------------------
-- Table des fabriques
----------------------------------------------------------------------

-- Marquage au sol (lignes de rive, pointillés, passages, lignes d'arrêt) :
-- une pièce blanche à la taille donnée par le serveur (v9.8 : 0 pièce serveur)
-- (v9.9, CITY99) peinture relevée de 0,07 (dessus à +0,12 : au-dessus des
-- ornières, rustines et fissures de TownRoads) et plus épaisse vers le bas
local function buildPaint(m: Model, F: CFrame, _seed: number, spot: Spot?)
	local size = spot and spot.Size or Vector3.new(1, 0.1, 1)
	newPart(m, "Paint", Vector3.new(size.X, size.Y + 0.2, size.Z), F * CFrame.new(0, 0.07 - 0.1, 0), rgb(250, 250, 246), M.SmoothPlastic)
end

local BUILDERS: { [string]: (Model, CFrame, number, Spot?) -> any } = {
	Paint = buildPaint,
	Bin = buildBin,
	Recycle = buildRecycle,
	Bench = buildBench,
	Planter = buildPlanter,
	PlanterSmall = buildPlanterSmall,
	Mailbox = buildMailbox,
	NewsBox = buildNewsBox,
	Bollards = buildBollards,
	PhoneBooth = buildPhoneBooth,
	Vending = buildVending,
	SpeedSign = buildSpeedSign,
	DogStation = buildDogStation,
	ParkMeter = buildParkMeter,
	DrinkFountain = buildDrinkFountain,
	Zebra = buildZebra,
	Beacon = buildBeacon,
	TrafficLight = buildTrafficLight,
	Manhole = buildManhole,
	Drain = buildDrain,
	BikeLane = buildBikeLane,
	Banner = buildBanner,
	StreetName = buildStreetName,
	Signpost = buildSignpost,
	Lamppost = buildLamppost,
	BusShelter = buildBusShelter,
	Morris = buildMorris,
	Billboard = buildBillboard,
	Kiosk = buildKiosk,
	Terrace = buildTerrace,
	FlowerStall = function(m: Model, F: CFrame, seed: number)
		buildStall(m, F, seed, true)
	end,
	BookStall = function(m: Model, F: CFrame, seed: number)
		buildStall(m, F, seed, false)
	end,
	ChessTables = buildChessTables,
	Statue = buildStatue,
	MarketSquare = buildMarketSquare,
	WindmillHill = buildWindmillHill,
	Turbine = buildTurbine,
}
-- (v9.9, CITY99) routes réalistes, allées, poteaux indicateurs (TownRoads)
for kind, builder in pairs(TownRoads.BUILDERS) do
	BUILDERS[kind] = builder
end
for kind in pairs(TownRoads.BIG) do
	BIG[kind] = true
end
for kind, builder in pairs(TownDistricts.BUILDERS) do
	BUILDERS[kind] = builder
end
for kind in pairs(TownDistricts.BIG) do
	BIG[kind] = true
end
-- (v10, CITY10) kits de la grande ville
local IMPOSTORS: { [string]: (Model, CFrame, number, any) -> any } = {}
local NEAR_R: { [string]: number } = {} -- (v10) rayon réduit des lieux denses
if okCity and type(CityPlan) == "table" then
	for kind, r in pairs(CityPlan.NEAR or {}) do
		NEAR_R[kind] = r
	end
	for kind, builder in pairs(CityPlan.BUILDERS) do
		BUILDERS[kind] = builder
	end
	for kind in pairs(CityPlan.BIG) do
		BIG[kind] = true
	end
	for kind, builder in pairs(CityPlan.IMPOSTORS) do
		IMPOSTORS[kind] = builder
	end
end
TownStreetLife.Kinds = BUILDERS

----------------------------------------------------------------------
-- Lecture des emplacements publiés par le serveur
----------------------------------------------------------------------

local function parseSpots(folder: Instance): { Spot }
	local list: { Spot } = {}
	for _, cell in ipairs(folder:GetChildren()) do
		local data = cell:GetAttribute("Data")
		if type(data) == "string" then
			for _, line in ipairs(string.split(data, "\n")) do
				local f = string.split(line, ";")
				local x, y, z, yaw = tonumber(f[2]), tonumber(f[3]), tonumber(f[4]), tonumber(f[5])
				if #f >= 6 and x and y and z and yaw then
					local cf = CFrame.new(x, y, z) * CFrame.Angles(0, yaw, 0)
					local size: Vector3? = nil
					if f[7] then
						local c = string.split(f[7], ",")
						local sx, sy, sz = tonumber(c[1]), tonumber(c[2]), tonumber(c[3])
						if sx and sy and sz then
							size = Vector3.new(sx, sy, sz)
						end
					end
					table.insert(list, { Kind = f[1], CF = cf, Seed = tonumber(f[6]) or 0, Pos = cf.Position, Size = size })
				end
			end
		end
	end
	-- (ordre stable : même construction sur tous les clients)
	table.sort(list, function(a, b)
		if a.Pos.X ~= b.Pos.X then
			return a.Pos.X < b.Pos.X
		end
		return a.Pos.Z < b.Pos.Z
	end)
	return list
end

local function serverNow(): number
	local ok, t = pcall(function()
		return workspace:GetServerTimeNow()
	end)
	return ok and type(t) == "number" and t or os.clock()
end

-- (v10) recale un emplacement du plan sur le sol réel (plateau des manoirs,
-- trottoirs, rampes) : un rayon vertical sur les coques du serveur, une fois
local function snapSpot(spot: Spot, parent: Instance)
	if not spot.Snap then
		return
	end
	spot.Snap = false
	local town = parent.Parent
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	local ignore: { Instance } = { parent }
	for _, plr in ipairs(game:GetService("Players"):GetPlayers()) do
		if plr.Character then
			table.insert(ignore, plr.Character)
		end
	end
	params.FilterDescendantsInstances = ignore
	local p = spot.CF.Position
	local ok, hit = pcall(function()
		return workspace:Raycast(p + Vector3.new(0, 30, 0), Vector3.new(0, -60, 0), params)
	end)
	if ok and hit and hit.Instance and (town == nil or hit.Instance:IsDescendantOf(town)) then
		local dy = hit.Position.Y - p.Y
		if math.abs(dy) > 0.01 and math.abs(dy) < 12 then
			spot.CF = spot.CF + Vector3.new(0, dy, 0)
			spot.Pos = spot.CF.Position
		end
	end
end

-- (v11, CITY11) trottoirs jamais PINCÉS : un petit mobilier de bordure qui
-- laisserait moins de 2,5 studs de passage avec un lampadaire / un autre
-- mobilier glisse le long du trottoir (axe X local), une fois, de façon
-- déterministe (mêmes données serveur : même résultat sur tous les clients)
local NUDGE = { ParkMeter = 0.3, Bin = 0.8, NewsBox = 0.7, Mailbox = 0.6, SpeedSign = 0.2, DogStation = 0.5, Recycle = 1.2, Vending = 1.1 }
local PASSAGE = 2.5
local function nudgeSpot(spot: Spot)
	local r0 = NUDGE[spot.Kind]
	if not r0 or spot.Nudged then
		return
	end
	spot.Nudged = true
	local okL, near = pcall(TownRoads.LampsNear, spot.Pos, 6)
	if not okL or type(near) ~= "table" then
		return
	end
	-- pincement : un obstacle EN FACE (même abscisse le long du trottoir, à
	-- moins de r + r' + 2,5 en travers) ; un voisin dans l'alignement ne gêne pas
	local home = spot.Pos
	local function blocked(cf: CFrame): boolean
		for _, o in ipairs(near) do
			local q: Vector3 = o[1]
			if Vector3.new(q.X - home.X, 0, q.Z - home.Z).Magnitude < 0.05 then
				continue -- (soi-même)
			end
			local rel = cf:PointToObjectSpace(q)
			local along, across = math.abs(rel.X), math.abs(rel.Z)
			if along < r0 + o[2] + 0.3 and across < r0 + o[2] + PASSAGE then
				return true
			end
		end
		return false
	end
	if not blocked(spot.CF) then
		return
	end
	for _, dx in ipairs({ 1.5, -1.5, 3, -3, 4.5, -4.5 }) do
		local cf = spot.CF * CFrame.new(dx, 0, 0)
		if not blocked(cf) then
			spot.CF = cf
			spot.Pos = cf.Position
			return
		end
	end
end

local function buildSpot(spot: Spot, parent: Instance)
	local builder = BUILDERS[spot.Kind]
	if not builder then
		return
	end
	snapSpot(spot, parent)
	pcall(nudgeSpot, spot)
	local m = Instance.new("Model")
	m.Name = spot.Kind
	local ok, anim = pcall(builder, m, spot.CF, spot.Seed, spot)
	if not ok then
		m:Destroy()
		warn("[TownStreetLife] " .. spot.Kind .. " : " .. tostring(anim))
		spot.Kind = "" -- (on n'essaie plus)
		return
	end
	m.Parent = parent
	spot.Model = m
	-- (v10) le détail remplace l'imposteur dans la même passe (jamais les deux)
	if spot.Imp then
		spot.Imp:Destroy()
		spot.Imp = nil
	end
	spot.Anim = anim
end

local function destroyImp(spot: Spot)
	if spot.Imp then
		spot.Imp:Destroy()
	end
	spot.Imp = nil
end

local function destroySpot(spot: Spot)
	if spot.Model then
		spot.Model:Destroy()
	end
	spot.Model = nil
	spot.Anim = nil
	destroyImp(spot)
end

-- (v10) imposteur : quelques pièces vues de loin (au-delà du flux détaillé)
local function buildImp(spot: Spot, parent: Instance)
	local builder = IMPOSTORS[spot.Kind]
	if not builder then
		return
	end
	snapSpot(spot, parent)
	local m = Instance.new("Model")
	m.Name = spot.Kind .. "_Far"
	local ok, err = pcall(builder, m, spot.CF, spot.Seed, spot)
	if not ok then
		m:Destroy()
		warn("[TownStreetLife] imposteur " .. spot.Kind .. " : " .. tostring(err))
		IMPOSTORS[spot.Kind] = nil
		return
	end
	m.Parent = parent
	spot.Imp = m
end

----------------------------------------------------------------------
-- Animation (20 Hz au plus)
----------------------------------------------------------------------

-- Cycle des feux (s) : vert 9, orange 2, rouge 9 (piétons verts pendant le rouge)
local LIGHT_CYCLE = 20
local function stepAnim(s: any, now: number, focus: Vector3?)
	for _, spot: Spot in ipairs(s.Spots) do
		local a = spot.Anim
		if a and spot.Model then
			local near = focus == nil or a.Far or (spot.Pos - focus).Magnitude < ANIM_RANGE
			if near then
				if a.Kind == "TrafficLight" then
					local t = (now + a.Group) % LIGHT_CYCLE
					local st = t < 9 and 3 or (t < 11 and 2 or 1)
					if st ~= a.State then
						a.State = st
						for i, lamp in ipairs(a.Lamps) do
							local on = i == st
							lamp.Part.Color = on and lamp.On or lamp.Off
							lamp.Part.Material = on and M.Neon or M.SmoothPlastic
						end
						local walk = st == 1
						a.Ped[1].Part.Color = walk and a.Ped[1].Off or a.Ped[1].On
						a.Ped[1].Part.Material = walk and M.SmoothPlastic or M.Neon
						a.Ped[2].Part.Color = walk and a.Ped[2].On or a.Ped[2].Off
						a.Ped[2].Part.Material = walk and M.Neon or M.SmoothPlastic
					end
				elseif a.Kind == "Beacon" then
					local on = (now * 1.25) % 1 < 0.5
					if on ~= a.On then
						a.On = on
						a.Globe.Material = on and M.Neon or M.SmoothPlastic
						a.Globe.Color = on and Color3.fromRGB(255, 176, 50) or Color3.fromRGB(200, 130, 50)
					end
				elseif a.Kind == "Windmill" or a.Kind == "Turbine" then
					local rot = a.Hub * CFrame.Angles(0, 0, now * a.Speed % (math.pi * 2))
					for i, loc in ipairs(a.Locals) do
						a.Frames[i] = rot * loc
					end
					workspace:BulkMoveTo(a.Parts, a.Frames, Enum.BulkMoveMode.FireCFrameChanged)
				elseif a.Kind == "Banner" then
					local sway = math.sin(now * 1.6 + a.Phase) * 0.12
					local rot = a.Pivot * CFrame.Angles(0, sway, 0) * a.Pivot:Inverse()
					a.Parts[1].CFrame = rot * a.Base[1]
					a.Parts[2].CFrame = rot * a.Base[2]
				end
			end
		end
	end
end

----------------------------------------------------------------------
-- Flux
----------------------------------------------------------------------

local function load(s: any): boolean
	local town = workspace:FindFirstChild("DopamineTown")
	local data = town and town:FindFirstChild("StreetLife")
	if not town or not data then
		return false
	end
	s.Spots = parseSpots(data)
	TownRoads.SetDestinations(s.Spots)
	-- (v10, CITY10) plan de la grande ville (client) : ajouté aux emplacements
	-- du serveur, en évitant les gros emplacements déjà publiés. Calculé dans
	-- un fil à part, étalé sur quelques images (pas d'à-coup à l'entrée) ;
	-- le flux le prend dès qu'il est prêt
	if okCity and type(CityPlan) == "table" then
		local origin = require(ReplicatedStorage.Shared.WorldLayout).Origin()
		local taken = {}
		for _, spot in ipairs(s.Spots) do
			if BIG[spot.Kind] and spot.Kind ~= "Paint" and spot.Kind ~= "BikeLane" then
				local r = spot.Size and math.max(spot.Size.X, spot.Size.Z) / 2 or 14
				table.insert(taken, { spot.Pos.X - origin.X, spot.Pos.Z - origin.Z, math.min(r, 30) })
			end
		end
		local count = tonumber(town:GetAttribute("PlotCount")) or 8
		local mySpots = s.Spots
		task.spawn(function()
			local okPlan, extra = pcall(CityPlan.Build, count, taken, function()
				task.wait()
			end)
			if okPlan and type(extra) == "table" then
				if state ~= s or s.Spots ~= mySpots then
					return -- (sorti de la ville / rechargé pendant le calcul)
				end
				for _, spot in ipairs(extra) do
					-- (copie : le plan en cache n'est jamais modifié)
					table.insert(s.Spots, { Kind = spot.Kind, CF = spot.CF, Seed = spot.Seed, Pos = spot.Pos, Size = spot.Size, Data = spot.Data, Snap = spot.Snap })
				end
				s.CityCount = #extra
			elseif not okPlan then
				warn("[TownStreetLife] CityPlan : " .. tostring(extra))
			end
		end)
	end
	-- (v9.9, CITY99) arbres de la ville : modèles VIDES posés par le serveur
	-- (TownKit.Tree, attribut TreeClient) ; on les construit ici
	s.Trees = {}
	-- (v11, CITY11) grilles de pied d'arbre du serveur : l'arbre posé dessus
	-- est un arbre D'ALIGNEMENT (espèce de ville, StreetTrees)
	local grates = {}
	for _, d in ipairs(town:GetDescendants()) do
		if d:IsA("BasePart") and d.Name == "TreeGrate" then
			table.insert(grates, d.Position)
		end
	end
	for _, d in ipairs(town:GetDescendants()) do
		if d:IsA("Model") and d:GetAttribute("TreeClient") == true then
			local base = d:GetAttribute("TreeBase")
			if typeof(base) == "Vector3" then
				local street = false
				for _, g in ipairs(grates) do
					if math.abs(g.X - base.X) < 1 and math.abs(g.Z - base.Z) < 1 and math.abs(g.Y - base.Y) < 2 then
						street = true
						break
					end
				end
				table.insert(s.Trees, { Model = d, Base = base, Built = nil, Street = street })
			end
		end
	end
	local folder = Instance.new("Folder")
	folder.Name = TownStreetLife.FOLDER_NAME
	-- (sous DopamineTown : TownAtmosphere suit les verres "NightGlow")
	folder.Parent = town
	s.Folder = folder
	s.Loaded = true
	return true
end

-- (v9.9, CITY99) Un arbre de la ville, construit DANS son modèle du serveur
-- (mêmes pièces que Greenery.Tree côté serveur avant v9.9 : même rendu,
-- même collision des troncs pour l'avatar local), sans les attributs
-- "TreeBase" (TownGreenery ne le prend pas pour un autre arbre).
-- (v10, CITY10) la grande ville a des MILLIERS d'arbres (ceinture verte,
-- campagne) : ils sont maintenant EN FLUX : arbre complet près de l'avatar
-- (< 300 studs), silhouette (niveau 0, 3-5 pièces) jusqu'à 720, rien au-delà
local TREES_PER_STEP = 14
local TREE_NEAR_IN, TREE_NEAR_OUT = 300, 350
local TREE_FAR_IN, TREE_FAR_OUT = 720, 780
local function buildTree(t: any, far: boolean?): number
	local m = t.Model
	if not m.Parent then
		return 0
	end
	local maxTier = far and 0 or (tonumber(m:GetAttribute("TreeTier")) or 0)
	if t.Street and not far and okST and type(StreetTrees) == "table" then
		-- (v11) arbre d'alignement : espèce de ville commune à la rue
		-- (graine du serveur : rue * 31 + rang), corset pour les jeunes
		local seed = tonumber(m:GetAttribute("TreeSeed")) or 1
		local h = tonumber(m:GetAttribute("TreeHeight")) or 12
		local okS, tree2, n2 = pcall(StreetTrees.Build, m, t.Base, h + 2, seed, StreetTrees.Pick(math.floor(seed / 31) * 31 + 7), { Guard = h < 14, Name = "TreeLocal" })
		if t.Built then
			t.Built:Destroy()
		end
		if okS then
			t.Built = tree2
			t.Far = false
			return n2
		end
		t.Built = false
		return 0
	end
	local ok, tree, n = pcall(function()
		return Greenery.Tree(m, t.Base, tonumber(m:GetAttribute("TreeHeight")) or 12, tonumber(m:GetAttribute("TreeSeed")) or 1, m:GetAttribute("TreeSpecies") :: any, maxTier, 0, {
			Lawn = m:GetAttribute("TreeLawn") == true,
			Name = far and "TreeFar" or "TreeLocal",
		})
	end)
	if t.Built then
		t.Built:Destroy()
	end
	if not ok then
		t.Built = false
		return 0
	end
	for _, key in ipairs({ "TreeBase", "TreeSpecies", "TreeHeight", "TreeSeed", "TreeTier", "TreeLawn" }) do
		tree:SetAttribute(key, nil)
	end
	t.Built = tree
	t.Far = far == true
	return n
end

local function dropTree(t: any)
	if t.Built then
		t.Built:Destroy()
	end
	t.Built = nil
	t.Far = nil
end

local function stepTrees(s: any, flat: Vector3, k: number?)
	local list = s.Trees
	if not list then
		return
	end
	local scale = k or 1
	-- les plus proches d'abord, TREES_PER_STEP par passe
	local todo = {}
	for _, t in ipairs(list) do
		if t.Built ~= false then
			local d = (Vector3.new(t.Base.X, 0, t.Base.Z) - flat).Magnitude
			if d < TREE_NEAR_IN * scale then
				if t.Built == nil or t.Far then
					table.insert(todo, { T = t, D = d, Far = false })
				end
			elseif d < TREE_FAR_IN * scale then
				if t.Built == nil or (not t.Far and d > TREE_NEAR_OUT * scale) then
					table.insert(todo, { T = t, D = d, Far = true })
				end
			elseif t.Built and d > TREE_FAR_OUT * scale then
				dropTree(t)
			end
		end
	end
	table.sort(todo, function(a, b)
		return a.D < b.D
	end)
	for i = 1, math.min(TREES_PER_STEP, #todo) do
		buildTree(todo[i].T, todo[i].Far)
	end
end

local function clearTrees(s: any)
	for _, t in ipairs(s.Trees or {}) do
		if t.Built then
			t.Built:Destroy()
		end
		t.Built = nil
		t.Far = nil
	end
end

local function focusPoint(): Vector3?
	local camera = workspace.CurrentCamera
	return camera and camera.CFrame.Position or nil
end

function TownStreetLife.Start()
	if state then
		return
	end
	state = { Spots = {}, Loaded = false, Acc = 0, Retry = 0 }
	pcall(load, state)
	state.Conn = RunService.Heartbeat:Connect(function(dt: number)
		local s = state
		if not s or not s.Loaded then
			return
		end
		-- (v9.9) personnages des nouveaux lieux : à chaque image, près de la caméra
		local okD, errD = pcall(TownDistricts.Step, dt)
		if not okD and not s.WarnedD then
			s.WarnedD = true
			warn("[TownStreetLife] TownDistricts : " .. tostring(errD))
		end
		-- (v10) acteurs des kits de la grande ville (portails, canards, serveurs...)
		if okKit and type(CityKit) == "table" then
			pcall(CityKit.Step, dt)
		end
		s.Acc += dt
		if s.Acc < ANIM_STEP then
			return
		end
		s.Acc = 0
		local ok, err = pcall(stepAnim, s, serverNow(), focusPoint())
		if not ok and not s.Warned then
			s.Warned = true
			warn("[TownStreetLife] " .. tostring(err))
		end
	end)
end

function TownStreetLife.Step(position: Vector3)
	local s = state
	if not s then
		return
	end
	if not s.Loaded or (s.Folder and s.Folder.Parent == nil) then
		-- (ville pas encore répliquée, ou reconstruite : on relit)
		s.Loaded = false
		s.Retry -= 1
		if s.Retry <= 0 then
			s.Retry = 4
			for _, spot in ipairs(s.Spots) do
				destroySpot(spot)
			end
			clearTrees(s)
			pcall(load, s)
		end
		return
	end
	local flat = Vector3.new(position.X, 0, position.Z)
	local k = detailScale()
	stepTrees(s, flat, k)
	-- (v9.9) les plus PROCHES d'abord : on ne voit jamais un trou au pied de
	-- l'avatar pendant que le flux construit au loin
	local todo = {}
	local impTodo = {}
	for _, spot: Spot in ipairs(s.Spots) do
		if not ANCHORS[spot.Kind] and BUILDERS[spot.Kind] then
			local d = (Vector3.new(spot.Pos.X, 0, spot.Pos.Z) - flat).Magnitude
			local inR, outR = BUILD_IN * k, BUILD_OUT * k
			if FAR[spot.Kind] then
				inR, outR = FAR_IN, FAR_OUT
			elseif NEAR_R[spot.Kind] then
				inR, outR = NEAR_R[spot.Kind] * k, (NEAR_R[spot.Kind] + 40) * k
			elseif BIG[spot.Kind] then
				inR, outR = BIG_IN * k, BIG_OUT * k
			end
			if spot.Model then
				if d > outR then
					destroySpot(spot)
				end
			elseif d < inR then
				table.insert(todo, { Spot = spot, D = d })
			end
			-- (v10) imposteur entre le rayon détaillé et IMP_IN (jamais les deux)
			if IMPOSTORS[spot.Kind] then
				if spot.Model then
					if spot.Imp then
						destroyImp(spot)
					end
				elseif d > IMP_OUT * k then
					if spot.Imp then
						destroyImp(spot)
					end
				elseif d < IMP_IN * k and d >= inR and not spot.Imp then
					table.insert(impTodo, { Spot = spot, D = d })
				end
			end
		end
	end
	table.sort(todo, function(a, b)
		return a.D < b.D
	end)
	for i = 1, math.min(BUILDS_PER_STEP, #todo) do
		buildSpot(todo[i].Spot, s.Folder)
	end
	table.sort(impTodo, function(a, b)
		return a.D < b.D
	end)
	for i = 1, math.min(BUILDS_PER_STEP * 2, #impTodo) do
		buildImp(impTodo[i].Spot, s.Folder)
	end
end

function TownStreetLife.Stop()
	local s = state
	state = nil
	if not s then
		return
	end
	if s.Conn then
		s.Conn:Disconnect()
	end
	for _, spot in ipairs(s.Spots) do
		destroySpot(spot)
	end
	clearTrees(s)
	if s.Folder then
		s.Folder:Destroy()
	end
end

-- (tests / détecteur de z-fighting) construit TOUT d'un coup
function TownStreetLife.BuildAll(): number
	local s = state
	if not s or not s.Loaded then
		return 0
	end
	local n = 0
	for _, spot: Spot in ipairs(s.Spots) do
		if not spot.Model and not ANCHORS[spot.Kind] and BUILDERS[spot.Kind] then
			buildSpot(spot, s.Folder)
			n += 1
		end
	end
	for _, t in ipairs(s.Trees or {}) do
		if t.Built == nil then
			buildTree(t)
			n += 1
		end
	end
	return n
end

-- Emplacements d'un type (TownPeople : bancs, terrasses, abribus…)
function TownStreetLife.Spots(kind: string): { { CF: CFrame, Seed: number } }
	local out = {}
	local s = state
	if s then
		for _, spot: Spot in ipairs(s.Spots) do
			if spot.Kind == kind then
				table.insert(out, { CF = spot.CF, Seed = spot.Seed })
			end
		end
	end
	return out
end

-- Lecture directe (sans Start) : TownPeople peut s'en servir seul
function TownStreetLife.ReadSpots(): { Spot }
	local town = workspace:FindFirstChild("DopamineTown")
	local data = town and town:FindFirstChild("StreetLife")
	return data and parseSpots(data) or {}
end

function TownStreetLife.Debug(): any
	local s = state
	local built, parts, kinds = 0, 0, {}
	local imps, impParts = 0, 0
	if s then
		for _, spot: Spot in ipairs(s.Spots) do
			kinds[spot.Kind] = (kinds[spot.Kind] or 0) + 1
			if spot.Model then
				built += 1
				for _, d in ipairs(spot.Model:GetDescendants()) do
					if d:IsA("BasePart") then
						parts += 1
					end
				end
			end
			if spot.Imp then
				imps += 1
				for _, d in ipairs(spot.Imp:GetDescendants()) do
					if d:IsA("BasePart") then
						impParts += 1
					end
				end
			end
		end
	end
	local trees, treeParts = 0, 0
	for _, t in ipairs(s and s.Trees or {}) do
		if t.Built then
			trees += 1
			for _, d in ipairs(t.Built:GetDescendants()) do
				if d:IsA("BasePart") then
					treeParts += 1
				end
			end
		end
	end
	return { Spots = s and #s.Spots or 0, Built = built, Parts = parts, Kinds = kinds, Created = partCount, City = s and s.CityCount or 0, Impostors = imps, ImpostorParts = impParts, Trees = s and s.Trees and #s.Trees or 0, TreesBuilt = trees, TreeParts = treeParts }
end

return TownStreetLife
