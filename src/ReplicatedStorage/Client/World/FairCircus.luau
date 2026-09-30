--[[
	FairCircus (ModuleScript)
	Emplacement : ReplicatedStorage > Client > World > FairCircus

	🎪 LE CIRQUE de la fête (v9.9, FAIR99), côté client :
	  - chapiteau rayé rouge / crème (24 pans de toile, lambrequin festonné,
	    2 mâts royaux, coupole, fanions, haubans et piquets), marquise
	    d'entrée à ampoules avec enseigne, guichet (caissière PNJ) ;
	  - dedans : sciure, piste ronde (bordure rouge et blanche, tapis),
	    gradins en arc sur 3 rangs (on s'y assoit pour de vrai : sièges du
	    serveur, invite E "Voir le spectacle"), rideau des coulisses en
	    velours, portique de trapèze avec filet, 2 projecteurs (lueur douce,
	    SpotLight ≤ 0,9 allumés seulement quand on est près) ;
	  - un SPECTACLE en boucle (64 s), le même pour tout le monde (heure du
	    serveur) : jongleur (3 balles en cascade), voiture de clowns qui fait
	    le tour de la piste et d'où sortent les clowns, monocycliste,
	    trapézistes pendus par les genoux qui se balancent, Monsieur Loyal,
	    salut final ; spectateurs PNJ qui applaudissent.
	Les artistes sont des PNJ (NPCModels) animés à chaque image quand la
	caméra est à moins de SHOW_R studs. Aucune pièce serveur ici (sauf les
	sièges, TownFair), aucun son.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local FairRides = require(ReplicatedStorage.Shared.FairRides)
local Locale = require(ReplicatedStorage.Shared.Locale)
local FairKit = require(script.Parent.FairKit)

local FairCircus = {}

local M = FairKit.M
local C = FairKit.C
local VERTICAL = FairKit.VERTICAL
local BALL, CYL = FairKit.BALL, FairKit.CYL
local TAU = FairKit.TAU
local Part, Solid, Glow = FairKit.Part, FairKit.Solid, FairKit.Glow
local Fixed = FairKit.Fixed

type RideFx = FairKit.RideFx

local SHOW_R = 85 -- (studs) la caméra doit être plus près pour animer le spectacle
local LIGHT_R = 60 -- ... pour allumer les 2 projecteurs

local RED = Color3.fromRGB(206, 40, 52)
local CANVAS = Color3.fromRGB(252, 244, 228)
local VELVET = Color3.fromRGB(140, 24, 40)
local SAWDUST = Color3.fromRGB(222, 196, 150)
local BENCH_BLUE = Color3.fromRGB(46, 70, 140)

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

local function polar(a: number, r: number, y: number): Vector3
	return Vector3.new(math.sin(a) * r, y, math.cos(a) * r)
end

local function smooth(u: number): number
	u = math.clamp(u, 0, 1)
	return u * u * (3 - 2 * u)
end

----------------------------------------------------------------------
-- Chapiteau
----------------------------------------------------------------------

local function buildTent(r: RideFx)
	local R = FairRides.CIRCUS_R
	local N = 24
	local wallH = 7
	-- murs de toile (entrée : 2 pans ouverts à -Z)
	for i = 0, N - 1 do
		local a = (i + 0.5) / N * TAU
		local deg = math.deg(a)
		if math.abs(deg - 180) > 15.1 then
			local p = polar(a, R, wallH / 2)
			local chord = 2 * R * math.sin(math.pi / N) + 0.08
			local wall = Solid(Fixed(r, "Canvas", Vector3.new(chord, wallH, 0.25), CFrame.lookAt(p, p + Vector3.new(p.X, 0, p.Z)), if i % 2 == 0 then RED else CANVAS, M.Fabric))
			wall.CastShadow = true
			-- ourlet au sol + lambrequin festonné (triangles) en haut
			Fixed(r, "Hem", Vector3.new(chord, 0.4, 0.32), CFrame.lookAt(polar(a, R, 0.2), polar(a, R + 1, 0.2)), Color3.fromRGB(120, 30, 40), M.Fabric)
		end
		local e = polar(a, R + 0.35, wallH + 0.25)
		local size, cf = FairKit.Tri(e, -FairKit.UP, Vector3.new(math.cos(a), 0, -math.sin(a)), 1.1, 2 * (R + 0.35) * math.sin(math.pi / N) / 2, 0.1)
		Part(r.Model, "Valance", size, r.Base * cf, if i % 2 == 0 then CANVAS else RED, M.Fabric, nil, "WedgePart")
		local size2, cf2 = FairKit.Tri(e, -FairKit.UP, -Vector3.new(math.cos(a), 0, -math.sin(a)), 1.1, 2 * (R + 0.35) * math.sin(math.pi / N) / 2, 0.1)
		Part(r.Model, "Valance", size2, r.Base * cf2, if i % 2 == 0 then CANVAS else RED, M.Fabric, nil, "WedgePart")
	end
	-- bourrelet doré à l'égout
	for i = 0, N - 1 do
		local a0, a1 = i / N * TAU, (i + 1) / N * TAU
		FairKit.Rod(r.Model, "Eave", r.Base * polar(a0, R + 0.35, wallH + 0.45), r.Base * polar(a1, R + 0.35, wallH + 0.45), 0.3, C.Gold, M.Metal)
	end
	-- toit : 24 pans rayés (2 triangles chacun) de l'égout à la coupole
	local e, y0, y1, top = R + 0.4, wallH + 0.4, 20.2, 2.6
	for k = 0, N - 1 do
		local a = (k + 0.5) / N * TAU
		local nrm = Vector3.new(math.sin(a), 0, math.cos(a))
		local side = FairKit.UP:Cross(nrm).Unit
		local half = e * math.tan(math.pi / N)
		local mid = nrm * e + Vector3.new(0, y0, 0)
		-- (sommet commun au centre : les bords de 2 pans voisins coïncident,
		-- aucune fente de ciel entre eux ; la coupole couvre le centre)
		local apex = Vector3.new(0, y1, 0)
		local w = apex - mid
		for _, sv in ipairs({ side, -side }) do
			-- (triangle rectangle : du milieu du bord d'égout vers la coupole)
			local size, cf = FairKit.Tri(mid, w.Unit, sv, w.Magnitude, half, 0.2)
			local pane = Part(r.Model, "Roof", size, r.Base * cf, if k % 2 == 0 then RED else CANVAS, M.Fabric, nil, "WedgePart")
			pane.CastShadow = true
		end
	end
	-- coupole + mâts royaux + fanions
	Fixed(r, "Cupola", Vector3.new(1.2, 2 * top + 0.6, 2 * top + 0.6), CFrame.new(0, y1 + 0.3, 0) * VERTICAL, RED, M.Fabric, CYL)
	Fixed(r, "CupolaRim", Vector3.new(0.3, 2 * top + 0.9, 2 * top + 0.9), CFrame.new(0, y1 + 0.95, 0) * VERTICAL, C.Gold, M.Metal, CYL)
	-- (mâts royaux de part et d'autre de la piste, pas dedans : la vue reste dégagée)
	for i, x in ipairs({ -7.4, 7.4 }) do
		local pole = Solid(Fixed(r, "KingPole", Vector3.new(24, 0.7, 0.7), CFrame.new(x, 12, 0) * VERTICAL, C.White, M.Metal, CYL))
		pole.CastShadow = true
		Fixed(r, "PoleBand", Vector3.new(0.5, 0.8, 0.8), CFrame.new(x, 3, 0) * VERTICAL, RED, M.Metal, CYL)
		Fixed(r, "Finial", Vector3.new(0.9, 0.9, 0.9), CFrame.new(x, 24.2, 0), C.Gold, M.Metal, BALL)
		local fs, fl = FairKit.Tri(r.Base * Vector3.new(x, 23.7, 0), r.Base:VectorToWorldSpace(Vector3.new(1, 0, 0)), -FairKit.UP, 2.4, 1.2, 0.06)
		Part(r.Model, "Pennant", fs, fl, if i == 1 then RED else C.Lemon, M.Fabric, nil, "WedgePart")
	end
	-- haubans + piquets (sauf devant l'entrée)
	for i = 0, 11 do
		local a = (i + 0.5) / 12 * TAU
		if math.abs(math.deg(a) - 180) > 30 then
			local from = r.Base * polar(a, R + 0.3, wallH + 0.3)
			local to = r.Base * polar(a, R + 2.2, 0.35)
			FairKit.Rod(r.Model, "Guy", from, to, 0.06, Color3.fromRGB(230, 220, 196), M.Fabric)
			Fixed(r, "Stake", Vector3.new(0.25, 0.8, 0.25), CFrame.new(polar(a, R + 2.25, 0.3)), C.WoodDark, M.Wood)
		end
	end
	-- marquise d'entrée : auvent sur 2 poteaux, enseigne à ampoules
	for _, sx in ipairs({ -1, 1 }) do
		Solid(Fixed(r, "MarqueePost", Vector3.new(0.4, 7.2, 0.4), CFrame.new(sx * 4.4, 3.6, -R - 3.4), C.Gold, M.Metal))
		Solid(Fixed(r, "Jamb", Vector3.new(0.5, wallH, 0.5), CFrame.new(sx * 4.75, wallH / 2, -R + 0.25), C.Gold, M.Metal))
		-- rideaux relevés (drapés) de chaque côté de l'entrée
		Fixed(r, "Drape", Vector3.new(1.4, 6, 0.3), CFrame.new(sx * 4.0, 3.9, -R + 0.1) * CFrame.Angles(0, 0, math.rad(sx * -8)), VELVET, M.Fabric)
		Fixed(r, "TieBack", Vector3.new(0.3, 0.3, 0.5), CFrame.new(sx * 3.8, 3.2, -R - 0.1), C.Gold, M.Metal, BALL)
	end
	for i = 0, 5 do
		local x = -4.6 + (i + 0.5) * 9.2 / 6
		Fixed(r, "Marquee", Vector3.new(9.2 / 6 + 0.02, 0.2, 4.2), CFrame.new(x, 7.45, -R - 1.6) * CFrame.Angles(math.rad(-10), 0, 0), if i % 2 == 0 then RED else CANVAS, M.Fabric).CastShadow = true
	end
	local board = Fixed(r, "Board", Vector3.new(9.5, 2.1, 0.3), CFrame.new(0, 9.1, -R - 3.3), Color3.fromRGB(150, 24, 40), M.SmoothPlastic)
	FairKit.Sign(board, "🎪 " .. Locale.T("Circus"), Color3.fromRGB(255, 226, 120), Color3.fromRGB(150, 24, 40), Enum.Font.Fondamento)
	FairKit.Bulbs(r.Model, r.Base * Vector3.new(-4.6, 10.35, -R - 3.5), r.Base * Vector3.new(4.6, 10.35, -R - 3.5), 12, 0.28, { C.Bulb, Color3.fromRGB(255, 190, 120) })
	FairKit.Bulbs(r.Model, r.Base * Vector3.new(-4.6, 7.85, -R - 3.5), r.Base * Vector3.new(4.6, 7.85, -R - 3.5), 12, 0.26, { C.Bulb })
	-- guichet (cabine rayée, vitre, comptoir, panneau)
	local booth = CFrame.new(7.2, 0, -R - 4.5) * CFrame.Angles(0, math.rad(-20), 0)
	Solid(Fixed(r, "Booth", Vector3.new(3, 4.2, 2.6), booth * CFrame.new(0, 2.1, 0.4), CANVAS, M.WoodPlanks))
	for i = 0, 3 do
		Fixed(r, "BoothStripe", Vector3.new(0.35, 4.2, 2.66), booth * CFrame.new(-1.2 + i * 0.8, 2.1, 0.4), RED, M.WoodPlanks)
	end
	local glass = Fixed(r, "BoothGlass", Vector3.new(2.2, 1.3, 0.08), booth * CFrame.new(0, 2.7, -0.92), Color3.fromRGB(180, 210, 230), M.Glass)
	glass.Transparency = 0.45
	Fixed(r, "BoothCounter", Vector3.new(2.6, 0.2, 0.6), booth * CFrame.new(0, 1.95, -1.15), C.Gold, M.Metal)
	Fixed(r, "BoothRoof", Vector3.new(3.4, 0.5, 3), booth * CFrame.new(0, 4.45, 0.4), RED, M.SmoothPlastic)
	local tag = Fixed(r, "BoothSign", Vector3.new(2.6, 0.7, 0.1), booth * CFrame.new(0, 3.7, -0.95), CANVAS, M.SmoothPlastic)
	FairKit.Sign(tag, "🎟️ " .. Locale.T("Tickets"), RED, CANVAS)
	return booth
end

----------------------------------------------------------------------
-- Intérieur : sciure, piste, gradins, coulisses, trapèze, projecteurs
----------------------------------------------------------------------

local function buildInside(r: RideFx): { any }
	local R = FairRides.CIRCUS_R
	Solid(Fixed(r, "Sawdust", Vector3.new(0.14, 2 * R - 0.4, 2 * R - 0.4), CFrame.new(0, 0.07, 0) * VERTICAL, SAWDUST, M.Sand, CYL))
	-- piste : tapis rouge + bordure (24 segments rouges / blancs, dessus rembourré)
	local ringR = FairRides.CIRCUS_RING
	Fixed(r, "RingMat", Vector3.new(0.06, 2 * ringR - 0.6, 2 * ringR - 0.6), CFrame.new(0, 0.17, 0) * VERTICAL, Color3.fromRGB(176, 36, 48), M.Fabric, CYL)
	Fixed(r, "RingStar", Vector3.new(0.05, 3.2, 3.2), CFrame.new(0, 0.215, 0) * VERTICAL, C.Gold, M.Fabric, CYL)
	for i = 0, 23 do
		local a = (i + 0.5) / 24 * TAU
		local p = polar(a, ringR, 0.45)
		local chord = 2 * ringR * math.sin(math.pi / 24) + 0.04
		Solid(Fixed(r, "Curb", Vector3.new(chord, 0.8, 0.6), CFrame.lookAt(p, p + Vector3.new(p.X, 0, p.Z)), if i % 2 == 0 then RED else C.White, M.SmoothPlastic))
		Fixed(r, "CurbPad", Vector3.new(chord, 0.14, 0.7), CFrame.lookAt(p + Vector3.new(0, 0.46, 0), p + Vector3.new(p.X, 0.46, p.Z)), C.Gold, M.Fabric)
	end
	-- gradins : 3 rangs par tribune (contremarches bleues, assises en bois)
	for tier = 0, FairRides.CIRCUS_TIERS - 1 do
		local rr = FairRides.CIRCUS_TIER_R0 + tier * FairRides.CIRCUS_TIER_DR
		local y = FairRides.CIRCUS_SEAT_Y0 + tier * FairRides.CIRCUS_TIER_DY
		for _, arc in ipairs(FairRides.CIRCUS_ARCS) do
			local a0, a1 = math.rad(arc[1] - 4), math.rad(arc[2] + 4)
			local n = 12
			for i = 0, n - 1 do
				local a = a0 + (a1 - a0) * (i + 0.5) / n
				local chord = 2 * rr * math.sin((a1 - a0) / n / 2) + 0.06
				local p = polar(a, rr, 0)
				local look = CFrame.lookAt(p, Vector3.new(0, 0, 0))
				-- (bloc du sol jusque sous l'assise : on monte dessus)
				Solid(Fixed(r, "Riser", Vector3.new(chord * (1 + 0.1 * tier), y - 0.3, FairRides.CIRCUS_TIER_DR), look * CFrame.new(0, (y - 0.3) / 2, 0), if i % 2 == 0 then BENCH_BLUE else BENCH_BLUE:Lerp(C.White, 0.12), M.SmoothPlastic))
				Fixed(r, "Plank", Vector3.new(chord, 0.3, 0.95), look * CFrame.new(0, y - 0.15, -0.35), C.Wood, M.WoodPlanks)
			end
		end
	end
	-- garde-corps derrière le dernier rang
	local rTop = FairRides.CIRCUS_TIER_R0 + FairRides.CIRCUS_TIERS * FairRides.CIRCUS_TIER_DR - 0.8
	local yTop = FairRides.CIRCUS_SEAT_Y0 + (FairRides.CIRCUS_TIERS - 1) * FairRides.CIRCUS_TIER_DY
	for _, arc in ipairs(FairRides.CIRCUS_ARCS) do
		local n = 10
		for i = 0, n - 1 do
			local a0 = math.rad(arc[1] - 4 + (arc[2] - arc[1] + 8) * i / n)
			local a1 = math.rad(arc[1] - 4 + (arc[2] - arc[1] + 8) * (i + 1) / n)
			FairKit.Rod(r.Model, "BackRail", r.Base * polar(a0, rTop, yTop + 1.3), r.Base * polar(a1, rTop, yTop + 1.3), 0.14, C.Gold, M.Metal)
			Fixed(r, "RailPost", Vector3.new(0.12, 1.3, 0.12), CFrame.new(polar(a0, rTop, yTop + 0.65)), C.Gold, M.Metal)
		end
	end
	-- coulisses : rideau de velours (plis) + arche dorée, au fond (+Z)
	for i = -4, 4 do
		local x = i * 0.75
		Fixed(r, "Curtain", Vector3.new(0.8, 6.4, 0.3), CFrame.new(x, 3.2, R - 1.2 + (i % 2) * 0.12), VELVET, M.Fabric)
	end
	Fixed(r, "Arch", Vector3.new(7.6, 0.6, 0.5), CFrame.new(0, 6.6, R - 1.45), C.Gold, M.Metal)
	for _, sx in ipairs({ -1, 1 }) do
		Fixed(r, "ArchPost", Vector3.new(0.5, 6.6, 0.5), CFrame.new(sx * 3.6, 3.3, R - 1.45), C.Gold, M.Metal)
	end
	-- portique de trapèze entre les mâts + filet de sécurité
	FairKit.Truss(r.Model, "Rig", r.Base * Vector3.new(-8.6, 14.6, 0), r.Base * Vector3.new(8.6, 14.6, 0), r.Base:VectorToWorldSpace(Vector3.new(0, 0, 1)), 0.8, 0.18, Color3.fromRGB(60, 60, 70), 10)
	local net = Fixed(r, "Net", Vector3.new(13, 0.08, 4.5), CFrame.new(0, 2.6, 0), Color3.fromRGB(30, 30, 36), M.Fabric)
	net.Transparency = 0.6
	for _, sx in ipairs({ -1, 1 }) do
		for _, sz in ipairs({ -1, 1 }) do
			Fixed(r, "NetPost", Vector3.new(0.14, 2.6, 0.14), CFrame.new(sx * 6.5, 1.3, sz * 2.25), C.Steel, M.Metal)
		end
	end
	-- 2 projecteurs sur le portique (lueur + faisceau très transparent)
	local lights = {}
	for _, sx in ipairs({ -1, 1 }) do
		local from = Vector3.new(sx * 8, 14.1, -2.5)
		local to = Vector3.new(sx * 1.2, 0.2, 0)
		local head = Fixed(r, "Projector", Vector3.new(0.9, 0.9, 1.4), CFrame.lookAt(from, to), Color3.fromRGB(40, 40, 46), M.Metal)
		Glow(Fixed(r, "Lens", Vector3.new(0.1, 0.7, 0.7), CFrame.lookAt(from, to) * CFrame.new(0, 0, -0.72) * CFrame.Angles(0, math.rad(90), 0), C.Bulb, M.SmoothPlastic, CYL))
		local beam = Fixed(r, "LightBeam", Vector3.new((to - from).Magnitude - 1, 2.2, 2.2), CFrame.lookAt((from + to) / 2, to) * CFrame.Angles(0, math.rad(90), 0), Color3.fromRGB(255, 244, 210), M.SmoothPlastic, CYL)
		beam.Transparency = 0.93
		local spot = Instance.new("SpotLight")
		spot.Name = "CircusSpot"
		spot.Brightness = 0.9
		spot.Range = 24
		spot.Angle = 32
		spot.Color = Color3.fromRGB(255, 240, 214)
		spot.Shadows = false
		spot.Face = Enum.NormalId.Front
		spot.Enabled = false
		spot.Parent = head
		table.insert(lights, spot)
	end
	return lights
end

----------------------------------------------------------------------
-- Le spectacle (64 s) : fonction PURE de l'heure du serveur
----------------------------------------------------------------------

local BACKSTAGE = Vector3.new(0, 0, 14.6)

-- (u de 0 à 1 : entrée ; de 1 à 0 : sortie) position le long d'un aller
-- des coulisses vers `to`
local function travel(to: Vector3, u: number): Vector3
	return BACKSTAGE:Lerp(to, smooth(u))
end

-- Fenêtre de présence [a, b] (s) avec 2 s d'entrée / de sortie :
-- renvoie (dedans 0..1, en marche ?)
local function window(t: number, a: number, b: number): (number, boolean)
	if t < a - 2 or t > b + 2 then
		return 0, false
	end
	if t < a then
		return (t - (a - 2)) / 2, true
	end
	if t > b then
		return 1 - (t - b) / 2, true
	end
	return 1, false
end

local function buildShow(r: RideFx, folder: Instance, booth: CFrame): any
	local N = npcModels()
	local show: any = { Npcs = {}, Props = {}, Parts = {}, Frames = {} }
	if not N or type(N.Build) ~= "function" then
		return show
	end
	local function npc(style: string, seed: number, opts: any): Model?
		local o = opts or {}
		o.Seed = seed
		o.Solid = if o.Solid == nil then false else o.Solid
		o.Look = false
		local ok, m = pcall(N.Build, style, o)
		if not ok or not m then
			return nil
		end
		m:PivotTo(r.Base * CFrame.new(BACKSTAGE))
		m.Parent = folder
		return m
	end
	show.Ringmaster = npc("salesperson", 501, { Shirt = Color3.fromRGB(186, 30, 44), Pants = Color3.fromRGB(30, 30, 36), Prop = "none" })
	show.Juggler = npc("pedestrian", 502, { Shirt = Color3.fromRGB(255, 200, 60), Pants = Color3.fromRGB(80, 60, 160), Prop = "none" })
	show.Rider = npc("jogger", 503, { Shirt = Color3.fromRGB(80, 170, 255), Pants = Color3.fromRGB(250, 250, 252), Prop = "none" })
	show.Acro1 = npc("jogger", 504, { Shirt = Color3.fromRGB(255, 132, 180), Pants = Color3.fromRGB(255, 132, 180), Prop = "none" })
	show.Acro2 = npc("jogger", 505, { Shirt = Color3.fromRGB(252, 244, 228), Pants = Color3.fromRGB(186, 150, 246), Prop = "none" })
	show.Clown1 = npc("pedestrian", 506, { Shirt = Color3.fromRGB(128, 214, 150), Pants = Color3.fromRGB(236, 72, 140), Hair = Color3.fromRGB(255, 120, 40), Prop = "none" })
	show.Clown2 = npc("kid", 507, { Shirt = Color3.fromRGB(255, 176, 60), Pants = Color3.fromRGB(80, 170, 255), Hair = Color3.fromRGB(60, 200, 255), Prop = "none" })
	-- caissière du guichet (dans la cabine)
	show.Cashier = npc("cashier", 508, { Solid = true })
	if show.Cashier then
		show.Cashier:PivotTo(r.Base * booth * CFrame.new(0, 0, 0.6))
	end
	-- spectateurs assis (quelques-uns, sur des places qui ne sont pas des sièges du serveur)
	show.Fans = {}
	local fanSeats = { { 1, 46 }, { 2, 118 }, { 0, -60 }, { 2, -104 }, { 1, 90 }, { 0, 132 } }
	-- (qualité "Détail" basse : 2 spectateurs seulement ; GraphicsQuality)
	local detail = 1
	pcall(function()
		local GQ = require(ReplicatedStorage.Shared.GraphicsQuality) :: any
		detail = GQ.DetailScale()
	end)
	local fans = if detail < 0.9 then 2 else #fanSeats
	for i, fs in ipairs(fanSeats) do
		if i > fans then
			break
		end
		local tier, deg = fs[1], fs[2]
		local rr = FairRides.CIRCUS_TIER_R0 + tier * FairRides.CIRCUS_TIER_DR
		local y = FairRides.CIRCUS_SEAT_Y0 + tier * FairRides.CIRCUS_TIER_DY
		local style = ({ "shopper", "kid", "elder", "pedestrian", "kid", "shopper" })[i]
		local m = npc(style, 520 + i, { Solid = true })
		if m then
			local p = polar(math.rad(deg), rr, 0)
			m:PivotTo(r.Base * CFrame.lookAt(p, Vector3.new(0, 0, 0)))
			pcall(N.SetSeated, m, y)
			table.insert(show.Fans, { Model = m, Seed = i * 1.3 })
		end
	end
	-- accessoires : 3 balles, monocycle, voiture de clowns, 2 trapèzes
	local model = r.Model
	for i = 1, 3 do
		table.insert(show.Props, { Kind = "Ball", Part = Part(model, "JuggleBall", Vector3.one * 0.42, r.Base, ({ RED, C.Lemon, C.Sky })[i], M.SmoothPlastic, BALL), I = i })
	end
	show.Uni = {
		Wheel = Part(model, "UniWheel", Vector3.new(0.22, 1.6, 1.6), r.Base, Color3.fromRGB(30, 30, 36), M.Rubber, CYL),
		Hub = Part(model, "UniHub", Vector3.new(0.26, 0.5, 0.5), r.Base, C.SteelLight, M.Metal, CYL),
		Post = Part(model, "UniPost", Vector3.new(0.14, 1.5, 0.14), r.Base, C.SteelLight, M.Metal),
		Saddle = Part(model, "UniSaddle", Vector3.new(0.45, 0.2, 0.8), r.Base, RED, M.Leather),
	}
	local car = {}
	local carColor = Color3.fromRGB(255, 196, 60)
	local function carPart(name: string, size: Vector3, loc: CFrame, color: Color3, mat: Enum.Material?, shape: Enum.PartType?)
		table.insert(car, { Part = Part(model, name, size, r.Base, color, mat or M.SmoothPlastic, shape), Loc = loc })
	end
	carPart("ClownCarBody", Vector3.new(2.4, 1.1, 3.4), CFrame.new(0, 0.95, 0), carColor, M.SmoothPlastic)
	carPart("ClownCarHood", Vector3.new(2.3, 0.9, 1.4), CFrame.new(0, 1.2, -1.3), carColor, M.SmoothPlastic, BALL)
	carPart("ClownCarCab", Vector3.new(2.1, 1.3, 1.6), CFrame.new(0, 1.95, 0.5), Color3.fromRGB(80, 170, 255), M.SmoothPlastic, BALL)
	carPart("ClownCarDots", Vector3.new(0.05, 0.5, 0.5), CFrame.new(1.22, 1.0, 0.3) * CFrame.Angles(0, math.rad(90), 0), RED, M.SmoothPlastic, CYL)
	carPart("ClownCarDots", Vector3.new(0.05, 0.5, 0.5), CFrame.new(-1.22, 1.0, 0.3) * CFrame.Angles(0, math.rad(90), 0), RED, M.SmoothPlastic, CYL)
	for _, wx in ipairs({ -1.1, 1.1 }) do
		for _, wz in ipairs({ -1.1, 1.1 }) do
			carPart("ClownCarWheel", Vector3.new(0.4, 0.9, 0.9), CFrame.new(wx, 0.45, wz), Color3.fromRGB(30, 30, 36), M.Rubber, CYL)
		end
	end
	carPart("ClownCarHorn", Vector3.new(0.3, 0.3, 0.6), CFrame.new(0.8, 1.6, -1.6), C.Gold, M.Metal, BALL)
	carPart("ClownCarFlower", Vector3.new(0.5, 0.5, 0.5), CFrame.new(-0.6, 2.8, 0.5), C.Pink, M.SmoothPlastic, BALL)
	show.Car = car
	show.Bars = {}
	for _, sx in ipairs({ -1, 1 }) do
		local bar = {
			X = sx * 5,
			Ropes = { Part(model, "TrapezeRope", Vector3.new(0.06, 4, 0.06), r.Base, CANVAS, M.Fabric), Part(model, "TrapezeRope", Vector3.new(0.06, 4, 0.06), r.Base, CANVAS, M.Fabric) },
			Bar = Part(model, "TrapezeBar", Vector3.new(1.4, 0.14, 0.14), r.Base, C.SteelLight, M.Metal, CYL),
		}
		table.insert(show.Bars, bar)
	end
	return show
end

local ROPE = 4
local PIV_Y = 14.3

-- Pose du spectacle à l'heure t (s) ; anime les PNJ si `near`
local function stepShow(r: RideFx, show: any, t: number, near: boolean)
	local N = npcModels()
	local T = FairRides.CIRCUS_SHOW
	local u = t % T
	local parts, frames = show.Parts, show.Frames
	table.clear(parts)
	table.clear(frames)
	local B = r.Base
	local function place(m: Model?, cf: CFrame, anim: string, seed: number)
		if not m or not N then
			return
		end
		m:PivotTo(B * cf)
		if near then
			pcall(N.Animate, m, anim, t + seed)
		end
	end
	-- 🤹 jongleur (0-22 s)
	do
		local k, moving = window(u, 1, 21)
		local target = Vector3.new(0, 0.2, -0.5)
		local p = travel(target, k)
		local dir = if moving then (if u < 11 then target - BACKSTAGE else BACKSTAGE - target) else Vector3.new(0, 0, -1)
		dir = Vector3.new(dir.X, 0, dir.Z).Unit
		local cf = CFrame.lookAt(p, p + dir)
		place(show.Juggler, cf, if moving then "walk" elseif k > 0.5 then "talk" else "idle", 2)
		-- cascade à 3 balles (en huit) au-dessus des mains
		for _, b in ipairs(show.Props) do
			local ph = (t * 1.6 + (b.I - 1) / 3) % 1
			local side = if math.floor(t * 1.6 + (b.I - 1) / 3) % 2 == 0 then 1 else -1
			local x = side * (0.55 - 1.1 * ph)
			local y = 4.3 + 2.1 * 4 * ph * (1 - ph)
			local world = if k > 0.99 then cf * CFrame.new(x, y, -0.75) else cf * CFrame.new(0.4, 2.6 + b.I * 0.001, -0.3)
			table.insert(parts, b.Part)
			table.insert(frames, B * world)
		end
	end
	-- 🚗 voiture de clowns (22-44 s) : 2 tours de piste, arrêt, les clowns sortent
	do
		local carCF
		local k, _ = window(u, 24, 42)
		local ringR = 3.6
		if u >= 24 and u < 34 then
			local a = (u - 24) / 10 * TAU * 1.5 + math.pi
			local p = Vector3.new(math.sin(a) * ringR, 0.2, math.cos(a) * ringR)
			carCF = CFrame.lookAt(p, p + Vector3.new(math.cos(a), 0, -math.sin(a)))
		elseif u >= 34 and u <= 42 then
			local a = 1.5 * TAU + math.pi
			local p = Vector3.new(math.sin(a) * ringR, 0.2, math.cos(a) * ringR)
			carCF = CFrame.lookAt(p, p + Vector3.new(math.cos(a), 0, -math.sin(a)))
		else
			-- aller / retour entre les coulisses et la piste
			local start = Vector3.new(0, 0.2, -ringR)
			local p = travel(start, k)
			carCF = CFrame.lookAt(p, p + (if u < 30 then (start - BACKSTAGE) else (BACKSTAGE - start)).Unit)
			if k <= 0 then
				carCF = CFrame.new(BACKSTAGE + Vector3.new(4.2, 0.2, 0.6)) * CFrame.Angles(0, math.rad(90), 0)
			end
		end
		local bounce = CFrame.new(0, math.abs(math.sin(t * 9)) * 0.08, 0)
		for _, c in ipairs(show.Car) do
			table.insert(parts, c.Part)
			table.insert(frames, B * carCF * bounce * c.Loc)
		end
		-- clowns : dans la voiture (cachés dessous) sauf de 34 à 41 s
		for i, m in ipairs({ show.Clown1, show.Clown2 }) do
			if m then
				local out = if u >= 34.3 + i * 0.4 and u < 41 - i * 0.3 then 1 else 0
				local pop = math.clamp((u - (34.3 + i * 0.4)) / 0.5, 0, 1)
				local sx = if i == 1 then -1 else 1
				if out > 0 then
					local step = carCF * CFrame.new(sx * (1.8 + pop * 0.8), 0, -0.4 - (i - 1) * 0.6) * CFrame.Angles(0, math.rad(sx * -70), 0)
					place(m, step, "cheer", i * 3)
				else
					place(m, carCF * CFrame.new(0, -6, 0), "idle", i * 3)
				end
			end
		end
	end
	-- 🚲 monocycliste (44-57 s) : tours de piste
	do
		local ringR = 4.4
		local k, _ = window(u, 45, 56)
		local p, fwd
		if u >= 45 and u <= 56 then
			local a = (u - 45) * 0.9
			p = Vector3.new(math.sin(a) * ringR, 0, math.cos(a) * ringR)
			fwd = Vector3.new(math.cos(a), 0, -math.sin(a))
		else
			local start = Vector3.new(0, 0, ringR)
			p = travel(start, k)
			fwd = if u < 50 then (start - BACKSTAGE) else (BACKSTAGE - start)
			if fwd.Magnitude < 0.01 then
				fwd = Vector3.new(0, 0, -1)
			end
			fwd = fwd.Unit
		end
		local base = CFrame.lookAt(p, p + fwd)
		local wobble = CFrame.Angles(0, 0, math.sin(t * 5) * 0.05)
		local lift = if k > 0 then 1.55 else 0
		place(show.Rider, base * CFrame.new(0, lift, 0) * wobble, if k > 0 then "walk" else "idle", 5)
		local uni = show.Uni
		local spin = CFrame.Angles(t * 6, 0, 0)
		local wheel = base * CFrame.new(0, 0.8, 0) * CFrame.Angles(0, math.rad(90), 0) * spin
		local hidden = if k > 0 then CFrame.identity else CFrame.new(0, -8, 0)
		for _, pair in ipairs({
			{ uni.Wheel, wheel },
			{ uni.Hub, base * CFrame.new(0, 0.8, 0) * CFrame.Angles(0, math.rad(90), 0) },
			{ uni.Post, base * CFrame.new(0, 1.5, 0) * wobble },
			{ uni.Saddle, base * CFrame.new(0, 2.25, 0) * wobble },
		}) do
			table.insert(parts, pair[1])
			table.insert(frames, B * hidden * pair[2])
		end
	end
	-- 🤸 trapèzes : balancement en opposition ; acrobates pendus par les genoux
	do
		local amp = math.rad(38)
		for i, bar in ipairs(show.Bars) do
			local sx = if i == 1 then -1 else 1
			local a = amp * math.sin(t * TAU / 4.2) * sx
			local pivot = CFrame.new(bar.X, PIV_Y, 0) * CFrame.Angles(0, 0, a)
			for k, rope in ipairs(bar.Ropes) do
				table.insert(parts, rope)
				table.insert(frames, B * pivot * CFrame.new(0, -ROPE / 2, if k == 1 then -0.65 else 0.65))
			end
			local barCF = pivot * CFrame.new(0, -ROPE, 0) * CFrame.Angles(0, math.rad(90), 0)
			table.insert(parts, bar.Bar)
			table.insert(frames, B * barCF)
			local acro = if i == 1 then show.Acro1 else show.Acro2
			-- (tête en bas : pieds au trapèze, face au public de devant)
			local hang = pivot * CFrame.new(0, -ROPE - 0.15, 0) * CFrame.Angles(math.pi, 0, 0) * CFrame.Angles(0, math.pi, 0)
			place(acro, hang, "cheer", 7 + i)
		end
	end
	-- 🎩 Monsieur Loyal : au bord de la piste, salut final au centre (57-64 s)
	do
		local final = u >= 57
		local spot = if final then Vector3.new(0, 0.2, -1.5) else Vector3.new(-2.5, 0.2, -7.4)
		local p = spot
		local look = if final then Vector3.new(0, 0.2, -12) else Vector3.new(0, 0.2, -1)
		place(show.Ringmaster, CFrame.lookAt(p, look), if final then "wave" else "talk", 11)
	end
	if near and N then
		for _, fan in ipairs(show.Fans) do
			pcall(N.Animate, fan.Model, if u >= 57 or (u > 34 and u < 40) then "cheer" else "clap", t + fan.Seed)
		end
		if show.Cashier then
			pcall(N.Animate, show.Cashier, "talk", t + 9)
		end
	end
	if #parts > 0 then
		workspace:BulkMoveTo(parts, frames, Enum.BulkMoveMode.FireCFrameChanged)
	end
end

----------------------------------------------------------------------
-- API
----------------------------------------------------------------------

function FairCircus.Build(r: RideFx, npcFolder: Instance)
	local booth = buildTent(r)
	local lights = buildInside(r)
	local show = buildShow(r, npcFolder, booth)
	r.Radius = FairRides.CIRCUS_R + 4
	r.Extra = {
		Show = show,
		Lights = lights,
		Step = function(t: number)
			local camera = workspace.CurrentCamera
			local dist = if camera then (camera.CFrame.Position - r.Base.Position).Magnitude else math.huge
			local near = dist < SHOW_R
			for _, l in ipairs(lights) do
				local on = dist < LIGHT_R
				if l.Enabled ~= on then
					l.Enabled = on
				end
			end
			if near or show.Parked ~= true then
				show.Parked = not near
				stepShow(r, show, t, near)
			end
		end,
	}
end

FairCircus.SHOW_R = SHOW_R

return FairCircus
