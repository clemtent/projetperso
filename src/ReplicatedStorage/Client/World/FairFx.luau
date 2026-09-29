--[[
	FairFx (ModuleScript)
	Emplacement : ReplicatedStorage > Client > World > FairFx

	🎡 FÊTE FORAINE + 🍦 NOURRITURE de Dopamine Town, côté CLIENT (v9.8, FAIR98).
	Le serveur (TownFair) ne pose que le sol, les SIÈGES des manèges, les
	bornes "Monter" / "Commander", l'arène et les autos tamponneuses. Ici :
	  - tout le DÉCOR de la fête (derrière la mairie) : arche d'entrée à
	    ampoules, clôture, allée en planches, guirlandes lumineuses, bancs,
	    stands de nourriture (auvents rayés, aliments exposés, vendeurs
	    PNJ), pêche aux canards, et les 6 manèges :
	      🎡 grande roue (2 jantes, rayons, 10 nacelles qui restent droites),
	      🎠 manège à chevaux (auvent rayé, 10 chevaux qui montent et
	         descendent, 2 carrosses), ☕ tasses (plateau + 5 tasses qui
	         tournent sur elles-mêmes, théière), 🎢 chaises volantes (les
	         chaises s'écartent avec la vitesse), 🗼 tour de chute (nacelle
	         annulaire qui monte, tourne, et redescend doucement),
	      🚗 autos tamponneuses (toit, perches, pare-chocs en caoutchouc) ;
	  - le COIN GOURMAND près de l'arrivée (food truck, stands, tables) ;
	  - le MOUVEMENT : même pose que le serveur (Shared/FairRides, fonction
	    de l'heure du serveur). Les sièges du serveur (invisibles) sont
	    déplacés localement AVEC le décor : un avatar assis suit sa nacelle
	    sans à-coup. Le manège où l'on est assis est animé à CHAQUE image
	    (RenderStepped), les autres 30 fois / s, et rien au loin ;
	  - la CONDUITE des autos tamponneuses (VehicleSeat : ZQSD / flèches /
	    joystick ; courant coupé pendant l'embarquement) ;
	  - la NOURRITURE : invites des stands -> menu (prix, boost, durée) ->
	    achat (remote "Food") ; l'aliment en main : bouton "🍴 Croquer",
	    bras qui porte l'aliment à la bouche (pour TOUS les mangeurs
	    visibles, d'après l'attribut "BiteAt"), miettes ; badge du boost
	    "🍦 x1,5 · 1:42" (ScreenGui "FairGui").
	Tout est ancré (sauf les pièces soudées aux autos), sans son, lueurs
	douces (attribut "NightGlow" : TownAtmosphere, la nuit seulement), 0
	vraie lumière. Construction en FLUX : quand l'avatar est à moins de
	BUILD_R studs, un morceau par image ; tout est détruit au-delà de DROP_R.

	API (TownClient, via optionalModule) :
	  FairFx.Start(options?)  options.Toast = fn(texte, couleur?) (toast du HUD)
	  FairFx.Step(dt)         à chaque image (30 Hz au plus ici)
	  FairFx.Stop()           à la sortie (tout est détruit, bras remis)
	  FairFx.Debug() -> table
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local ProximityPromptService = game:GetService("ProximityPromptService")

local Client = script.Parent.Parent
local UIUtil = require(Client.UIUtil)
local ClientState = require(Client.ClientState)
local Config = require(ReplicatedStorage.Shared.Config)
local Locale = require(ReplicatedStorage.Shared.Locale)
local NumberFormatter = require(ReplicatedStorage.Shared.NumberFormatter)
local Net = require(ReplicatedStorage.Shared.Net)
local FairRides = require(ReplicatedStorage.Shared.FairRides)
local FoodRules = require(ReplicatedStorage.Shared.FoodRules)
local FoodModels = require(ReplicatedStorage.Shared.FoodModels)

local FairFx = {}

local LocalPlayer = Players.LocalPlayer

local STEP = 1 / 30
local BUILD_R = 300 -- (studs) du centre de la fête : on construit
local DROP_R = 380 -- ... au-delà : on détruit
local ANIM_R = 230 -- manèges animés
local NPC_R = 70 -- vendeurs animés
local CORNER_BUILD_R = 220
local CORNER_DROP_R = 290
local MENU_RANGE = 16
local TAU = math.pi * 2

local M = Enum.Material
local UP = Vector3.new(0, 1, 0)
local VERTICAL = CFrame.Angles(0, 0, math.rad(90)) -- cylindre debout (axe X -> Y)
local BALL = Enum.PartType.Ball
local CYL = Enum.PartType.Cylinder

local PINK = Color3.fromRGB(255, 132, 180)
local HOT = Color3.fromRGB(236, 72, 140)
local CREAM = Color3.fromRGB(255, 244, 226)
local GOLD = Color3.fromRGB(236, 196, 96)
local WHITE = Color3.fromRGB(255, 255, 255)
local MINT = Color3.fromRGB(128, 222, 190)
local SKY = Color3.fromRGB(126, 196, 255)
local LILAC = Color3.fromRGB(186, 150, 246)
local LEMON = Color3.fromRGB(255, 222, 110)
local STEEL = Color3.fromRGB(96, 100, 120)
local STEEL_LIGHT = Color3.fromRGB(196, 200, 214)
local WOOD = Color3.fromRGB(186, 134, 90)
local WOOD_DARK = Color3.fromRGB(140, 98, 66)
local INK = Color3.fromRGB(92, 58, 96)
local BULB = Color3.fromRGB(255, 232, 180)
local PALETTE = { PINK, SKY, LEMON, MINT, LILAC, Color3.fromRGB(255, 170, 120) }

local state: any = nil

----------------------------------------------------------------------
-- Fabrique de pièces (locales)
----------------------------------------------------------------------

local function newPart(parent: Instance, name: string, size: Vector3, cf: CFrame, color: Color3, material: Enum.Material?, shape: Enum.PartType?, className: string?): BasePart
	local p = Instance.new((className or "Part") :: any) :: BasePart
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
	if shape then
		(p :: Part).Shape = shape
	end
	p.Parent = parent
	return p
end

-- Pièce sur laquelle on marche / contre laquelle on bute (localement)
local function solid(p: BasePart): BasePart
	p.CanCollide = true
	p.CastShadow = true
	return p
end

-- Ampoule : mate le jour, Neon la nuit (TownAtmosphere, attribut NightGlow)
local function glow(p: BasePart): BasePart
	p:SetAttribute("NightGlow", true)
	return p
end

local function rodCF(a: Vector3, b: Vector3): CFrame
	return CFrame.lookAt((a + b) / 2, b) * CFrame.Angles(0, math.rad(90), 0)
end

local function rod(parent: Instance, name: string, a: Vector3, b: Vector3, d: number, color: Color3, material: Enum.Material?): BasePart
	return newPart(parent, name, Vector3.new((b - a).Magnitude, d, d), rodCF(a, b), color, material or M.Metal, CYL)
end

local function beamCF(a: Vector3, b: Vector3): CFrame
	local dir = b - a
	if math.abs(dir.Unit.Y) > 0.98 then
		return CFrame.new((a + b) / 2) * CFrame.Angles(math.rad(90), 0, 0)
	end
	return CFrame.lookAt((a + b) / 2, b)
end

local function beam(parent: Instance, name: string, a: Vector3, b: Vector3, w: number, h: number, color: Color3, material: Enum.Material?): BasePart
	return newPart(parent, name, Vector3.new(w, h, (b - a).Magnitude), beamCF(a, b), color, material or M.Metal)
end

-- Triangle rectangle (WedgePart) : angle droit en p0, côtés le long de u (l1) et v (l2)
local function triCF(p0: Vector3, u: Vector3, v: Vector3, l1: number, l2: number, t: number): (Vector3, CFrame)
	local Z = -v
	local X = u:Cross(Z)
	return Vector3.new(t, l1, l2), CFrame.fromMatrix(p0 + u * (l1 / 2) + v * (l2 / 2), X, u, Z)
end

-- Panneau (SurfaceGui sur la face avant d'une pièce) avec un texte
local function sign(p: BasePart, text: string, textColor: Color3, bg: Color3?, font: Enum.Font?): TextLabel
	local gui = Instance.new("SurfaceGui")
	gui.Name = "Sign"
	gui.Face = Enum.NormalId.Front
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 40
	gui.LightInfluence = 0.5
	gui.MaxDistance = 260
	gui.Parent = p
	local frame = Instance.new("Frame")
	frame.Size = UDim2.fromScale(1, 1)
	frame.BackgroundColor3 = bg or WHITE
	frame.BackgroundTransparency = bg and 0 or 1
	frame.BorderSizePixel = 0
	frame.Parent = gui
	local label = Instance.new("TextLabel")
	label.Name = "Text"
	label.BackgroundTransparency = 1
	label.Position = UDim2.fromScale(0.04, 0.1)
	label.Size = UDim2.fromScale(0.92, 0.8)
	label.Font = font or Enum.Font.FredokaOne
	label.Text = text
	label.TextColor3 = textColor
	label.TextScaled = true
	label.Parent = frame
	return label
end

----------------------------------------------------------------------
-- Manèges : pièces MOBILES rangées par groupe (FairRides.Pose)
----------------------------------------------------------------------

type RideFx = {
	Def: any,
	Base: CFrame,
	Model: Model,
	Parts: { BasePart },
	Locals: { CFrame },
	Group: { number },
	Frames: { CFrame },
	Groups: { CFrame },
	Seats: { BasePart },
	SeatIndex: { number },
	SeatFrames: { CFrame },
	SeatCheck: number,
	Extra: any,
}

local function newRide(folder: Instance, def: any, F: CFrame): RideFx
	local model = Instance.new("Model")
	model.Name = def.Id
	model.Parent = folder
	local r: RideFx = {
		Def = def,
		Base = FairRides.RideBase(F, def),
		Model = model,
		Parts = {},
		Locals = {},
		Group = {},
		Frames = {},
		Groups = {},
		Seats = {},
		SeatIndex = {},
		SeatFrames = {},
		SeatCheck = 0,
		Extra = nil,
	}
	FairRides.Pose(def, workspace:GetServerTimeNow(), r.Groups)
	return r
end

-- Pièce fixe du manège (repère de la Base)
local function fixed(r: RideFx, name: string, size: Vector3, loc: CFrame, color: Color3, material: Enum.Material?, shape: Enum.PartType?, className: string?): BasePart
	return newPart(r.Model, name, size, r.Base * loc, color, material, shape, className)
end

-- Pièce qui suit le groupe `g` (loc = repère du groupe)
local function moving(r: RideFx, g: number, name: string, size: Vector3, loc: CFrame, color: Color3, material: Enum.Material?, shape: Enum.PartType?, className: string?): BasePart
	local world = r.Base * (r.Groups[g] or CFrame.identity) * loc
	local p = newPart(r.Model, name, size, world, color, material, shape, className)
	table.insert(r.Parts, p)
	table.insert(r.Locals, loc)
	table.insert(r.Group, g)
	table.insert(r.Frames, world)
	return p
end

-- Sièges du serveur (Fair > Rides > <Id> > RideSeat)
local function findSeats(r: RideFx, fairFolder: Instance)
	table.clear(r.Seats)
	table.clear(r.SeatIndex)
	table.clear(r.SeatFrames)
	local rides = fairFolder:FindFirstChild("Rides")
	local folder = rides and rides:FindFirstChild(r.Def.Id)
	if not folder then
		return
	end
	for _, d in ipairs(folder:GetChildren()) do
		local index = d:GetAttribute("SeatIndex")
		if d:IsA("Seat") and type(index) == "number" then
			table.insert(r.Seats, d)
			table.insert(r.SeatIndex, index)
		end
	end
end

local function stepRide(r: RideFx, t: number)
	local kind = r.Def.Kind
	if kind == "Bumper" then
		return
	end
	local groups = r.Groups
	FairRides.Pose(r.Def, t, groups)
	local frames, locals, group, base = r.Frames, r.Locals, r.Group, r.Base
	for i = 1, #frames do
		frames[i] = base * groups[group[i]] * locals[i]
	end
	if #frames > 0 then
		workspace:BulkMoveTo(r.Parts, frames, Enum.BulkMoveMode.FireCFrameChanged)
	end
	local seats = r.Seats
	if #seats > 0 then
		local seatFrames, idx = r.SeatFrames, r.SeatIndex
		for i = 1, #seats do
			seatFrames[i] = base * FairRides.SeatLocal(kind, idx[i], groups)
		end
		workspace:BulkMoveTo(seats, seatFrames, Enum.BulkMoveMode.FireCFrameChanged)
	end
	if r.Extra and r.Extra.Step then
		r.Extra.Step(t)
	end
end

----------------------------------------------------------------------
-- 🎡 Grande roue
----------------------------------------------------------------------

local function buildFerris(r: RideFx)
	local R, hub, N = FairRides.FERRIS_R, FairRides.FERRIS_HUB, FairRides.FERRIS_N
	local frame = Color3.fromRGB(250, 250, 255)
	-- quai d'embarquement + 2 marches
	solid(fixed(r, "Deck", Vector3.new(16, 0.6, 7), CFrame.new(0, 0.3, -1), Color3.fromRGB(200, 186, 226), M.WoodPlanks))
	solid(fixed(r, "Step", Vector3.new(6, 0.3, 1.2), CFrame.new(0, 0.15, -5.1), Color3.fromRGB(214, 202, 236), M.WoodPlanks))
	-- deux chevalets en A (plans z = ±4,6) + entretoises, axe
	for _, sz in ipairs({ -1, 1 }) do
		local top = Vector3.new(0, hub, sz * 3.4)
		for _, sx in ipairs({ -1, 1 }) do
			local foot = Vector3.new(sx * 12.5, 0, sz * 6.2)
			local leg = beam(r.Model, "Leg", r.Base * foot, r.Base * top, 0.7, 0.7, frame, M.Metal)
			leg.CastShadow = true
			solid(fixed(r, "Foot", Vector3.new(1.8, 0.5, 1.8), CFrame.new(foot + Vector3.new(0, 0.25, 0)), STEEL, M.Concrete))
		end
		beam(r.Model, "Brace", r.Base * Vector3.new(-7.2, 8.8, sz * 5.1), r.Base * Vector3.new(7.2, 8.8, sz * 5.1), 0.45, 0.45, frame, M.Metal)
		beam(r.Model, "Brace", r.Base * Vector3.new(-3.6, 15.1, sz * 4.3), r.Base * Vector3.new(3.6, 15.1, sz * 4.3), 0.4, 0.4, frame, M.Metal)
	end
	fixed(r, "Axle", Vector3.new(7.4, 0.9, 0.9), CFrame.new(0, hub, 0) * CFrame.Angles(0, math.rad(90), 0), STEEL, M.Metal, CYL)
	-- ce qui TOURNE (groupe 1 : repère du moyeu)
	for _, z in ipairs({ -2.2, 2.2 }) do
		moving(r, 1, "Hub", Vector3.new(0.6, 3.2, 3.2), CFrame.new(0, 0, z) * CFrame.Angles(0, math.rad(90), 0), HOT, M.Metal, CYL)
		local segs = 20
		for i = 0, segs - 1 do
			local a = (i + 0.5) / segs * TAU
			local rr = R + 0.3
			local p = Vector3.new(math.sin(a) * rr, -math.cos(a) * rr, z)
			local tangent = Vector3.new(math.cos(a), math.sin(a), 0)
			local len = TAU * rr / segs + 0.12
			moving(r, 1, "Rim", Vector3.new(0.45, 0.55, len), CFrame.lookAt(p, p + tangent, Vector3.new(0, 0, 1)), frame, M.Metal)
			-- anneau intérieur décoratif
			local ri = R * 0.52
			local pi = Vector3.new(math.sin(a) * ri, -math.cos(a) * ri, z)
			moving(r, 1, "Ring", Vector3.new(0.3, 0.3, TAU * ri / segs + 0.08), CFrame.lookAt(pi, pi + tangent, Vector3.new(0, 0, 1)), PINK, M.Metal)
			if z < 0 then
				-- ampoules sur la jante avant
				local b = Vector3.new(math.sin(a) * (R + 0.8), -math.cos(a) * (R + 0.8), z)
				glow(moving(r, 1, "Bulb", Vector3.new(0.42, 0.42, 0.42), CFrame.new(b), if i % 2 == 0 then BULB else Color3.fromRGB(255, 190, 214), M.SmoothPlastic, BALL))
			end
		end
		for k = 0, N - 1 do
			local a = k / N * TAU
			local tip = Vector3.new(math.sin(a) * R, -math.cos(a) * R, z)
			local mid = tip / 2 + Vector3.new(0, 0, 0)
			moving(r, 1, "Spoke", Vector3.new(0.22, 0.22, R), CFrame.lookAt(mid, tip, Vector3.new(0, 0, 1)), frame, M.Metal)
		end
	end
	-- axes des nacelles (entre les deux jantes)
	for k = 0, N - 1 do
		local a = k / N * TAU
		local p = Vector3.new(math.sin(a) * R, -math.cos(a) * R, 0)
		moving(r, 1, "Pin", Vector3.new(4.7, 0.3, 0.3), CFrame.new(p) * CFrame.Angles(0, math.rad(90), 0), STEEL_LIGHT, M.Metal, CYL)
	end
	-- nacelles (groupes 2..N+1 : repère = axe de la nacelle, toujours droit)
	local drop = FairRides.FERRIS_DROP
	for k = 1, N do
		local g = 1 + k
		local color = PALETTE[(k - 1) % #PALETTE + 1]
		for _, z in ipairs({ -1.5, 1.5 }) do
			moving(r, g, "Hanger", Vector3.new(0.18, 1.25, 0.18), CFrame.new(0, -0.62, z), STEEL, M.Metal)
		end
		moving(r, g, "Roof", Vector3.new(4.9, 0.7, 3.8), CFrame.new(0, -1.5, 0), color, M.SmoothPlastic, BALL)
		moving(r, g, "RoofRim", Vector3.new(4.9, 0.22, 3.6), CFrame.new(0, -1.62, 0), WHITE, M.SmoothPlastic)
		for _, sx in ipairs({ -1, 1 }) do
			for _, z in ipairs({ -1.58, 1.58 }) do
				moving(r, g, "Post", Vector3.new(0.16, drop - 1.75, 0.16), CFrame.new(sx * 2.2, -1.72 - (drop - 1.75) / 2, z), WHITE, M.Metal)
			end
			-- banquette + dossier (face au centre de la nacelle)
			moving(r, g, "Bench", Vector3.new(1.1, 0.45, 3), CFrame.new(sx * 1.55, -drop + 1.2, 0), CREAM, M.Fabric)
			moving(r, g, "Back", Vector3.new(0.3, 1.5, 3), CFrame.new(sx * 2.05, -drop + 1.95, 0), color, M.SmoothPlastic)
		end
		moving(r, g, "Floor", Vector3.new(4.6, 0.3, 3.4), CFrame.new(0, -drop + 0.15, 0), Color3.fromRGB(236, 232, 244), M.Metal)
		for _, z in ipairs({ -1.64, 1.64 }) do
			moving(r, g, "Panel", Vector3.new(4.5, 1.2, 0.14), CFrame.new(0, -drop + 0.9, z), color, M.SmoothPlastic)
		end
		moving(r, g, "Under", Vector3.new(3.4, 0.5, 2.4), CFrame.new(0, -drop - 0.15, 0), color, M.SmoothPlastic, BALL)
	end
end

----------------------------------------------------------------------
-- 🎠 Manège à chevaux (plus léger que celui de la place, autres couleurs)
----------------------------------------------------------------------

local HORSES = {
	{ Body = Color3.fromRGB(252, 250, 246), Mane = Color3.fromRGB(120, 180, 255), Saddle = Color3.fromRGB(56, 96, 196) },
	{ Body = Color3.fromRGB(96, 70, 60), Mane = Color3.fromRGB(252, 240, 220), Saddle = Color3.fromRGB(214, 60, 96) },
	{ Body = Color3.fromRGB(255, 220, 236), Mane = Color3.fromRGB(236, 72, 140), Saddle = Color3.fromRGB(150, 70, 170) },
	{ Body = Color3.fromRGB(200, 226, 255), Mane = Color3.fromRGB(255, 214, 96), Saddle = Color3.fromRGB(40, 140, 120) },
	{ Body = Color3.fromRGB(236, 226, 206), Mane = Color3.fromRGB(150, 110, 80), Saddle = Color3.fromRGB(214, 90, 60) },
}

local function horse(r: RideFx, g: number, colors: any, seed: number)
	local body, mane = colors.Body, colors.Mane
	moving(r, g, "Body", Vector3.new(2.5, 1.2, 1.2), CFrame.Angles(0, math.rad(90), 0), body, M.SmoothPlastic, CYL)
	moving(r, g, "Chest", Vector3.new(1.3, 1.3, 1.3), CFrame.new(0, 0.08, -1.15), body, M.SmoothPlastic, BALL)
	moving(r, g, "Rump", Vector3.new(1.35, 1.35, 1.35), CFrame.new(0, 0.05, 1.1), body, M.SmoothPlastic, BALL)
	local neck = CFrame.new(0, 0.95, -1.55) * CFrame.Angles(math.rad(-28), 0, 0)
	moving(r, g, "Neck", Vector3.new(0.6, 1.7, 0.78), neck, body, M.SmoothPlastic)
	moving(r, g, "Mane", Vector3.new(0.22, 1.75, 0.3), neck * CFrame.new(0, 0.12, 0.42), mane, M.SmoothPlastic)
	local head = CFrame.new(0, 1.85, -2.2) * CFrame.Angles(math.rad(-18), 0, 0)
	moving(r, g, "Head", Vector3.new(0.6, 0.62, 1.3), head, body, M.SmoothPlastic)
	moving(r, g, "Muzzle", Vector3.new(0.55, 0.55, 0.55), head * CFrame.new(0, -0.08, -0.6), body, M.SmoothPlastic, BALL)
	moving(r, g, "Bridle", Vector3.new(0.66, 0.68, 0.1), head * CFrame.new(0, 0, -0.3), GOLD, M.Metal)
	moving(r, g, "Ears", Vector3.new(0.5, 0.3, 0.14), head * CFrame.new(0, 0.42, 0.42), body, M.SmoothPlastic)
	moving(r, g, "Saddle", Vector3.new(1, 0.25, 1.1), CFrame.new(0, 0.75, -0.05), colors.Saddle, M.Leather)
	moving(r, g, "Tail", Vector3.new(0.3, 1.3, 0.34), CFrame.new(0, -0.12, 1.85) * CFrame.Angles(math.rad(-25), 0, 0), mane, M.SmoothPlastic)
	local lift = (seed % 3) * 8
	for _, l in ipairs({ { -0.33, -1.1, 70 - lift }, { 0.33, -1.1, 42 + lift }, { -0.33, 1.1, -34 }, { 0.33, 1.1, -22 - lift / 2 } }) do
		local pivot = CFrame.new(l[1], -0.4, l[2]) * CFrame.Angles(math.rad(l[3]), 0, 0)
		moving(r, g, "Leg", Vector3.new(0.28, 1.5, 0.28), pivot * CFrame.new(0, -0.72, 0), body, M.SmoothPlastic)
	end
end

local function buildCarousel(r: RideFx)
	local blue = Color3.fromRGB(96, 150, 236)
	local top = 0 -- (la Base est déjà le dessus du socle : FairRides, y = 1,2)
	-- socle (fixe, SOUS la Base) : deux marches
	solid(fixed(r, "Plinth", Vector3.new(0.6, 20.4, 20.4), CFrame.new(0, -0.9, 0) * VERTICAL, Color3.fromRGB(196, 206, 230), M.Slate, CYL))
	solid(fixed(r, "Platform", Vector3.new(0.6, 18.6, 18.6), CFrame.new(0, -0.3, 0) * VERTICAL, Color3.fromRGB(226, 232, 246), M.Marble, CYL))
	local Y = CFrame.new(0, top, 0)
	solid(fixed(r, "Deck", Vector3.new(0.3, 16.8, 16.8), Y * CFrame.new(0, 0.15, 0) * VERTICAL, Color3.fromRGB(214, 164, 116), M.WoodPlanks, CYL))
	solid(fixed(r, "Drum", Vector3.new(7.8, 3.6, 3.6), Y * CFrame.new(0, 4.1, 0) * VERTICAL, CREAM, M.SmoothPlastic, CYL))
	fixed(r, "Ceiling", Vector3.new(0.25, 17.7, 17.7), Y * CFrame.new(0, 8.025, 0) * VERTICAL, CREAM, M.SmoothPlastic, CYL)
	local function ring(n: number, i: number, rad: number, y: number): CFrame
		local a = (i + 0.5) / n * TAU
		local p = Vector3.new(math.sin(a) * rad, y + top, math.cos(a) * rad)
		return CFrame.lookAt(p, p + Vector3.new(p.X, 0, p.Z))
	end
	-- jupe, pilastres du fût, bandeau à ampoules, auvent rayé bleu / crème
	for i = 0, 11 do
		moving(r, 1, "Skirt", Vector3.new(4.5, 0.6, 0.12), ring(12, i, 8.45, 0.12), i % 2 == 0 and GOLD or blue, i % 2 == 0 and M.Metal or M.SmoothPlastic)
		local board = ring(12, i, 9.05, 7.6)
		moving(r, 1, "Board", Vector3.new(4.82, 1.1, 0.3), board, i % 2 == 0 and CREAM or blue, M.SmoothPlastic)
		for _, x in ipairs({ -1.2, 1.2 }) do
			glow(moving(r, 1, "Bulb", Vector3.new(0.32, 0.32, 0.32), board * CFrame.new(x, 0, -0.25), BULB, M.SmoothPlastic, BALL))
		end
	end
	for i = 0, 7 do
		moving(r, 1, "Pilaster", Vector3.new(0.28, 6.5, 0.28), ring(8, i, 1.95, 3.95), GOLD, M.Metal)
	end
	local e, y0, y1 = 9.35, 8.15 + top, 11.4 + top
	local apex = Vector3.new(0, y1, 0)
	local half = e * math.tan(math.pi / 12)
	for k = 0, 11 do
		local a = k / 12 * TAU
		local nrm = Vector3.new(math.sin(a), 0, math.cos(a))
		local side = UP:Cross(nrm).Unit
		local mid = nrm * e + Vector3.new(0, y0, 0)
		local w = apex - mid
		for _, sv in ipairs({ side, -side }) do
			local size, loc = triCF(mid, w.Unit, sv, w.Magnitude, half, 0.2)
			moving(r, 1, "Canopy", size, loc, k % 2 == 0 and blue or CREAM, M.Fabric, nil, "WedgePart")
		end
	end
	moving(r, 1, "Crown", Vector3.new(0.8, 1.6, 1.6), CFrame.new(0, y1, 0) * VERTICAL, GOLD, M.Metal, CYL)
	moving(r, 1, "CrownBall", Vector3.new(1.1, 1.1, 1.1), CFrame.new(0, y1 + 0.9, 0), PINK, M.SmoothPlastic, BALL)
	-- chevaux (groupes 2..11) + carrosses (plateau) + barres de laiton
	local horseIndex = 0
	for _, s in ipairs(FairRides.CarouselSpots()) do
		if s.Carriage then
			local tint = if horseIndex % 2 == 0 then PINK else LILAC
			local b = s.Base
			moving(r, 1, "CarriageFloor", Vector3.new(2.3, 0.3, 3.4), b * CFrame.new(0, 0.45, 0), GOLD, M.Metal)
			for _, sx in ipairs({ -1, 1 }) do
				moving(r, 1, "CarriageSide", Vector3.new(0.25, 1.4, 3.3), b * CFrame.new(sx * 1.08, 1.3, 0), tint, M.SmoothPlastic)
			end
			moving(r, 1, "CarriageBack", Vector3.new(2.1, 1.9, 0.3), b * CFrame.new(0, 1.55, 1.5), tint, M.SmoothPlastic)
			moving(r, 1, "CarriageSeat", Vector3.new(1.9, 0.45, 1), b * CFrame.new(0, 0.825, 0.85), CREAM, M.Fabric)
			moving(r, 1, "CarriageFront", Vector3.new(2.1, 1.2, 0.3), b * CFrame.new(0, 1.2, -1.5), tint, M.SmoothPlastic)
			moving(r, 1, "CarriageSwan", Vector3.new(0.9, 0.9, 0.9), b * CFrame.new(0, 2.1, -1.55), GOLD, M.Metal, BALL)
		else
			horseIndex += 1
			local k = s.Horse :: number
			moving(r, 1, "Pole", Vector3.new(7.6, 0.24, 0.24), CFrame.new(s.Pos.X, top + 4.1, s.Pos.Z) * VERTICAL, GOLD, M.Metal, CYL)
			horse(r, 1 + k, HORSES[(k - 1) % #HORSES + 1], k)
		end
	end
end

----------------------------------------------------------------------
-- ☕ Tasses
----------------------------------------------------------------------

local CUP_COLORS = { PINK, SKY, LEMON, MINT, LILAC }

local function buildCups(r: RideFx)
	local deckY = FairRides.CUPS_DECK
	solid(fixed(r, "Base", Vector3.new(deckY, 23, 23), CFrame.new(0, deckY / 2, 0) * VERTICAL, Color3.fromRGB(206, 214, 236), M.Slate, CYL))
	fixed(r, "Edge", Vector3.new(0.3, 23.4, 23.4), CFrame.new(0, 0.15, 0) * VERTICAL, WHITE, M.Marble, CYL)
	-- plateau qui tourne : rayons roses (groupe 1) + théière au centre
	local deck = Color3.fromRGB(255, 236, 244)
	moving(r, 1, "Deck", Vector3.new(0.2, 21, 21), CFrame.new(0, 0.1, 0) * VERTICAL, deck, M.SmoothPlastic, CYL)
	for i = 0, 5 do
		local a = i / 6 * TAU
		local d = Vector3.new(math.sin(a), 0, math.cos(a))
		local mid = d * 5.2 + Vector3.new(0, 0.22, 0)
		moving(r, 1, "Stripe", Vector3.new(1.1, 0.06, 10.2), CFrame.lookAt(mid, mid + d), Color3.fromRGB(255, 190, 214), M.SmoothPlastic)
	end
	moving(r, 1, "Teapot", Vector3.new(3.4, 3, 3.4), CFrame.new(0, 1.7, 0), WHITE, M.SmoothPlastic, BALL)
	moving(r, 1, "TeapotLid", Vector3.new(0.5, 1.8, 1.8), CFrame.new(0, 3.2, 0) * VERTICAL, PINK, M.SmoothPlastic, CYL)
	moving(r, 1, "TeapotKnob", Vector3.new(0.6, 0.6, 0.6), CFrame.new(0, 3.65, 0), GOLD, M.Metal, BALL)
	moving(r, 1, "Spout", Vector3.new(0.5, 1.8, 0.5), CFrame.new(1.9, 2.1, 0) * CFrame.Angles(0, 0, math.rad(-45)), WHITE, M.SmoothPlastic)
	moving(r, 1, "Handle", Vector3.new(0.35, 1.5, 0.35), CFrame.new(-1.85, 2, 0), PINK, M.SmoothPlastic)
	-- tasses (groupes 2..6)
	for k = 1, FairRides.CUPS_N do
		local g = 1 + k
		local color = CUP_COLORS[(k - 1) % #CUP_COLORS + 1]
		moving(r, g, "Saucer", Vector3.new(0.25, 5.2, 5.2), CFrame.new(0, 0.16, 0) * VERTICAL, WHITE, M.SmoothPlastic, CYL)
		moving(r, g, "CupFloor", Vector3.new(0.3, 4.2, 4.2), CFrame.new(0, 0.35, 0) * VERTICAL, color, M.SmoothPlastic, CYL)
		-- paroi : 10 panneaux (on voit dedans), bord doré
		local n = 10
		for i = 0, n - 1 do
			local a = (i + 0.5) / n * TAU
			local rr = 2.05
			local p = Vector3.new(math.sin(a) * rr, 1.35, math.cos(a) * rr)
			local w = TAU * rr / n + 0.1
			local wallCF = CFrame.lookAt(p, p + Vector3.new(p.X, 0, p.Z))
			moving(r, g, "Wall", Vector3.new(w, 1.9, 0.18), wallCF, color, M.SmoothPlastic)
			-- bord doré (un tronçon par panneau : on voit dans la tasse)
			moving(r, g, "Rim", Vector3.new(w + 0.02, 0.16, 0.3), wallCF * CFrame.new(0, 0.99, 0), GOLD, M.Metal)
			if i % 3 == 0 then
				moving(r, g, "Dot", Vector3.new(0.05, 0.5, 0.5), CFrame.lookAt(p, p + Vector3.new(p.X, 0, p.Z)) * CFrame.new(0, 0.1, -0.12) * CFrame.Angles(0, math.rad(90), 0), WHITE, M.SmoothPlastic, CYL)
			end
		end
		moving(r, g, "CupHandle", Vector3.new(0.35, 1.3, 0.35), CFrame.new(0, 1.4, 2.45), color, M.SmoothPlastic)
		moving(r, g, "Wheel", Vector3.new(0.18, 1.1, 1.1), CFrame.new(0, 1.8, 0) * CFrame.Angles(0, 0, 0) * VERTICAL, WHITE, M.SmoothPlastic, CYL)
		moving(r, g, "WheelPost", Vector3.new(0.2, 1.3, 0.2), CFrame.new(0, 1.15, 0), GOLD, M.Metal)
		for _, sx in ipairs({ -1, 1 }) do
			moving(r, g, "Bench", Vector3.new(0.9, 0.5, 2.2), CFrame.new(sx * 1.25, 0.95, 0), CREAM, M.Fabric)
		end
	end
end

----------------------------------------------------------------------
-- 🎢 Chaises volantes
----------------------------------------------------------------------

local function buildSwings(r: RideFx)
	local topY, r0, L = FairRides.SWING_TOP, FairRides.SWING_R0, FairRides.SWING_L
	solid(fixed(r, "Plinth", Vector3.new(0.8, 6.4, 6.4), CFrame.new(0, 0.4, 0) * VERTICAL, Color3.fromRGB(206, 214, 236), M.Slate, CYL))
	solid(fixed(r, "Tower", Vector3.new(topY + 1, 1.8, 1.8), CFrame.new(0, (topY + 1) / 2, 0) * VERTICAL, WHITE, M.Metal, CYL))
	for i, y in ipairs({ 2.5, 5.5, 8.5 }) do
		fixed(r, "TowerBand", Vector3.new(0.5, 2.1, 2.1), CFrame.new(0, y, 0) * VERTICAL, PALETTE[i], M.SmoothPlastic, CYL)
	end
	-- sol d'embarquement (anneau de dalles)
	for i = 0, 11 do
		local a = (i + 0.5) / 12 * TAU
		-- (une dalle sur deux un peu plus haute : jamais coplanaires aux coins)
		local p = Vector3.new(math.sin(a) * 8.5, if i % 2 == 0 then 0.06 else 0.1, math.cos(a) * 8.5)
		fixed(r, "Pad", Vector3.new(4.2, 0.12, 3.2), CFrame.lookAt(p, p + Vector3.new(p.X, 0, p.Z)), i % 2 == 0 and Color3.fromRGB(236, 226, 250) or Color3.fromRGB(214, 226, 250), M.Slate)
	end
	-- dessus qui tourne : chapeau rayé (12 pans), bandeau à ampoules
	local e = r0 + 0.8
	local y0, y1 = topY + 0.2, topY + 3.6
	local apex = Vector3.new(0, y1, 0)
	local half = e * math.tan(math.pi / 12)
	for k = 0, 11 do
		local a = k / 12 * TAU
		local nrm = Vector3.new(math.sin(a), 0, math.cos(a))
		local side = UP:Cross(nrm).Unit
		local mid = nrm * e + Vector3.new(0, y0, 0)
		local w = apex - mid
		for _, sv in ipairs({ side, -side }) do
			local size, loc = triCF(mid, w.Unit, sv, w.Magnitude, half, 0.2)
			moving(r, 1, "Hat", size, loc, k % 2 == 0 and HOT or CREAM, M.Fabric, nil, "WedgePart")
		end
		local bp = CFrame.lookAt(nrm * (e + 0.05) + Vector3.new(0, y0 - 0.45, 0), nrm * (e + 1) + Vector3.new(0, y0 - 0.45, 0))
		moving(r, 1, "Band", Vector3.new(2 * half + 0.1, 0.9, 0.2), bp, k % 2 == 0 and CREAM or PINK, M.SmoothPlastic)
		glow(moving(r, 1, "Bulb", Vector3.new(0.34, 0.34, 0.34), bp * CFrame.new(0, 0, -0.18), BULB, M.SmoothPlastic, BALL))
	end
	moving(r, 1, "Crown", Vector3.new(0.9, 0.9, 0.9), CFrame.new(0, y1 + 0.3, 0), GOLD, M.Metal, BALL)
	-- chaises (groupes 2..13 : repère = bout des chaînes, penché avec elles)
	for k = 1, FairRides.SWING_N do
		local g = 1 + k
		local color = PALETTE[(k - 1) % #PALETTE + 1]
		moving(r, g, "Chair", Vector3.new(1.3, 0.25, 1.2), CFrame.new(0, -0.55, 0), color, M.SmoothPlastic)
		moving(r, g, "ChairBack", Vector3.new(1.3, 1.25, 0.2), CFrame.new(0, 0.05, 0.62), color, M.SmoothPlastic)
		moving(r, g, "FootBar", Vector3.new(1.1, 0.14, 0.14), CFrame.new(0, -1.25, -0.75), STEEL, M.Metal)
		for _, sx in ipairs({ -0.62, 0.62 }) do
			moving(r, g, "Chain", Vector3.new(0.08, L - 0.2, 0.08), CFrame.new(sx, (L - 0.2) / 2 + 0.2, 0.05), STEEL_LIGHT, M.Metal)
		end
	end
end

----------------------------------------------------------------------
-- 🗼 Tour de chute (douce)
----------------------------------------------------------------------

local function buildTower(r: RideFx)
	local H = FairRides.TOWER_H
	solid(fixed(r, "Plinth", Vector3.new(0.6, 10, 10), CFrame.new(0, 0.3, 0) * VERTICAL, Color3.fromRGB(206, 214, 236), M.Slate, CYL))
	solid(fixed(r, "Mast", Vector3.new(H, 2.4, 2.4), CFrame.new(0, H / 2, 0) * VERTICAL, Color3.fromRGB(246, 246, 252), M.Metal, CYL))
	for i = 1, 5 do
		fixed(r, "Band", Vector3.new(0.6, 2.7, 2.7), CFrame.new(0, i * 6.2, 0) * VERTICAL, PALETTE[(i - 1) % #PALETTE + 1], M.SmoothPlastic, CYL)
	end
	-- rails (4) + lueurs verticales
	for i = 0, 3 do
		local a = (i + 0.5) / 4 * TAU
		local d = Vector3.new(math.sin(a), 0, math.cos(a))
		fixed(r, "Rail", Vector3.new(0.3, H - 2, 0.3), CFrame.new(d * 1.3 + Vector3.new(0, H / 2, 0)), STEEL, M.Metal)
	end
	for i = 1, 8 do
		glow(fixed(r, "Dot", Vector3.new(0.4, 0.4, 0.4), CFrame.new(0, 4 + i * 3.8, -1.25), if i % 2 == 0 then BULB else Color3.fromRGB(255, 190, 214), M.SmoothPlastic, BALL))
	end
	fixed(r, "Cap", Vector3.new(1.4, 4.2, 4.2), CFrame.new(0, H + 0.7, 0) * VERTICAL, HOT, M.SmoothPlastic, CYL)
	fixed(r, "Top", Vector3.new(2.6, 2.6, 2.6), CFrame.new(0, H + 2, 0), PINK, M.SmoothPlastic, BALL)
	glow(fixed(r, "Star", Vector3.new(1, 1, 1), CFrame.new(0, H + 3.6, 0), LEMON, M.SmoothPlastic, BALL))
	-- nacelle annulaire (groupe 1) : anneau + 8 sièges baquets vers l'extérieur
	moving(r, 1, "Ring", Vector3.new(0.7, 8.8, 8.8), CFrame.new(0, 0.35, 0) * VERTICAL, Color3.fromRGB(70, 74, 92), M.Metal, CYL)
	moving(r, 1, "Collar", Vector3.new(1.6, 3.2, 3.2), CFrame.new(0, 1.5, 0) * VERTICAL, HOT, M.Metal, CYL)
	for k = 1, FairRides.TOWER_N do
		local a = (k - 1) / FairRides.TOWER_N * TAU
		local frame = CFrame.Angles(0, a, 0) * CFrame.new(0, 0, -FairRides.TOWER_R)
		local color = PALETTE[(k - 1) % #PALETTE + 1]
		moving(r, 1, "Seat", Vector3.new(1.4, 0.35, 1.1), frame * CFrame.new(0, 1.1, 0), color, M.SmoothPlastic)
		moving(r, 1, "SeatBack", Vector3.new(1.4, 1.9, 0.3), frame * CFrame.new(0, 2.1, 0.6), color, M.SmoothPlastic)
		moving(r, 1, "Bar", Vector3.new(1.1, 0.16, 0.16), frame * CFrame.new(0, 2.3, -0.62), LEMON, M.Metal)
	end
end

----------------------------------------------------------------------
-- 🚗 Autos tamponneuses : toit + habillage des autos (soudé à la caisse)
----------------------------------------------------------------------

local function buildBumperHall(r: RideFx)
	local W, D = FairRides.BUMPER_W, FairRides.BUMPER_D
	local roofY = 7.6
	for _, x in ipairs({ -W / 2 - 1.2, 0, W / 2 + 1.2 }) do
		for _, z in ipairs({ -D / 2 - 1.2, D / 2 + 1.2 }) do
			solid(fixed(r, "Post", Vector3.new(0.6, roofY, 0.6), CFrame.new(x, roofY / 2, z), STEEL_LIGHT, M.Metal))
		end
	end
	-- toit rayé (6 bandes)
	for i = 0, 5 do
		local w = (W + 4) / 6
		fixed(r, "Roof", Vector3.new(w, 0.5, D + 4), CFrame.new(-(W + 4) / 2 + (i + 0.5) * w, roofY + 0.25, 0), if i % 2 == 0 then Color3.fromRGB(255, 176, 206) else Color3.fromRGB(252, 250, 255), M.SmoothPlastic).CastShadow = true
	end
	-- filet électrique (au plafond) : quelques câbles
	for i = -3, 3 do
		fixed(r, "Grid", Vector3.new(W, 0.08, 0.08), CFrame.new(0, roofY - 0.1, i * D / 7), STEEL, M.Metal)
	end
	-- bandeau rayé + enseigne
	for i, s in ipairs({ { 0, -D / 2 - 2.05, W + 4.2, 0.2 }, { 0, D / 2 + 2.05, W + 4.2, 0.2 }, { -W / 2 - 2.05, 0, 0.2, D + 4.2 }, { W / 2 + 2.05, 0, 0.2, D + 4.2 } }) do
		fixed(r, "Fascia", Vector3.new(s[3], 1.3, s[4]), CFrame.new(s[1], roofY - 0.1, s[2]), i % 2 == 0 and PINK or SKY, M.SmoothPlastic)
	end
	local board = fixed(r, "Board", Vector3.new(14, 2.4, 0.3), CFrame.new(0, roofY + 1.7, -D / 2 - 2.4), Color3.fromRGB(255, 244, 250), M.SmoothPlastic)
	sign(board, "🚗 " .. Locale.T("Bumper cars"), HOT, Color3.fromRGB(255, 244, 250))
	for i = 0, 9 do
		glow(fixed(r, "Bulb", Vector3.new(0.34, 0.34, 0.34), CFrame.new(-6.5 + i * 1.45, roofY + 3.05, -D / 2 - 2.4), BULB, M.SmoothPlastic, BALL))
	end
end

-- Habillage d'une auto (pièces locales soudées à la caisse du serveur)
local function dressBumper(body: BasePart): Model
	local fx = Instance.new("Model")
	fx.Name = "BumperFx"
	local color = body.Color
	local function add(name: string, size: Vector3, loc: CFrame, c: Color3, mat: Enum.Material?, shape: Enum.PartType?): BasePart
		local p = newPart(fx, name, size, body.CFrame * loc, c, mat, shape)
		p.Anchored = false
		p.Massless = true
		local weld = Instance.new("WeldConstraint")
		weld.Part0 = body
		weld.Part1 = p
		weld.Parent = p
		return p
	end
	local rubber = Color3.fromRGB(46, 46, 56)
	add("BumperFront", Vector3.new(3.9, 0.6, 0.6), CFrame.new(0, -0.15, -2.45), rubber, M.Rubber)
	add("BumperBack", Vector3.new(3.9, 0.6, 0.6), CFrame.new(0, -0.15, 2.45), rubber, M.Rubber)
	for _, sx in ipairs({ -1, 1 }) do
		add("BumperSide", Vector3.new(0.6, 0.6, 4.3), CFrame.new(sx * 1.95, -0.15, 0), rubber, M.Rubber)
	end
	add("Nose", Vector3.new(3, 0.9, 1.5), CFrame.new(0, 0.7, -1.6), color, M.SmoothPlastic, BALL)
	add("SeatBack", Vector3.new(2.1, 1.5, 0.4), CFrame.new(0, 1.3, 1.45), Color3.fromRGB(255, 244, 250), M.Fabric)
	add("Wheel", Vector3.new(0.16, 0.9, 0.9), CFrame.new(0, 1.3, -0.55) * CFrame.Angles(math.rad(-60), 0, 0) * VERTICAL * CFrame.Angles(0, 0, 0), rubber, M.SmoothPlastic, CYL)
	add("Pole", Vector3.new(0.14, 5.4, 0.14), CFrame.new(0, 3.9, 1.95), STEEL_LIGHT, M.Metal)
	glow(add("Spark", Vector3.new(0.4, 0.4, 0.4), CFrame.new(0, 6.65, 1.95), LEMON, M.SmoothPlastic, BALL))
	for _, sx in ipairs({ -0.9, 0.9 }) do
		glow(add("Lamp", Vector3.new(0.34, 0.34, 0.34), CFrame.new(sx, 0.45, -2.25), BULB, M.SmoothPlastic, BALL))
	end
	fx.Parent = body
	return fx
end

----------------------------------------------------------------------
-- Guérite de chaque manège : panneau + état ("Départ dans 5 s")
----------------------------------------------------------------------

local function buildBooth(folder: Instance, F: CFrame, def: any): TextLabel
	local model = Instance.new("Model")
	model.Name = "Booth_" .. def.Id
	model.Parent = folder
	-- la borne regarde vers le manège ; le panneau vers l'allée
	local gate = F * CFrame.new(def.Gate)
	local toRide = (F * def.Pos) - gate.Position
	local face = CFrame.lookAt(gate.Position, gate.Position - Vector3.new(toRide.X, 0, toRide.Z))
	solid(newPart(model, "Post", Vector3.new(0.5, 4.6, 0.5), face * CFrame.new(-1.4, 2.3, 0), WHITE, M.Metal))
	solid(newPart(model, "Post", Vector3.new(0.5, 4.6, 0.5), face * CFrame.new(1.4, 2.3, 0), WHITE, M.Metal))
	local board = newPart(model, "Board", Vector3.new(3.6, 1.9, 0.2), face * CFrame.new(0, 4.1, -0.05), Color3.fromRGB(255, 244, 250), M.SmoothPlastic)
	board.CastShadow = true
	local title = sign(board, def.Icon .. " " .. Locale.T(def.Name), HOT, Color3.fromRGB(255, 244, 250))
	title.Size = UDim2.fromScale(0.92, 0.5)
	local status = Instance.new("TextLabel")
	status.Name = "Status"
	status.BackgroundTransparency = 1
	status.Position = UDim2.fromScale(0.06, 0.58)
	status.Size = UDim2.fromScale(0.88, 0.34)
	status.Font = Enum.Font.GothamBold
	status.TextColor3 = INK
	status.TextScaled = true
	status.Text = ""
	status.Parent = title.Parent
	glow(newPart(model, "Lamp", Vector3.new(0.5, 0.5, 0.5), face * CFrame.new(0, 5.35, 0), BULB, M.SmoothPlastic, BALL))
	-- petite file d'attente (barrières basses)
	for _, sx in ipairs({ -1, 1 }) do
		newPart(model, "Rope", Vector3.new(0.12, 0.12, 3), face * CFrame.new(sx * 1.4, 1.6, -1.6), HOT, M.Fabric)
		solid(newPart(model, "Stanchion", Vector3.new(0.3, 2.2, 0.3), face * CFrame.new(sx * 1.4, 1.1, -3.1), GOLD, M.Metal))
	end
	return status
end

----------------------------------------------------------------------
-- Stands de nourriture (décor ; la borne "Commander" est au serveur)
----------------------------------------------------------------------

local STALL_THEME = {
	Churros = { A = Color3.fromRGB(236, 150, 80), B = CREAM, Wall = Color3.fromRGB(255, 226, 190), Title = "🥖 Churros & crêpes" },
	Donut = { A = PINK, B = WHITE, Wall = Color3.fromRGB(255, 220, 236), Title = "🍩 Donuts & shakes" },
	Popcorn = { A = Color3.fromRGB(226, 40, 60), B = WHITE, Wall = Color3.fromRGB(255, 240, 220), Title = "🍿 Popcorn & candy floss" },
	HotDog = { A = Color3.fromRGB(255, 196, 60), B = Color3.fromRGB(226, 72, 60), Wall = Color3.fromRGB(255, 236, 196), Title = "🌭 Hot dogs & candy apples" },
	IceCream = { A = MINT, B = WHITE, Wall = Color3.fromRGB(226, 250, 240), Title = "🍦 Ice cream & shakes" },
	Truck = { A = SKY, B = WHITE, Wall = Color3.fromRGB(220, 236, 255), Title = "🌮 Tacos & pizza" },
}

local function awning(model: Instance, cf: CFrame, w: number, depth: number, n: number, a: Color3, b: Color3)
	local slope = CFrame.Angles(math.rad(-18), 0, 0)
	for i = 0, n - 1 do
		local x = -w / 2 + (i + 0.5) * w / n
		newPart(model, "Awning", Vector3.new(w / n, 0.14 + (i % 2) * 0.06, depth), cf * slope * CFrame.new(x, 0, -depth / 2), i % 2 == 0 and a or b, M.Fabric).CastShadow = true
	end
end

-- Stand classique : `cf` au sol, devant (-Z) vers les clients
local function buildStall(folder: Instance, cf: CFrame, style: string, foods: { string }, seed: number): any
	local th = STALL_THEME[style] or STALL_THEME.Churros
	local model = Instance.new("Model")
	model.Name = "Stall_" .. style
	model.Parent = folder
	if style == "Truck" then
		-- food truck : caisse, cabine, roues, trappe de service + auvent
		local body = th.A
		solid(newPart(model, "Box", Vector3.new(9, 5.2, 5), cf * CFrame.new(0, 3.3, 0.6), body, M.SmoothPlastic))
		solid(newPart(model, "Cab", Vector3.new(3.4, 3.6, 4.8), cf * CFrame.new(-6.2, 2.5, 0.6), body, M.SmoothPlastic))
		newPart(model, "Windshield", Vector3.new(0.12, 1.6, 4.2), cf * CFrame.new(-7.93, 3.3, 0.6), Color3.fromRGB(150, 196, 230), M.Glass).Transparency = 0.25
		newPart(model, "Stripe", Vector3.new(12.6, 0.6, 5.1), cf * CFrame.new(-1.7, 1.5, 0.6), WHITE, M.SmoothPlastic)
		for _, x in ipairs({ -6, 2.6 }) do
			for _, z in ipairs({ -1.9, 3.1 }) do
				newPart(model, "Wheel", Vector3.new(0.7, 1.7, 1.7), cf * CFrame.new(x, 0.85, z) * CFrame.Angles(0, math.rad(90), 0), Color3.fromRGB(40, 40, 48), M.Rubber, CYL)
			end
		end
		newPart(model, "Hatch", Vector3.new(6.4, 2.2, 0.1), cf * CFrame.new(0.4, 3.9, -1.96), Color3.fromRGB(60, 50, 64), M.SmoothPlastic)
		solid(newPart(model, "Counter", Vector3.new(6.8, 0.25, 1.2), cf * CFrame.new(0.4, 2.8, -2.4), WHITE, M.Marble))
		awning(model, cf * CFrame.new(0.4, 5.9, -1.9), 7.2, 2.6, 8, th.A, th.B)
		local board = newPart(model, "Sign", Vector3.new(7, 1.3, 0.12), cf * CFrame.new(0.4, 5.3 + 0.95, -1.95 - 0.1), WHITE, M.SmoothPlastic)
		sign(board, Locale.T(th.Title), HOT, WHITE)
		local displays = {}
		for i, id in ipairs(foods) do
			local m = FoodModels.Build(id, cf * CFrame.new(-1.6 + (i - 1) * 2, 3.35, -2.4), 1.1)
			if m then
				m.Parent = model
				table.insert(displays, m)
			end
		end
		return { Model = model, VendorCF = cf * CFrame.new(0.4, 1.25, -0.6) }
	end
	-- comptoir, dessus, cabane, montants, auvent rayé, panneau
	solid(newPart(model, "Counter", Vector3.new(5.6, 2.9, 2.2), cf * CFrame.new(0, 1.45, 0), th.Wall, M.WoodPlanks))
	newPart(model, "Top", Vector3.new(6, 0.25, 2.6), cf * CFrame.new(0, 3, 0), WHITE, M.Marble)
	newPart(model, "Skirt", Vector3.new(5.7, 0.7, 0.1), cf * CFrame.new(0, 2.3, -1.16), th.A, M.SmoothPlastic)
	solid(newPart(model, "Back", Vector3.new(6, 6.4, 0.3), cf * CFrame.new(0, 3.2, 3.2), th.Wall, M.WoodPlanks))
	for _, sx in ipairs({ -1, 1 }) do
		solid(newPart(model, "Side", Vector3.new(0.3, 6.4, 3.5), cf * CFrame.new(sx * 2.95, 3.2, 1.6), th.Wall, M.WoodPlanks))
		newPart(model, "Post", Vector3.new(0.22, 3.9, 0.22), cf * CFrame.new(sx * 2.85, 5, -1.05), WHITE, M.Metal)
	end
	newPart(model, "Roof", Vector3.new(6.3, 0.3, 4.6), cf * CFrame.new(0, 6.5, 1.2), th.A, M.SmoothPlastic).CastShadow = true
	awning(model, cf * CFrame.new(0, 6.85, 0.1), 6.4, 2.9, 8, th.A, th.B)
	local board = newPart(model, "Sign", Vector3.new(5.6, 1.1, 0.12), cf * CFrame.new(0, 7.55, -0.2), WHITE, M.SmoothPlastic)
	sign(board, Locale.T(th.Title), HOT, WHITE)
	-- ampoules sous l'auvent
	for i = 0, 5 do
		glow(newPart(model, "Bulb", Vector3.new(0.28, 0.28, 0.28), cf * CFrame.new(-2.5 + i, 5.95, -1.2), BULB, M.SmoothPlastic, BALL))
	end
	-- aliments exposés sur le comptoir (vrais modèles, un peu plus grands)
	for i, id in ipairs(foods) do
		local x = if #foods == 1 then 0 else -1.6 + (i - 1) * 3.2 / (#foods - 1)
		local m = FoodModels.Build(id, cf * CFrame.new(x, 3.55, -0.45), 1.15)
		if m then
			m.Parent = model
		end
	end
	-- ardoise "menu" à côté
	local slate = newPart(model, "Menu", Vector3.new(1.5, 2.1, 0.1), cf * CFrame.new(3.9, 1.2, -1.4) * CFrame.Angles(math.rad(-12), math.rad(-20), 0), Color3.fromRGB(58, 62, 66), M.Slate)
	local label = sign(slate, "", Color3.fromRGB(250, 246, 236), nil, Enum.Font.FredokaOne)
	local icons = {}
	for _, id in ipairs(foods) do
		local food = Config.FoodById[id]
		if food then
			table.insert(icons, food.Icon .. " x" .. string.format("%.1f", food.Multiplier))
		end
	end
	label.Text = "MENU\n" .. table.concat(icons, "\n")
	newPart(model, "MenuLeg", Vector3.new(0.12, 2.2, 0.12), cf * CFrame.new(3.9, 1.1, -0.95), WOOD_DARK, M.Wood)
	return { Model = model, VendorCF = cf * CFrame.new(0, 0, 1.55), Seed = seed }
end

----------------------------------------------------------------------
-- Décor général de la fête
----------------------------------------------------------------------

local function sag(a: Vector3, b: Vector3, s: number, t: number): Vector3
	return a:Lerp(b, t) - Vector3.new(0, s * 4 * t * (1 - t), 0)
end

-- Guirlande entre deux points : câble en segments + ampoules colorées
local function garland(model: Instance, a: Vector3, b: Vector3, s: number, n: number)
	local prev = a
	for i = 1, n do
		local p = sag(a, b, s, i / n)
		rod(model, "Wire", prev, p, 0.07, Color3.fromRGB(60, 60, 70), M.SmoothPlastic)
		local mid = sag(a, b, s, (i - 0.5) / n)
		glow(newPart(model, "Bulb", Vector3.new(0.34, 0.34, 0.34), CFrame.new(mid - Vector3.new(0, 0.2, 0)), PALETTE[(i - 1) % #PALETTE + 1], M.SmoothPlastic, BALL))
		prev = p
	end
end

local function buildArch(folder: Instance, F: CFrame)
	local model = Instance.new("Model")
	model.Name = "Arch"
	model.Parent = folder
	local z = -FairRides.FAIR_HALF_D
	local halfW = 7.5
	for _, sx in ipairs({ -1, 1 }) do
		-- colonnes en sucre d'orge (anneaux rouges / blancs)
		for i = 0, 9 do
			solid(newPart(model, "Pillar", Vector3.new(1, 1.8, 1.8), F * CFrame.new(sx * halfW, 0.5 + i, z) * VERTICAL, i % 2 == 0 and HOT or WHITE, M.SmoothPlastic, CYL))
		end
		newPart(model, "PillarTop", Vector3.new(2.4, 2.4, 2.4), F * CFrame.new(sx * halfW, 10.9, z), GOLD, M.Metal, BALL)
		rod(model, "FlagPole", F * Vector3.new(sx * halfW, 12, z), F * Vector3.new(sx * halfW, 15.5, z), 0.14, WHITE)
		local fSize, fLoc = triCF(F * Vector3.new(sx * halfW, 15.3, z), F:VectorToWorldSpace(Vector3.new(sx, 0, 0)), -UP, 2, 1.2, 0.06)
		newPart(model, "Flag", fSize, fLoc, sx < 0 and SKY or PINK, M.Fabric, nil, "WedgePart")
	end
	-- arc (demi-cercle en segments) + ampoules
	local n = 10
	local R = halfW
	local cy = 10.5
	local prev = F * Vector3.new(-R, cy, z)
	for i = 1, n do
		local a = math.pi - i / n * math.pi
		local p = F * Vector3.new(math.cos(a) * R, cy + math.sin(a) * 4.2, z)
		beam(model, "Arc", prev, p, 0.9, 0.9, i % 2 == 0 and PINK or CREAM, M.SmoothPlastic)
		glow(newPart(model, "Bulb", Vector3.new(0.4, 0.4, 0.4), CFrame.new(p) * F.Rotation * CFrame.new(0, 0, -0.55), BULB, M.SmoothPlastic, BALL))
		prev = p
	end
	-- grand panneau (lisible des deux côtés)
	-- (face avant -Z : vers la place, d'où l'on arrive ; le dos, vers la fête)
	local board = newPart(model, "Board", Vector3.new(13, 2.8, 0.3), F * CFrame.new(0, 9, z), Color3.fromRGB(255, 244, 250), M.SmoothPlastic)
	board.CastShadow = true
	sign(board, "🎡 " .. Locale.T("Fun fair") .. " 🎠", HOT, Color3.fromRGB(255, 244, 250))
	local back = newPart(model, "BoardBack", Vector3.new(12.6, 2.5, 0.1), F * CFrame.new(0, 9, z + 0.18) * CFrame.Angles(0, math.pi, 0), Color3.fromRGB(255, 244, 250), M.SmoothPlastic)
	sign(back, "🎡 " .. Locale.T("Fun fair") .. " 🎠", HOT, Color3.fromRGB(255, 244, 250))
	for i = 0, 11 do
		glow(newPart(model, "BoardBulb", Vector3.new(0.3, 0.3, 0.3), F * CFrame.new(-6 + i * 12 / 11, 10.55, z - 0.3), PALETTE[i % #PALETTE + 1], M.SmoothPlastic, BALL))
	end
	-- ballons attachés aux colonnes
	for _, sx in ipairs({ -1, 1 }) do
		for k = 0, 2 do
			local p = F * Vector3.new(sx * (halfW + 0.6 + k * 0.5), 12.5 + k * 1.1, z - 0.6 + k * 0.4)
			newPart(model, "Balloon", Vector3.new(1.3, 1.6, 1.3), CFrame.new(p), PALETTE[(k + (sx > 0 and 3 or 0)) % #PALETTE + 1], M.SmoothPlastic, BALL)
			rod(model, "String", F * Vector3.new(sx * halfW, 10, z), p - Vector3.new(0, 0.8, 0), 0.04, WHITE, M.SmoothPlastic)
		end
	end
end

local function buildFence(folder: Instance, F: CFrame)
	local model = Instance.new("Model")
	model.Name = "Fence"
	model.Parent = folder
	local hw, hd = FairRides.FAIR_HALF_W - 0.5, FairRides.FAIR_HALF_D - 0.5
	-- côtés (segments entre les ouvertures) : avant (arche x ±8), côtés (z -6..4)
	local runs = {
		{ Vector3.new(-hw, 0, -hd), Vector3.new(-8.6, 0, -hd) },
		{ Vector3.new(8.6, 0, -hd), Vector3.new(hw, 0, -hd) },
		{ Vector3.new(-hw, 0, hd), Vector3.new(hw, 0, hd) },
		{ Vector3.new(-hw, 0, -hd), Vector3.new(-hw, 0, -6) },
		{ Vector3.new(-hw, 0, 4), Vector3.new(-hw, 0, hd) },
		{ Vector3.new(hw, 0, -hd), Vector3.new(hw, 0, -6) },
		{ Vector3.new(hw, 0, 4), Vector3.new(hw, 0, hd) },
	}
	local white = Color3.fromRGB(255, 252, 246)
	for i, run in ipairs(runs) do
		local a, b = run[1], run[2]
		local len = (b - a).Magnitude
		local mid = (a + b) / 2
		local cf = F * CFrame.lookAt(mid, b)
		solid(newPart(model, "Rail", Vector3.new(0.25, 0.25, len), cf * CFrame.new(0, 3.1, 0), white, M.Wood))
		newPart(model, "Rail", Vector3.new(0.2, 0.2, len), cf * CFrame.new(0, 1.2, 0), white, M.Wood)
		-- panneaux ajourés colorés (un par travée de 5,5 studs)
		local spans = math.max(1, math.floor(len / 5.5 + 0.5))
		for k = 0, spans do
			local t = k / spans
			solid(newPart(model, "Post", Vector3.new(0.45, 3.6, 0.45), F * CFrame.new(a:Lerp(b, t) + Vector3.new(0, 1.8, 0)), white, M.Wood))
			if k < spans then
				local p = a:Lerp(b, (k + 0.5) / spans)
				newPart(model, "Panel", Vector3.new(0.12, 1.6, len / spans - 0.7), F * CFrame.lookAt(p, b) * CFrame.new(0, 2.15, 0) * CFrame.Angles(0, math.rad(90), 0) * CFrame.Angles(0, math.rad(-90), 0), PALETTE[(i + k) % #PALETTE + 1], M.SmoothPlastic)
			end
		end
	end
end

local function buildGrounds(folder: Instance, F: CFrame)
	local model = Instance.new("Model")
	model.Name = "Grounds"
	model.Parent = folder
	-- allée en planches (de l'arche à la grande roue) + bordures
	local z0, z1 = -FairRides.FAIR_HALF_D - 5, 14
	local len = z1 - z0
	newPart(model, "Alley", Vector3.new(11, 0.12, len), F * CFrame.new(0, 0.06, (z0 + z1) / 2), Color3.fromRGB(214, 170, 122), M.WoodPlanks)
	for _, sx in ipairs({ -1, 1 }) do
		newPart(model, "AlleyEdge", Vector3.new(0.5, 0.2, len), F * CFrame.new(sx * 5.75, 0.1, (z0 + z1) / 2), Color3.fromRGB(150, 110, 80), M.Wood)
	end
	-- allée en gravier derrière la mairie (le couloir entre la mairie et
	-- la fête) + deux chemins depuis les passages de chaque côté de la mairie
	-- (sol du pré : y = -GROUND ; dessus 0,1 au-dessus)
	local g = -FairRides.GROUND
	local walk = Color3.fromRGB(222, 212, 196)
	local zc = -FairRides.FAIR_HALF_D - 6.5
	newPart(model, "Walkway", Vector3.new(84, 0.1, 5), F * CFrame.new(0, g + 0.05, zc), walk, M.Pavement)
	for _, sx in ipairs({ -1, 1 }) do
		local a0 = Vector3.new(sx * 39, g + 0.07, zc)
		local a1 = Vector3.new(sx * 39, g + 0.07, zc - 24)
		newPart(model, "SidePath", Vector3.new(4, 0.1, 24.5), F * CFrame.lookAt((a0 + a1) / 2, a1), walk, M.Pavement)
	end
	-- place ronde devant la grande roue
	newPart(model, "Round", Vector3.new(0.07, 22, 22), F * CFrame.new(0, 0.035, 8) * VERTICAL, Color3.fromRGB(236, 214, 190), M.Pavement, CYL)
	-- poteaux + guirlandes au-dessus de l'allée (en zigzag)
	local poles = {}
	for i, z in ipairs({ -33, -20, -6 }) do
		for _, sx in ipairs({ -1, 1 }) do
			local base = Vector3.new(sx * 7.6, 0, z)
			solid(newPart(model, "Pole", Vector3.new(0.4, 9, 0.4), F * CFrame.new(base + Vector3.new(0, 4.5, 0)), WHITE, M.Metal))
			newPart(model, "PoleTop", Vector3.new(0.8, 0.8, 0.8), F * CFrame.new(base + Vector3.new(0, 9.2, 0)), PALETTE[i], M.SmoothPlastic, BALL)
			table.insert(poles, F * (base + Vector3.new(0, 8.8, 0)))
		end
	end
	-- (paires : en travers puis en diagonale)
	for i = 1, #poles - 1 do
		garland(model, poles[i], poles[i + 1], 1.1, 7)
	end
	-- guirlandes vers la grande roue et les côtés
	garland(model, poles[5], F * Vector3.new(-6.5, 8.6, 12), 0.9, 7)
	garland(model, poles[6], F * Vector3.new(6.5, 8.6, 12), 0.9, 7)
	-- bancs (simples, en bois) + poubelles + jardinières
	local function bench(cf: CFrame)
		newPart(model, "BenchSeat", Vector3.new(4, 0.25, 1.2), cf * CFrame.new(0, 1.7, 0), WOOD, M.Wood)
		newPart(model, "BenchBack", Vector3.new(4, 1, 0.2), cf * CFrame.new(0, 2.6, 0.55) * CFrame.Angles(math.rad(-10), 0, 0), WOOD, M.Wood)
		for _, x in ipairs({ -1.7, 1.7 }) do
			solid(newPart(model, "BenchLeg", Vector3.new(0.25, 1.6, 1.1), cf * CFrame.new(x, 0.8, 0.05), Color3.fromRGB(60, 58, 72), M.Metal))
		end
	end
	bench(F * CFrame.new(-7.6, 0, -13) * CFrame.Angles(0, math.rad(-90), 0))
	bench(F * CFrame.new(7.6, 0, -13) * CFrame.Angles(0, math.rad(90), 0))
	bench(F * CFrame.new(-6, 0, 18) * CFrame.Angles(0, math.rad(200), 0))
	bench(F * CFrame.new(6, 0, 18) * CFrame.Angles(0, math.rad(160), 0))
	for i, p in ipairs({ Vector3.new(-7.4, 0, -31), Vector3.new(7.4, 0, -31), Vector3.new(-9, 0, 15) }) do
		solid(newPart(model, "Bin", Vector3.new(1.6, 1, 1), F * CFrame.new(p + Vector3.new(0, 0.8, 0)) * VERTICAL, PALETTE[i + 1], M.SmoothPlastic, CYL))
		newPart(model, "BinLid", Vector3.new(0.2, 1.1, 1.1), F * CFrame.new(p + Vector3.new(0, 1.7, 0)) * VERTICAL, WHITE, M.SmoothPlastic, CYL)
	end
	for i, p in ipairs({ Vector3.new(-10.5, 0, -39.5), Vector3.new(10.5, 0, -39.5), Vector3.new(-52, 0, -33), Vector3.new(52, 0, -33), Vector3.new(-52, 0, 33), Vector3.new(52, 0, 33) }) do
		solid(newPart(model, "Planter", Vector3.new(1.2, 2.4, 2.4), F * CFrame.new(p + Vector3.new(0, 0.6, 0)) * VERTICAL, WHITE, M.Concrete, CYL))
		newPart(model, "Shrub", Vector3.new(2.8, 2.4, 2.8), F * CFrame.new(p + Vector3.new(0, 2.2, 0)), Color3.fromRGB(100, 176, 96), M.Grass, BALL)
		newPart(model, "Flowers", Vector3.new(1, 1, 1), F * CFrame.new(p + Vector3.new(0.6, 3, -0.5)), PALETTE[i], M.SmoothPlastic, BALL)
	end
end

-- 🦆 Pêche aux canards (décor animé : les canards tournent)
local function buildDucks(folder: Instance, F: CFrame): any
	local model = Instance.new("Model")
	model.Name = "Ducks"
	model.Parent = folder
	local c = F * CFrame.new(15.5, 0, 1)
	solid(newPart(model, "Tub", Vector3.new(1.6, 6.4, 6.4), c * CFrame.new(0, 0.8, 0) * VERTICAL, SKY, M.SmoothPlastic, CYL))
	newPart(model, "TubRim", Vector3.new(0.3, 6.8, 6.8), c * CFrame.new(0, 1.7, 0) * VERTICAL, WHITE, M.SmoothPlastic, CYL)
	local water = newPart(model, "Water", Vector3.new(0.1, 5.6, 5.6), c * CFrame.new(0, 1.62, 0) * VERTICAL, Color3.fromRGB(96, 186, 236), M.Glass, CYL)
	water.Transparency = 0.2
	newPart(model, "Island", Vector3.new(0.6, 2.2, 2.2), c * CFrame.new(0, 1.8, 0) * VERTICAL, LEMON, M.SmoothPlastic, CYL)
	local ducks = { Parts = {}, Frames = {}, Center = c }
	for i = 1, 8 do
		local d = newPart(model, "Duck", Vector3.new(0.8, 0.7, 1), c, Color3.fromRGB(255, 214, 60), M.SmoothPlastic, BALL)
		table.insert(ducks.Parts, d)
		table.insert(ducks.Frames, c)
	end
	-- lots (peluches) sur une étagère + panneau
	solid(newPart(model, "Shelf", Vector3.new(6, 3, 1), c * CFrame.new(0, 1.5, 4.4), WOOD, M.WoodPlanks))
	for i = 0, 4 do
		newPart(model, "Plush", Vector3.new(0.9, 1, 0.8), c * CFrame.new(-2.4 + i * 1.2, 3.5, 4.4), PALETTE[i + 1], M.Fabric, BALL)
	end
	local board = newPart(model, "Sign", Vector3.new(5, 1.2, 0.12), c * CFrame.new(0, 4.9, 4.95), WHITE, M.SmoothPlastic)
	sign(board, "🦆 " .. Locale.T("Duck fishing"), Color3.fromRGB(56, 140, 200), WHITE)
	ducks.Step = function(t: number)
		for i, d in ipairs(ducks.Parts) do
			local a = t * 0.5 + i / 8 * TAU
			local p = Vector3.new(math.sin(a) * 2.2, 1.95 + math.sin(t * 3 + i) * 0.05, math.cos(a) * 2.2)
			ducks.Frames[i] = c * CFrame.lookAt(p, p + Vector3.new(math.cos(a), 0, -math.sin(a)))
		end
		workspace:BulkMoveTo(ducks.Parts, ducks.Frames, Enum.BulkMoveMode.FireCFrameChanged)
	end
	return ducks
end

----------------------------------------------------------------------
-- Vendeurs (PNJ de CITY98, s'ils existent)
----------------------------------------------------------------------

local npcModule: any = nil
local function npcModels(): any
	if npcModule == nil then
		local shared = ReplicatedStorage:FindFirstChild("Shared")
		local m = shared and shared:FindFirstChild("NPCModels")
		local ok, result = false, nil
		if m and m:IsA("ModuleScript") then
			ok, result = pcall(require, m)
		end
		npcModule = (ok and type(result) == "table") and result or false
	end
	return npcModule or nil
end

local function addVendor(folder: Instance, cf: CFrame, seed: number, style: string?): Model?
	local N = npcModels()
	if not N or type(N.Build) ~= "function" then
		return nil
	end
	local ok, npc = pcall(N.Build, style or "baker", { Seed = seed })
	if not ok or not npc then
		return nil
	end
	npc:PivotTo(cf)
	npc.Parent = folder
	return npc
end

----------------------------------------------------------------------
-- Construction en FLUX (un morceau par image)
----------------------------------------------------------------------

local function queueFair(s: any, fair: Instance)
	local F = fair:GetAttribute("FairCF")
	if typeof(F) ~= "CFrame" then
		return false
	end
	local folder = Instance.new("Folder")
	folder.Name = "FairFx"
	s.Fair = { Folder = folder, Source = fair, F = F, Rides = {}, Boards = {}, Vendors = {}, Ducks = nil, Queue = {}, Built = false }
	local fx = s.Fair
	local q = fx.Queue
	table.insert(q, function()
		buildGrounds(folder, F)
	end)
	table.insert(q, function()
		buildArch(folder, F)
	end)
	table.insert(q, function()
		buildFence(folder, F)
	end)
	for _, def in ipairs(FairRides.Rides) do
		table.insert(q, function()
			local r = newRide(folder, def, F)
			if def.Kind == "Ferris" then
				buildFerris(r)
			elseif def.Kind == "Carousel" then
				buildCarousel(r)
			elseif def.Kind == "Cups" then
				buildCups(r)
			elseif def.Kind == "Swings" then
				buildSwings(r)
			elseif def.Kind == "Tower" then
				buildTower(r)
			elseif def.Kind == "Bumper" then
				buildBumperHall(r)
			end
			findSeats(r, fair)
			table.insert(fx.Rides, r)
			fx.Boards[def.Id] = buildBooth(folder, F, def)
		end)
	end
	for i, st in ipairs(FairRides.Stalls) do
		table.insert(q, function()
			local cf = F * CFrame.new(st.Pos) * CFrame.Angles(0, math.rad(st.Yaw), 0)
			local info = buildStall(folder, cf, st.Style, st.Foods, i)
			local npc = addVendor(folder, info.VendorCF, 40 + i, if i % 2 == 0 then "cashier" else "baker")
			if npc then
				table.insert(fx.Vendors, { Model = npc, Seed = i * 1.7, Anim = "idle" })
			end
		end)
	end
	table.insert(q, function()
		fx.Ducks = buildDucks(folder, F)
	end)
	-- opérateurs des manèges (debout près des guérites)
	table.insert(q, function()
		for i, def in ipairs(FairRides.Rides) do
			if i % 2 == 1 then
				local gate = F * CFrame.new(def.Gate)
				local toRide = (F * def.Pos) - gate.Position
				local look = CFrame.lookAt(gate.Position, gate.Position - Vector3.new(toRide.X, 0, toRide.Z))
				local npc = addVendor(folder, look * CFrame.new(2.6, 0, 0.8), 70 + i, "worker")
				if npc then
					table.insert(fx.Vendors, { Model = npc, Seed = i * 2.3, Anim = "wave" })
				end
			end
		end
	end)
	return true
end

local function queueCorner(s: any, corner: Instance)
	local C = corner:GetAttribute("CornerCF")
	if typeof(C) ~= "CFrame" then
		return false
	end
	local folder = Instance.new("Folder")
	folder.Name = "FoodCornerFx"
	s.Corner = { Folder = folder, Source = corner, C = C, Queue = {}, Vendors = {}, Built = false }
	local cx = s.Corner
	local q = cx.Queue
	for i, st in ipairs(FairRides.CornerStalls) do
		table.insert(q, function()
			local cf = C * CFrame.new(st.Pos) * CFrame.Angles(0, math.rad(st.Yaw), 0)
			local info = buildStall(folder, cf, st.Style, st.Foods, 10 + i)
			local npc = addVendor(folder, info.VendorCF, 60 + i, if i == 1 then "cashier" else "baker")
			if npc then
				table.insert(cx.Vendors, { Model = npc, Seed = i * 1.3, Anim = "talk" })
			end
		end)
	end
	-- tables de pique-nique à parasol + guirlande + panneau
	table.insert(q, function()
		local model = Instance.new("Model")
		model.Name = "Tables"
		model.Parent = folder
		for i, p in ipairs({ Vector3.new(4, 0, 8), Vector3.new(10, 0, 12), Vector3.new(-2, 0, -12), Vector3.new(6, 0, -14) }) do
			local cf = C * CFrame.new(p)
			solid(newPart(model, "Table", Vector3.new(0.3, 3.4, 3.4), cf * CFrame.new(0, 2.5, 0) * VERTICAL, WHITE, M.SmoothPlastic, CYL))
			solid(newPart(model, "TableLeg", Vector3.new(2.4, 0.4, 0.4), cf * CFrame.new(0, 1.2, 0) * VERTICAL, STEEL, M.Metal, CYL))
			newPart(model, "Umbrella", Vector3.new(0.9, 5.4, 5.4), cf * CFrame.new(0, 6.2, 0) * VERTICAL, PALETTE[i], M.Fabric, CYL).CastShadow = true
			newPart(model, "UmbrellaTop", Vector3.new(0.7, 0.7, 0.7), cf * CFrame.new(0, 6.9, 0), WHITE, M.SmoothPlastic, BALL)
			newPart(model, "UmbrellaPole", Vector3.new(0.14, 4.3, 0.14), cf * CFrame.new(0, 4.6, 0), WHITE, M.Metal)
			for _, a in ipairs({ 0, 120, 240 }) do
				local sp = cf * CFrame.Angles(0, math.rad(a), 0) * CFrame.new(0, 0, -2.6)
				solid(newPart(model, "Stool", Vector3.new(1.6, 1.1, 1.1), sp * CFrame.new(0, 0.8, 0) * VERTICAL, PALETTE[(i + a / 120) % #PALETTE + 1], M.SmoothPlastic, CYL))
			end
		end
		local poles = {}
		for _, p in ipairs({ Vector3.new(-18, 0, -20), Vector3.new(18, 0, -20), Vector3.new(18, 0, 20), Vector3.new(-18, 0, 20) }) do
			solid(newPart(model, "Pole", Vector3.new(0.35, 8, 0.35), C * CFrame.new(p + Vector3.new(0, 4, 0)), WHITE, M.Metal))
			table.insert(poles, C * (p + Vector3.new(0, 7.8, 0)))
		end
		garland(model, poles[1], poles[3], 1.4, 9)
		garland(model, poles[2], poles[4], 1.4, 9)
		local board = newPart(model, "Sign", Vector3.new(8, 1.8, 0.2), C * CFrame.new(0, 3.8, -20.5), Color3.fromRGB(255, 244, 250), M.SmoothPlastic)
		sign(board, "🍦 " .. Locale.T("Snack corner") .. " 🌮", HOT, Color3.fromRGB(255, 244, 250))
		for _, sx in ipairs({ -3.6, 3.6 }) do
			solid(newPart(model, "SignLeg", Vector3.new(0.3, 3, 0.3), C * CFrame.new(sx, 1.5, -20.5), WHITE, M.Metal))
		end
	end)
	return true
end

local function destroyFair(s: any)
	local fx = s.Fair
	s.Fair = nil
	if fx and fx.Folder then
		fx.Folder:Destroy()
	end
end

local function destroyCorner(s: any)
	local cx = s.Corner
	s.Corner = nil
	if cx and cx.Folder then
		cx.Folder:Destroy()
	end
end

----------------------------------------------------------------------
-- Invites : traduction locale, "Monter" caché quand on est assis
----------------------------------------------------------------------

local function foodIcons(list: string): string
	local icons = {}
	for id in string.gmatch(list, "[^,]+") do
		local food = Config.FoodById[id]
		if food then
			table.insert(icons, food.Icon)
		end
	end
	return table.concat(icons, " ")
end

local function localizePrompt(p: ProximityPrompt, seated: boolean)
	local action = p:GetAttribute("LocAction")
	if type(action) == "string" then
		local text = Locale.T(action)
		if p.ActionText ~= text then
			p.ActionText = text
		end
	end
	local foods = p:GetAttribute("Foods")
	if type(foods) == "string" then
		local text = foodIcons(foods) .. " " .. Locale.T("Snacks")
		if p.ObjectText ~= text then
			p.ObjectText = text
		end
	else
		local rideId = p:GetAttribute("RideId")
		local def = type(rideId) == "string" and FairRides.ById[rideId]
		local text = if def then def.Icon .. " " .. Locale.T(def.Name) elseif rideId == "PlazaCarousel" then "🎠 " .. Locale.T("Carousel") else nil
		if text and p.ObjectText ~= text then
			p.ObjectText = text
		end
		-- (déjà assis : pas d'invite "Monter" autour)
		p.Enabled = not seated
	end
end

local function refreshPrompts(s: any)
	local town = workspace:FindFirstChild("DopamineTown")
	local decor = town and town:FindFirstChild("Decor")
	if not decor then
		return
	end
	local character = LocalPlayer and LocalPlayer.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local seated = humanoid ~= nil and humanoid.SeatPart ~= nil
	for _, name in ipairs({ "Fair", "FoodCorner", "Plaza" }) do
		local f = decor:FindFirstChild(name)
		if f then
			local list = s.PromptCache[name]
			if not list or s.PromptAge > 20 then
				list = {}
				for _, d in ipairs(f:GetDescendants()) do
					if d:IsA("ProximityPrompt") and d.Name == "FairPrompt" then
						table.insert(list, d)
					end
				end
				s.PromptCache[name] = list
			end
			for _, p in ipairs(list) do
				if p.Parent then
					localizePrompt(p, seated)
				end
			end
		end
	end
	if s.PromptAge > 20 then
		s.PromptAge = 0
	end
end

----------------------------------------------------------------------
-- Interface : menu du stand, badge du boost, bouton "Croquer"
----------------------------------------------------------------------

local function isPhone(): boolean
	local camera = workspace.CurrentCamera
	return camera ~= nil and camera.ViewportSize.Y < 520
end

local function toast(text: string, color: Color3?)
	local s = state
	if s and s.Toast then
		pcall(s.Toast, text, color)
	end
end

local function fmtClock(seconds: number): string
	seconds = math.max(0, math.floor(seconds))
	return string.format("%d:%02d", math.floor(seconds / 60), seconds % 60)
end

local function fmtMult(m: number): string
	local text = string.format("%.1f", m)
	if Locale.IsFrench() then
		text = string.gsub(text, "%.", ",")
	end
	return "x" .. text
end

local function ensureGui(s: any): any
	if s.Gui and s.Gui.Screen.Parent then
		return s.Gui
	end
	local playerGui = LocalPlayer and LocalPlayer:FindFirstChildOfClass("PlayerGui")
	if not playerGui then
		return nil
	end
	local screen = Instance.new("ScreenGui")
	screen.Name = "FairGui"
	screen.ResetOnSpawn = false
	screen.IgnoreGuiInset = false
	screen.DisplayOrder = 25 -- (au-dessus du HUD de la ville : le menu est une fenêtre)
	screen.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	local scale = Instance.new("UIScale")
	scale.Parent = screen
	-- badge du boost (sous le compteur de Dopamine du HUD)
	local badge = Instance.new("Frame")
	badge.Name = "FoodBadge"
	badge.AnchorPoint = Vector2.new(0.5, 0)
	badge.Size = UDim2.fromOffset(190, 34)
	badge.BackgroundColor3 = Color3.fromRGB(255, 244, 250)
	badge.Visible = false
	badge.Parent = screen
	UIUtil.Corner(badge, UDim.new(1, 0))
	UIUtil.Stroke(badge, PINK, 2, 0)
	local badgeText = Instance.new("TextLabel")
	badgeText.Name = "Text"
	badgeText.BackgroundTransparency = 1
	badgeText.Size = UDim2.new(1, -16, 1, -6)
	badgeText.Position = UDim2.fromOffset(8, 3)
	badgeText.Font = Enum.Font.FredokaOne
	badgeText.TextColor3 = HOT
	badgeText.TextScaled = true
	badgeText.Text = ""
	badgeText.Parent = badge
	-- bouton "Croquer" (en bas au milieu : libre sur PC et téléphone)
	local bite = Instance.new("TextButton")
	bite.Name = "BiteButton"
	bite.AnchorPoint = Vector2.new(0.5, 1)
	bite.Size = UDim2.fromOffset(210, 54)
	bite.BackgroundColor3 = HOT
	bite.AutoButtonColor = true
	bite.Font = Enum.Font.FredokaOne
	bite.TextColor3 = WHITE
	bite.TextScaled = true
	bite.Text = ""
	bite.Visible = false
	bite.Parent = screen
	UIUtil.Corner(bite, UDim.new(1, 0))
	UIUtil.Stroke(bite, WHITE, 3, 0)
	local pad = Instance.new("UIPadding")
	pad.PaddingTop = UDim.new(0, 9)
	pad.PaddingBottom = UDim.new(0, 9)
	pad.PaddingLeft = UDim.new(0, 14)
	pad.PaddingRight = UDim.new(0, 14)
	pad.Parent = bite
	-- menu d'un stand (carte au centre)
	local dim = Instance.new("TextButton")
	dim.Name = "MenuDim"
	dim.Size = UDim2.fromScale(1, 1)
	dim.BackgroundColor3 = Color3.new(0, 0, 0)
	dim.BackgroundTransparency = 0.55
	dim.AutoButtonColor = false
	dim.Text = ""
	dim.Visible = false
	dim.Parent = screen
	local card = Instance.new("Frame")
	card.Name = "Menu"
	card.AnchorPoint = Vector2.new(0.5, 0.5)
	card.Position = UDim2.fromScale(0.5, 0.52)
	card.Size = UDim2.fromOffset(560, 340)
	card.BackgroundColor3 = Color3.fromRGB(255, 250, 253)
	card.Visible = false
	card.Parent = screen
	UIUtil.Corner(card, UDim.new(0, 22))
	UIUtil.Stroke(card, PINK, 3, 0)
	UIUtil.SinkClicks(card)
	local title = Instance.new("TextLabel")
	title.Name = "Title"
	title.BackgroundTransparency = 1
	title.Position = UDim2.fromOffset(22, 14)
	title.Size = UDim2.new(1, -90, 0, 38)
	title.Font = Enum.Font.FredokaOne
	title.TextColor3 = HOT
	title.TextScaled = true
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.Text = ""
	title.Parent = card
	local sub = Instance.new("TextLabel")
	sub.Name = "Sub"
	sub.BackgroundTransparency = 1
	sub.Position = UDim2.fromOffset(22, 54)
	sub.Size = UDim2.new(1, -44, 0, 34)
	sub.Font = Enum.Font.GothamBold
	sub.TextColor3 = INK
	sub.TextSize = 15
	sub.TextWrapped = true
	sub.TextXAlignment = Enum.TextXAlignment.Left
	sub.Text = ""
	sub.Parent = card
	local close = UIUtil.CloseButton({ Name = "CloseMenu", Size = 40, AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -14, 0, 14), ZIndex = 5, Hitbox = 0 })
	close.Parent = card
	local list = Instance.new("Frame")
	list.Name = "List"
	list.BackgroundTransparency = 1
	list.Position = UDim2.fromOffset(16, 96)
	list.Size = UDim2.new(1, -32, 1, -136)
	list.Parent = card
	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.Padding = UDim.new(0, 12)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = list
	local status = Instance.new("TextLabel")
	status.Name = "Status"
	status.BackgroundTransparency = 1
	status.AnchorPoint = Vector2.new(0.5, 1)
	status.Position = UDim2.new(0.5, 0, 1, -10)
	status.Size = UDim2.new(1, -40, 0, 26)
	status.Font = Enum.Font.GothamBold
	status.TextColor3 = INK
	status.TextScaled = true
	status.Text = ""
	status.Parent = card
	screen.Parent = playerGui
	local gui = {
		Screen = screen,
		Scale = scale,
		Badge = badge,
		BadgeText = badgeText,
		Bite = bite,
		Dim = dim,
		Card = card,
		Title = title,
		Sub = sub,
		List = list,
		Status = status,
		Cards = {},
		Conns = {},
	}
	table.insert(gui.Conns, close.Activated:Connect(function()
		FairFx.CloseMenu()
	end))
	table.insert(gui.Conns, dim.Activated:Connect(function()
		FairFx.CloseMenu()
	end))
	table.insert(gui.Conns, bite.Activated:Connect(function()
		FairFx.Bite()
	end))
	s.Gui = gui
	return gui
end

local function layoutGui(gui: any)
	local phone = isPhone()
	gui.Scale.Scale = if phone then 0.62 else 1
	gui.Card.Position = UDim2.fromScale(0.5, if phone then 0.58 else 0.52)
	gui.Badge.Position = UDim2.new(0.5, 0, 0, if phone then 64 else 84)
	-- (au-dessus du bouton "Se lever" du HUD, lui aussi en bas au milieu)
	gui.Bite.Position = UDim2.new(0.5, 0, 1, if phone then -64 else -92)
end

-- Carte d'un aliment dans le menu
local function foodCard(gui: any, food: any, order: number, stallId: string): Frame
	local card = Instance.new("Frame")
	card.Name = "Food_" .. food.Id
	card.LayoutOrder = order
	card.Size = UDim2.fromOffset(160, 196)
	card.BackgroundColor3 = WHITE
	card.Parent = gui.List
	UIUtil.Corner(card, UDim.new(0, 16))
	UIUtil.Stroke(card, Color3.fromRGB(255, 200, 224), 2, 0)
	local icon = Instance.new("TextLabel")
	icon.BackgroundTransparency = 1
	icon.Position = UDim2.fromOffset(0, 6)
	icon.Size = UDim2.new(1, 0, 0, 52)
	icon.Font = Enum.Font.GothamBold
	icon.TextScaled = true
	icon.Text = food.Icon
	icon.Parent = card
	local name = Instance.new("TextLabel")
	name.BackgroundTransparency = 1
	name.Position = UDim2.fromOffset(8, 60)
	name.Size = UDim2.new(1, -16, 0, 24)
	name.Font = Enum.Font.FredokaOne
	name.TextColor3 = INK
	name.TextScaled = true
	name.Text = Locale.T(food.Name)
	name.Parent = card
	local boost = Instance.new("TextLabel")
	boost.Name = "Boost"
	boost.BackgroundColor3 = Color3.fromRGB(255, 236, 246)
	boost.Position = UDim2.fromOffset(12, 88)
	boost.Size = UDim2.new(1, -24, 0, 26)
	boost.Font = Enum.Font.GothamBold
	boost.TextColor3 = HOT
	boost.TextScaled = true
	boost.Text = "⚡ " .. fmtMult(food.Multiplier) .. " · " .. fmtClock(food.Duration)
	boost.Parent = card
	UIUtil.Corner(boost, UDim.new(1, 0))
	local price = Instance.new("TextLabel")
	price.Name = "Price"
	price.BackgroundTransparency = 1
	price.Position = UDim2.fromOffset(8, 118)
	price.Size = UDim2.new(1, -16, 0, 22)
	price.Font = Enum.Font.GothamBold
	price.TextColor3 = Color3.fromRGB(120, 90, 160)
	price.TextScaled = true
	price.Text = ""
	price.Parent = card
	local buy = Instance.new("TextButton")
	buy.Name = "Buy"
	buy.AnchorPoint = Vector2.new(0.5, 1)
	buy.Position = UDim2.new(0.5, 0, 1, -10)
	buy.Size = UDim2.new(1, -24, 0, 38)
	buy.BackgroundColor3 = Color3.fromRGB(70, 190, 120)
	buy.Font = Enum.Font.FredokaOne
	buy.TextColor3 = WHITE
	buy.TextScaled = true
	buy.Text = Locale.T("Buy")
	buy.Parent = card
	UIUtil.Corner(buy, UDim.new(1, 0))
	local bp = Instance.new("UIPadding")
	bp.PaddingTop = UDim.new(0, 7)
	bp.PaddingBottom = UDim.new(0, 7)
	bp.Parent = buy
	table.insert(gui.Conns, buy.Activated:Connect(function()
		task.spawn(FairFx.Buy, food.Id, stallId)
	end))
	return card
end

local function currentPrice(food: any): number
	local data = ClientState.Data
	if type(data) ~= "table" then
		return FoodRules.Price(food, 0, 0, 1)
	end
	local boost = data.FoodBoost
	local m = type(boost) == "table" and (tonumber(boost.Multiplier) or 1) or 1
	return FoodRules.Price(food, data.PerSecond, data.ClickValue, m)
end

local function refreshMenu(s: any)
	local gui = s.Gui
	local menu = s.Menu
	if not gui or not menu then
		return
	end
	local have = tonumber(ClientState.Data and ClientState.Data.Dopamine) or 0
	for id, card in pairs(gui.Cards) do
		local food = Config.FoodById[id]
		if food then
			local price = currentPrice(food)
			local label = card:FindFirstChild("Price") :: TextLabel?
			if label then
				label.Text = "🧠 " .. NumberFormatter.Format(price)
				label.TextColor3 = if have >= price then Color3.fromRGB(120, 90, 160) else Color3.fromRGB(226, 80, 90)
			end
		end
	end
end

function FairFx.OpenMenu(stallId: string, foods: { string }, anchor: Vector3?)
	local s = state
	if not s then
		return
	end
	local gui = ensureGui(s)
	if not gui then
		return
	end
	layoutGui(gui)
	for _, card in pairs(gui.Cards) do
		card:Destroy()
	end
	table.clear(gui.Cards)
	local icons = {}
	for i, id in ipairs(foods) do
		local food = Config.FoodById[id]
		if food then
			gui.Cards[id] = foodCard(gui, food, i, stallId)
			table.insert(icons, food.Icon)
		end
	end
	local n = 0
	for _ in pairs(gui.Cards) do
		n += 1
	end
	gui.Card.Size = UDim2.fromOffset(math.max(400, n * 172 + 40), 344)
	gui.Title.Text = table.concat(icons, " ") .. "  " .. Locale.T("Snacks")
	gui.Sub.Text = Locale.T("Eat it for a Dopamine boost! One boost at a time, it stacks up to 5 min.")
	gui.Status.Text = ""
	gui.Dim.Visible = true
	gui.Card.Visible = true
	UIUtil.Pop(gui.Card, 0.85, 0.2)
	s.Menu = { Stall = stallId, Anchor = anchor }
	refreshMenu(s)
end

function FairFx.CloseMenu()
	local s = state
	if not s or not s.Gui then
		return
	end
	s.Menu = nil
	s.Gui.Dim.Visible = false
	s.Gui.Card.Visible = false
end

function FairFx.Buy(foodId: string, stallId: string): boolean
	local s = state
	if not s or s.Busy then
		return false
	end
	local food = Config.FoodById[foodId]
	if not food then
		return false
	end
	s.Busy = true
	local ok, success, message, missing = pcall(function()
		return Net.Function("Food"):InvokeServer("buy", foodId, stallId)
	end)
	s.Busy = false
	local gui = s.Gui
	if not ok then
		if gui then
			gui.Status.Text = Locale.T("Network error, try again.")
		end
		return false
	end
	if success then
		FairFx.CloseMenu()
		toast(tostring(message or (food.Icon .. " " .. Locale.T(food.Name))), Color3.fromRGB(70, 190, 120))
		return true
	end
	if gui then
		if type(missing) == "number" and missing > 0 then
			gui.Status.Text = Locale.T("You need %s more Dopamine", NumberFormatter.Format(math.max(1, missing))) .. "  " .. Locale.T("👆 Click to earn more!")
		else
			gui.Status.Text = tostring(message or "")
		end
		gui.Status.TextColor3 = Color3.fromRGB(226, 80, 90)
	end
	return false
end

function FairFx.Bite()
	local s = state
	if not s then
		return
	end
	task.spawn(function()
		pcall(function()
			Net.Function("Food"):InvokeServer("bite")
		end)
	end)
end

----------------------------------------------------------------------
-- Manger : bras qui porte l'aliment à la bouche + miettes (tous les
-- mangeurs visibles, d'après l'attribut "BiteAt" de l'outil)
----------------------------------------------------------------------

local BITE_UP, BITE_HOLD, BITE_DOWN = 0.18, 0.22, 0.24

local function shoulderOf(character: Model): (Motor6D?, boolean)
	local upper = character:FindFirstChild("RightUpperArm")
	local m = upper and upper:FindFirstChild("RightShoulder")
	if m and m:IsA("Motor6D") then
		return m, true
	end
	local torso = character:FindFirstChild("Torso")
	local m6 = torso and torso:FindFirstChild("Right Shoulder")
	if m6 and m6:IsA("Motor6D") then
		return m6, false
	end
	return nil, false
end

-- Rotation du bras (en plus de la pose "outil" : bras tendu devant)
local function armOffset(r15: boolean, k: number): CFrame
	if r15 then
		-- bras (tendu devant, pose "outil") relevé de 35° puis ramené de 45°
		-- vers le milieu : la main arrive devant la bouche
		return CFrame.Angles(0, math.rad(45) * k, 0) * CFrame.Angles(math.rad(35) * k, 0, 0)
	end
	-- R6 : l'épaule tourne autour de son axe Z (lever le bras vers l'avant)
	return CFrame.Angles(0, 0, math.rad(35) * k)
end

local function crumbs(tool: Tool, food: any)
	local handle = tool:FindFirstChild("Handle")
	if not handle or not handle:IsA("BasePart") then
		return
	end
	local emitter = handle:FindFirstChild("FairCrumbs") :: ParticleEmitter?
	if not emitter then
		local e = Instance.new("ParticleEmitter")
		e.Name = "FairCrumbs"
		e.Rate = 0
		e.Lifetime = NumberRange.new(0.4, 0.8)
		e.Speed = NumberRange.new(3, 6)
		e.SpreadAngle = Vector2.new(70, 70)
		e.Acceleration = Vector3.new(0, -32, 0)
		e.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.14), NumberSequenceKeypoint.new(1, 0.05) })
		e.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(1, 0.4) })
		e.Color = ColorSequence.new(food and food.Crumb or Color3.fromRGB(236, 196, 120))
		e.LightEmission = 0
		e.EmissionDirection = Enum.NormalId.Top
		e.Parent = handle
		emitter = e
	end
	if emitter then
		emitter:Emit(10)
	end
end

local function watchTool(s: any, character: Model, tool: Tool)
	if s.Tools[tool] then
		return
	end
	local entry = { Character = character, Tool = tool, Food = Config.FoodById[tool:GetAttribute("FoodId") or ""], Last = tool:GetAttribute("BiteAt") }
	s.Tools[tool] = entry
	-- (signal + relevé à 10 Hz dans scanEaters : jamais de bouchée manquée)
	entry.Check = function()
		local at = tool:GetAttribute("BiteAt")
		if type(at) ~= "number" or at == entry.Last then
			return
		end
		entry.Last = at
		crumbs(tool, entry.Food)
		local motor, r15 = shoulderOf(character)
		if motor then
			local anim = s.Arms[motor]
			if not anim then
				anim = { Motor = motor, Base = motor.C0, R15 = r15, T = 0 }
				s.Arms[motor] = anim
			end
			anim.T = 0
		end
		-- dernière bouchée (le mien) : petite fête
		if character == (LocalPlayer and LocalPlayer.Character) and (tool:GetAttribute("BitesLeft") or 1) <= 0 and entry.Food then
			local food = entry.Food
			toast("⚡ " .. Locale.T("Dopamine boost %s for %s!", fmtMult(food.Multiplier), fmtClock(food.Duration)), HOT)
		end
	end
	entry.Conn = tool:GetAttributeChangedSignal("BiteAt"):Connect(entry.Check)
end

local function stepArms(s: any, dt: number)
	for motor, anim in pairs(s.Arms) do
		anim.T += dt
		local t = anim.T
		local k
		if t < BITE_UP then
			k = t / BITE_UP
		elseif t < BITE_UP + BITE_HOLD then
			k = 1
		elseif t < BITE_UP + BITE_HOLD + BITE_DOWN then
			k = 1 - (t - BITE_UP - BITE_HOLD) / BITE_DOWN
		else
			k = 0
		end
		k = k * k * (3 - 2 * k)
		if motor.Parent then
			motor.C0 = anim.Base * armOffset(anim.R15, k)
		end
		if k <= 0 and t > BITE_UP then
			if motor.Parent then
				motor.C0 = anim.Base
			end
			s.Arms[motor] = nil
		end
	end
end

local function restoreArms(s: any)
	for motor, anim in pairs(s.Arms) do
		if motor.Parent then
			motor.C0 = anim.Base
		end
	end
	table.clear(s.Arms)
end

-- 10 fois / s : outils "DopamineFood" tenus par les avatars proches
local function scanEaters(s: any)
	for tool, entry in pairs(s.Tools) do
		if not tool.Parent or tool.Parent ~= entry.Character then
			if entry.Conn then
				entry.Conn:Disconnect()
			end
			s.Tools[tool] = nil
		end
	end
	local mine: Tool? = nil
	for _, player in ipairs(Players:GetPlayers()) do
		local character = player.Character
		if character then
			local tool = character:FindFirstChild("DopamineFood")
			if tool and tool:IsA("Tool") then
				watchTool(s, character, tool)
				local entry = s.Tools[tool]
				if entry and entry.Check then
					entry.Check()
				end
				if player == LocalPlayer then
					mine = tool
				end
			end
		end
	end
	-- bouton "Croquer" (le mien)
	local gui = s.Gui
	if mine or (gui and gui.Bite.Visible) then
		gui = ensureGui(s)
		if gui then
			layoutGui(gui)
			if mine then
				local food = Config.FoodById[mine:GetAttribute("FoodId") or ""]
				local left = tonumber(mine:GetAttribute("BitesLeft")) or 0
				gui.Bite.Text = "🍴 " .. Locale.T("Take a bite") .. " " .. (food and food.Icon or "") .. " (" .. tostring(math.max(0, math.floor(left))) .. ")"
				gui.Bite.Visible = left > 0
			else
				gui.Bite.Visible = false
			end
		end
	end
end

----------------------------------------------------------------------
-- Badge du boost (lu dans l'état du clicker : FoodBoost)
----------------------------------------------------------------------

local function onState(s: any)
	local data = ClientState.Data
	local boost = type(data) == "table" and data.FoodBoost or nil
	local remaining = type(boost) == "table" and tonumber(boost.Remaining) or 0
	local m = type(boost) == "table" and tonumber(boost.Multiplier) or 1
	if remaining and remaining > 0 and m and m > 1 then
		local newEnd = os.clock() + remaining
		if math.abs(newEnd - (s.BoostEnd or 0)) > 1 then
			s.BoostEnd = newEnd
		end
		s.BoostMult = m
		local food = Config.FoodById[boost.Food or ""]
		s.BoostIcon = food and food.Icon or "🍦"
	else
		s.BoostEnd = 0
	end
	if s.Menu then
		refreshMenu(s)
	end
end

local function stepBadge(s: any)
	local left = (s.BoostEnd or 0) - os.clock()
	local gui = s.Gui
	if left > 0 then
		gui = ensureGui(s)
		if not gui then
			return
		end
		layoutGui(gui)
		gui.Badge.Visible = true
		gui.BadgeText.Text = (s.BoostIcon or "🍦") .. " " .. Locale.T("Boost") .. " " .. fmtMult(s.BoostMult or 1) .. " · " .. fmtClock(left)
	elseif gui then
		gui.Badge.Visible = false
	end
end

----------------------------------------------------------------------
-- Autos tamponneuses : conduite (client du conducteur)
----------------------------------------------------------------------

local BUMP_MAX, BUMP_REVERSE, BUMP_ACCEL, BUMP_TURN = 14, 7, 20, 2.3

local function driveBumper(s: any, seat: VehicleSeat, dt: number)
	local body = seat.Parent
	if not body or not body:IsA("BasePart") then
		return
	end
	local velocity = body:FindFirstChild("BumperVelocity") :: LinearVelocity?
	local align = body:FindFirstChild("BumperAlign") :: AlignOrientation?
	if not velocity or not align then
		return
	end
	local d = s.Drive
	if not d or d.Seat ~= seat then
		local look = body.CFrame.LookVector
		d = { Seat = seat, Heading = math.atan2(-look.X, -look.Z), Speed = 0 }
		s.Drive = d
	end
	local def = FairRides.ById.Bumper
	local phase = FairRides.Phase(def, workspace:GetServerTimeNow())
	local throttle = math.clamp(tonumber(seat.ThrottleFloat) or 0, -1, 1)
	local steer = math.clamp(tonumber(seat.SteerFloat) or 0, -1, 1)
	if phase ~= "run" then
		throttle = 0
	end
	local look = Vector3.new(-math.sin(d.Heading), 0, -math.cos(d.Heading))
	local current = body.AssemblyLinearVelocity
	local actual = if typeof(current) == "Vector3" then current:Dot(look) else d.Speed
	local target = if throttle > 0.05 then throttle * BUMP_MAX elseif throttle < -0.05 then throttle * BUMP_REVERSE else 0
	local base = if math.abs(actual - d.Speed) > 5 then actual else d.Speed
	local speed = base + math.clamp(target - base, -BUMP_ACCEL * dt, BUMP_ACCEL * dt)
	if phase ~= "run" then
		speed = base + math.clamp(-base, -BUMP_ACCEL * 1.5 * dt, BUMP_ACCEL * 1.5 * dt)
	end
	d.Speed = speed
	-- les autos tamponneuses tournent même à l'arrêt (un peu)
	local factor = 0.45 + 0.55 * math.clamp(math.abs(speed) / BUMP_MAX, 0, 1)
	if phase == "run" then
		d.Heading -= steer * BUMP_TURN * factor * (if speed < -0.5 then -1 else 1) * dt
	end
	look = Vector3.new(-math.sin(d.Heading), 0, -math.cos(d.Heading))
	local v = look * speed
	velocity.PlaneVelocity = Vector2.new(v.X, v.Z)
	align.CFrame = CFrame.Angles(0, d.Heading, 0)
end

----------------------------------------------------------------------
-- Boucle
----------------------------------------------------------------------

local function findSources(): (Instance?, Instance?, Instance?)
	local town = workspace:FindFirstChild("DopamineTown")
	local decor = town and town:FindFirstChild("Decor")
	if not decor then
		return nil, nil, nil
	end
	local fair = decor:FindFirstChild("Fair")
	local corner = decor:FindFirstChild("FoodCorner")
	return town, (fair and fair:GetAttribute("FxVersion") ~= nil) and fair or nil, (corner and corner:GetAttribute("FxVersion") ~= nil) and corner or nil
end

local function focusPoint(): Vector3?
	local character = LocalPlayer and LocalPlayer.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if root and root:IsA("BasePart") then
		return root.Position
	end
	local camera = workspace.CurrentCamera
	return camera and camera.CFrame.Position or nil
end

local function mySeat(): BasePart?
	local character = LocalPlayer and LocalPlayer.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	return humanoid and humanoid.SeatPart or nil
end

-- Manège où l'avatar local est assis (animé à chaque image)
local function ridingFx(s: any): RideFx?
	local seat = mySeat()
	local fx = s.Fair
	if not seat or not fx then
		return nil
	end
	local rideId = seat:GetAttribute("RideId")
	if type(rideId) ~= "string" then
		return nil
	end
	for _, r in ipairs(fx.Rides) do
		if r.Def.Id == rideId then
			return r
		end
	end
	return nil
end

local function renderStep(dt: number)
	local s = state
	if not s then
		return
	end
	local ok, err = pcall(function()
		local r = ridingFx(s)
		if r then
			stepRide(r, workspace:GetServerTimeNow())
			s.RidingId = r.Def.Id
		else
			s.RidingId = nil
		end
		local seat = mySeat()
		if seat and seat:IsA("VehicleSeat") and seat.Name == "BumperSeat" then
			driveBumper(s, seat, math.min(dt, 0.1))
		elseif s.Drive then
			s.Drive = nil
		end
		if next(s.Arms) ~= nil then
			stepArms(s, math.min(dt, 0.1))
		end
	end)
	if not ok and not s.RenderWarned then
		s.RenderWarned = true
		warn("[FairFx] " .. tostring(err))
	end
end

local function dressCars(fx: any)
	local rides = fx.Source:FindFirstChild("Rides")
	local folder = rides and rides:FindFirstChild("Bumper")
	if not folder then
		return
	end
	fx.Dressed = fx.Dressed or {}
	for _, body in ipairs(folder:GetChildren()) do
		if body:IsA("BasePart") and body.Name == "BumperBody" and not fx.Dressed[body] then
			fx.Dressed[body] = dressBumper(body)
		end
	end
end

local function undressCars(fx: any)
	if fx and fx.Dressed then
		for _, model in pairs(fx.Dressed) do
			model:Destroy()
		end
		fx.Dressed = nil
	end
end

local function stepBuild(queueOwner: any): boolean
	local q = queueOwner.Queue
	if #q == 0 then
		queueOwner.Built = true
		return false
	end
	local job = table.remove(q, 1)
	local ok, err = pcall(job)
	if not ok then
		warn("[FairFx] " .. tostring(err))
	end
	return true
end

local function stepVendors(list: { any }, focus: Vector3, t: number)
	local N = npcModels()
	if not N or type(N.Animate) ~= "function" then
		return
	end
	for _, v in ipairs(list) do
		local model = v.Model
		if model.Parent and (model:GetPivot().Position - focus).Magnitude < NPC_R then
			pcall(N.Animate, model, v.Anim, t + v.Seed)
		end
	end
end

function FairFx.Start(options: any?)
	if state then
		return
	end
	state = {
		Acc = 0,
		Frame = 0,
		Time = 0,
		Slow = 0,
		Fair = nil,
		Corner = nil,
		Tools = {},
		Arms = {},
		PromptCache = {},
		PromptAge = 0,
		Busy = false,
		Menu = nil,
		Gui = nil,
		Toast = options and options.Toast or nil,
		BoostEnd = 0,
		Conns = {},
	}
	local s = state
	table.insert(s.Conns, RunService.RenderStepped:Connect(renderStep))
	table.insert(s.Conns, ProximityPromptService.PromptTriggered:Connect(function(prompt, player)
		if player ~= LocalPlayer then
			return
		end
		local stall = prompt:GetAttribute("FoodStall")
		local foods = prompt:GetAttribute("Foods")
		if type(stall) == "string" and type(foods) == "string" then
			local list = {}
			for id in string.gmatch(foods, "[^,]+") do
				table.insert(list, id)
			end
			local host = prompt.Parent
			FairFx.OpenMenu(stall, list, if host and host:IsA("BasePart") then host.Position else nil)
		end
	end))
	table.insert(s.Conns, ClientState.Changed:Connect(function()
		pcall(onState, s)
	end))
	table.insert(s.Conns, UserInputService.InputBegan:Connect(function(input, processed)
		if input.KeyCode == Enum.KeyCode.Escape and s.Menu then
			FairFx.CloseMenu()
		end
		local _ = processed
	end))
	pcall(onState, s)
end

function FairFx.Step(dt: number)
	local s = state
	if not s then
		return
	end
	s.Acc += dt
	if s.Acc < STEP then
		return
	end
	local elapsed = math.min(s.Acc, 0.25)
	s.Acc = 0
	s.Time += elapsed
	s.Slow += elapsed
	local town, fair, corner = findSources()
	local focus = focusPoint()
	if not town or not focus then
		return
	end
	-- (ville reconstruite : nos pièces sont parties)
	if s.Fair and (s.Fair.Source.Parent == nil or s.Fair.Folder.Parent == nil and s.Fair.Built) then
		undressCars(s.Fair)
		destroyFair(s)
	end
	if s.Corner and (s.Corner.Source.Parent == nil) then
		destroyCorner(s)
	end
	local t = workspace:GetServerTimeNow()
	-- 🎡 fête : construire / détruire selon la distance
	if fair then
		local F = fair:GetAttribute("FairCF")
		local dist = typeof(F) == "CFrame" and (Vector3.new(focus.X, 0, focus.Z) - Vector3.new(F.Position.X, 0, F.Position.Z)).Magnitude or math.huge
		if not s.Fair and dist < BUILD_R then
			if queueFair(s, fair) then
				s.Fair.Folder.Parent = town
			end
		elseif s.Fair and dist > DROP_R then
			undressCars(s.Fair)
			destroyFair(s)
		end
		local fx = s.Fair
		if fx then
			if not fx.Built then
				stepBuild(fx)
			end
			if dist < ANIM_R then
				-- (manèges loin de l'avatar : 15 fois / s suffisent)
				s.Frame += 1
				for _, r in ipairs(fx.Rides) do
					if r.Def.Id ~= s.RidingId then
						local far = (r.Base.Position - focus).Magnitude > 90
						if not far or s.Frame % 2 == 0 then
							stepRide(r, t)
						end
					end
				end
				if fx.Ducks then
					fx.Ducks.Step(t)
				end
				stepVendors(fx.Vendors, focus, t)
			end
		end
	end
	-- 🍦 coin gourmand
	if corner then
		local C = corner:GetAttribute("CornerCF")
		local dist = typeof(C) == "CFrame" and (focus - C.Position).Magnitude or math.huge
		if not s.Corner and dist < CORNER_BUILD_R then
			if queueCorner(s, corner) then
				s.Corner.Folder.Parent = town
			end
		elseif s.Corner and dist > CORNER_DROP_R then
			destroyCorner(s)
		end
		local cx = s.Corner
		if cx then
			if not cx.Built then
				stepBuild(cx)
			end
			stepVendors(cx.Vendors, focus, t)
		end
	end
	-- 10 fois / s : sièges répliqués, panneaux, invites, mangeurs, menu, badge
	if s.Slow >= 0.1 then
		s.Slow = 0
		s.PromptAge += 1
		local fx = s.Fair
		if fx then
			for _, r in ipairs(fx.Rides) do
				r.SeatCheck -= 0.1
				if #r.Seats == 0 and r.SeatCheck <= 0 and r.Def.Kind ~= "Bumper" then
					r.SeatCheck = 1
					findSeats(r, fx.Source)
				end
				local board = fx.Boards[r.Def.Id]
				if board then
					local phase, left = FairRides.Phase(r.Def, t)
					local text = if phase == "load" then "⏳ " .. Locale.T("Departure in %s s", tostring(math.max(1, math.ceil(left)))) else "▶ " .. Locale.T("Running")
					if board.Text ~= text then
						board.Text = text
					end
				end
			end
			dressCars(fx)
		end
		pcall(refreshPrompts, s)
		pcall(scanEaters, s)
		stepBadge(s)
		-- menu : on s'éloigne du stand -> fermé
		local menu = s.Menu
		if menu and menu.Anchor and (focus - menu.Anchor).Magnitude > MENU_RANGE then
			FairFx.CloseMenu()
		end
	end
end

function FairFx.Stop()
	local s = state
	state = nil
	if not s then
		return
	end
	for _, c in ipairs(s.Conns) do
		c:Disconnect()
	end
	for _, entry in pairs(s.Tools) do
		if entry.Conn then
			entry.Conn:Disconnect()
		end
	end
	restoreArms(s)
	undressCars(s.Fair)
	destroyFair(s)
	destroyCorner(s)
	if s.Gui then
		for _, c in ipairs(s.Gui.Conns) do
			c:Disconnect()
		end
		s.Gui.Screen:Destroy()
	end
end

function FairFx.Debug(): any
	return { State = state, StepRide = stepRide }
end

return FairFx
