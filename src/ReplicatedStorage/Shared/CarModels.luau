--[[
	CarModels (ModuleScript)
	Emplacement : ReplicatedStorage > Shared > CarModels

	🚗 Les voitures de Dopamine Town (v9.6), construites en pièces (blocs,
	coins, cylindres) : utilisé par le SERVEUR (voitures garées de la ville,
	TownKit.Car ; voiture qu'on conduit, CarService) ET par le CLIENT
	(concession, garage du manoir). Pur : que des Instances, aucun service.

	8 modèles "réalistes stylisés" : vraie silhouette (capot, habitacle,
	coffre / hayon / benne), toit arrondi, vitres (Glass transparent) avec
	montants, phares et feux, calandre, pare-chocs, 4 roues (pneu, jante,
	moyeu) dans leurs passages de roue, rétroviseurs, plaques, poignées,
	sièges et volant visibles derrière les vitres.
	  BubbleCar : petite voiture ronde kawaii (phares ronds, toit blanc,
	              roue de secours) ;
	  CityCar   : citadine 3 portes ;
	  Hatchback : compacte 5 portes, becquet ;
	  Pickup    : pick-up (cabine + benne, grosses roues) ;
	  SUV       : grand SUV (barres de toit, roue de secours) ;
	  Van       : combi / camping-car bicolore ;
	  SportsCar : roadster décapotable (aileron, doubles échappements) ;
	  Limo      : limousine (3 vitres par côté, chromes).
	Pas de lumière, pas de Neon, pas de son (le client ajoute de petits
	phares la nuit à SA voiture seulement).

	API :
	  CarModels.Build(carId, color?, opts?) -> Model
	    color : Color3 | Id de Config.Cars.Colors | nil (couleur par défaut)
	    opts  : { Detail = "Full" | "Parked", Plate = "TEXTE"?,
	              Scale = number | Vector3 (x = largeur, y = hauteur, z = longueur) }
	    Repère : pivot = centre du DESSOUS (au sol), avant vers -Z. Tout est
	    ANCRÉ ; PrimaryPart "Root" = boîte de collision invisible (seule pièce
	    CanCollide), les autres pièces sont du décor (CanCollide / CanQuery /
	    CanTouch false). Attributs : CarId, Length, Width, Height, SeatCF
	    (CFrame du siège du conducteur, repère du pivot), WheelRadius.
	  CarModels.Dimensions(carId) -> Vector3 (largeur, hauteur, longueur)
	  CarModels.WheelPositions(carId) -> { Vector3 } (centres des roues, repère du pivot)
	  CarModels.ColorOf(carId, color?) -> Color3
	  CarModels.LockReason(data, carId) -> string? (nil = débloquée ; texte traduit)
	  CarModels.Kinds : ids des modèles
]]

local Config = require(script.Parent.Config)

local CarModels = {}

local M = Enum.Material
local PI = math.pi

export type Spec = {
	L: number, -- longueur
	W: number, -- largeur (carrosserie)
	WheelD: number, -- diamètre des roues
	TyreW: number, -- largeur des pneus
	Clear: number, -- dessous de la carrosserie
	Low: number, -- dessus du bas de caisse (départ du capot)
	Belt: number, -- ligne de ceinture (bas des vitres)
	Roof: number, -- dessus du toit
	AxleF: number, -- z de l'essieu avant
	AxleR: number, -- z de l'essieu arrière
	Ws: number, -- pied du pare-brise
	R0: number, -- avant du toit
	R1: number, -- arrière du toit
	Rw: number, -- pied de la lunette arrière
	Inset: number, -- rentré de l'habitacle (de chaque côté)
	HoodFront: number, -- 0..1 : hauteur du nez du capot (0 = en coin, 1 = plat)
	TrunkDrop: number, -- coffre plus bas que la ceinture de...
	Doors: number, -- 2 ou 4 (joints / poignées)
	Style: string,
}

local SPECS: { [string]: Spec } = {
	BubbleCar = { L = 9.2, W = 5.2, WheelD = 2.0, TyreW = 0.75, Clear = 0.72, Low = 1.85, Belt = 2.75, Roof = 5.0,
		AxleF = -2.85, AxleR = 2.85, Ws = -2.5, R0 = -1.05, R1 = 1.85, Rw = 3.2, Inset = 0.45, HoodFront = 0.55, TrunkDrop = 0.15, Doors = 2, Style = "Bubble" },
	CityCar = { L = 10.6, W = 5.2, WheelD = 2.1, TyreW = 0.8, Clear = 0.72, Low = 1.8, Belt = 2.85, Roof = 5.0,
		AxleF = -3.45, AxleR = 3.35, Ws = -2.35, R0 = -0.85, R1 = 2.75, Rw = 4.25, Inset = 0.4, HoodFront = 0.45, TrunkDrop = 0.05, Doors = 2, Style = "City" },
	Hatchback = { L = 11.6, W = 5.4, WheelD = 2.2, TyreW = 0.85, Clear = 0.72, Low = 1.8, Belt = 2.95, Roof = 5.0,
		AxleF = -3.8, AxleR = 3.7, Ws = -2.45, R0 = -0.7, R1 = 3.55, Rw = 5.0, Inset = 0.4, HoodFront = 0.4, TrunkDrop = 0, Doors = 4, Style = "Hatch" },
	Pickup = { L = 13, W = 6.0, WheelD = 2.7, TyreW = 1.0, Clear = 1.15, Low = 2.45, Belt = 3.6, Roof = 6.0,
		AxleF = -4.1, AxleR = 4.0, Ws = -2.7, R0 = -1.55, R1 = 1.35, Rw = 1.45, Inset = 0.35, HoodFront = 0.75, TrunkDrop = 0, Doors = 4, Style = "Pickup" },
	SUV = { L = 12.6, W = 6.0, WheelD = 2.6, TyreW = 0.95, Clear = 1.0, Low = 2.35, Belt = 3.55, Roof = 6.1,
		AxleF = -4.0, AxleR = 3.9, Ws = -2.75, R0 = -1.35, R1 = 5.3, Rw = 5.75, Inset = 0.35, HoodFront = 0.7, TrunkDrop = 0, Doors = 4, Style = "SUV" },
	Van = { L = 13, W = 6.0, WheelD = 2.4, TyreW = 0.9, Clear = 0.9, Low = 2.2, Belt = 3.35, Roof = 6.7,
		AxleF = -4.4, AxleR = 4.2, Ws = -5.15, R0 = -3.85, R1 = 6.15, Rw = 6.2, Inset = 0.3, HoodFront = 0.6, TrunkDrop = 0, Doors = 2, Style = "Van" },
	SportsCar = { L = 12.6, W = 5.8, WheelD = 2.3, TyreW = 1.05, Clear = 0.55, Low = 1.45, Belt = 2.55, Roof = 2.55,
		AxleF = -4.05, AxleR = 3.85, Ws = -1.2, R0 = -0.2, R1 = 1.9, Rw = 2.9, Inset = 0.45, HoodFront = 0, TrunkDrop = 0.15, Doors = 2, Style = "Sports" },
	Limo = { L = 15.2, W = 5.8, WheelD = 2.2, TyreW = 0.85, Clear = 0.7, Low = 1.8, Belt = 2.95, Roof = 5.0,
		AxleF = -5.2, AxleR = 5.1, Ws = -3.4, R0 = -2.0, R1 = 5.0, Rw = 6.1, Inset = 0.4, HoodFront = 0.5, TrunkDrop = 0.1, Doors = 4, Style = "Limo" },
}
CarModels.Specs = SPECS
CarModels.Kinds = { "BubbleCar", "CityCar", "Hatchback", "Pickup", "SUV", "Van", "SportsCar", "Limo" }

-- Couleurs fixes
local GLASS = Color3.fromRGB(64, 88, 116)
local TRIM = Color3.fromRGB(44, 44, 54)
local TYRE = Color3.fromRGB(32, 32, 38)
local CHROME = Color3.fromRGB(214, 218, 226)
local LAMP = Color3.fromRGB(255, 250, 228)
local TAIL = Color3.fromRGB(214, 36, 56)
local AMBER = Color3.fromRGB(255, 170, 60)
local PLATE = Color3.fromRGB(248, 248, 244)
local PLATE_BAND = Color3.fromRGB(40, 80, 190)
local SEAT = Color3.fromRGB(70, 56, 66)
local WHITE = Color3.new(1, 1, 1)
local BLACK = Color3.new(0, 0, 0)

local function kindOf(carId: string?): string
	if type(carId) == "string" then
		if SPECS[carId] then
			return carId
		end
		local car = Config.CarsById and Config.CarsById[carId]
		if car and type(car.Kind) == "string" and SPECS[car.Kind] then
			return car.Kind
		end
	end
	return "CityCar"
end

function CarModels.Dimensions(carId: string?): Vector3
	local s = SPECS[kindOf(carId)]
	local height = s.Roof
	if s.Style == "Sports" then
		height = s.Belt + 1.3
	end
	return Vector3.new(s.W, height, s.L)
end

function CarModels.WheelPositions(carId: string?): { Vector3 }
	local s = SPECS[kindOf(carId)]
	local x = s.W / 2 - s.TyreW / 2 + 0.08
	local out = {}
	for _, z in ipairs({ s.AxleF, s.AxleR }) do
		for _, sx in ipairs({ -1, 1 }) do
			table.insert(out, Vector3.new(sx * x, s.WheelD / 2, z))
		end
	end
	return out
end

function CarModels.ColorOf(carId: string?, color: any?): Color3
	if typeof(color) == "Color3" then
		return color
	end
	local byId = Config.CarColorsById or {}
	if type(color) == "string" and byId[color] then
		return byId[color].Color
	end
	local car = type(carId) == "string" and Config.CarsById and Config.CarsById[carId] or nil
	local default = car and byId[car.DefaultColor]
	if default then
		return default.Color
	end
	return Color3.fromRGB(255, 150, 196)
end

-- 🔒 Raison du verrou (nil = débloquée) : visites à l'océan
function CarModels.LockReason(data: any, carId: string): string?
	local car = Config.CarsById and Config.CarsById[carId]
	if not car then
		return "?"
	end
	local need = tonumber(car.RequiresRebirths) or 0
	local have = type(data) == "table" and tonumber(data.Rebirths) or 0
	if (have or 0) >= need then
		return nil
	end
	local text = "🔒 Unlocked after %d visits to the ocean"
	local okLocale, Locale = pcall(require, script.Parent:FindFirstChild("Locale") :: any)
	if okLocale and type(Locale) == "table" and type(Locale.T) == "function" then
		return Locale.T(text, need)
	end
	return string.format(text, need)
end

----------------------------------------------------------------------
-- Constructeur (repère local : sol au centre, avant vers -Z)
----------------------------------------------------------------------

type B = {
	Model: Model,
	S: Vector3, -- échelle
	Count: number,
	Paint: Color3?, -- couleur de carrosserie (pièces marquées "Paint" : repeinture sans reconstruire)
}

local function newPart(b: B, className: string, name: string, size: Vector3, cf: CFrame, color: Color3, material: Enum.Material, shadow: boolean?): BasePart
	local p = Instance.new(className :: any) :: BasePart
	p.Name = name
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = shadow == true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Size = Vector3.new(math.max(0.05, size.X), math.max(0.05, size.Y), math.max(0.05, size.Z))
	p.CFrame = cf
	p.Color = color
	p.Material = material
	if b.Paint and color == b.Paint then
		p:SetAttribute("Paint", true)
	end
	p.Parent = b.Model
	b.Count += 1
	return p
end

local function P(b: B, x: number, y: number, z: number): Vector3
	return Vector3.new(x * b.S.X, y * b.S.Y, z * b.S.Z)
end

-- Bloc aligné : bornes x0..x1, y0..y1, z0..z1
local function box(b: B, name: string, x0: number, x1: number, y0: number, y1: number, z0: number, z1: number, color: Color3, material: Enum.Material?, shadow: boolean?): BasePart
	local s = b.S
	return newPart(b, "Part", name, Vector3.new(math.abs(x1 - x0) * s.X, math.abs(y1 - y0) * s.Y, math.abs(z1 - z0) * s.Z),
		CFrame.new(P(b, (x0 + x1) / 2, (y0 + y1) / 2, (z0 + z1) / 2)), color, material or M.SmoothPlastic, shadow)
end

-- Coin (WedgePart) : haut du côté +Z (dos) si `highBack`, sinon côté -Z
local function wedge(b: B, name: string, x0: number, x1: number, y0: number, y1: number, z0: number, z1: number, highBack: boolean, color: Color3, material: Enum.Material?, shadow: boolean?): BasePart
	local s = b.S
	local cf = CFrame.new(P(b, (x0 + x1) / 2, (y0 + y1) / 2, (z0 + z1) / 2))
	if not highBack then
		cf *= CFrame.Angles(0, PI, 0)
	end
	return newPart(b, "WedgePart", name, Vector3.new(math.abs(x1 - x0) * s.X, math.abs(y1 - y0) * s.Y, math.abs(z1 - z0) * s.Z), cf, color, material or M.SmoothPlastic, shadow)
end

-- Plaque inclinée entre deux points (y, z) du plan de côté, à l'abscisse x
local function slab(b: B, name: string, x: number, width: number, y0: number, z0: number, y1: number, z1: number, thick: number, color: Color3, material: Enum.Material?): BasePart
	local a = P(b, x, y0, z0)
	local c = P(b, x, y1, z1)
	local len = (c - a).Magnitude
	local cf = CFrame.lookAt((a + c) / 2, c)
	return newPart(b, "Part", name, Vector3.new(width * b.S.X, thick * b.S.Y, len), cf, color, material or M.SmoothPlastic)
end

-- Cylindre couché le long de X (roues, nez arrondi)
local function cylX(b: B, name: string, x: number, y: number, z: number, length: number, diameter: number, color: Color3, material: Enum.Material?, shadow: boolean?): BasePart
	local m = math.min(b.S.Y, b.S.Z)
	local p = newPart(b, "Part", name, Vector3.new(length * b.S.X, diameter * m, diameter * m), CFrame.new(P(b, x, y, z)), color, material or M.SmoothPlastic, shadow)
	;(p :: Part).Shape = Enum.PartType.Cylinder
	return p
end

-- Cylindre le long de Z (arêtes du toit, échappements, phares ronds)
local function cylZ(b: B, name: string, x: number, y: number, z: number, length: number, diameter: number, color: Color3, material: Enum.Material?): BasePart
	local m = math.min(b.S.X, b.S.Y)
	local p = newPart(b, "Part", name, Vector3.new(length * b.S.Z, diameter * m, diameter * m), CFrame.new(P(b, x, y, z)) * CFrame.Angles(0, PI / 2, 0), color, material or M.SmoothPlastic)
	;(p :: Part).Shape = Enum.PartType.Cylinder
	return p
end

----------------------------------------------------------------------
-- Éléments
----------------------------------------------------------------------

local function wheel(b: B, s: Spec, x: number, z: number, full: boolean, rim: Color3)
	local r = s.WheelD / 2
	local side = x > 0 and 1 or -1
	-- passage de roue (disque sombre juste devant le flanc)
	-- (faces décalées d'au moins 0,04 : aucun z-fighting)
	cylX(b, "WheelArch", side * (s.W / 2 - 0.03), r + 0.1, z, 0.1, s.WheelD + 0.55, TRIM, M.SmoothPlastic)
	cylX(b, "Tyre", x, r, z, s.TyreW, s.WheelD, TYRE, M.Rubber, true)
	cylX(b, "Rim", x + side * 0.14, r, z, s.TyreW - 0.2, s.WheelD * 0.6, rim, M.Metal)
	if full then
		cylX(b, "Hub", x + side * (s.TyreW / 2 - 0.05), r, z, 0.3, s.WheelD * 0.2, TRIM, M.Metal)
	end
end

local function plate(b: B, name: string, z: number, y: number, facing: number, full: boolean, text: string?)
	local p = box(b, name, -0.9, 0.9, y - 0.24, y + 0.24, z - 0.03, z + 0.03, PLATE, M.SmoothPlastic)
	if full then
		box(b, name .. "Band", -0.9, -0.66, y - 0.24, y + 0.24, z - 0.04 * facing - 0.025, z - 0.04 * facing + 0.025, PLATE_BAND, M.SmoothPlastic)
	end
	if text and text ~= "" then
		local gui = Instance.new("SurfaceGui")
		gui.Name = "PlateText"
		gui.Face = facing > 0 and Enum.NormalId.Back or Enum.NormalId.Front
		gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
		gui.PixelsPerStud = 40
		gui.LightInfluence = 1
		gui.MaxDistance = 60
		local label = Instance.new("TextLabel")
		label.BackgroundTransparency = 1
		label.Size = UDim2.new(0.8, 0, 1, 0)
		label.Position = UDim2.fromScale(0.16, 0)
		label.Font = Enum.Font.GothamBlack
		label.TextScaled = true
		label.TextColor3 = Color3.fromRGB(30, 30, 40)
		label.Text = string.upper(string.sub(text, 1, 8))
		label.Parent = gui
		gui.Parent = p
	end
end

local function interior(b: B, s: Spec, seatZ: number, seatTop: number)
	local wc = s.W - 2 * s.Inset
	local seatX = wc * 0.22
	for _, sx in ipairs({ -1, 1 }) do
		local x = sx * seatX
		box(b, "SeatCushion", x - 0.75, x + 0.75, seatTop - 0.35, seatTop, seatZ - 0.7, seatZ + 0.75, SEAT, M.Fabric)
		slab(b, "SeatBack", x, 1.5, seatTop, seatZ + 0.85, seatTop + 1.9, seatZ + 1.2, 0.35, SEAT, M.Fabric)
	end
	-- tableau de bord + volant (devant le conducteur, à gauche)
	box(b, "Dashboard", -wc / 2 + 0.1, wc / 2 - 0.1, s.Belt - 0.5, s.Belt + 0.05, s.Ws + 0.05, s.Ws + 0.85, TRIM, M.SmoothPlastic)
	local wheelZ = math.min(seatZ - 1.4, s.Ws + 1.2)
	local sw = cylZ(b, "SteeringWheel", -seatX, s.Belt + 0.25, wheelZ, 0.14, 1.05, TRIM, M.SmoothPlastic)
	sw.CFrame = sw.CFrame * CFrame.Angles(0, 0, math.rad(-25))
end

----------------------------------------------------------------------
-- Construction
----------------------------------------------------------------------

function CarModels.Build(carId: string?, color: any?, opts: any?): Model
	local options = type(opts) == "table" and opts or {}
	local kind = kindOf(carId)
	local s = SPECS[kind]
	local paint = CarModels.ColorOf(type(carId) == "string" and carId or kind, color)
	local full = options.Detail ~= "Parked"
	local scale = Vector3.new(1, 1, 1)
	if typeof(options.Scale) == "Vector3" then
		scale = options.Scale
	elseif type(options.Scale) == "number" and options.Scale > 0 then
		scale = Vector3.new(options.Scale, options.Scale, options.Scale)
	end
	local model = Instance.new("Model")
	model.Name = "Car_" .. kind
	local b: B = { Model = model, S = scale, Count = 0, Paint = paint }

	local dark = paint:Lerp(BLACK, 0.3)
	local light = paint:Lerp(WHITE, 0.35)
	local zF, zB = -s.L / 2, s.L / 2
	local wc = s.W - 2 * s.Inset
	local roofT = 0.34
	local style = s.Style
	local convertible = style == "Sports"
	local rim = CHROME
	if style == "Bubble" then
		rim = WHITE
	elseif style == "Sports" then
		rim = Color3.fromRGB(40, 40, 46)
	end

	-- boîte de collision (surélevée : les bordures passent dessous)
	local rootBottom = math.max(s.Clear, 0.95)
	local rootTop = math.max(s.Belt, rootBottom + 1.2)
	local root = box(b, "Root", -s.W / 2 + 0.1, s.W / 2 - 0.1, rootBottom, rootTop, zF + 0.2, zB - 0.2, paint, M.SmoothPlastic)
	root.Transparency = 1
	root.CanCollide = true
	root.CanQuery = true
	model.PrimaryPart = root
	root.PivotOffset = CFrame.new(0, -((rootBottom + rootTop) / 2) * scale.Y, 0)

	-- ░ bas de caisse : bloc + nez / arrière arrondis ░
	local lowH = s.Low - s.Clear
	local r = lowH / 2
	box(b, "Body", -s.W / 2, s.W / 2, s.Clear, s.Low, zF + r, zB - r, paint, M.SmoothPlastic, true)
	cylX(b, "NoseRound", 0, s.Clear + r, zF + r, s.W - 0.02, lowH, paint, M.SmoothPlastic, true)
	cylX(b, "TailRound", 0, s.Clear + r, zB - r, s.W - 0.02, lowH, paint, M.SmoothPlastic, true)
	-- pare-chocs (bas, sombres) + bas de caisse
	box(b, "BumperF", -s.W / 2 - 0.04, s.W / 2 + 0.04, s.Clear - 0.07, s.Clear + 0.36, zF - 0.04, zF + 0.9, TRIM, M.SmoothPlastic)
	box(b, "BumperR", -s.W / 2 - 0.04, s.W / 2 + 0.04, s.Clear - 0.07, s.Clear + 0.36, zB - 0.9, zB + 0.04, TRIM, M.SmoothPlastic)

	-- ░ haut de caisse : capot (coin), bas de l'habitacle, coffre ░
	local upH = s.Belt - s.Low
	local hoodZ0 = zF + 0.35
	local hf = upH * s.HoodFront
	if hf > 0.05 then
		box(b, "HoodBase", -s.W / 2, s.W / 2, s.Low, s.Low + hf, hoodZ0, s.Ws, paint, M.SmoothPlastic, true)
	end
	if upH - hf > 0.05 then
		wedge(b, "Hood", -s.W / 2, s.W / 2, s.Low + hf, s.Belt, hoodZ0, s.Ws, true, paint, M.SmoothPlastic, true)
	end
	local trunkEnd = zB - 0.35
	if convertible then
		-- baquet ouvert : plancher + flancs + tablier + capot arrière
		box(b, "CockpitFloor", -wc / 2, wc / 2, s.Low - 0.3, s.Low - 0.1, s.Ws, s.Rw, TRIM, M.Fabric)
		for _, sx in ipairs({ -1, 1 }) do
			box(b, "Flank", sx * wc / 2, sx * s.W / 2, s.Low, s.Belt, s.Ws, s.Rw, paint, M.SmoothPlastic, true)
		end
		box(b, "Cowl", -wc / 2, wc / 2, s.Low, s.Belt, s.Ws, s.Ws + 0.5, paint, M.SmoothPlastic)
		box(b, "Bulkhead", -wc / 2, wc / 2, s.Low, s.Belt - 0.05, s.Rw - 0.4, s.Rw, paint, M.SmoothPlastic)
		box(b, "RearDeck", -s.W / 2, s.W / 2, s.Low, s.Belt - s.TrunkDrop, s.Rw, trunkEnd, paint, M.SmoothPlastic, true)
		-- carénages derrière les appuie-tête
		for _, sx in ipairs({ -1, 1 }) do
			local x = sx * wc * 0.22
			wedge(b, "Fairing", x - 0.55, x + 0.55, s.Belt - s.TrunkDrop, s.Belt + 0.75, s.Rw, s.Rw + 1.6, false, paint, M.SmoothPlastic)
		end
	elseif style == "Pickup" then
		box(b, "CabLower", -s.W / 2, s.W / 2, s.Low, s.Belt, s.Ws, s.Rw + 0.1, paint, M.SmoothPlastic, true)
		-- benne : plancher, ridelles, hayon
		box(b, "BedFloor", -s.W / 2 + 0.35, s.W / 2 - 0.35, s.Low - 0.25, s.Low + 0.06, s.Rw + 0.1, trunkEnd - 0.25, TRIM, M.WoodPlanks)
		for _, sx in ipairs({ -1, 1 }) do
			box(b, "BedSide", sx * (s.W / 2 - 0.3), sx * s.W / 2, s.Low, s.Belt, s.Rw + 0.1, trunkEnd, paint, M.SmoothPlastic, true)
			box(b, "BedRail", sx * (s.W / 2 - 0.34), sx * (s.W / 2 + 0.02), s.Belt, s.Belt + 0.12, s.Rw + 0.1, trunkEnd, TRIM, M.SmoothPlastic)
		end
		box(b, "BedFront", -s.W / 2 + 0.33, s.W / 2 - 0.33, s.Low, s.Belt - 0.04, s.Rw + 0.1, s.Rw + 0.4, paint, M.SmoothPlastic)
		box(b, "Tailgate", -s.W / 2 + 0.33, s.W / 2 - 0.33, s.Low - 0.3, s.Belt - 0.04, trunkEnd - 0.3, trunkEnd, paint, M.SmoothPlastic, true)
	else
		box(b, "CabinLower", -s.W / 2, s.W / 2, s.Low, s.Belt, s.Ws, s.Rw, paint, M.SmoothPlastic, true)
		if trunkEnd - s.Rw > 0.1 then
			box(b, "Trunk", -s.W / 2, s.W / 2, s.Low, s.Belt - s.TrunkDrop, s.Rw, trunkEnd, paint, M.SmoothPlastic, true)
		end
	end

	-- ░ habitacle : vitres (pare-brise, côtés, lunette), montants, toit ░
	local seatTop = math.min(s.Low + 0.35, s.Roof - 3.05)
	local seatZ = s.R0 + (s.R1 - s.R0) * 0.42
	if style == "Van" then
		seatZ = s.R0 + 1.15
	elseif style == "Pickup" then
		seatZ = s.R0 + 1.05
	elseif convertible then
		seatZ = s.Rw - 1.6
		seatTop = s.Low + 0.15
	elseif style == "Limo" then
		seatZ = s.R0 + 1.2
	end
	if convertible then
		-- pare-brise court et incliné, cadre
		slab(b, "Windshield", 0, wc - 0.2, s.Belt, s.Ws + 0.1, s.Belt + 1.35, s.Ws + 1.05, 0.12, GLASS, M.Glass).Transparency = 0.35
		for _, sx in ipairs({ -1, 1 }) do
			slab(b, "WindshieldFrame", sx * (wc / 2 - 0.05), 0.14, s.Belt, s.Ws + 0.05, s.Belt + 1.42, s.Ws + 1.05, 0.2, TRIM, M.SmoothPlastic)
		end
		slab(b, "WindshieldTop", 0, wc - 0.1, s.Belt + 1.35, s.Ws + 1.02, s.Belt + 1.42, s.Ws + 1.1, 0.14, TRIM, M.SmoothPlastic)
	else
		local gTop = s.Roof - roofT
		local front = wedge(b, "GlassFront", -wc / 2, wc / 2, s.Belt, gTop, s.Ws, s.R0, true, GLASS, M.Glass)
		front.Transparency = 0.4
		local midEnd = s.R1
		if style == "Van" then
			midEnd = s.R0 + 2.7
			box(b, "CargoBox", -wc / 2, wc / 2, s.Belt, gTop, midEnd, s.R1, light, M.SmoothPlastic, true)
			-- petites vitres arrière du combi
			box(b, "CamperWindow", -wc / 2 - 0.03, wc / 2 + 0.03, s.Belt + 0.5, gTop - 0.6, midEnd + 3.2, midEnd + 5.4, GLASS, M.Glass).Transparency = 0.4
			box(b, "RearWindow", -wc / 2 + 0.5, wc / 2 - 0.5, s.Belt + 0.6, gTop - 0.5, s.R1 - 0.02, s.R1 + 0.03, GLASS, M.Glass).Transparency = 0.4
		end
		box(b, "GlassSide", -wc / 2, wc / 2, s.Belt, gTop, s.R0, midEnd, GLASS, M.Glass).Transparency = 0.4
		if s.Rw - s.R1 > 0.1 then
			wedge(b, "GlassRear", -wc / 2, wc / 2, s.Belt, gTop, s.R1, s.Rw, false, GLASS, M.Glass).Transparency = 0.4
		elseif style ~= "Van" then
			box(b, "RearWindow", -wc / 2 + 0.2, wc / 2 - 0.2, s.Belt + 0.2, gTop - 0.1, s.R1 - 0.07, s.R1 + 0.02, GLASS, M.Glass).Transparency = 0.4
			box(b, "RearPanel", -wc / 2, wc / 2, s.Belt, gTop, s.R1, s.R1 + 0.1, paint, M.SmoothPlastic)
		end
		-- toit (bords arrondis)
		local roofColor = paint
		if style == "Bubble" or style == "Van" then
			roofColor = WHITE:Lerp(paint, 0.08)
		end
		box(b, "Roof", -wc / 2 + 0.15, wc / 2 - 0.15, gTop, s.Roof, s.R0 - 0.08, s.R1 + 0.08, roofColor, M.SmoothPlastic, true)
		for _, sx in ipairs(if full then { -1, 1 } else {}) do
			cylZ(b, "RoofEdge", sx * (wc / 2 - 0.15), gTop + roofT / 2, (s.R0 + s.R1) / 2, s.R1 - s.R0 + 0.16, roofT + 0.02, roofColor, M.SmoothPlastic)
		end
		-- montants : A (le long du pare-brise), B, C
		for _, sx in ipairs({ -1, 1 }) do
			local x = sx * (wc / 2 + 0.03)
			slab(b, "PillarA", x, 0.12, s.Belt, s.Ws, gTop, s.R0, 0.3, dark, M.SmoothPlastic)
			if s.Rw - s.R1 > 0.1 then
				slab(b, "PillarC", x, 0.12, gTop, s.R1, s.Belt, s.Rw, 0.5, paint, M.SmoothPlastic)
			else
				box(b, "PillarC", x - 0.06, x + 0.06, s.Belt, gTop, s.R1 - 0.45, s.R1 + 0.07, paint, M.SmoothPlastic)
			end
			if not full then
				-- (version garée : pas de montant B)
			elseif style ~= "Van" then
				local bz = if s.Doors == 4 then s.R0 + (s.R1 - s.R0) * 0.46 else s.R0 + (s.R1 - s.R0) * 0.62
				box(b, "PillarB", x - 0.06, x + 0.06, s.Belt, gTop, bz - 0.18, bz + 0.18, TRIM, M.SmoothPlastic)
				if style == "Limo" then
					box(b, "PillarB", x - 0.06, x + 0.06, s.Belt, gTop, bz + 1.9, bz + 2.3, TRIM, M.SmoothPlastic)
				end
			else
				box(b, "PillarB", x - 0.06, x + 0.06, s.Belt, gTop, midEnd - 0.1, midEnd + 0.2, TRIM, M.SmoothPlastic)
			end
		end
		-- rétroviseurs
		for _, sx in ipairs({ -1, 1 }) do
			box(b, "Mirror", sx * (s.W / 2 - 0.05), sx * (s.W / 2 + 0.45), s.Belt + 0.05, s.Belt + 0.42, s.Ws + 0.25, s.Ws + 0.6, dark, M.SmoothPlastic)
		end
	end
	if convertible then
		for _, sx in ipairs({ -1, 1 }) do
			box(b, "Mirror", sx * (s.W / 2 - 0.05), sx * (s.W / 2 + 0.45), s.Belt + 0.05, s.Belt + 0.4, s.Ws + 0.3, s.Ws + 0.62, dark, M.SmoothPlastic)
		end
	end

	-- ░ ligne de ceinture chromée ░
	for _, sx in ipairs(if full then { -1, 1 } else {}) do
		box(b, "BeltTrim", sx * (s.W / 2 - 0.02), sx * (s.W / 2 + 0.07), s.Belt - 0.16, s.Belt - 0.06, s.Ws, if style == "Pickup" then s.Rw else s.Rw + 0.2, CHROME, M.Metal)
	end

	-- ░ roues ░
	for _, pos in ipairs(CarModels.WheelPositions(kind)) do
		wheel(b, s, pos.X, pos.Z, full, rim)
	end

	-- ░ phares, feux, calandre ░
	local lampY = s.Low + math.min(0.32, math.max(0.2, hf * 0.5))
	-- (haut du phare jamais au ras du dessus du capot)
	local lampTop = lampY + 0.24
	if math.abs(lampTop - (s.Low + hf)) < 0.05 then
		lampTop = s.Low + hf - 0.06
	end
	if style == "Bubble" then
		for _, sx in ipairs({ -1, 1 }) do
			local x = sx * s.W * 0.3
			cylZ(b, "HeadlightRim", x, s.Low + 0.42, hoodZ0 + 0.02, 0.2, 1.15, WHITE, M.SmoothPlastic)
			cylZ(b, "Headlight", x, s.Low + 0.42, hoodZ0 - 0.06, 0.1, 0.85, LAMP, M.Glass)
		end
	elseif hf < 0.1 then
		-- nez en coin (roadster) : phares couchés dans la pente du capot
		local function onHood(t: number): (number, number)
			return s.Low + t * (s.Belt - s.Low) + 0.03, hoodZ0 + t * (s.Ws - hoodZ0)
		end
		local ya, za = onHood(0.04)
		local yb, zb = onHood(0.16)
		for _, sx in ipairs({ -1, 1 }) do
			slab(b, "Headlight", sx * s.W * 0.32, s.W * 0.24, ya, za, yb, zb, 0.1, LAMP, M.Glass)
		end
	else
		for _, sx in ipairs({ -1, 1 }) do
			local x0, x1 = sx * s.W * 0.2, sx * s.W * 0.44
			box(b, "Headlight", math.min(x0, x1), math.max(x0, x1), lampY - 0.2, lampTop, hoodZ0 - 0.08, hoodZ0 + 0.1, LAMP, M.Glass)
			if full then
				box(b, "Indicator", sx * s.W * 0.44, sx * s.W * 0.485, lampY - 0.2, lampY + 0.12, hoodZ0 - 0.06, hoodZ0 + 0.1, AMBER, M.SmoothPlastic)
			end
		end
	end
	local tailY = math.min(s.Belt - s.TrunkDrop - 0.35, s.Low + 0.45)
	local tailZ = if style == "Pickup" or convertible then trunkEnd + 0.02 else math.max(trunkEnd, s.Rw)
	for _, sx in ipairs({ -1, 1 }) do
		local x0, x1 = sx * s.W * 0.3, sx * s.W * 0.48
		box(b, "Taillight", math.min(x0, x1), math.max(x0, x1), tailY - 0.24, tailY + 0.24, tailZ - 0.1, tailZ + 0.08, TAIL, M.Glass)
	end
	-- calandre (sur le nez) + badge
	local grilleY = s.Clear + lowH * 0.66
	box(b, "Grille", -s.W * 0.22, s.W * 0.22, grilleY - lowH * 0.22, grilleY + lowH * 0.22, zF - 0.04, zF + 0.3, TRIM, M.Metal)
	if full then
		for k = -1, 1, 2 do
			box(b, "GrilleBar", -s.W * 0.21, s.W * 0.21, grilleY + k * lowH * 0.08 - 0.03, grilleY + k * lowH * 0.08 + 0.03, zF - 0.07, zF + 0.1, CHROME, M.Metal)
		end
	end
	if full then
		cylZ(b, "Badge", 0, grilleY, zF - 0.08, 0.08, 0.34, if style == "Limo" or style == "Sports" then CHROME else Color3.fromRGB(255, 120, 170), M.Metal)
	end

	-- ░ plaques ░
	if full then
		plate(b, "PlateFront", zF - 0.06, s.Clear + 0.17, -1, full, nil)
	end
	plate(b, "PlateRear", zB + 0.06, s.Clear + lowH * 0.55, 1, full, options.Plate)

	-- ░ détails (joints de portes, poignées, échappement, intérieur) ░
	if full then
		local bz = if s.Doors == 4 then s.R0 + (s.R1 - s.R0) * 0.46 else s.R0 + (s.R1 - s.R0) * 0.62
		if style == "Van" then
			bz = s.R0 + 2.7
		elseif convertible then
			bz = s.Rw - 0.3
		end
		local doorFront = if convertible then s.Ws + 0.6 else s.Ws + 0.12
		for _, sx in ipairs({ -1, 1 }) do
			local x0, x1 = sx * (s.W / 2 - 0.02), sx * (s.W / 2 + 0.05)
			local lo, hi = math.min(x0, x1), math.max(x0, x1)
			box(b, "DoorSeam", lo, hi, s.Clear + 0.35, s.Belt - 0.15, doorFront - 0.03, doorFront + 0.03, dark, M.SmoothPlastic)
			box(b, "DoorSeam", lo, hi, s.Clear + 0.35, s.Belt - 0.15, bz - 0.03, bz + 0.03, dark, M.SmoothPlastic)
			local hx0, hx1 = sx * (s.W / 2 - 0.02), sx * (s.W / 2 + 0.14)
			box(b, "Handle", math.min(hx0, hx1), math.max(hx0, hx1), s.Belt - 0.5, s.Belt - 0.36, bz - 0.75, bz - 0.25, CHROME, M.Metal)
			if s.Doors == 4 and style ~= "Pickup" then
				local rz = if style == "Limo" then bz + 2.3 else s.Rw - 0.2
				box(b, "DoorSeam", lo, hi, s.Clear + 0.35, s.Belt - 0.15, rz - 0.03, rz + 0.03, dark, M.SmoothPlastic)
				box(b, "Handle", math.min(hx0, hx1), math.max(hx0, hx1), s.Belt - 0.5, s.Belt - 0.36, rz - 0.75, rz - 0.25, CHROME, M.Metal)
			elseif style == "Pickup" then
				local rz = s.Rw
				box(b, "Handle", math.min(hx0, hx1), math.max(hx0, hx1), s.Belt - 0.5, s.Belt - 0.36, rz - 0.75, rz - 0.25, CHROME, M.Metal)
			end
		end
		cylZ(b, "Exhaust", s.W * 0.28, s.Clear + 0.12, zB + 0.05, 0.7, 0.34, CHROME, M.Metal)
		interior(b, s, seatZ, seatTop)
	end

	-- ░ particularités de chaque modèle ░
	if style == "Bubble" then
		-- roue de secours ronde à l'arrière + petite barre "sourire" chromée
		cylZ(b, "SpareWheel", 0, s.Low + 0.55, trunkEnd + 0.25, 0.5, 1.5, TYRE, M.Rubber)
		cylZ(b, "SpareRim", 0, s.Low + 0.55, trunkEnd + 0.3, 0.52, 0.9, WHITE, M.SmoothPlastic)
		box(b, "Smile", -0.8, 0.8, s.Clear + 0.42, s.Clear + 0.5, zF - 0.08, zF + 0.1, CHROME, M.Metal)
	elseif style == "Hatch" then
		box(b, "Spoiler", -wc / 2 + 0.2, wc / 2 - 0.2, s.Roof - 0.1, s.Roof + 0.12, s.R1 - 0.1, s.R1 + 0.6, dark, M.SmoothPlastic)
	elseif style == "SUV" then
		for _, sx in ipairs({ -1, 1 }) do
			box(b, "RoofRail", sx * (wc / 2 - 0.45), sx * (wc / 2 - 0.25), s.Roof, s.Roof + 0.3, s.R0 + 0.4, s.R1 - 0.4, TRIM, M.Metal)
		end
		cylZ(b, "SpareWheel", 0, s.Belt + 0.5, trunkEnd + 0.4, 0.7, 2.2, TYRE, M.Rubber)
		cylZ(b, "SpareCover", 0, s.Belt + 0.5, trunkEnd + 0.5, 0.6, 1.7, paint, M.SmoothPlastic)
		box(b, "SkidPlate", -s.W * 0.3, s.W * 0.3, s.Clear - 0.05, s.Clear + 0.2, zF + 0.1, zF + 1.2, CHROME, M.Metal)
	elseif style == "Pickup" then
		box(b, "RollBar", -wc / 2 + 0.3, wc / 2 - 0.3, s.Belt + 0.9, s.Belt + 1.15, s.Rw + 0.55, s.Rw + 0.8, TRIM, M.Metal)
		for _, sx in ipairs({ -1, 1 }) do
			box(b, "RollBarPost", sx * (wc / 2 - 0.3) - 0.12, sx * (wc / 2 - 0.3) + 0.12, s.Belt, s.Belt + 1.15, s.Rw + 0.55, s.Rw + 0.8, TRIM, M.Metal)
		end
		box(b, "SkidPlate", -s.W * 0.3, s.W * 0.3, s.Clear - 0.05, s.Clear + 0.2, zF + 0.1, zF + 1.2, CHROME, M.Metal)
	elseif style == "Van" then
		-- bande de couleur bicolore + porte coulissante
		for _, sx in ipairs({ -1, 1 }) do
			box(b, "Stripe", sx * (wc / 2 - 0.02), sx * (wc / 2 + 0.05), s.Belt + 0.1, s.Belt + 0.45, s.R0 + 2.75, s.R1 - 0.2, paint, M.SmoothPlastic)
		end
		if full then
			box(b, "SlideRail", wc / 2 - 0.02, wc / 2 + 0.06, s.Roof - roofT - 0.75, s.Roof - roofT - 0.65, s.R0 + 2.8, s.R0 + 7, TRIM, M.Metal)
		end
	elseif style == "Sports" then
		-- aileron, prises d'air, doubles échappements
		box(b, "Wing", -s.W / 2 + 0.3, s.W / 2 - 0.3, s.Belt + 0.75, s.Belt + 0.9, trunkEnd - 1.1, trunkEnd - 0.2, dark, M.SmoothPlastic)
		for _, sx in ipairs({ -1, 1 }) do
			box(b, "WingPost", sx * s.W * 0.3 - 0.08, sx * s.W * 0.3 + 0.08, s.Belt - s.TrunkDrop, s.Belt + 0.76, trunkEnd - 0.75, trunkEnd - 0.5, dark, M.SmoothPlastic)
			box(b, "SideIntake", sx * (s.W / 2 - 0.02), sx * (s.W / 2 + 0.13), s.Clear + 0.45, s.Low - 0.1, s.Rw - 0.2, s.Rw + 0.9, TRIM, M.Metal)
		end
		cylZ(b, "Exhaust2", -s.W * 0.28, s.Clear + 0.12, zB + 0.05, 0.7, 0.34, CHROME, M.Metal)
		slab(b, "HoodStripe", 0, 0.7, s.Low + 0.03, hoodZ0 + 0.3, s.Belt + 0.03, s.Ws - 0.05, 0.04, WHITE, M.SmoothPlastic)
	elseif style == "Limo" then
		for _, sx in ipairs({ -1, 1 }) do
			box(b, "ChromeSill", sx * (s.W / 2 - 0.02), sx * (s.W / 2 + 0.13), s.Clear + 0.1, s.Clear + 0.22, zF + 1.8, zB - 1.8, CHROME, M.Metal)
		end
		cylZ(b, "Ornament", 0, s.Belt - 0.02, hoodZ0 + 0.6, 0.3, 0.3, CHROME, M.Metal)
	end

	-- attributs (siège du conducteur : repère du pivot)
	local seatX = -(s.W - 2 * s.Inset) * 0.22
	model:SetAttribute("CarId", type(carId) == "string" and carId or kind)
	model:SetAttribute("CarKind", kind)
	model:SetAttribute("Length", s.L * scale.Z)
	model:SetAttribute("Width", s.W * scale.X)
	model:SetAttribute("Height", CarModels.Dimensions(kind).Y * scale.Y)
	model:SetAttribute("WheelRadius", s.WheelD / 2 * math.min(scale.Y, scale.Z))
	model:SetAttribute("SeatCF", CFrame.new(P(b, seatX, seatTop, seatZ)))
	model:SetAttribute("PartCount", b.Count)
	return model
end

return CarModels
