--[[
	TownPlaza (ModuleScript)
	Emplacement : ServerScriptService > Services > World > TownPlaza

	⛲ La place centrale de Dopamine Town (v9.4) :
	  - pavage en pierre avec anneaux et soleil rayonnant (motifs de pavés) ;
	  - FONTAINE monumentale : bassin à margelle, eau transparente, deux
	    vasques, jets animés (particules) et, au sommet, la mascotte :
	    un CERVEAU rose kawaii qui crache de l'eau ;
	  - kiosque à musique, manège, chariot à ballons, parterres de fleurs,
	    arbres en bacs, bancs (vrais Seat), lampadaires reliés par des
	    guirlandes lumineuses ;
	  - couronne de BOUTIQUES tout autour (TownBuildings) en laissant libres
	    les débouchés des rues et la mairie (au fond, face à l'avenue).
	v9.6 (SHOPS96) : la couronne commence par les 6 BOUTIQUES OÙ L'ON ENTRE
	(TownShops : animalerie, jouets, cuisine, meubles, setup, jardinerie ;
	intérieurs construits par le client, ShopInteriors), complétées par des
	boutiques de décor fermées ; lumières adoucies (plus de "flash") :
	lumière de la fontaine 1, ampoules des guirlandes plus petites, plus de
	néon sur les grandes surfaces.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local WorldLayout = require(ReplicatedStorage.Shared.WorldLayout)
local TownKit = require(script.Parent.TownKit)
local TownBuildings = require(script.Parent.TownBuildings)
local TownShops = require(script.Parent.TownShops)

local TownPlaza = {}

local M = TownKit.M
local C = TownKit.C
local part = TownKit.Part

local WALK_Y = WorldLayout.WALK_Y
local R = WorldLayout.PLAZA_R
local FACADE_R = R + 4 -- façades des boutiques de la place

local function emitter(host: BasePart, props: { [string]: any })
	local e = Instance.new("ParticleEmitter")
	e.Name = "Water"
	e.Color = ColorSequence.new(Color3.fromRGB(214, 244, 255), Color3.fromRGB(255, 255, 255))
	e.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.15), NumberSequenceKeypoint.new(0.7, 0.35), NumberSequenceKeypoint.new(1, 1) })
	e.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.35), NumberSequenceKeypoint.new(1, 0.8) })
	e.LightEmission = 0.15
	e.Acceleration = Vector3.new(0, -24, 0)
	for key, value in pairs(props) do
		(e :: any)[key] = value
	end
	e.Parent = host
	return e
end

----------------------------------------------------------------------
-- Pavage
----------------------------------------------------------------------

local function paving(folder: Instance, O: Vector3)
	local model = TownKit.Model(folder, "Paving")
	local base = O + Vector3.new(0, WALK_Y, 0)
	TownKit.Disc(model, "Plaza", base, R, 1.3, C.Paving, M.Cobblestone, "solid")
	TownKit.Disc(model, "RingRose", base + Vector3.new(0, 0.03, 0), R - 4, 0.4, C.PavingRose, M.Cobblestone, "deco")
	TownKit.Disc(model, "RingInner", base + Vector3.new(0, 0.06, 0), R - 5.5, 0.4, C.Paving, M.Cobblestone, "deco")
	-- soleil rayonnant (16 rais de pavés lilas)
	for i = 0, 15 do
		local a = (i + 0.5) / 16 * math.pi * 2
		local d = Vector3.new(math.sin(a), 0, math.cos(a))
		local mid = base + d * 31 + Vector3.new(0, 0.1, 0)
		part(model, "Ray", Vector3.new(1.4, 0.1, 20), CFrame.lookAt(mid, mid + d), i % 2 == 0 and C.PavingLilac or C.PavingRose, M.Cobblestone, "deco")
	end
	TownKit.Disc(model, "FountainRing", base + Vector3.new(0, 0.12, 0), 21.5, 0.4, C.PavingLilac, M.Cobblestone, "deco")
	TownKit.Disc(model, "FountainApron", base + Vector3.new(0, 0.15, 0), 20, 0.4, C.Stone, M.Slate, "deco")
end

----------------------------------------------------------------------
-- Fontaine + cerveau mascotte
----------------------------------------------------------------------

local function brain(model: Instance, cf: CFrame, scale: number)
	local pink = Color3.fromRGB(255, 150, 196)
	local pinkDeep = Color3.fromRGB(240, 118, 172)
	local s = scale
	-- deux hémisphères + circonvolutions
	TownKit.Ball(model, "Lobe", (cf * CFrame.new(-1.1 * s, 0, 0)).Position, 4.2 * s, pink, M.SmoothPlastic, "decoS")
	TownKit.Ball(model, "Lobe", (cf * CFrame.new(1.1 * s, 0, 0)).Position, 4.2 * s, pink, M.SmoothPlastic, "decoS")
	local bumps = { { -1.9, 1.3, 0.6 }, { 1.9, 1.3, 0.6 }, { -0.8, 1.9, -0.6 }, { 0.8, 1.9, -0.6 }, { -2.3, 0.2, -1.1 }, { 2.3, 0.2, -1.1 }, { 0, 1.2, 1.5 } }
	for i, b in ipairs(bumps) do
		TownKit.Ball(model, "Fold", (cf * CFrame.new(b[1] * s, b[2] * s, b[3] * s)).Position, (2.1 + (i % 2) * 0.4) * s, i % 2 == 0 and pinkDeep or pink, M.SmoothPlastic, "deco")
	end
	part(model, "Groove", Vector3.new(0.18 * s, 3.2 * s, 4.2 * s), cf * CFrame.new(0, 0.6 * s, 0), pinkDeep, M.SmoothPlastic, "deco")
	-- visage kawaii (vers l'avant : -Z)
	for _, sx in ipairs({ -1, 1 }) do
		TownKit.Ball(model, "Eye", (cf * CFrame.new(sx * 0.9 * s, 0.1 * s, -2.05 * s)).Position, 0.75 * s, C.Ink, M.SmoothPlastic, "deco")
		TownKit.Ball(model, "Shine", (cf * CFrame.new(sx * 0.9 * s + 0.15 * s, 0.3 * s, -2.35 * s)).Position, 0.25 * s, C.White, M.Neon, "deco")
		part(model, "Blush", Vector3.new(0.7 * s, 0.35 * s, 0.1 * s), cf * CFrame.new(sx * 1.6 * s, -0.45 * s, -1.95 * s) * CFrame.Angles(0, sx * math.rad(20), 0), Color3.fromRGB(255, 110, 150), M.SmoothPlastic, "deco")
	end
	part(model, "Smile", Vector3.new(0.9 * s, 0.18 * s, 0.1 * s), cf * CFrame.new(0, -0.55 * s, -2.12 * s), C.Ink, M.SmoothPlastic, "deco")
end

local function fountain(folder: Instance, O: Vector3): BasePart
	local model = TownKit.Model(folder, "Fountain")
	local base = O + Vector3.new(0, WALK_Y + 0.15, 0)
	local marble = Color3.fromRGB(250, 244, 246)
	local basinR = 13.6
	-- margelle (12 blocs) : on peut s'y asseoir / grimper
	for i = 0, 11 do
		local a = (i + 0.5) / 12 * math.pi * 2
		local d = Vector3.new(math.sin(a), 0, math.cos(a))
		local p = base + d * basinR + Vector3.new(0, 1.3, 0)
		part(model, "Rim", Vector3.new(2 * basinR * math.tan(math.pi / 12) + 0.9, 2.6, 1.6), CFrame.lookAt(p, p + d), marble, M.Marble, "solid")
		part(model, "RimCap", Vector3.new(2 * basinR * math.tan(math.pi / 12) + 1.2, 0.35, 2.1), CFrame.lookAt(p + Vector3.new(0, 1.45, 0), p + Vector3.new(0, 1.45, 0) + d), C.PavingRose, M.Marble, "deco")
	end
	TownKit.Disc(model, "PoolFloor", base + Vector3.new(0, 0.1, 0), basinR, 0.4, C.WaterDeep, M.Slate, "solid")
	local water = TownKit.Disc(model, "Water", base + Vector3.new(0, 1.9, 0), basinR - 0.2, 0.5, C.Water, M.Glass, "deco")
	water.Transparency = 0.35
	water.Reflectance = 0.1
	-- pied central, vasque basse, fût, vasque haute
	TownKit.Column(model, "Pedestal", base, 6, 3.6, marble, M.Marble, "solid")
	TownKit.Disc(model, "Bowl", base + Vector3.new(0, 6.6, 0), 5.8, 0.9, C.PavingRose, M.Marble, "decoS")
	TownKit.Disc(model, "BowlWater", base + Vector3.new(0, 6.75, 0), 5.1, 0.2, C.Water, M.Glass, "deco").Transparency = 0.2
	TownKit.Column(model, "Shaft", base + Vector3.new(0, 6.6, 0), 3.6, 1.8, marble, M.Marble, "deco")
	TownKit.Disc(model, "BowlTop", base + Vector3.new(0, 10.6, 0), 3.4, 0.7, C.PavingLilac, M.Marble, "deco")
	TownKit.Column(model, "Stem", base + Vector3.new(0, 10.6, 0), 1.3, 1.2, marble, M.Marble, "deco")
	-- le cerveau mascotte au sommet (regarde l'entrée : +Z)
	local brainCF = CFrame.lookAt(base + Vector3.new(0, 13.6, 0), base + Vector3.new(0, 13.6, 10))
	brain(model, brainCF, 1)
	-- rideau d'eau de la vasque basse + jet du cerveau + 6 jets autour
	local bowl = model:FindFirstChild("Bowl") :: BasePart
	emitter(bowl, {
		Shape = Enum.ParticleEmitterShape.Disc,
		ShapeStyle = Enum.ParticleEmitterShapeStyle.Surface,
		ShapeInOut = Enum.ParticleEmitterShapeInOut.Outward,
		EmissionDirection = Enum.NormalId.Top,
		Rate = 40,
		Speed = NumberRange.new(1, 2),
		Lifetime = NumberRange.new(0.9, 1.1),
		SpreadAngle = Vector2.new(8, 8),
	})
	local nozzle = part(model, "Nozzle", Vector3.new(0.6, 0.6, 0.6), CFrame.new(base + Vector3.new(0, 16.4, 0)), C.White, M.SmoothPlastic, "deco")
	nozzle.Transparency = 1
	emitter(nozzle, {
		EmissionDirection = Enum.NormalId.Top,
		Rate = 30,
		Speed = NumberRange.new(13, 16),
		Lifetime = NumberRange.new(1.3, 1.6),
		SpreadAngle = Vector2.new(9, 9),
	})
	for i = 0, 5 do
		local a = i / 6 * math.pi * 2
		local p = base + Vector3.new(math.sin(a) * 9.5, 1.95, math.cos(a) * 9.5)
		local jet = part(model, "Jet", Vector3.new(0.5, 0.3, 0.5), CFrame.lookAt(p, base + Vector3.new(0, 1.95, 0)) * CFrame.Angles(math.rad(-35), 0, 0), C.MetalLight, M.Metal, "deco")
		emitter(jet, {
			EmissionDirection = Enum.NormalId.Top,
			Rate = 14,
			Speed = NumberRange.new(9, 11),
			Lifetime = NumberRange.new(0.9, 1.1),
			SpreadAngle = Vector2.new(4, 4),
		})
	end
	-- lumière sous l'eau (1 vraie lumière)
	-- (v9.6 : douce, pas d'éblouissement)
	TownKit.Light(water, Color3.fromRGB(150, 220, 255), 18, 1)
	-- plaque
	local plaque = part(model, "Plaque", Vector3.new(6, 1.6, 0.3), CFrame.lookAt(base + Vector3.new(0, 1.4, basinR + 0.9), base + Vector3.new(0, 1.4, basinR + 10)), Color3.fromRGB(214, 176, 96), M.Metal, "deco")
	local _, body = TownKit.Surface(plaque, Enum.NormalId.Front, 40, nil, 120, 0.3)
	TownKit.Label(body, "Text", "🧠 The Dopamine Fountain", 0.04, 0.1, 0.92, 0.8, Color3.fromRGB(92, 58, 40), Enum.Font.FredokaOne, true)
	return water
end

----------------------------------------------------------------------
-- Kiosque, manège, ballons, guirlandes
----------------------------------------------------------------------

local function bandstand(folder: Instance, center: Vector3)
	local model = TownKit.Model(folder, "Bandstand")
	local roof = Color3.fromRGB(150, 110, 200)
	TownKit.Column(model, "Platform", center, 2.2, 17, C.Stone, M.Marble, "solid")
	TownKit.Column(model, "Deck", center + Vector3.new(0, 2.2, 0), 0.2, 16, C.WoodLight, M.WoodPlanks, "deco")
	for i = 0, 7 do
		local a = (i + 0.5) / 8 * math.pi * 2
		local p = center + Vector3.new(math.sin(a) * 7.2, 2.4, math.cos(a) * 7.2)
		TownKit.Column(model, "Post", p, 8.4, 0.6, C.White, M.Metal, "prop")
		-- garde-corps entre deux poteaux (sauf l'entrée)
		if i ~= 0 then
			local b = (i + 1.5) / 8 * math.pi * 2
			local q = center + Vector3.new(math.sin(b) * 7.2, 2.4, math.cos(b) * 7.2)
			TownKit.Beam(model, "Rail", p + Vector3.new(0, 2.6, 0), q + Vector3.new(0, 2.6, 0), 0.25, 0.25, C.White, M.Metal, "deco")
		end
	end
	TownKit.Column(model, "Eave", center + Vector3.new(0, 10.8, 0), 0.6, 19, C.White, M.SmoothPlastic, "decoS")
	TownKit.Column(model, "Roof1", center + Vector3.new(0, 11.4, 0), 1.2, 17, roof, M.Slate, "decoS")
	TownKit.Column(model, "Roof2", center + Vector3.new(0, 12.6, 0), 1.2, 12.5, roof, M.Slate, "deco")
	TownKit.Column(model, "Roof3", center + Vector3.new(0, 13.8, 0), 1.2, 8, roof, M.Slate, "deco")
	TownKit.Column(model, "Roof4", center + Vector3.new(0, 15, 0), 1, 3.6, roof, M.Slate, "deco")
	TownKit.Ball(model, "Finial", center + Vector3.new(0, 16.8, 0), 1.6, C.Yellow, M.Metal, "deco")
	-- pupitres et instruments (notes de musique néon)
	part(model, "Stand", Vector3.new(0.2, 3, 0.2), CFrame.new(center + Vector3.new(-2, 3.9, 1)), C.Metal, M.Metal, "deco")
	part(model, "Note", Vector3.new(1.4, 1.8, 0.2), CFrame.new(center + Vector3.new(-2, 5.6, 1)), C.Pink, M.SmoothPlastic, "deco")
end

local function carousel(folder: Instance, center: Vector3)
	local model = TownKit.Model(folder, "Carousel")
	TownKit.Column(model, "Base", center, 1.2, 15, C.PavingLilac, M.Marble, "solid")
	TownKit.Column(model, "Pole", center + Vector3.new(0, 1.2, 0), 10, 1.6, C.Yellow, M.Metal, "prop")
	TownKit.Column(model, "Canopy", center + Vector3.new(0, 10.6, 0), 1.4, 16, C.Pink, M.Fabric, "decoS")
	TownKit.Column(model, "Canopy2", center + Vector3.new(0, 12, 0), 1.2, 11, C.White, M.Fabric, "deco")
	TownKit.Column(model, "Canopy3", center + Vector3.new(0, 13.2, 0), 1.2, 6, C.Pink, M.Fabric, "deco")
	TownKit.Ball(model, "Top", center + Vector3.new(0, 15, 0), 1.8, C.Yellow, M.Metal, "deco")
	local colors = { C.White, C.Mint, C.Sky, C.Lemon, C.Lilac, C.Peach }
	for i = 0, 5 do
		local a = i / 6 * math.pi * 2
		local d = Vector3.new(math.sin(a), 0, math.cos(a))
		local p = center + d * 5.4
		TownKit.Column(model, "HorsePole", p + Vector3.new(0, 1.2, 0), 9.4, 0.3, C.Yellow, M.Metal, "deco")
		local cf = CFrame.lookAt(p + Vector3.new(0, 3.6 + (i % 2) * 0.8, 0), p + Vector3.new(0, 3.6 + (i % 2) * 0.8, 0) + Vector3.new(d.Z, 0, -d.X))
		part(model, "Horse", Vector3.new(1, 1.4, 3), cf, colors[i + 1], M.SmoothPlastic, "deco")
		part(model, "Neck", Vector3.new(0.8, 1.8, 0.9), cf * CFrame.new(0, 1, -1.4) * CFrame.Angles(math.rad(-25), 0, 0), colors[i + 1], M.SmoothPlastic, "deco")
		part(model, "Saddle", Vector3.new(1.1, 0.3, 1.2), cf * CFrame.new(0, 0.8, 0.2), C.Pink, M.Leather, "deco")
	end
end

local function balloonCart(folder: Instance, cf: CFrame)
	local model = TownKit.Model(folder, "BalloonCart")
	part(model, "Cart", Vector3.new(4, 2.4, 2.4), cf * CFrame.new(0, 2.2, 0), C.White, M.WoodPlanks, "solid")
	part(model, "Stripe", Vector3.new(4.1, 0.6, 2.5), cf * CFrame.new(0, 2.6, 0), C.Pink, M.SmoothPlastic, "deco")
	for _, x in ipairs({ -1.5, 1.5 }) do
		local w = part(model, "Wheel", Vector3.new(0.4, 2, 2), cf * CFrame.new(x, 1, 1.3) * CFrame.Angles(0, math.rad(90), 0), C.Metal, M.Rubber, "deco")
		;(w :: Part).Shape = Enum.PartType.Cylinder
	end
	local tie = (cf * CFrame.new(0, 3.4, 0)).Position
	local colors = { C.Pink, C.Sky, C.Lemon, C.Mint, C.Lilac, Color3.fromRGB(255, 120, 120), C.Peach }
	for i = 1, 7 do
		local a = i / 7 * math.pi * 2
		local top = tie + Vector3.new(math.cos(a) * 2.4, 7.5 + (i % 3) * 1.2, math.sin(a) * 2.4)
		TownKit.Rod(model, "String", tie, top, 0.08, C.White, M.SmoothPlastic, "deco")
		TownKit.Ball(model, "Balloon", top + Vector3.new(0, 1.1, 0), 2.3, colors[i], M.SmoothPlastic, "deco").Reflectance = 0.1
	end
end

-- Guirlande lumineuse entre deux points (fil en 2 segments qui pend, ampoules)
local function garland(folder: Instance, a: Vector3, b: Vector3, seed: number)
	local mid = (a + b) / 2 - Vector3.new(0, 2.2, 0)
	TownKit.Rod(folder, "Wire", a, mid, 0.1, C.Metal, M.SmoothPlastic, "deco")
	TownKit.Rod(folder, "Wire", mid, b, 0.1, C.Metal, M.SmoothPlastic, "deco")
	local colors = { C.Glow, C.Pink, C.Sky, C.Lemon, C.Mint }
	for i = 1, 5 do
		local t = i / 6
		local p = a:Lerp(b, t) - Vector3.new(0, 2.2 * (1 - (2 * t - 1) ^ 2) + 0.35, 0)
		TownKit.Ball(folder, "Bulb", p, 0.42, colors[(i + seed) % #colors + 1], M.Neon, "deco")
	end
end

----------------------------------------------------------------------
-- Couronne de boutiques
----------------------------------------------------------------------

-- Intervalles d'angles occupés (radians, 0..2π) -> intervalles libres
local function freeArcs(blocked: { { number } }): { { number } }
	local twoPi = math.pi * 2
	local list = {}
	for _, b in ipairs(blocked) do
		local a0, a1 = b[1] % twoPi, b[2] % twoPi
		if a0 <= a1 then
			table.insert(list, { a0, a1 })
		else
			table.insert(list, { a0, twoPi })
			table.insert(list, { 0, a1 })
		end
	end
	table.sort(list, function(x, y)
		return x[1] < y[1]
	end)
	local free = {}
	local cursor = 0
	for _, b in ipairs(list) do
		if b[1] > cursor then
			table.insert(free, { cursor, b[1] })
		end
		cursor = math.max(cursor, b[2])
	end
	if cursor < twoPi then
		table.insert(free, { cursor, twoPi })
	end
	-- (recolle l'arc qui passe par 0)
	if #free >= 2 and free[1][1] == 0 and free[#free][2] == twoPi then
		local last = table.remove(free) :: { number }
		free[1] = { last[1] - twoPi, free[1][2] }
	end
	return free
end

-- (v9.6) Couronne : d'abord les 6 BOUTIQUES OÙ L'ON ENTRE (TownShops,
-- 30 studs de large : elles tiennent toujours, de 4 à 12 parcelles), puis
-- des boutiques de décor (fermées) dans la place qui reste, de part et
-- d'autre. Renvoie (boutiques de décor, boutiques où l'on entre).
local SHOP_MARGIN = 1.2 -- (studs) de chaque côté d'une façade
local function angularWidth(w: number): number
	return 2 * math.atan((w / 2 + SHOP_MARGIN) / FACADE_R)
end

local function shopRing(folder: Instance, geo: TownKit.Geo, shopsFolder: Instance): (number, number)
	local O = geo.Origin
	local blocked = {}
	for _, slot in ipairs(geo.Streets) do
		local a = geo.SlotAngle(slot)
		local half = math.atan((slot == 0 and 23 or 15) / FACADE_R)
		table.insert(blocked, { a - half, a + half })
	end
	-- mairie (au fond, face à l'avenue)
	local hallHalf = math.atan(36 / FACADE_R)
	table.insert(blocked, { math.pi - hallHalf, math.pi + hallHalf })
	local enterQueue = table.clone(TownShops.SPECS)
	-- décor : pas de 2e magasin de jouets / de fleurs (la jardinerie en vend)
	local decor = {}
	for _, spec in ipairs(TownBuildings.SHOPS) do
		if spec.Kind ~= "Toys" and spec.Kind ~= "Flowers" then
			table.insert(decor, spec)
		end
	end
	local used, entered = 0, 0
	local enterWidth = angularWidth(TownShops.W)
	for _, arc in ipairs(freeArcs(blocked)) do
		local span = arc[2] - arc[1]
		local inner, sides = {}, {}
		local total = 0
		while enterQueue[1] and total + enterWidth <= span do
			table.insert(inner, { Enter = table.remove(enterQueue, 1), Width = enterWidth })
			total += enterWidth
		end
		while true do
			local spec = decor[(used + #sides) % #decor + 1]
			local width = angularWidth(spec.W)
			if total + width > span then
				break
			end
			table.insert(sides, { Spec = spec, Width = width })
			total += width
		end
		-- décor réparti des deux côtés des boutiques où l'on entre
		local chosen = {}
		for i = 1, #sides, 2 do
			table.insert(chosen, sides[i])
		end
		for _, item in ipairs(inner) do
			table.insert(chosen, item)
		end
		for i = 2, #sides, 2 do
			table.insert(chosen, sides[i])
		end
		local a = (arc[1] + arc[2]) / 2 - total / 2
		for _, item in ipairs(chosen) do
			local angle = a + item.Width / 2
			local d = Vector3.new(math.sin(angle), 0, math.cos(angle))
			local p = O + d * FACADE_R + Vector3.new(0, WALK_Y, 0)
			-- (façade vers la place : LookVector = vers le centre)
			local cf = CFrame.lookAt(p, Vector3.new(O.X, p.Y, O.Z))
			local w = item.Enter and TownShops.W or item.Spec.W
			-- trottoir devant la boutique (un poil au-dessus du pavage : pas de
			-- faces confondues avec la place)
			part(folder, "ShopApron", Vector3.new(w + 2, 1.3, 6), cf * CFrame.new(0, -0.65 + 0.04, -2.5), C.Walk, M.Pavement, "solid")
			if item.Enter then
				entered += 1
				TownShops.Shop(shopsFolder, cf, item.Enter, entered)
			else
				TownBuildings.Shop(folder, cf, item.Spec, used + 1)
				used += 1
			end
			a += item.Width
		end
	end
	if enterQueue[1] then
		warn("[TownPlaza] boutiques sans place : " .. #enterQueue)
	end
	return used, entered
end

----------------------------------------------------------------------
-- Construction
----------------------------------------------------------------------

export type PlazaResult = { Screen: TownBuildings.Screen, ShopsUsed: number, Enterable: number }

-- `shopsFolder` : dossier des boutiques où l'on entre (DopamineTown.Shops)
function TownPlaza.Build(folder: Instance, geo: TownKit.Geo, shopsFolder: Instance?): PlazaResult
	local plaza = Instance.new("Folder")
	plaza.Name = "Plaza"
	plaza.Parent = folder
	local O = geo.Origin
	local ground = O + Vector3.new(0, WALK_Y, 0)
	paving(plaza, O)
	fountain(plaza, O)
	-- bancs autour de la fontaine (dossier vers l'extérieur, jamais dans l'axe de l'entrée)
	for i = 0, 7 do
		local a = (i + 0.5) / 8 * math.pi * 2
		local p = ground + Vector3.new(math.sin(a) * 19, 0, math.cos(a) * 19)
		TownKit.Bench(plaza, CFrame.lookAt(p, ground))
	end
	-- lampadaires + guirlandes (anneau)
	local lampR = R - 6
	local tops = {}
	for i = 0, 7 do
		local a = (i + 0.5) / 8 * math.pi * 2
		local d = Vector3.new(math.sin(a), 0, math.cos(a))
		local p = ground + d * lampR
		TownKit.Lamp(plaza, p, TownKit.Facing(-d), i % 2 == 1)
		tops[i + 1] = p + Vector3.new(0, 12.2, 0)
	end
	local lights = TownKit.Model(plaza, "StringLights")
	for i = 1, 8 do
		garland(lights, tops[i], tops[i % 8 + 1], i)
	end
	-- kiosque (arrière gauche), manège (arrière droit), ballons (avant droit)
	local function spot(angle: number, dist: number): Vector3
		return ground + Vector3.new(math.sin(angle) * dist, 0, math.cos(angle) * dist)
	end
	bandstand(plaza, spot(math.rad(225), 41))
	carousel(plaza, spot(math.rad(135), 41))
	balloonCart(plaza, CFrame.lookAt(spot(math.rad(38), 34), ground))
	-- parterres fleuris + arbres en bacs
	for i, deg in ipairs({ 58, 110, 160, 200, 250, 302, 322 }) do
		local p = spot(math.rad(deg), 48)
		if i % 2 == 1 then
			TownKit.Column(plaza, "BedRim", p, 1.4, 9, C.Stone, M.Concrete, "prop")
			TownKit.Disc(plaza, "BedSoil", p + Vector3.new(0, 1.45, 0), 4, 0.2, Color3.fromRGB(110, 78, 60), M.Ground, "deco")
			TownKit.Ball(plaza, "BedLeaves", p + Vector3.new(0, 1.6, 0), 6.4, C.GrassDark, M.Grass, "deco")
			for k = 0, 4 do
				local b = k / 5 * math.pi * 2 + i
				TownKit.Ball(plaza, "Flower", p + Vector3.new(math.cos(b) * 2.3, 3.2 + (k % 2) * 0.5, math.sin(b) * 2.3), 1.4, TownKit.FLOWERS[(i + k) % #TownKit.FLOWERS + 1], M.SmoothPlastic, "deco")
			end
		else
			TownKit.Column(plaza, "TreeBox", p, 2, 5, C.White, M.Concrete, "prop")
			TownKit.Tree(plaza, p + Vector3.new(0, 2, 0), 12, i * 13, 4)
		end
	end
	-- mairie (au fond) + écran des meilleurs joueurs
	local hallP = ground + Vector3.new(0, 0, -(R + 4))
	local hallCF = CFrame.lookAt(hallP, ground)
	part(plaza, "HallApron", Vector3.new(70, 1.3, 8), hallCF * CFrame.new(0, -0.65, -1.5), C.Walk, M.Pavement, "solid")
	local _, screen = TownBuildings.TownHall(plaza, hallCF)
	local used, entered = shopRing(plaza, geo, shopsFolder or plaza)
	return { Screen = screen, ShopsUsed = used, Enterable = entered }
end

return TownPlaza
