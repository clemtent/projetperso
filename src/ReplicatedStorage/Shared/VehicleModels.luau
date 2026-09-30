--[[
	VehicleModels (ModuleScript)
	Emplacement : ReplicatedStorage > Shared > VehicleModels

	🚌 Les autres véhicules de Dopamine Town (v9.7, VEHICLES97), construits
	en pièces : utilisé par le SERVEUR (décor fixe : TownVehicles, TownKit)
	ET par le CLIENT (circulation d'ambiance : TownTraffic). Pur : que des
	Instances, aucun service, aucune lumière, aucun Neon, aucun son.

	  Bus(opts)          : vrai bus de ville (12 m) : face avant arrondie,
	                       grand pare-brise, girouette "DOPAMINE TOWN",
	                       2 portes doubles vitrées, vitres + sièges visibles,
	                       barres jaunes, roues dans leurs passages, rétros
	                       "oreilles de lapin", livrée blanche / rose ;
	  Bike(opts)         : vélo (cadre en losange, 2 roues à jante + rayons,
	                       guidon, selle, pédalier, garde-chaîne, garde-boue,
	                       porte-bagages / panier) ; Kind = "City" | "Sport" |
	                       "Kid" (petites roues + stabilisateurs) ;
	  KickScooter(opts)  : trottinette électrique ;
	  Scooter(opts)      : scooter (type Vespa) ;
	  BikeRack(opts)     : arceaux inox (vélos garés entre les arceaux) ;
	  DeliveryVan(opts)  : camion de livraison "📦 Dopa Express" ;
	  FoodTruck(opts)    : food truck "🌮 Taco Party" (passe-plat, auvent,
	                       menu, taco géant sur le toit).
	Repère de chaque modèle : pivot = centre du DESSOUS (au sol), avant vers
	-Z. PrimaryPart "Root" invisible (boîte englobante ; CanCollide selon
	opts.Solid). Attributs : Kind, Length, Width, Height, PartCount.
	opts communs : Detail = "Full" | "Light" (circulation : moins de
	pièces), Color (couleur principale), Solid (bool).
	Textes : clé anglaise en attribut "LocText" (TownClient la traduit) ;
	opts.T = fonction de traduction (client) pour les modèles hors ville.
]]

local VehicleModels = {}

local M = Enum.Material
local PI = math.pi

-- Couleurs
local WHITE = Color3.fromRGB(248, 247, 250)
local PINK = Color3.fromRGB(255, 118, 172)
local LILAC = Color3.fromRGB(186, 150, 246)
local TRIM = Color3.fromRGB(40, 40, 50)
local TYRE = Color3.fromRGB(32, 32, 38)
local STEEL = Color3.fromRGB(200, 204, 212)
local CHROME = Color3.fromRGB(222, 226, 232)
local GLASS = Color3.fromRGB(70, 96, 124)
local GLASS_DARK = Color3.fromRGB(46, 58, 76)
local LAMP = Color3.fromRGB(255, 250, 228)
local DRL = Color3.fromRGB(255, 252, 240)
local TAIL = Color3.fromRGB(214, 36, 56)
local AMBER = Color3.fromRGB(255, 170, 60)
local POLE = Color3.fromRGB(255, 206, 64)
local FLOOR = Color3.fromRGB(96, 98, 110)
local SEAT = Color3.fromRGB(168, 96, 170)
local SEAT_BACK = Color3.fromRGB(120, 72, 140)
local LED = Color3.fromRGB(255, 184, 64)

----------------------------------------------------------------------
-- Petit kit (repère local du modèle ; tout ancré, décor sans collision)
----------------------------------------------------------------------

type K = {
	Model: Model,
	Count: number,
	T: (string) -> string,
	WheelTag: number?, -- (v9.9) pièces de la roue n° (animation : TownTraffic / CarModels.WheelRig)
	Spin: boolean?, -- (v9.9) la pièce tourne avec la roue
	Door: number?, -- (v9.9) battant de porte (bus) : n° de porte
	Leaf: number?, -- (v9.9) sens d'ouverture du battant le long de z (-1 / 1)
}

local function newKit(name: string, opts: any): K
	local model = Instance.new("Model")
	model.Name = name
	local translate = type(opts) == "table" and type(opts.T) == "function" and opts.T or function(s: string): string
		return s
	end
	return { Model = model, Count = 0, T = translate }
end

local function newPart(k: K, className: string, name: string, size: Vector3, cf: CFrame, color: Color3, material: Enum.Material?, shadow: boolean?): BasePart
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
	p.Material = material or M.SmoothPlastic
	if k.WheelTag then
		p:SetAttribute("Wheel", k.WheelTag)
		if k.Spin then
			p:SetAttribute("Spin", true)
		end
	end
	if k.Door then
		p:SetAttribute("Door", k.Door)
		p:SetAttribute("Leaf", k.Leaf or 1)
	end
	p.Parent = k.Model
	k.Count += 1
	return p
end

-- Bloc aligné : bornes x0..x1, y0..y1, z0..z1
local function box(k: K, name: string, x0: number, x1: number, y0: number, y1: number, z0: number, z1: number, color: Color3, material: Enum.Material?, shadow: boolean?): BasePart
	return newPart(k, "Part", name, Vector3.new(math.abs(x1 - x0), math.abs(y1 - y0), math.abs(z1 - z0)),
		CFrame.new((x0 + x1) / 2, (y0 + y1) / 2, (z0 + z1) / 2), color, material, shadow)
end

-- Bloc centré, tourné autour de X (angle en rad) : jantes, arches
local function boxRotX(k: K, name: string, x: number, y: number, z: number, sx: number, sy: number, sz: number, angle: number, color: Color3, material: Enum.Material?): BasePart
	return newPart(k, "Part", name, Vector3.new(sx, sy, sz), CFrame.new(x, y, z) * CFrame.Angles(angle, 0, 0), color, material)
end

-- Coin : haut côté +Z si `highBack`, sinon côté -Z
local function wedge(k: K, name: string, x0: number, x1: number, y0: number, y1: number, z0: number, z1: number, highBack: boolean, color: Color3, material: Enum.Material?): BasePart
	local cf = CFrame.new((x0 + x1) / 2, (y0 + y1) / 2, (z0 + z1) / 2)
	if not highBack then
		cf *= CFrame.Angles(0, PI, 0)
	end
	return newPart(k, "WedgePart", name, Vector3.new(math.abs(x1 - x0), math.abs(y1 - y0), math.abs(z1 - z0)), cf, color, material)
end

-- Cylindre le long de X (roues), de Z, debout (Y)
local function cylX(k: K, name: string, x: number, y: number, z: number, length: number, diameter: number, color: Color3, material: Enum.Material?, shadow: boolean?): BasePart
	local p = newPart(k, "Part", name, Vector3.new(length, diameter, diameter), CFrame.new(x, y, z), color, material, shadow)
	;(p :: Part).Shape = Enum.PartType.Cylinder
	return p
end
local function cylZ(k: K, name: string, x: number, y: number, z: number, length: number, diameter: number, color: Color3, material: Enum.Material?): BasePart
	local p = newPart(k, "Part", name, Vector3.new(length, diameter, diameter), CFrame.new(x, y, z) * CFrame.Angles(0, PI / 2, 0), color, material)
	;(p :: Part).Shape = Enum.PartType.Cylinder
	return p
end
local function cylY(k: K, name: string, x: number, y0: number, y1: number, z: number, diameter: number, color: Color3, material: Enum.Material?, shadow: boolean?): BasePart
	local p = newPart(k, "Part", name, Vector3.new(math.abs(y1 - y0), diameter, diameter), CFrame.new(x, (y0 + y1) / 2, z) * CFrame.Angles(0, 0, PI / 2), color, material, shadow)
	;(p :: Part).Shape = Enum.PartType.Cylinder
	return p
end

-- Tube cylindrique entre deux points (cadres de vélo, barres, rétros)
local function rod(k: K, name: string, a: Vector3, b: Vector3, diameter: number, color: Color3, material: Enum.Material?): BasePart
	local len = (b - a).Magnitude
	local cf = CFrame.lookAt((a + b) / 2, b) * CFrame.Angles(0, PI / 2, 0)
	local p = newPart(k, "Part", name, Vector3.new(math.max(0.05, len), diameter, diameter), cf, color, material)
	;(p :: Part).Shape = Enum.PartType.Cylinder
	return p
end

-- Plaque inclinée entre deux points (y, z) à l'abscisse x (pare-brise, dossiers)
local function slab(k: K, name: string, x: number, width: number, y0: number, z0: number, y1: number, z1: number, thick: number, color: Color3, material: Enum.Material?): BasePart
	local a = Vector3.new(x, y0, z0)
	local c = Vector3.new(x, y1, z1)
	return newPart(k, "Part", name, Vector3.new(width, thick, (c - a).Magnitude), CFrame.lookAt((a + c) / 2, c), color, material)
end

-- Anneau de `n` segments dans le plan YZ (roues de vélo) : centre (x, y, z), rayon r
local function ring(k: K, name: string, x: number, y: number, z: number, r: number, n: number, width: number, thick: number, color: Color3, material: Enum.Material?)
	local chord = 2 * r * math.sin(PI / n) + 0.02
	for i = 0, n - 1 do
		local a = (i + 0.5) / n * 2 * PI
		boxRotX(k, name, x, y + math.cos(a) * r, z + math.sin(a) * r, width, thick, chord, a, color, material)
	end
end

-- (v9.9) Coin dans le plan du flanc (x0..x1) : triangle rectangle entre la
-- corde (za, ya) -> (zb, yb) et l'horizontale y = max(ya, yb) (au-dessus)
local function chordWedge(k: K, name: string, x0: number, x1: number, za: number, ya: number, zb: number, yb: number, color: Color3, material: Enum.Material?)
	local ymax, ymin = math.max(ya, yb), math.min(ya, yb)
	if ymax - ymin < 0.02 or math.abs(zb - za) < 0.02 then
		return
	end
	local cf = CFrame.new((x0 + x1) / 2, (ya + yb) / 2, (za + zb) / 2)
	cf *= if yb > ya then CFrame.Angles(PI, 0, 0) else CFrame.Angles(0, 0, PI)
	newPart(k, "WedgePart", name, Vector3.new(math.abs(x1 - x0), ymax - ymin, math.abs(zb - za)), cf, color, material)
end

-- (v9.9) Panneau de flanc (x0..x1, y0..top) avec un passage de roue en ARC
-- (demi-cercle de rayon `ra` centré en (axle, cy)) : n segments bloc + coin
local function archPanel(k: K, name: string, x0: number, x1: number, axle: number, cy: number, ra: number, top: number, n: number, color: Color3, material: Enum.Material?)
	for i = 0, n - 1 do
		local a0 = -PI / 2 + i * PI / n
		local a1 = a0 + PI / n
		local za, ya = axle + ra * math.sin(a0), cy + ra * math.cos(a0)
		local zb, yb = axle + ra * math.sin(a1), cy + ra * math.cos(a1)
		local ymax = math.max(ya, yb)
		if top - ymax > 0.02 then
			box(k, name, math.min(x0, x1), math.max(x0, x1), ymax, top, za, zb, color, material)
		end
		chordWedge(k, name, x0, x1, za, ya, zb, yb, color, material)
	end
end

-- (v9.9) Roue de poids lourd : pneu + flanc, jante acier (voile, lèvre,
-- 8 goujons ou enjoliveur), moyeu ; pièces marquées "Wheel" / "Spin"
local function heavyWheel(k: K, index: number, x: number, y: number, z: number, side: number, d: number, width: number, full: boolean, rim: Color3?)
	k.WheelTag = index
	k.Spin = true
	cylX(k, "Tyre", x, y, z, width, d, TYRE, M.Rubber, true)
	local face = x + side * width / 2
	local function layer(name: string, out: number, thick: number, diameter: number, color: Color3, material: Enum.Material)
		cylX(k, name, face + side * (out - thick / 2), y, z, thick, diameter, color, material)
	end
	local rimColor = rim or STEEL
	if full then
		-- (couches espacées de ≥ 0,04 : aucun z-fighting)
		layer("Sidewall", 0.04, 0.1, d - 0.14, Color3.fromRGB(44, 44, 50), M.Rubber)
		layer("RimLip", 0.08, 0.1, d * 0.64, rimColor, M.Metal)
		layer("RimDish", 0.12, 0.1, d * 0.5, Color3.fromRGB(150, 154, 162), M.Metal)
		for i = 0, 7 do
			local a = i / 8 * 2 * PI
			local rr = d * 0.17
			cylX(k, "LugNut", face + side * 0.17, y + math.cos(a) * rr, z + math.sin(a) * rr, 0.08, d * 0.045, CHROME, M.Metal)
		end
		layer("Hub", 0.27, 0.12, d * 0.22, CHROME, M.Metal)
	else
		layer("Rim", 0.05, 0.1, d * 0.62, rimColor, M.Metal)
		layer("Hub", 0.1, 0.08, d * 0.22, CHROME, M.Metal)
	end
	k.WheelTag = nil
	k.Spin = nil
end

-- Panneau SurfaceGui + texte (clé anglaise "LocText" si `localize`)
local function sign(k: K, part: BasePart, face: Enum.NormalId, ppu: number, text: string, textColor: Color3, background: Color3?, font: Enum.Font?, localize: boolean?, light: number?)
	local gui = Instance.new("SurfaceGui")
	gui.Name = "Sign"
	gui.Face = face
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = ppu
	gui.LightInfluence = light or 0.5
	gui.MaxDistance = 220
	local label = Instance.new("TextLabel")
	label.Name = "Text"
	label.Size = UDim2.fromScale(0.94, 0.86)
	label.Position = UDim2.fromScale(0.03, 0.07)
	label.BackgroundTransparency = 1
	label.Font = font or Enum.Font.GothamBlack
	label.TextScaled = true
	label.TextColor3 = textColor
	label.Text = if localize then k.T(text) else text
	if localize then
		label:SetAttribute("LocText", text)
	end
	label.Parent = gui
	if background then
		local bg = Instance.new("Frame")
		bg.Name = "Back"
		bg.Size = UDim2.fromScale(1, 1)
		bg.BackgroundColor3 = background
		bg.BorderSizePixel = 0
		bg.ZIndex = 0
		bg.Parent = gui
		label.ZIndex = 2
	end
	gui.Parent = part
	return gui
end

-- Racine invisible (boîte englobante) + pivot au sol + attributs
local function finish(k: K, kind: string, x0: number, x1: number, y0: number, y1: number, z0: number, z1: number, solid: boolean): Model
	local root = box(k, "Root", x0, x1, y0, y1, z0, z1, WHITE, M.SmoothPlastic)
	root.Transparency = 1
	root.CanCollide = solid
	root.CanQuery = solid
	root.CastShadow = false
	local model = k.Model
	model.PrimaryPart = root
	root.PivotOffset = CFrame.new(0, -(y0 + y1) / 2, -(z0 + z1) / 2) * CFrame.new(-(x0 + x1) / 2, 0, 0)
	model:SetAttribute("Kind", kind)
	model:SetAttribute("Length", math.abs(z1 - z0))
	model:SetAttribute("Width", math.abs(x1 - x0))
	model:SetAttribute("Height", y1)
	model:SetAttribute("PartCount", k.Count)
	return model
end

----------------------------------------------------------------------
-- 🚌 Bus de ville
----------------------------------------------------------------------

VehicleModels.BUS = { L = 30, W = 7.6, H = 9.3, WheelD = 3.1, AxleF = -8.25, AxleR = 6.75 }

function VehicleModels.Bus(opts: any?): Model
	local o = type(opts) == "table" and opts or {}
	local full = o.Detail ~= "Light"
	local body = typeof(o.Color) == "Color3" and o.Color or WHITE
	local livery = typeof(o.Livery) == "Color3" and o.Livery or PINK
	local k = newKit("Bus", o)
	local B = VehicleModels.BUS
	local L, W = B.L, B.W
	local hw = W / 2
	local zF, zB = -L / 2, L / 2
	local yLow, floorY, sill, winTop, wallTop, roofTop = 0.7, 1.5, 3.9, 7.6, 8.4, 8.85
	local r = B.WheelD / 2
	local ra = r + 0.35 -- demi-ouverture des passages de roue
	local archTop = B.WheelD + 0.35
	local rc = 0.7 -- rayon des coins avant
	local rcb = 0.5 -- rayon des coins arrière
	local wall = 0.3
	-- portes (côté droit = +X, trottoir) : avant (devant l'essieu) et milieu
	local doorF0, doorF1 = zF + 1.5, zF + 4.6
	local doorM0, doorM1 = B.AxleF + ra + 1.2, B.AxleF + ra + 4.8
	local glassT = if full then 0.35 else 0.1
	local glassC = if full then GLASS else GLASS_DARK

	-- ░ châssis, plancher, passages de roue ░
	box(k, "Chassis", -hw + 1.25, hw - 1.25, yLow, floorY - 0.2, zF + 1, zB - 1, TRIM, M.SmoothPlastic)
	box(k, "Floor", -hw + wall, hw - wall, floorY - 0.2, floorY, zF + 0.4, zB - 0.3, FLOOR, M.Slate)
	local wheelIndex = 0
	for _, za in ipairs({ B.AxleF, B.AxleR }) do
		for _, sx in ipairs({ -1, 1 }) do
			local x0, x1 = sx * (hw - 1.3), sx * (hw - 0.34)
			box(k, "WheelHousing", math.min(x0, x1), math.max(x0, x1), yLow + 0.02, archTop, za - ra, za + ra, TRIM, M.SmoothPlastic)
			-- (v9.9) vraie roue de bus (jante acier, goujons) + passage de roue en ARC
			wheelIndex += 1
			heavyWheel(k, wheelIndex, sx * (hw - 0.55), r, za, sx, B.WheelD, 1.0, full, nil)
			archPanel(k, "ArchPanel", sx * (hw - wall), sx * hw, za, r, ra, sill, if full then 5 else 3, livery, M.SmoothPlastic)
			-- lèvre de caoutchouc noir autour de l'arche
			if full then
				local n = 5
				for i = 0, n - 1 do
					local a = -PI / 2 + (i + 0.5) * PI / n
					local rr = ra + 0.08
					local lx0, lx1 = sx * (hw - 0.1), sx * (hw + 0.05)
					boxRotX(k, "ArchLip", (lx0 + lx1) / 2, r + math.cos(a) * rr, za + math.sin(a) * rr, math.abs(lx1 - lx0), 0.16, 2 * rr * math.tan(PI / (2 * n)) + 0.03, a, TRIM, M.Rubber)
				end
			end
		end
	end

	-- ░ flancs : bas rose (jupe) + bande blanche sous les vitres, coupés
	-- aux passages de roue (et aux portes côté droit) ░
	local split = 2.4 -- hauteur de la jupe rose
	for _, sx in ipairs({ -1, 1 }) do
		local cuts = { { B.AxleF - ra, B.AxleF + ra }, { B.AxleR - ra, B.AxleR + ra } }
		if sx > 0 then
			table.insert(cuts, { doorF0, doorF1 })
			table.insert(cuts, { doorM0, doorM1 })
		end
		table.sort(cuts, function(a, b)
			return a[1] < b[1]
		end)
		local segs = {}
		local zs = zF + rc
		for _, c in ipairs(cuts) do
			if c[1] - zs > 0.05 then
				table.insert(segs, { zs, c[1] })
			end
			zs = c[2]
		end
		if zB - rcb - zs > 0.05 then
			table.insert(segs, { zs, zB - rcb })
		end
		local x0, x1 = sx * (hw - wall), sx * hw
		local lo, hi = math.min(x0, x1), math.max(x0, x1)
		for i, sg in ipairs(segs) do
			box(k, "Skirt", lo, hi, yLow, split, sg[1], sg[2], livery, M.SmoothPlastic, true)
			local band = box(k, "SideBand", lo, hi, split, sill, sg[1], sg[2], body, M.SmoothPlastic, true)
			-- logo "🧠 DOPAMINE TOWN" sur le plus long panneau
			local longest = true
			for _, other in ipairs(segs) do
				if other[2] - other[1] > sg[2] - sg[1] + 0.01 then
					longest = false
				end
			end
			if full and longest and i > 0 then
				sign(k, band, if sx > 0 then Enum.NormalId.Right else Enum.NormalId.Left, 24, "🧠 DOPAMINE TOWN", PINK, nil, Enum.Font.FredokaOne, false)
			end
		end
		-- vague rose qui monte vers l'arrière (livrée)
		local wz0, wz1 = B.AxleR + ra + 0.05, zB - rcb - 0.05
		local wx0, wx1 = sx * (hw - 0.05), sx * (hw + 0.03)
		wedge(k, "Swoosh", math.min(wx0, wx1), math.max(wx0, wx1), split, sill - 0.25, wz0, wz1, true, livery, M.SmoothPlastic)
		-- bande haute (au-dessus des vitres)
		box(k, "UpperWall", lo, hi, winTop, wallTop, zF + rc, zB - rcb, body, M.SmoothPlastic, true)
		-- joint noir sous les vitres
		local jx0, jx1 = sx * (hw - 0.1), sx * (hw + 0.03)
		box(k, "WindowSeal", math.min(jx0, jx1), math.max(jx0, jx1), sill - 0.06, sill + 0.08, zF + rc, zB - rcb, TRIM, M.Rubber)
		-- vitres (côté droit : interrompues par les portes)
		local gx0, gx1 = sx * (hw - 0.22), sx * (hw - 0.08)
		local glo, ghi = math.min(gx0, gx1), math.max(gx0, gx1)
		local runs = if sx > 0 then { { doorF1 + 0.08, doorM0 - 0.08 }, { doorM1 + 0.08, zB - 1.2 } } else { { zF + rc, zB - 1.2 } }
		for _, run in ipairs(runs) do
			box(k, "Window", glo, ghi, sill + 0.08, winTop, run[1], run[2], glassC, M.Glass).Transparency = glassT
			-- montants noirs tous les ~3,6 studs
			local n = math.max(1, math.floor((run[2] - run[1]) / 3.6 + 0.5))
			for j = 1, n - 1 do
				local z = run[1] + j * (run[2] - run[1]) / n
				local px0, px1 = sx * (hw - 0.12), sx * (hw + 0.04)
				box(k, "WindowPost", math.min(px0, px1), math.max(px0, px1), sill + 0.08, winTop, z - 0.16, z + 0.16, TRIM, M.SmoothPlastic)
			end
		end
		-- bout arrière vitré (bande arrière au-delà de la dernière vitre)
		box(k, "RearQuarter", lo, hi, sill, winTop, zB - 1.2, zB - rcb, body, M.SmoothPlastic)
	end

	-- ░ portes doubles vitrées (côté droit) + marches ░
	for doorIndex, d in ipairs({ { doorF0, doorF1 }, { doorM0, doorM1 } }) do
		local z0, z1 = d[1], d[2]
		local zc = (z0 + z1) / 2
		local x0, x1 = hw - 0.2, hw - 0.06
		box(k, "DoorStep", hw - 1.1, hw - 0.1, yLow + 0.04, floorY - 0.06, z0 + 0.1, z1 - 0.1, FLOOR, M.DiamondPlate)
		if full then
			-- (v9.9) 2 battants louvoyants (attributs Door / Leaf : TownTraffic
			-- les ouvre à l'arrêt : ils sortent puis glissent de chaque côté)
			for leafIndex, side in ipairs({ { z0 + 0.1, zc - 0.05 }, { zc + 0.05, z1 - 0.1 } }) do
				k.Door = doorIndex
				k.Leaf = if leafIndex == 1 then -1 else 1
				box(k, "DoorGlass", x0, x1, floorY + 0.9, winTop - 0.15, side[1], side[2], GLASS, M.Glass).Transparency = 0.3
				box(k, "DoorKick", x0 - 0.02, x1 + 0.02, floorY, floorY + 0.9, side[1], side[2], TRIM, M.SmoothPlastic)
				local sealZ = if leafIndex == 1 then side[2] else side[1]
				box(k, "DoorSeal", x0 - 0.04, hw + 0.05, floorY + 0.03, winTop - 0.16, sealZ - 0.05, sealZ + 0.05, TRIM, M.Rubber)
				k.Door = nil
				k.Leaf = nil
			end
			box(k, "DoorHeader", hw - 0.3, hw + 0.04, winTop - 0.15, winTop, z0, z1, TRIM, M.SmoothPlastic)
			for _, zz in ipairs({ z0, z1 }) do
				box(k, "DoorJamb", hw - 0.26, hw + 0.04, floorY, winTop - 0.02, zz - 0.1, zz + 0.1, TRIM, M.SmoothPlastic)
			end
		else
			for leafIndex, side in ipairs({ { z0 + 0.05, zc - 0.03 }, { zc + 0.03, z1 - 0.05 } }) do
				k.Door = doorIndex
				k.Leaf = if leafIndex == 1 then -1 else 1
				box(k, "DoorGlass", x0, x1, floorY, winTop, side[1], side[2], GLASS_DARK, M.Glass).Transparency = 0.1
				k.Door = nil
				k.Leaf = nil
			end
		end
	end

	-- ░ face avant arrondie : coins, tablier, pare-brise, girouette ░
	for _, sx in ipairs({ -1, 1 }) do
		cylY(k, "CornerLow", sx * (hw - rc), yLow + 0.04, sill, zF + rc, rc * 2, body, M.SmoothPlastic, true)
		cylY(k, "CornerHigh", sx * (hw - rc), sill, wallTop, zF + rc, rc * 2, TRIM, M.SmoothPlastic)
		cylY(k, "CornerRearLow", sx * (hw - rcb), yLow, split, zB - rcb, rcb * 2, livery, M.SmoothPlastic)
		cylY(k, "CornerRear", sx * (hw - rcb), split, wallTop, zB - rcb, rcb * 2, body, M.SmoothPlastic)
	end
	box(k, "FrontPanel", -hw + rc, hw - rc, yLow, 3.3, zF, zF + rc, body, M.SmoothPlastic, true)
	box(k, "FrontSkirt", -hw + rc, hw - rc, yLow + 0.08, 1.5, zF - 0.05, zF + 0.5, livery, M.SmoothPlastic)
	box(k, "Bumper", -hw + 0.3, hw - 0.3, yLow - 0.1, yLow + 0.55, zF - 0.25, zF + 0.4, TRIM, M.SmoothPlastic)
	-- pare-brise panoramique (léger fruit vers l'arrière)
	slab(k, "Windshield", 0, W - 2 * rc + 0.2, 3.3, zF + 0.3, 6.9, zF + 0.7, 0.16, glassC, M.Glass).Transparency = if full then 0.3 else 0.12
	box(k, "WindshieldBase", -hw + rc, hw - rc, 3.2, 3.42, zF + 0.1, zF + 0.6, TRIM, M.Rubber)
	-- girouette (panneau à LED) + bandeau au-dessus (sous le nez arrondi du toit)
	local dest = box(k, "DestinationSign", -hw + rc + 0.1, hw - rc - 0.1, 6.9, 7.85, zF + 0.5, zF + 0.95, Color3.fromRGB(24, 22, 30), M.SmoothPlastic)
	local destGui = sign(k, dest, Enum.NormalId.Front, 30, "DOPAMINE TOWN", LED, Color3.fromRGB(24, 22, 30), Enum.Font.Arcade, false, 0.3)
	local destText = destGui:FindFirstChild("Text") :: TextLabel?
	if destText then
		destText.Position = UDim2.fromScale(0.2, 0.12)
		destText.Size = UDim2.fromScale(0.77, 0.76)
	end
	local lineNo = Instance.new("TextLabel")
	lineNo.Name = "Line"
	lineNo.BackgroundColor3 = LED
	lineNo.BorderSizePixel = 0
	lineNo.Position = UDim2.fromScale(0.03, 0.1)
	lineNo.Size = UDim2.fromScale(0.13, 0.8)
	lineNo.Font = Enum.Font.GothamBlack
	lineNo.TextScaled = true
	lineNo.TextColor3 = Color3.fromRGB(24, 22, 30)
	lineNo.Text = "9"
	lineNo.ZIndex = 2
	lineNo.Parent = destGui
	box(k, "FrontHeader", -hw + rc, hw - rc, 7.85, wallTop, zF + 0.55, zF + 1.0, body, M.SmoothPlastic)
	-- toit arrondi, climatisation, trappe
	box(k, "Roof", -hw + 0.45, hw - 0.45, wallTop, roofTop, zF + 0.6, zB - 0.4, body, M.SmoothPlastic, true)
	for _, sx in ipairs({ -1, 1 }) do
		cylZ(k, "RoofEdge", sx * (hw - 0.45), wallTop, (zF + 0.6 + zB - 0.4) / 2, L - 1.0, 0.9, body, M.SmoothPlastic)
	end
	cylX(k, "RoofNose", 0, wallTop, zF + 0.6, W - 0.9, 0.9, body, M.SmoothPlastic)
	box(k, "AirCon", -2.1, 2.1, roofTop, roofTop + 0.7, 1.5, 7.5, Color3.fromRGB(226, 226, 234), M.SmoothPlastic, true)
	if full then
		for _, z in ipairs({ 3.2, 5.8 }) do
			cylY(k, "Fan", -0.9, roofTop + 0.7, roofTop + 0.76, z, 1.3, TRIM, M.Metal)
			cylY(k, "Fan", 0.9, roofTop + 0.7, roofTop + 0.76, z, 1.3, TRIM, M.Metal)
		end
		box(k, "RoofHatch", -1, 1, roofTop, roofTop + 0.18, -6.5, -4.7, Color3.fromRGB(210, 212, 222), M.SmoothPlastic)
	end
	-- (v9.9) masque avant noir laqué sur toute la largeur (bus moderne) +
	-- blocs optiques : boîtier, 2 modules ronds, bande LED, clignotant
	box(k, "FrontMask", -hw + rc - 0.05, hw - rc + 0.05, 1.55, 2.75, zF - 0.08, zF + 0.3, TRIM, M.SmoothPlastic).Reflectance = 0.15
	for _, sx in ipairs({ -1, 1 }) do
		local x0, x1 = sx * (hw - rc - 0.15), sx * (hw - rc - 1.75)
		box(k, "HeadlightHousing", math.min(x0, x1), math.max(x0, x1), 1.7, 2.6, zF - 0.14, zF + 0.3, Color3.fromRGB(56, 58, 66), M.Metal)
		for _, f in ipairs({ 0.3, 0.72 }) do
			cylZ(k, "Headlight", sx * (hw - rc - 0.15 - 1.6 * f), 2.22, zF - 0.17, 0.08, 0.6, LAMP, M.Glass)
		end
		if full then
			local l0, l1 = sx * (hw - rc - 0.25), sx * (hw - rc - 1.65)
			box(k, "HeadlightDRL", math.min(l0, l1), math.max(l0, l1), 1.76, 1.86, zF - 0.19, zF + 0.2, DRL, M.SmoothPlastic)
			local i0, i1 = sx * (hw - rc + 0.02), sx * (hw - rc - 0.12)
			box(k, "Indicator", math.min(i0, i1), math.max(i0, i1), 1.75, 2.55, zF - 0.12, zF + 0.3, AMBER, M.SmoothPlastic)
		end
	end
	local logo = box(k, "FrontLogo", -0.6, 0.6, 2.8, 3.2, zF - 0.04, zF + 0.02, body, M.SmoothPlastic)
	sign(k, logo, Enum.NormalId.Front, 30, "🧠", PINK, nil, Enum.Font.GothamBlack, false)
	box(k, "PlateFront", -1.1, 1.1, 0.9, 1.4, zF - 0.33, zF - 0.27, Color3.fromRGB(248, 248, 244), M.SmoothPlastic)
	-- essuie-glaces (posés à 0,04 devant la vitre)
	if full then
		for _, sx in ipairs({ -1, 1 }) do
			slab(k, "Wiper", sx * 1.1, 0.1, 3.5, zF + 0.2, 5.4, zF + 0.4, 0.08, TRIM, M.SmoothPlastic)
		end
	end
	-- rétroviseurs "oreilles de lapin"
	for _, sx in ipairs({ -1, 1 }) do
		local top = Vector3.new(sx * (hw - 0.3), 7.9, zF + 0.9)
		local out = Vector3.new(sx * (hw + 0.45), 7.7, zF - 0.9)
		local down = Vector3.new(sx * (hw + 0.45), 6.3, zF - 0.9)
		rod(k, "MirrorArm", top, out, 0.14, TRIM, M.Metal)
		if full then
			rod(k, "MirrorArm", out, down, 0.12, TRIM, M.Metal)
		end
		box(k, "Mirror", sx * (hw + 0.45) - 0.28, sx * (hw + 0.45) + 0.28, 5.0, 6.35, zF - 1.02, zF - 0.72, TRIM, M.SmoothPlastic)
	end

	-- ░ arrière : paroi, lunette, feux verticaux, grille moteur, pare-chocs ░
	local back = box(k, "RearWall", -hw + rcb, hw - rcb, yLow, wallTop, zB - 0.3, zB, body, M.SmoothPlastic, true)
	box(k, "RearSkirt", -hw + rcb, hw - rcb, yLow, split, zB - 0.25, zB + 0.03, livery, M.SmoothPlastic)
	box(k, "RearWindow", -hw + 1.2, hw - 1.2, 5.3, winTop, zB - 0.02, zB + 0.06, glassC, M.Glass).Transparency = glassT
	box(k, "EngineGrille", -2.2, 2.2, 1.5, 2.3, zB - 0.02, zB + 0.08, TRIM, M.SmoothPlastic)
	if full then
		for j = 0, 2 do
			local y = 1.66 + j * 0.25
			box(k, "Louver", -2.1, 2.1, y, y + 0.08, zB + 0.08, zB + 0.12, Color3.fromRGB(70, 70, 82), M.Metal)
		end
		local ad = box(k, "RearAd", -2.6, 2.6, 2.9, 4.9, zB - 0.02, zB + 0.05, Color3.fromRGB(255, 226, 240), M.SmoothPlastic)
		sign(k, ad, Enum.NormalId.Back, 24, "🧠 Click more!", PINK, nil, Enum.Font.FredokaOne, true)
	end
	for _, sx in ipairs({ -1, 1 }) do
		local x0, x1 = sx * (hw - rcb - 0.05), sx * (hw - rcb - 0.55)
		box(k, "Taillight", math.min(x0, x1), math.max(x0, x1), 2.8, 4.9, zB - 0.02, zB + 0.1, TAIL, M.Glass)
		if full then
			box(k, "RearIndicator", math.min(x0, x1), math.max(x0, x1), 5.0, 5.5, zB - 0.02, zB + 0.1, AMBER, M.SmoothPlastic)
			box(k, "ReverseLight", math.min(x0, x1), math.max(x0, x1), 2.3, 2.7, zB - 0.02, zB + 0.1, Color3.fromRGB(236, 236, 240), M.Glass)
		end
	end
	box(k, "RearBumper", -hw + 0.3, hw - 0.3, yLow - 0.1, yLow + 0.55, zB - 0.4, zB + 0.25, TRIM, M.SmoothPlastic)
	local routeBox = box(k, "RearRoute", -0.8, 0.8, 7.7, 8.25, zB - 0.02, zB + 0.06, Color3.fromRGB(24, 22, 30), M.SmoothPlastic)
	sign(k, routeBox, Enum.NormalId.Back, 30, "9", LED, Color3.fromRGB(24, 22, 30), Enum.Font.Arcade, false, 0.3)
	local _ = back

	-- ░ intérieur (vu par les vitres) : sièges, barres, poste de conduite ░
	if full then
		local function seatAt(x: number, z: number, raise: number, facing: number)
			local top = floorY + 1.5 + raise
			box(k, "Seat", x - 1.1, x + 1.1, top - 0.35, top, z - 0.65, z + 0.6, SEAT, M.Fabric)
			local backZ = z + facing * 0.75
			slab(k, "SeatBack", x, 2.2, top, backZ, top + 1.9, backZ + facing * 0.3, 0.3, SEAT_BACK, M.Fabric)
		end
		local seatX = hw - wall - 1.25
		-- rangée gauche (côté conducteur), du poste de conduite au fond
		local z = zF + 5.4
		while z < zB - 2.2 do
			local onWheel = math.abs(z - B.AxleF) < ra or math.abs(z - B.AxleR) < ra
			seatAt(-seatX, z, if onWheel then archTop - floorY - 1.1 else 0, 1)
			z += 2.6
		end
		-- rangée droite : hors des portes
		z = doorF1 + 1.2
		while z < zB - 2.2 do
			local inDoor = z + 0.8 > doorM0 - 0.3 and z - 0.8 < doorM1 + 0.3
			if not inDoor then
				local onWheel = math.abs(z - B.AxleF) < ra or math.abs(z - B.AxleR) < ra
				seatAt(seatX, z, if onWheel then archTop - floorY - 1.1 else 0, 1)
			end
			z += 2.6
		end
		-- banquette du fond
		box(k, "RearBench", -hw + wall + 0.1, hw - wall - 0.1, floorY + 1.15, floorY + 1.5, zB - 1.9, zB - 0.6, SEAT, M.Fabric)
		slab(k, "RearBenchBack", 0, W - 2 * wall - 0.2, floorY + 1.5, zB - 0.55, floorY + 3.4, zB - 0.4, 0.25, SEAT_BACK, M.Fabric)
		-- barres jaunes verticales (portes, allée) + mains courantes au plafond
		for _, pz in ipairs({ doorF1 + 0.3, doorM0 - 0.3, doorM1 + 0.3, -9.5, 0.8, 9.5 }) do
			cylY(k, "Pole", 0.9, floorY, wallTop - 0.05, pz, 0.18, POLE, M.Metal)
		end
		for _, sx in ipairs({ -1, 1 }) do
			rod(k, "Handrail", Vector3.new(sx * 1.6, 7.1, zF + 4.5), Vector3.new(sx * 1.6, 7.1, zB - 2), 0.14, POLE, M.Metal)
		end
		box(k, "CeilingLight", -0.5, 0.5, wallTop - 0.08, wallTop, zF + 3, zB - 2, Color3.fromRGB(252, 250, 244), M.SmoothPlastic)
		-- poste de conduite (à gauche) : siège, volant presque à plat, tableau de bord, valideur
		local dx = -hw + 1.7
		box(k, "DriverSeat", dx - 0.75, dx + 0.75, floorY + 1.1, floorY + 1.45, zF + 2.4, zF + 3.6, TRIM, M.Fabric)
		slab(k, "DriverBack", dx, 1.4, floorY + 1.45, zF + 3.65, floorY + 3.6, zF + 3.95, 0.3, TRIM, M.Fabric)
		box(k, "Dashboard", -hw + 0.4, hw - 2.2, 2.4, 3.25, zF + 0.75, zF + 1.7, Color3.fromRGB(60, 60, 72), M.SmoothPlastic)
		-- volant de bus : presque à plat, incliné vers le conducteur
		local wheelPart = newPart(k, "Part", "SteeringWheel", Vector3.new(0.1, 1.3, 1.3), CFrame.new(dx, 3.6, zF + 2.0) * CFrame.Angles(math.rad(35), 0, 0) * CFrame.Angles(0, 0, PI / 2), TRIM, M.SmoothPlastic)
		;(wheelPart :: Part).Shape = Enum.PartType.Cylinder
		rod(k, "SteeringColumn", Vector3.new(dx, 2.6, zF + 1.5), Vector3.new(dx, 3.55, zF + 1.95), 0.16, TRIM, M.SmoothPlastic)
		box(k, "TicketMachine", -0.55, -0.1, floorY, floorY + 3.3, zF + 3.2, zF + 3.6, Color3.fromRGB(90, 200, 170), M.SmoothPlastic)
	end

	local model = finish(k, "Bus", -hw, hw, yLow, roofTop + 0.7, zF - 0.3, zB + 0.3, o.Solid == true)
	model:SetAttribute("DoorSide", 1)
	return model
end

----------------------------------------------------------------------
-- 🚲 Vélos
----------------------------------------------------------------------

-- Roue de vélo : pneu en anneau, jante, rayons (barres croisées), moyeu
local function bikeWheel(k: K, y: number, z: number, d: number, rim: Color3, spokes: number, light: boolean)
	local r = d / 2
	ring(k, "Tyre", 0, y, z, r - 0.07, if light then 8 else 12, 0.13, 0.14, TYRE, M.Rubber)
	if not light then
		ring(k, "RimRing", 0, y, z, r - 0.19, 12, 0.08, 0.07, rim, M.Metal)
	end
	-- (v9.9) rayons croisés des deux côtés du moyeu (2 nappes décalées : on
	-- voit la roue "à rayons" de près), valve
	for i = 0, spokes - 1 do
		local a = i / spokes * PI
		boxRotX(k, "Spokes", -0.03, y, z, 0.02, 0.025, d - 0.36, a, STEEL, M.Metal)
		if not light then
			boxRotX(k, "Spokes", 0.03, y, z, 0.02, 0.025, d - 0.36, a + PI / spokes / 2, STEEL, M.Metal)
		end
	end
	cylX(k, "Hub", 0, y, z, 0.2, 0.18, STEEL, M.Metal)
	if not light then
		cylX(k, "HubFlange", 0, y, z, 0.12, 0.3, CHROME, M.Metal)
	end
end

function VehicleModels.Bike(opts: any?): Model
	local o = type(opts) == "table" and opts or {}
	local kind = if o.Kind == "Kid" or o.Kind == "Sport" then o.Kind else "City"
	local light = o.Detail == "Light"
	local color = typeof(o.Color) == "Color3" and o.Color or Color3.fromRGB(126, 196, 255)
	local k = newKit("Bike", o)
	local kid = kind == "Kid"
	local s = if kid then 0.62 else 1 -- échelle
	local d = (if kid then 1.4 else 2.2) -- diamètre des roues
	local r = d / 2
	local zR, zFr = 1.72 * s, -1.72 * s
	local P = function(y: number, z: number): Vector3
		return Vector3.new(0, y, z)
	end
	-- points du cadre (cadre en losange ; "City" : tube supérieur plongeant)
	local rear = P(r, zR)
	local bb = P(r - 0.12 * s, 0.3 * s)
	local seatTop = P(r + 1.45 * s, 0.72 * s)
	local headTop = P(r + (if kind == "City" then 1.55 else 1.6) * s, -1.0 * s)
	local headBot = P(r + 1.05 * s, -1.2 * s)
	local front = P(r, zFr)
	local tube = if kid then 0.14 else 0.13
	rod(k, "DownTube", bb, headBot, tube + 0.02, color, M.Metal)
	rod(k, "SeatTube", bb, seatTop, tube, color, M.Metal)
	if kind == "City" then
		-- cadre col-de-cygne : tube bas incliné du pédalier vers la douille
		rod(k, "TopTube", seatTop + Vector3.new(0, -0.55 * s, 0.05), headBot + Vector3.new(0, 0.3 * s, 0), tube, color, M.Metal)
	else
		rod(k, "TopTube", seatTop + Vector3.new(0, -0.08, 0), headTop + Vector3.new(0, -0.12, 0), tube, color, M.Metal)
	end
	rod(k, "HeadTube", headBot, headTop, tube + 0.05, color, M.Metal)
	for _, sx in ipairs({ -1, 1 }) do
		local off = Vector3.new(sx * 0.11, 0, 0)
		rod(k, "ChainStay", bb + off, rear + off, 0.08, color, M.Metal)
		rod(k, "SeatStay", seatTop + Vector3.new(0, -0.1, 0) + off * 0.6, rear + off, 0.07, color, M.Metal)
		rod(k, "Fork", headBot + off * 0.7, front + off, 0.09, if kind == "Sport" then TRIM else color, M.Metal)
	end
	-- roues
	local rimColor = if kind == "Sport" then TRIM else STEEL
	bikeWheel(k, r, zR, d, rimColor, if light then 2 else 6, light)
	bikeWheel(k, r, zFr, d, rimColor, if light then 2 else 6, light)
	-- selle + tige
	local post = seatTop + Vector3.new(0, 0.35 * s, 0.03)
	rod(k, "SeatPost", seatTop, post, 0.09, STEEL, M.Metal)
	box(k, "Saddle", -0.2, 0.2, post.Y, post.Y + 0.16, post.Z - 0.42 * s, post.Z + 0.3 * s, Color3.fromRGB(60, 44, 40), M.Leather)
	-- potence + cintre / guidon
	local stem = headTop + Vector3.new(0, 0.3 * s, (if kind == "Sport" then -0.25 else 0.05) * s)
	rod(k, "Stem", headTop, stem, 0.1, STEEL, M.Metal)
	local barW = (if kind == "Sport" then 0.55 else 0.8) * s + (if kid then 0.1 else 0)
	local barBack = if kind == "City" then 0.35 * s else 0
	rod(k, "Handlebar", stem + Vector3.new(-barW, 0, barBack), stem + Vector3.new(barW, 0, barBack), 0.08, STEEL, M.Metal)
	for _, sx in ipairs({ -1, 1 }) do
		cylX(k, "Grip", sx * (barW - 0.12), stem.Y, stem.Z + barBack, 0.26, 0.14, Color3.fromRGB(60, 44, 40), M.Rubber)
	end
	-- pédalier : plateau, manivelles, pédales ; garde-chaîne
	cylX(k, "Chainring", 0.2, bb.Y, bb.Z, 0.05, 0.75 * s + 0.1, STEEL, M.Metal)
	for _, sx in ipairs({ -1, 1 }) do
		local a = if sx > 0 then math.rad(25) else math.rad(205)
		local tip = bb + Vector3.new(sx * 0.3, -math.cos(a) * 0.5 * s, math.sin(a) * 0.5 * s)
		rod(k, "Crank", bb + Vector3.new(sx * 0.24, 0, 0), tip, 0.08, STEEL, M.Metal)
		box(k, "Pedal", tip.X + (if sx > 0 then 0.02 else -0.3), tip.X + (if sx > 0 then 0.3 else -0.02), tip.Y - 0.05, tip.Y + 0.05, tip.Z - 0.14, tip.Z + 0.14, TRIM, M.Rubber)
	end
	if not light and kind ~= "Sport" then
		-- garde-chaîne (le long de la base, côté droit)
		local g0 = bb + Vector3.new(0.26, 0.2 * s, 0)
		local g1 = rear + Vector3.new(0.26, 0.15 * s, -0.35 * s)
		rod(k, "ChainGuard", g0, g1, 0.2 * s + 0.06, color:Lerp(Color3.new(1, 1, 1), 0.35), M.SmoothPlastic)
	end
	if kind == "City" and not light then
		-- garde-boues + porte-bagages + panier en osier
		-- (arc de 2 plaques à r + 0,14 : jamais dans le pneu)
		local fr = r + 0.14
		local function fenderArc(z: number, angles: { number })
			for i = 1, #angles - 1 do
				local a, b = math.rad(angles[i]), math.rad(angles[i + 1])
				slab(k, "Fender", 0, 0.24, r + math.cos(a) * fr, z + math.sin(a) * fr, r + math.cos(b) * fr, z + math.sin(b) * fr, 0.05, color, M.SmoothPlastic)
			end
		end
		fenderArc(zR, { -20, 20, 62 })
		fenderArc(zFr, { -62, -20, 20 })
		box(k, "Rack", -0.26, 0.26, r + 1.3, r + 1.37, zR - 0.45, zR + 0.55, STEEL, M.Metal)
		for _, sx in ipairs({ -1, 1 }) do
			rod(k, "RackStay", Vector3.new(sx * 0.22, r + 1.3, zR + 0.5), Vector3.new(sx * 0.14, r, zR), 0.05, STEEL, M.Metal)
		end
		box(k, "Basket", -0.42, 0.42, stem.Y - 0.55, stem.Y + 0.02, stem.Z - 0.95, stem.Z - 0.2, Color3.fromRGB(206, 164, 110), M.Wood)
	end
	if not light then
		-- (v9.9) freins sur jante, câbles, phare, catadioptre, sonnette, béquille
		for _, zw in ipairs({ zR, zFr }) do
			for _, sx in ipairs({ -1, 1 }) do
				box(k, "BrakePad", sx * 0.1 - 0.03, sx * 0.1 + 0.03, r + (d / 2 - 0.2), r + (d / 2 - 0.08), zw + (if zw > 0 then -0.2 else 0.2) - 0.06, zw + (if zw > 0 then -0.2 else 0.2) + 0.06, TRIM, M.Rubber)
			end
		end
		rod(k, "BrakeCable", stem + Vector3.new(0.2, 0, barBack), headBot + Vector3.new(0.12, 0, -0.1), 0.03, TRIM, M.Rubber)
		cylZ(k, "BikeLight", 0, headTop.Y - 0.25, headTop.Z - 0.22, 0.2, 0.22, LAMP, M.Glass)
		box(k, "Reflector", -0.08, 0.08, seatTop.Y - 0.35, seatTop.Y - 0.2, seatTop.Z + 0.12, seatTop.Z + 0.16, TAIL, M.Glass)
		cylX(k, "Bell", -barW * 0.6, stem.Y + 0.07, stem.Z + barBack, 0.12, 0.16, CHROME, M.Metal)
		rod(k, "Kickstand", bb + Vector3.new(-0.18, -0.05, 0.25), Vector3.new(-0.55, 0.02, bb.Z + 0.75), 0.06, STEEL, M.Metal)
	end
	if kid then
		-- petites roues stabilisatrices + fanion
		for _, sx in ipairs({ -1, 1 }) do
			rod(k, "TrainerArm", rear + Vector3.new(sx * 0.12, 0, 0), Vector3.new(sx * 0.62, 0.3, zR + 0.12), 0.06, STEEL, M.Metal)
			cylX(k, "TrainerWheel", sx * 0.66, 0.26, zR + 0.12, 0.1, 0.52, TYRE, M.Rubber)
		end
		rod(k, "FlagPole", rear + Vector3.new(-0.1, 0, 0.1), rear + Vector3.new(-0.1, 2.6, 0.3), 0.04, STEEL, M.Metal)
		wedge(k, "Flag", -0.12, -0.08, rear.Y + 2.05, rear.Y + 2.55, zR + 0.3, zR + 0.9, false, Color3.fromRGB(255, 140, 60), M.Fabric)
	end
	local top = math.max(stem.Y, post.Y) + 0.2
	local half = math.max(0.8 * s + 0.1, if kid then 0.8 else 0)
	return finish(k, "Bike", -half, half, 0, top, zFr - r - 0.05, zR + r + 0.05, false)
end

-- 🛴 Trottinette électrique (béquille : légèrement penchée si opts.Lean)
function VehicleModels.KickScooter(opts: any?): Model
	local o = type(opts) == "table" and opts or {}
	local color = typeof(o.Color) == "Color3" and o.Color or Color3.fromRGB(64, 200, 170)
	local k = newKit("KickScooter", o)
	local d = 0.62
	cylX(k, "WheelF", 0, d / 2, -1.25, 0.16, d, TYRE, M.Rubber)
	cylX(k, "WheelR", 0, d / 2, 1.2, 0.16, d, TYRE, M.Rubber)
	cylX(k, "HubF", 0, d / 2, -1.25, 0.24, 0.26, STEEL, M.Metal)
	cylX(k, "HubR", 0, d / 2, 1.2, 0.24, 0.26, STEEL, M.Metal)
	box(k, "Deck", -0.3, 0.3, 0.32, 0.48, -0.9, 1.0, TRIM, M.SmoothPlastic)
	box(k, "DeckGrip", -0.26, 0.26, 0.48, 0.51, -0.8, 0.85, Color3.fromRGB(70, 70, 82), M.Sand)
	box(k, "Battery", -0.22, 0.22, 0.2, 0.32, -0.7, 0.7, color, M.SmoothPlastic)
	slab(k, "RearFender", 0, 0.28, 0.66, 0.95, 0.55, 1.52, 0.06, color, M.SmoothPlastic)
	rod(k, "Neck", Vector3.new(0, 0.46, -0.95), Vector3.new(0, d / 2, -1.25), 0.14, color, M.Metal)
	rod(k, "Stem", Vector3.new(0, 0.46, -0.95), Vector3.new(0, 3.6, -1.35), 0.16, color, M.Metal)
	rod(k, "Handlebar", Vector3.new(-0.75, 3.6, -1.35), Vector3.new(0.75, 3.6, -1.35), 0.1, TRIM, M.Metal)
	for _, sx in ipairs({ -1, 1 }) do
		cylX(k, "Grip", sx * 0.62, 3.6, -1.35, 0.28, 0.16, TRIM, M.Rubber)
	end
	box(k, "Display", -0.16, 0.16, 3.52, 3.72, -1.46, -1.28, Color3.fromRGB(44, 70, 104), M.Glass)
	cylZ(k, "FrontLight", 0, 2.9, -1.35, 0.14, 0.22, LAMP, M.Glass)
	box(k, "Stand", 0.18, 0.24, 0.02, 0.36, 0.3, 0.36, STEEL, M.Metal)
	local model = finish(k, "KickScooter", -0.85, 0.85, 0, 3.75, -1.6, 1.6, false)
	return model
end

-- 🛵 Scooter (type Vespa) : tablier avant, plancher, capot arrière arrondi,
-- selle, guidon avec phare, petites roues, top-case
function VehicleModels.Scooter(opts: any?): Model
	local o = type(opts) == "table" and opts or {}
	local color = typeof(o.Color) == "Color3" and o.Color or Color3.fromRGB(150, 220, 200)
	local light = o.Detail == "Light"
	local k = newKit("Scooter", o)
	local d = 1.25
	local r = d / 2
	cylX(k, "WheelF", 0, r, -1.9, 0.36, d, TYRE, M.Rubber)
	cylX(k, "WheelR", 0, r, 1.65, 0.4, d, TYRE, M.Rubber)
	cylX(k, "RimF", 0, r, -1.9, 0.44, d * 0.56, STEEL, M.Metal)
	cylX(k, "RimR", 0, r, 1.65, 0.48, d * 0.56, STEEL, M.Metal)
	if not light then
		-- (v9.9) jantes à 5 branches des deux côtés, disque de frein, étrier
		for _, w in ipairs({ { -1.9, 0.44 }, { 1.65, 0.48 } }) do
			for _, sx in ipairs({ -1, 1 }) do
				for i = 0, 4 do
					local a = i / 5 * 2 * PI
					boxRotX(k, "RimSpoke", sx * (w[2] / 2 + 0.02), r + math.cos(a) * d * 0.14, w[1] + math.sin(a) * d * 0.14, 0.04, 0.08, d * 0.26, a - PI / 2, TRIM, M.Metal)
				end
			end
		end
		cylX(k, "BrakeDisc", -0.28, r, -1.9, 0.05, d * 0.5, CHROME, M.Metal)
		box(k, "Caliper", -0.36, -0.28, r + 0.15, r + 0.35, -1.75, -1.5, Color3.fromRGB(212, 40, 52), M.Metal)
	end
	-- garde-boue avant + fourche
	slab(k, "FrontFender", 0, 0.5, r + 0.62, -2.35, r + 0.7, -1.5, 0.12, color, M.SmoothPlastic)
	rod(k, "ForkLeg", Vector3.new(0.14, r, -1.9), Vector3.new(0.14, 2.2, -1.62), 0.12, TRIM, M.Metal)
	-- tablier (bouclier) + plancher
	slab(k, "LegShield", 0, 1.2, 0.95, -1.25, 3.0, -1.55, 0.18, color, M.SmoothPlastic)
	box(k, "Floorboard", -0.55, 0.55, 0.7, 0.9, -1.25, 0.35, color, M.SmoothPlastic)
	box(k, "FloorMat", -0.48, 0.48, 0.9, 0.93, -1.15, 0.25, TRIM, M.Rubber)
	-- capot arrière arrondi (flancs bombés)
	box(k, "RearBody", -0.62, 0.62, 0.75, 1.95, 0.35, 2.25, color, M.SmoothPlastic, true)
	for _, sx in ipairs({ -1, 1 }) do
		cylZ(k, "Cowl", sx * 0.5, 1.45, 1.35, 1.9, 0.9, color, M.SmoothPlastic)
	end
	wedge(k, "Tail", -0.55, 0.55, 1.55, 1.95, 2.25, 2.7, false, color, M.SmoothPlastic)
	-- selle biplace
	box(k, "Seat", -0.5, 0.5, 1.95, 2.3, 0.4, 2.2, Color3.fromRGB(70, 50, 44), M.Leather)
	-- colonne + guidon + phare
	rod(k, "Column", Vector3.new(0, 1.9, -1.45), Vector3.new(0, 3.3, -1.25), 0.3, color, M.SmoothPlastic)
	box(k, "HandlebarCover", -0.5, 0.5, 3.25, 3.55, -1.5, -1.05, color, M.SmoothPlastic)
	rod(k, "Handlebar", Vector3.new(-0.95, 3.42, -1.15), Vector3.new(0.95, 3.42, -1.15), 0.1, TRIM, M.Metal)
	cylZ(k, "Headlight", 0, 3.4, -1.55, 0.1, 0.4, LAMP, M.Glass)
	box(k, "Taillight", -0.25, 0.25, 1.62, 1.82, 2.66, 2.74, TAIL, M.Glass)
	if not light then
		for _, sx in ipairs({ -1, 1 }) do
			cylX(k, "Grip", sx * 0.85, 3.42, -1.15, 0.3, 0.16, TRIM, M.Rubber)
			rod(k, "MirrorStem", Vector3.new(sx * 0.6, 3.5, -1.2), Vector3.new(sx * 0.75, 4.0, -1.25), 0.05, CHROME, M.Metal)
			cylZ(k, "Mirror", sx * 0.78, 4.08, -1.25, 0.06, 0.34, CHROME, M.Metal)
		end
		box(k, "TopCase", -0.5, 0.5, 2.0, 2.65, 2.1, 2.85, WHITE, M.SmoothPlastic)
		box(k, "Stand", -0.3, 0.3, 0.02, 0.2, 0.1, 0.3, STEEL, M.Metal)
	end
	return finish(k, "Scooter", -1.0, 1.0, 0, 4.2, -2.6, 2.8, false)
end

-- Arceaux à vélos (inox) : `count` arceaux en U renversé, espacés de `gap`
-- (le long de X, arceaux dans le plan YZ) ; opts.Plate = plaque au sol
function VehicleModels.BikeRack(opts: any?): Model
	local o = type(opts) == "table" and opts or {}
	local count = math.clamp(tonumber(o.Count) or 3, 1, 8)
	local gap = tonumber(o.Gap) or 2.2
	local k = newKit("BikeRack", o)
	local span = (count - 1) * gap
	for i = 0, count - 1 do
		local x = -span / 2 + i * gap
		for _, z in ipairs({ -0.85, 0.85 }) do
			cylY(k, "HoopLeg", x, 0, 2.3, z, 0.16, STEEL, M.Metal)
		end
		cylZ(k, "HoopTop", x, 2.4, 0, 1.7, 0.16, STEEL, M.Metal)
		-- coudes (petits coins arrondis ; opts.Bends = false : version serveur)
		for _, z in ipairs(if o.Bends == false then {} else { -0.85, 0.85 }) do
			local p = newPart(k, "Part", "HoopBend", Vector3.new(0.2, 0.2, 0.2), CFrame.new(x, 2.33, z), STEEL, M.Metal)
			;(p :: Part).Shape = Enum.PartType.Ball
		end
	end
	if o.Plate ~= false then
		box(k, "RackPlate", -span / 2 - 1.3, span / 2 + 1.3, 0, 0.06, -1.5, 1.5, Color3.fromRGB(150, 150, 164), M.DiamondPlate)
	end
	return finish(k, "BikeRack", -span / 2 - 1.3, span / 2 + 1.3, 0, 2.5, -1.5, 1.5, false)
end

----------------------------------------------------------------------
-- 🚚 Camion de livraison, 🌮 food truck (cabine commune)
----------------------------------------------------------------------

type Truck = { L: number, W: number, CabL: number, BoxH: number, WheelD: number }

-- (v9.9, CARS99) Cabine avancée réaliste + châssis + roues d'un petit
-- camion (avant vers -Z) : coins avant arrondis, capot court, pare-brise
-- encadré, vitres latérales, toit aux bords roulés, passage de roue avant
-- en ARC, calandre, optiques, pare-chocs, rétroviseurs de camion, portes,
-- marchepied ; à l'arrière : longerons, garde-boue noirs, barres
-- anti-encastrement ; roues marquées "Wheel" / "Spin".
-- Renvoie le début (z) de la caisse et la hauteur de son plancher.
local function truckBase(k: K, t: Truck, cabColor: Color3, full: boolean): (number, number)
	local hw = t.W / 2
	local zF, zB = -t.L / 2, t.L / 2
	local D = t.WheelD
	local r = D / 2
	local ra = r + 0.28
	local low, belt, roof = 0.85, 3.35, 5.7
	local hoodF = belt - 0.5
	local cabEnd = zF + t.CabL
	local axF, axR = zF + 2.75, zB - 2.7
	local tw = 0.9
	local rc = 0.6
	local archTop = r + ra
	local boxY = archTop + 0.15
	local wsBase, wsTop = zF + 1.25, zF + 2.15
	-- châssis : 2 longerons
	for _, sx in ipairs({ -1, 1 }) do
		local x0, x1 = sx * (hw - 1.9), sx * (hw - 1.45)
		box(k, "ChassisRail", math.min(x0, x1), math.max(x0, x1), 0.95, 1.55, cabEnd - 0.5, zB - 0.25, TRIM, M.Metal)
	end
	-- ░ cabine : coins arrondis, face avant, capot court ░
	for _, sx in ipairs({ -1, 1 }) do
		cylY(k, "CabCorner", sx * (hw - rc), low, hoodF, zF + rc + 0.05, rc * 2, cabColor, M.SmoothPlastic, true)
	end
	box(k, "CabFront", -hw + rc, hw - rc, low, hoodF, zF + 0.05, zF + rc + 0.05, cabColor, M.SmoothPlastic, true)
	wedge(k, "CabNose", -hw + 0.05, hw - 0.05, hoodF, belt, zF + 0.05, wsBase, true, cabColor, M.SmoothPlastic)
	box(k, "CabUpperLow", -hw, hw, archTop, belt, zF + rc + 0.05, cabEnd, cabColor, M.SmoothPlastic, true)
	-- bas de cabine découpé autour de la roue avant
	box(k, "CabCore", -hw + tw + 0.35, hw - tw - 0.35, low, archTop, zF + rc + 0.05, cabEnd, cabColor, M.SmoothPlastic)
	for _, sx in ipairs({ -1, 1 }) do
		local xo, xi = sx * hw, sx * (hw - 0.25)
		local lo, hi = math.min(xo, xi), math.max(xo, xi)
		if axF - ra - (zF + rc + 0.05) > 0.05 then
			box(k, "CabSide", lo, hi, low, archTop, zF + rc + 0.05, axF - ra, cabColor, M.SmoothPlastic)
		end
		archPanel(k, "CabArch", xo, xi, axF, r, ra, archTop, if full then 4 else 3, cabColor, M.SmoothPlastic)
		box(k, "CabSide", lo, hi, low, archTop, axF + ra, cabEnd, cabColor, M.SmoothPlastic)
		-- passage de roue sombre (toit + fond)
		local wx0, wx1 = sx * (hw - tw - 0.35), sx * (hw - 0.25)
		box(k, "WheelWell", math.min(wx0, wx1), math.max(wx0, wx1), archTop - 0.1, archTop - 0.02, axF - ra + 0.1, axF + ra - 0.1, TRIM, M.SmoothPlastic)
		cylX(k, "WheelWell", sx * (hw - tw - 0.3), r, axF, 0.08, ra * 2, TRIM, M.SmoothPlastic)
		-- lèvre noire autour de l'arche
		if full then
			for i = 0, 3 do
				local a = -PI / 2 + (i + 0.5) * PI / 4
				local rr = ra + 0.08
				local lx0, lx1 = sx * (hw - 0.1), sx * (hw + 0.05)
				boxRotX(k, "ArchLip", (lx0 + lx1) / 2, r + math.cos(a) * rr, axF + math.sin(a) * rr, math.abs(lx1 - lx0), 0.16, 2 * rr * math.tan(PI / 8) + 0.03, a, TRIM, M.Rubber)
			end
		end
	end
	-- ░ pare-brise encadré, vitres, montants, toit arrondi ░
	slab(k, "WindshieldFrame", 0, t.W - 0.4, belt - 0.02, wsBase - 0.05, roof - 0.05, wsTop + 0.02, 0.1, TRIM, M.SmoothPlastic)
	local ws = slab(k, "Windshield", 0, t.W - 0.7, belt + 0.05, wsBase - 0.08, roof - 0.15, wsTop - 0.04, 0.06, GLASS, M.Glass)
	ws.Transparency = 0.35
	ws.Reflectance = 0.15
	for _, sx in ipairs({ -1, 1 }) do
		local x0, x1 = sx * (hw - 0.02), sx * (hw - 0.12)
		box(k, "CabGlass", math.min(x0, x1), math.max(x0, x1), belt, roof - 0.12, wsTop, cabEnd - 0.35, GLASS, M.Glass).Transparency = 0.35
		rod(k, "PillarA", Vector3.new(sx * (hw - 0.2), belt, wsBase), Vector3.new(sx * (hw - 0.2), roof - 0.1, wsTop), 0.22, TRIM, M.SmoothPlastic)
		local px0, px1 = sx * (hw + 0.03), sx * (hw - 0.17)
		box(k, "PillarB", math.min(px0, px1), math.max(px0, px1), belt, roof - 0.1, cabEnd - 0.45, cabEnd - 0.2, TRIM, M.SmoothPlastic)
		box(k, "PillarB", math.min(px0, px1), math.max(px0, px1), belt, roof - 0.1, wsTop - 0.05, wsTop + 0.12, TRIM, M.SmoothPlastic)
	end
	box(k, "CabBack", -hw, hw, belt, roof - 0.1, cabEnd - 0.2, cabEnd, cabColor, M.SmoothPlastic)
	box(k, "CabRoof", -hw + 0.3, hw - 0.3, roof - 0.12, roof + 0.2, wsTop - 0.05, cabEnd, cabColor, M.SmoothPlastic, true)
	for _, sx in ipairs({ -1, 1 }) do
		cylZ(k, "RoofEdge", sx * (hw - 0.3), roof + 0.02, (wsTop - 0.05 + cabEnd) / 2, cabEnd - wsTop + 0.05, 0.36, cabColor, M.SmoothPlastic)
	end
	cylX(k, "RoofNose", 0, roof + 0.02, wsTop - 0.05, t.W - 0.6, 0.36, cabColor, M.SmoothPlastic)
	-- ░ face avant : calandre, optiques, pare-chocs ░
	local gy0, gy1 = low + 0.75, hoodF - 0.15
	box(k, "GrilleFrame", -hw * 0.44, hw * 0.44, gy0, gy1, zF - 0.03, zF + 0.2, CHROME, M.Metal)
	box(k, "Grille", -hw * 0.44 + 0.1, hw * 0.44 - 0.1, gy0 + 0.08, gy1 - 0.08, zF - 0.09, zF + 0.12, TRIM, M.DiamondPlate) -- (v10 : 0,06 devant le cadre, plus de z-fight)
	if full then
		for j = 1, 3 do
			local y = gy0 + j * (gy1 - gy0) / 4
			box(k, "GrilleBar", -hw * 0.44 + 0.12, hw * 0.44 - 0.12, y - 0.04, y + 0.04, zF - 0.08, zF - 0.02, CHROME, M.Metal)
		end
		cylZ(k, "Badge", 0, (gy0 + gy1) / 2, zF - 0.1, 0.06, 0.45, CHROME, M.Metal)
	end
	for _, sx in ipairs({ -1, 1 }) do
		local h0, h1 = sx * (hw * 0.5), sx * (hw - rc * 0.4)
		local lo, hi = math.min(h0, h1), math.max(h0, h1)
		box(k, "HeadlightHousing", lo, hi, gy0 + 0.05, gy1, zF - 0.04, zF + 0.15, TRIM, M.SmoothPlastic)
		box(k, "Headlight", lo + 0.06, hi - 0.06, gy0 + 0.25, gy1 - 0.06, zF - 0.07, zF - 0.01, LAMP, M.Glass)
		if full then
			box(k, "HeadlightDRL", lo + 0.06, hi - 0.06, gy0 + 0.1, gy0 + 0.18, zF - 0.08, zF - 0.02, DRL, M.SmoothPlastic)
			local i0, i1 = sx * (hw - rc * 0.4), sx * (hw - 0.02)
			box(k, "Indicator", math.min(i0, i1), math.max(i0, i1), gy0 + 0.25, gy1 - 0.06, zF + 0.1, zF + 0.35, AMBER, M.SmoothPlastic):SetAttribute("Side", sx)
		end
	end
	box(k, "Bumper", -hw - 0.05, hw + 0.05, 0.55, low + 0.6, zF - 0.15, zF + 0.55, TRIM, M.Plastic)
	box(k, "PlateFront", -1.0, 1.0, 0.75, 1.25, zF - 0.2, zF - 0.14, Color3.fromRGB(248, 248, 244), M.SmoothPlastic)
	if full then
		for _, sx in ipairs({ -1, 1 }) do
			cylZ(k, "FogLight", sx * (hw - 0.75), 1.0, zF - 0.16, 0.06, 0.34, LAMP, M.Glass)
		end
	end
	-- ░ rétroviseurs de camion, portes, marchepied ░
	for _, sx in ipairs({ -1, 1 }) do
		local base = Vector3.new(sx * (hw - 0.05), belt + 0.4, wsBase + 0.1)
		local tip = Vector3.new(sx * (hw + 0.55), belt + 0.7, wsBase - 0.2)
		rod(k, "MirrorArm", base, tip, 0.1, TRIM, M.Metal)
		box(k, "Mirror", tip.X - 0.16, tip.X + 0.16, belt + 0.35, belt + 1.45, tip.Z - 0.12, tip.Z + 0.12, TRIM, M.SmoothPlastic)
		if full then
			box(k, "MirrorGlass", tip.X - 0.12, tip.X + 0.12, belt + 0.42, belt + 1.38, tip.Z + 0.12, tip.Z + 0.15, CHROME, M.Glass)
			local sx0, sx1 = sx * (hw + 0.012), sx * (hw - 0.02)
			box(k, "DoorSeam", math.min(sx0, sx1), math.max(sx0, sx1), archTop + 0.05, belt, axF + ra + 0.15, axF + ra + 0.2, Color3.fromRGB(22, 22, 28), M.SmoothPlastic)
			local hx0, hx1 = sx * (hw - 0.02), sx * (hw + 0.07)
			box(k, "Handle", math.min(hx0, hx1), math.max(hx0, hx1), belt - 0.45, belt - 0.32, cabEnd - 1.1, cabEnd - 0.6, TRIM, M.SmoothPlastic)
			local st0, st1 = sx * (hw - 0.6), sx * (hw + 0.1)
			box(k, "CabStep", math.min(st0, st1), math.max(st0, st1), low - 0.25, low - 0.1, axF + ra + 0.15, cabEnd - 0.1, TRIM, M.DiamondPlate)
		end
	end
	-- ░ poste de conduite (vu par les vitres) ░
	if full then
		for _, sx in ipairs({ -1, 1 }) do
			local x = sx * hw * 0.4
			box(k, "CabSeat", x - 0.65, x + 0.65, belt - 0.95, belt - 0.6, cabEnd - 1.7, cabEnd - 0.55, Color3.fromRGB(60, 60, 70), M.Fabric)
			slab(k, "CabSeatBack", x, 1.2, belt - 0.6, cabEnd - 0.5, roof - 0.9, cabEnd - 0.35, 0.3, Color3.fromRGB(60, 60, 70), M.Fabric)
		end
		box(k, "CabDash", -hw + 0.3, hw - 0.3, belt - 0.5, belt + 0.1, wsBase + 0.15, wsBase + 0.9, Color3.fromRGB(50, 50, 60), M.SmoothPlastic)
		local sw = newPart(k, "Part", "SteeringWheel", Vector3.new(0.1, 1.1, 1.1), CFrame.new(-hw * 0.45, belt + 0.4, wsBase + 1.4) * CFrame.Angles(math.rad(-30), 0, 0) * CFrame.Angles(0, PI / 2, 0), TRIM, M.SmoothPlastic)
		;(sw :: Part).Shape = Enum.PartType.Cylinder
	end
	-- ░ arrière : garde-boue noirs, barres anti-encastrement, feux, pare-chocs ░
	for _, sx in ipairs({ -1, 1 }) do
		local x0, x1 = sx * (hw - tw - 0.25), sx * (hw + 0.06)
		local n = if full then 4 else 2
		for i = 0, n - 1 do
			local a = -PI / 2 + (i + 0.5) * PI / n
			local rr = ra - 0.05
			boxRotX(k, "Mudguard", (x0 + x1) / 2, r + math.cos(a) * rr, axR + math.sin(a) * rr, math.abs(x1 - x0), 0.1, 2 * rr * math.tan(PI / (2 * n)) + 0.03, a, TRIM, M.Plastic)
		end
		if full then
			local g0, g1 = sx * (hw - 0.25), sx * (hw - 0.1)
			for _, y in ipairs({ 1.15, 1.75 }) do
				box(k, "SideGuard", math.min(g0, g1), math.max(g0, g1), y - 0.08, y + 0.08, axF + ra + 1.4, axR - ra - 0.25, STEEL, M.Metal)
			end
		end
		local t0, t1 = sx * (hw - 0.15), sx * (hw - 0.75)
		box(k, "Taillight", math.min(t0, t1), math.max(t0, t1), boxY + 0.25, boxY + 1.05, zB - 0.02, zB + 0.1, TAIL, M.Glass)
		if full then
			box(k, "RearIndicator", math.min(t0, t1), math.max(t0, t1), boxY + 1.08, boxY + 1.35, zB - 0.02, zB + 0.1, AMBER, M.SmoothPlastic):SetAttribute("Side", sx)
		end
	end
	box(k, "RearBumper", -hw + 0.3, hw - 0.3, 0.75, 1.2, zB - 0.4, zB - 0.1, STEEL, M.Metal)
	box(k, "PlateRear", -0.9, 0.9, 1.25, 1.7, zB - 0.26, zB - 0.2, Color3.fromRGB(248, 248, 244), M.SmoothPlastic)
	-- ░ roues ░
	local index = 0
	for _, z in ipairs({ axF, axR }) do
		for _, sx in ipairs({ -1, 1 }) do
			index += 1
			heavyWheel(k, index, sx * (hw - tw / 2 - 0.08), r, z, sx, D, tw, full, nil)
		end
	end
	return cabEnd, boxY
end

function VehicleModels.DeliveryVan(opts: any?): Model
	local o = type(opts) == "table" and opts or {}
	local full = o.Detail ~= "Light"
	local color = typeof(o.Color) == "Color3" and o.Color or Color3.fromRGB(255, 214, 120)
	local k = newKit("DeliveryVan", o)
	local t: Truck = { L = 17, W = 6.6, CabL = 4.4, BoxH = 8.2, WheelD = 2.5 }
	local hw = t.W / 2
	local zB = t.L / 2
	local cabEnd, boxY = truckBase(k, t, color, full)
	-- caisse (fourgon, posée sur le châssis) + bande + logo
	local cargo = box(k, "CargoBox", -hw, hw, boxY, t.BoxH, cabEnd, zB, WHITE, M.SmoothPlastic, true)
	box(k, "CargoFloor", -hw + 0.05, hw - 0.05, boxY - 0.2, boxY, cabEnd + 0.05, zB - 0.02, Color3.fromRGB(70, 70, 80), M.Metal)
	for _, sx in ipairs({ -1, 1 }) do
		local x0, x1 = sx * (hw + 0.02), sx * (hw + 0.07)
		box(k, "CargoStripe", math.min(x0, x1), math.max(x0, x1), 3.0, 3.7, cabEnd + 0.3, zB - 0.3, color, M.SmoothPlastic)
	end
	for _, face in ipairs({ Enum.NormalId.Right, Enum.NormalId.Left }) do
		local g = sign(k, cargo, face, 22, "📦 Dopa Express", Color3.fromRGB(236, 72, 140), nil, Enum.Font.FredokaOne, false)
		local title = g:FindFirstChild("Text") :: TextLabel?
		if title then
			title.Size = UDim2.fromScale(0.94, 0.5)
			title.Position = UDim2.fromScale(0.03, 0.12)
		end
		local sub = Instance.new("TextLabel")
		sub.Name = "Slogan"
		sub.BackgroundTransparency = 1
		sub.Size = UDim2.fromScale(0.8, 0.2)
		sub.Position = UDim2.fromScale(0.1, 0.66)
		sub.Font = Enum.Font.GothamBold
		sub.TextScaled = true
		sub.TextColor3 = Color3.fromRGB(92, 58, 96)
		sub.Text = k.T("Fast delivery all over town 🚚")
		sub:SetAttribute("LocText", "Fast delivery all over town 🚚")
		sub.Parent = g
	end
	-- portes arrière (2 battants + poignées)
	for _, sx in ipairs({ -1, 1 }) do
		local x0, x1 = sx * 0.04, sx * (hw - 0.05)
		box(k, "RearDoor", math.min(x0, x1), math.max(x0, x1), boxY + 0.15, t.BoxH - 0.15, zB, zB + 0.06, Color3.fromRGB(236, 236, 240), M.SmoothPlastic)
		if full then
			box(k, "DoorHandle", sx * 0.25 - 0.06, sx * 0.25 + 0.06, 3.8, 4.8, zB + 0.06, zB + 0.12, TRIM, M.Metal)
		end
	end
	-- déflecteur au-dessus de la cabine
	wedge(k, "Deflector", -hw + 0.3, hw - 0.3, 5.92, t.BoxH - 0.2, cabEnd - 2.0, cabEnd, true, color, M.SmoothPlastic)
	return finish(k, "DeliveryVan", -hw - 0.5, hw + 0.5, 0.6, t.BoxH, -t.L / 2 - 0.1, zB + 0.12, o.Solid == true)
end

function VehicleModels.FoodTruck(opts: any?): Model
	local o = type(opts) == "table" and opts or {}
	local full = o.Detail ~= "Light"
	local color = typeof(o.Color) == "Color3" and o.Color or Color3.fromRGB(255, 214, 120)
	local k = newKit("FoodTruck", o)
	local t: Truck = { L = 16, W = 6.4, CabL = 4.2, BoxH = 7.8, WheelD = 2.4 }
	local hw = t.W / 2
	local zB = t.L / 2
	local cabEnd, boxY = truckBase(k, t, color, full)
	-- caisse avec passe-plat côté droit (+X) : bas, haut, montants
	local h0, h1 = math.max(3.4, boxY + 0.5), 6.2 -- ouverture du passe-plat
	local w0, w1 = cabEnd + 1.0, zB - 1.0
	box(k, "BoxLow", -hw, hw, boxY, h0, cabEnd, zB, color, M.SmoothPlastic, true)
	box(k, "BoxTop", -hw, hw, h1, t.BoxH, cabEnd, zB, color, M.SmoothPlastic, true)
	-- (niche de cuisine de 1,8 de profondeur derrière le passe-plat)
	box(k, "BoxLeft", -hw, hw - 1.8, h0, h1, cabEnd, zB, color, M.SmoothPlastic)
	box(k, "HatchPostF", hw - 1.8, hw, h0, h1, cabEnd, w0, color, M.SmoothPlastic)
	box(k, "HatchPostR", hw - 1.8, hw, h0, h1, w1, zB, color, M.SmoothPlastic)
	-- intérieur vu par le passe-plat : plan de travail inox, étagère, bocaux
	box(k, "Kitchen", hw - 1.75, hw - 0.45, h0, h0 + 0.9, w0, w1, Color3.fromRGB(210, 214, 222), M.Metal)
	box(k, "Shelf", hw - 1.8, hw - 1.45, h0 + 1.5, h0 + 1.6, w0, w1, STEEL, M.Metal)
	if full then
		for i = 0, 3 do
			local z = w0 + 0.8 + i * (w1 - w0 - 1.6) / 3
			cylY(k, "Jar", hw - 1.62, h0 + 1.6, h0 + 2.1, z, 0.34, ({ Color3.fromRGB(255, 140, 60), Color3.fromRGB(120, 200, 90), Color3.fromRGB(230, 70, 60), Color3.fromRGB(255, 214, 120) })[i + 1], M.Glass)
		end
	end
	-- comptoir extérieur + auvent rayé relevé
	box(k, "Counter", hw, hw + 0.9, h0 - 0.1, h0 + 0.05, w0, w1, Color3.fromRGB(206, 164, 110), M.Wood)
	local stripes = 6
	for i = 0, stripes - 1 do
		local z0 = w0 - 0.2 + i * (w1 - w0 + 0.4) / stripes
		local z1 = w0 - 0.2 + (i + 1) * (w1 - w0 + 0.4) / stripes
		local p = box(k, "Awning", hw, hw + 2.2, h1 + 0.1, h1 + 0.25, z0, z1, if i % 2 == 0 then Color3.fromRGB(255, 132, 184) else WHITE, M.Fabric)
		p.CFrame = CFrame.new(hw, h1 + 0.1, (z0 + z1) / 2) * CFrame.Angles(0, 0, math.rad(-16)) * CFrame.new(1.1, 0.075, 0)
	end
	-- menu (tableau noir) + enseigne sur le toit + taco géant
	local menu = box(k, "Menu", hw + 0.02, hw + 0.08, 4.0, 5.8, zB - 0.95, zB - 0.25, Color3.fromRGB(40, 44, 48), M.Slate)
	sign(k, menu, Enum.NormalId.Right, 30, "🌮 Tacos · 🌯 Burritos · 🥤 Drinks", WHITE, nil, Enum.Font.FredokaOne, true)
	local board = box(k, "TruckSign", -0.15, 0.15, t.BoxH + 0.1, t.BoxH + 1.6, cabEnd + 0.8, zB - 0.8, WHITE, M.SmoothPlastic)
	sign(k, board, Enum.NormalId.Right, 30, "🌮 Taco Party", Color3.fromRGB(236, 72, 140), nil, Enum.Font.FredokaOne, false)
	sign(k, board, Enum.NormalId.Left, 30, "🌮 Taco Party", Color3.fromRGB(236, 72, 140), nil, Enum.Font.FredokaOne, false)
	for _, z in ipairs({ cabEnd + 1.4, zB - 1.4 }) do
		box(k, "SignPost", -0.1, 0.1, t.BoxH, t.BoxH + 0.15, z - 0.1, z + 0.1, TRIM, M.Metal)
	end
	if full then
		-- guirlande de fanions sous l'auvent + marchepied
		for i = 0, 4 do
			local z = w0 + 0.4 + i * (w1 - w0 - 0.8) / 4
			wedge(k, "Bunting", hw + 1.3, hw + 1.36, h1 - 0.7, h1 - 0.25, z - 0.25, z + 0.25, i % 2 == 0, if i % 2 == 0 then LILAC else Color3.fromRGB(128, 222, 190), M.Fabric)
		end
		box(k, "Step", hw, hw + 0.8, 0.7, 0.85, w0 + 0.5, w0 + 2.0, STEEL, M.DiamondPlate)
	end
	return finish(k, "FoodTruck", -hw - 0.5, hw + 2.4, 0.6, t.BoxH + 2.8, -t.L / 2 - 0.1, zB + 0.1, o.Solid == true)
end

return VehicleModels
