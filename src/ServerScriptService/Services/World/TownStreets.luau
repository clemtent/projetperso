--[[
	TownStreets (ModuleScript)
	Emplacement : ServerScriptService > Services > World > TownStreets

	🛣️ Les rues de Dopamine Town (v9.4) :
	  - BOULEVARD polygonal : un côté droit devant chaque parcelle (et devant
	    l'entrée), chaussée en asphalte 2 voies, ligne médiane en pointillés,
	    lignes de rive, trottoirs surélevés avec bordures, coins en onglet
	    (pas de trou entre deux côtés) ;
	  - AVENUE principale (entrée -> place) façon "rambla" : promenade
	    centrale pavée bordée d'arbres et de lampadaires doubles, une voie de
	    chaque côté, trottoirs ; passage piéton vers la place d'accueil ;
	  - deux RUES latérales (T avec le boulevard) : chaussée, pointillés,
	    trottoirs, passage piéton, ligne d'arrêt, panneau "stop" ;
	  - zones piétonnes (bornes) à l'arrivée sur la place ;
	  - mobilier : arbres d'alignement, lampadaires (quelques vraies
	    lumières), bancs, poubelles, bouches d'incendie, voitures garées.
	Construit une fois par TownMap.Build.
	v9.8 (CITY98) : les rues PLEINES DE VIE. Le serveur note seulement les
	emplacements (TownKit.LifeSpot, 0 pièce) du mobilier que le client
	construit en flux (TownStreetLife : poubelles, bacs de tri, bancs,
	abribus, kiosque, cabines, distributeurs, feux tricolores, passages
	piétons, pistes cyclables, oriflammes, plaques de rue...) et les
	chemins des passants (TownKit.LifePath -> TownPeople).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local WorldLayout = require(ReplicatedStorage.Shared.WorldLayout)
local TownKit = require(script.Parent.TownKit)
local TownBuildings = require(script.Parent.TownBuildings)
local TownVehicles = require(script.Parent.TownVehicles) -- (v9.7, VEHICLES97) places de stationnement, 2-roues

local TownStreets = {}

local M = TownKit.M
local C = TownKit.C
local part = TownKit.Part
local hash = TownKit.Hash

local ROAD_Y = WorldLayout.ROAD_Y
local WALK_Y = WorldLayout.WALK_Y
local ROAD_W = WorldLayout.ROAD_W
local WALK_W = WorldLayout.WALK_W

-- Avenue principale (x latéral depuis l'axe)
local PROM = 7 -- demi-largeur de la promenade centrale
local LANE_OUT = 15 -- bord extérieur des voies
local AVE_OUT = LANE_OUT + WALK_W -- bord extérieur des trottoirs (21)
-- Rues latérales
local ST_HALF = WorldLayout.AVENUE_W / 2 -- 8
local ST_WALK = 5
local ST_OUT = ST_HALF + ST_WALK -- 13

-- (v9.7, VEHICLES97 : teintes des voitures garées -> TownVehicles.PARKED_COLORS)

----------------------------------------------------------------------
-- Bandes droites avec trous (croisements)
----------------------------------------------------------------------

-- Pièces le long de x (repère `cf`) de x0 à x1, sans les intervalles `gaps`
-- (v9.6 : `grow` allonge chaque morceau aux deux bouts : une bordure dépasse
-- ainsi du trottoir au lieu d'avoir ses faces d'extrémité confondues)
local function strip(parent: Instance, name: string, cf: CFrame, x0: number, x1: number, z0: number, z1: number, top: number, thick: number, color: Color3, material: Enum.Material, profile: string?, gaps: { { number } }?, grow: number?)
	local ranges = { { x0, x1 } }
	for _, gap in ipairs(gaps or {}) do
		local nextRanges = {}
		for _, r in ipairs(ranges) do
			if gap[2] <= r[1] or gap[1] >= r[2] then
				table.insert(nextRanges, r)
			else
				if gap[1] > r[1] then
					table.insert(nextRanges, { r[1], gap[1] })
				end
				if gap[2] < r[2] then
					table.insert(nextRanges, { gap[2], r[2] })
				end
			end
		end
		ranges = nextRanges
	end
	local g = grow or 0
	for _, r in ipairs(ranges) do
		local len = r[2] - r[1]
		if len > 0.2 then
			local size = Vector3.new(len + 2 * g, thick, math.abs(z1 - z0))
			local pcf = cf * CFrame.new((r[1] + r[2]) / 2, top - thick / 2, (z0 + z1) / 2)
			if profile == "paint" then
				-- (v9.8, CITY98) peinture au sol : construite côté client (TownStreetLife)
				TownKit.LifeSpot("Paint", pcf, 0, size)
			else
				part(parent, name, size, pcf, color, material, profile)
			end
		end
	end
end

-- (v9.8, CITY98) marquage au sol construit côté CLIENT (0 pièce serveur)
local function paint(size: Vector3, cf: CFrame)
	TownKit.LifeSpot("Paint", cf, 0, size)
end

----------------------------------------------------------------------
-- Boulevard
----------------------------------------------------------------------

local function isStreet(geo: TownKit.Geo, slot: number): boolean
	return table.find(geo.Streets, slot) ~= nil
end

local function buildBoulevard(folder: Instance, geo: TownKit.Geo)
	local m = geo.Slots
	local A = geo.Road
	local tanH = math.tan(geo.HalfAngle)
	local hw = ROAD_W / 2
	for k = 0, m - 1 do
		local side = TownKit.Model(folder, "Boulevard_" .. k)
		local F = geo.SideFrame(k, A)
		local junction = isStreet(geo, k)
		local jw = k == 0 and LANE_OUT or ST_HALF
		local innerGaps = junction and { { -jw, jw } } or nil
		-- chaussée (coins en onglet : longueur au bord extérieur)
		local roadHalf = (A + hw) * tanH
		strip(side, "Asphalt", F, -roadHalf, roadHalf, -hw, hw, ROAD_Y, 0.7, C.Asphalt, M.Asphalt, "solid")
		-- trottoirs (surélevés) + bordures
		local innerHalf = (A - hw) * tanH
		strip(side, "Sidewalk", F, -innerHalf, innerHalf, -hw - WALK_W, -hw, WALK_Y, 1.3, C.Walk, M.Pavement, "solid", innerGaps)
		-- (v9.6 z-fighting : la bordure avance de 0.05 vers la chaussée et dépasse
		-- de 0.05 aux bouts : sa face n'est plus confondue avec celle du trottoir)
		strip(side, "Curb", F, -innerHalf, innerHalf, -hw - 0.8, -hw + 0.05, WALK_Y + 0.03, 0.4, C.Curb, M.Concrete, "deco", innerGaps, 0.05)
		local outerHalf = (A + hw + WALK_W) * tanH
		strip(side, "Sidewalk", F, -outerHalf, outerHalf, hw, hw + WALK_W, WALK_Y, 1.3, C.Walk, M.Pavement, "solid")
		strip(side, "Curb", F, -(A + hw + 0.8) * tanH, (A + hw + 0.8) * tanH, hw - 0.05, hw + 0.8, WALK_Y + 0.03, 0.4, C.Curb, M.Concrete, "deco")
		-- lignes de rive
		local edgeZ = hw - 1.1
		strip(side, "EdgeLine", F, -(A + edgeZ) * tanH, (A + edgeZ) * tanH, edgeZ - 0.18, edgeZ + 0.18, ROAD_Y + 0.05, 0.1, C.Line, M.SmoothPlastic, "paint")
		strip(side, "EdgeLine", F, -(A - edgeZ) * tanH, (A - edgeZ) * tanH, -edgeZ - 0.18, -edgeZ + 0.18, ROAD_Y + 0.05, 0.1, C.Line, M.SmoothPlastic, "paint", innerGaps)
		-- ligne médiane en pointillés (arrêtée avant les coins et les croisements)
		local limit = A * tanH - 10
		local x = -limit
		while x + 5 <= limit do
			local cx = x + 2.5
			if not (junction and math.abs(cx) < jw + 5) then
				paint(Vector3.new(6, 0.1, 0.4), F * CFrame.new(cx, ROAD_Y + 0.05, 0))
			end
			x += 18
		end
		if junction then
			if k == 0 then
				-- passage piéton : de la place d'accueil à la promenade de l'avenue
				for i = 0, 7 do
					local z = -hw + 1.6 + i * (ROAD_W - 3.2) / 7
					paint(Vector3.new(12, 0.1, 1.1), F * CFrame.new(0, ROAD_Y + 0.05, z))
				end
			else
				-- flèches de tourne-à-gauche / droite : simple ligne "cédez" pointillée
				for i = -3, 3 do
					paint(Vector3.new(1.6, 0.1, 0.4), F * CFrame.new(i * 2.4, ROAD_Y + 0.05, -hw + 3))
				end
			end
		end
		-- mobilier : lampadaires sur le trottoir extérieur, arbres côté intérieur,
		-- une voiture garée le long du trottoir intérieur (un côté sur deux ou presque)
		local half = A * tanH
		for _, lx in ipairs({ -half * 0.5, half * 0.5 }) do
			if not (junction and math.abs(lx) < jw + 8) then
				local base = (F * CFrame.new(lx, WALK_Y, hw + WALK_W - 1.2)).Position
				-- (bras au-dessus de la chaussée ; vraies lumières : devant l'entrée)
				TownKit.Lamp(side, base, TownKit.Facing(F.LookVector), k == 0)
			end
		end
		local treeHalf = (A - hw - WALK_W - 4) * tanH - 8
		local n = math.max(1, math.floor(2 * treeHalf / 34))
		for i = 0, n do
			local tx = -treeHalf + i * (2 * treeHalf) / math.max(1, n)
			if not (junction and math.abs(tx) < jw + 7) then
				local base = (F * CFrame.new(tx, WorldLayout.GROUND_Y, -hw - WALK_W - 4)).Position
				-- (v9.7 NATURE97) boulevard : chênes, érables, peupliers, cerisiers (silhouette ; détails de près côté client)
				TownKit.Tree(side, base, 12 + hash(k, i) * 5, k * 17 + i, ({ "Oak", "Poplar", "Maple", "Oak", "Cherry" })[(i + k) % 5 + 1], { Lawn = true })
			end
		end
		if not (k == 0) then
			-- (v9.7, VEHICLES97) 3 places marquées le long du trottoir intérieur
			-- (voitures alignées, roues sur la chaussée, conduite à droite) ;
			-- budget du serveur : 1 voiture serveur sur un côté sur quatre, les
			-- autres places occupées sont remplies côté client (TownTraffic, en flux)
			local rowHalf = 1.5 * TownVehicles.BAY_LENGTH
			local cx = (hash(k, 5) - 0.5) * half * 0.9
			if junction and math.abs(cx) < jw + 12 + rowHalf then
				cx = (if cx < 0 then -1 else 1) * (jw + 12 + rowHalf)
			end
			if math.abs(cx) + rowHalf < (A - hw) * tanH - 8 then
				TownVehicles.ParkingRow(side, F * CFrame.new(cx, ROAD_Y, -hw + 0.05) * CFrame.Angles(0, math.pi, 0), 3, k * 13 + 5, if k % 4 == 1 then 1 else 0)
			end
		end
		-- bouche d'incendie + poubelle sur le trottoir intérieur
		local hx = half * 0.25
		if k % 2 == 1 and not (junction and math.abs(hx) < jw + 6) then
			TownKit.Hydrant(side, (F * CFrame.new(hx, WALK_Y, -hw - 1.6)).Position)
			TownKit.Bin(side, (F * CFrame.new(hx + 3, WALK_Y, -hw - 1.6)).Position, k % 2 == 0 and Color3.fromRGB(96, 150, 110) or Color3.fromRGB(110, 140, 200))
		end
	end
end

----------------------------------------------------------------------
-- Avenue principale (rambla) et rues latérales
----------------------------------------------------------------------

-- Repère radial : origine au centre, -Z = vers l'extérieur le long de l'emplacement
local function radialFrame(geo: TownKit.Geo, slot: number): CFrame
	local d = geo.Dir(geo.SlotAngle(slot))
	return CFrame.lookAt(geo.Origin, geo.Origin + d)
end

-- Segment radial (s0 -> s1, x0 -> x1) dans le repère radial
local function radialBox(parent: Instance, name: string, R: CFrame, s0: number, s1: number, x0: number, x1: number, top: number, thick: number, color: Color3, material: Enum.Material, profile: string?)
	local size = Vector3.new(math.abs(x1 - x0), thick, math.abs(s1 - s0))
	local cf = R * CFrame.new((x0 + x1) / 2, top - thick / 2, -(s0 + s1) / 2)
	if profile == "paint" then
		-- (v9.8, CITY98) peinture au sol : construite côté client (TownStreetLife)
		TownKit.LifeSpot("Paint", cf, 0, size)
	else
		part(parent, name, size, cf, color, material, profile)
	end
end

local function buildAvenue(folder: Instance, geo: TownKit.Geo)
	local ave = TownKit.Model(folder, "Avenue")
	local R = radialFrame(geo, 0)
	local plazaR = WorldLayout.PLAZA_R
	local s0 = geo.StreetStart
	local roadEdge = geo.Road - ROAD_W / 2
	-- zone piétonne entre la place et le début des voies
	-- (v9.8 z-fighting : 0,03 sous le pavage de la place qu'elle chevauche)
	radialBox(ave, "PedestrianZone", R, plazaR - 2, s0, -AVE_OUT, AVE_OUT, WALK_Y - 0.03, 1.3, C.Paving, M.Cobblestone, "solid")
	-- promenade centrale (pavés roses bordés de pierre)
	radialBox(ave, "Promenade", R, s0, roadEdge, -PROM, PROM, WALK_Y, 1.3, C.Paving, M.Cobblestone, "solid")
	-- (v9.6 z-fighting : bande raccourcie de 0.05 aux bouts, bordures qui
	-- dépassent de 0.05 : plus aucune face confondue avec la promenade)
	radialBox(ave, "PromenadeBand", R, s0 + 0.05, roadEdge - 0.05, -2, 2, WALK_Y + 0.03, 0.2, C.PavingRose, M.Cobblestone, "deco")
	for _, sx in ipairs({ -1, 1 }) do
		radialBox(ave, "PromenadeCurb", R, s0 - 0.05, roadEdge + 0.05, sx * (PROM - 0.8), sx * (PROM + 0.05), WALK_Y + 0.03, 0.4, C.Curb, M.Concrete, "deco")
		-- voie (sens unique) + ligne de rive
		radialBox(ave, "Lane", R, s0, roadEdge + 0.5, sx * PROM, sx * LANE_OUT, ROAD_Y, 0.7, C.Asphalt, M.Asphalt, "solid")
		-- trottoir extérieur + bordure
		radialBox(ave, "Sidewalk", R, s0, geo.Inner + 0.5, sx * LANE_OUT, sx * AVE_OUT, WALK_Y, 1.3, C.Walk, M.Pavement, "solid")
		radialBox(ave, "Curb", R, s0 - 0.05, geo.Inner + 0.55, sx * (LANE_OUT - 0.05), sx * (LANE_OUT + 0.8), WALK_Y + 0.03, 0.4, C.Curb, M.Concrete, "deco")
		-- ligne d'arrêt au bout de la voie + flèche
		radialBox(ave, "StopLine", R, roadEdge - 2.4, roadEdge - 1.8, sx * (PROM + 0.4), sx * (LANE_OUT - 0.4), ROAD_Y + 0.05, 0.1, C.Line, M.SmoothPlastic, "paint")
		-- bornes à l'entrée de la zone piétonne
		for i = 0, 3 do
			local x = sx * (PROM + 1.2 + i * 2.2)
			TownKit.Bollard(ave, (R * CFrame.new(x, WALK_Y, -s0 + 0.8)).Position)
		end
	end
	-- arbres (double rangée) sur la promenade ; entre deux arbres : un
	-- lampadaire ou un banc tourné vers l'axe (le milieu reste libre pour marcher)
	local length = roadEdge - 6 - (s0 + 6)
	-- (pas de 14 studs, 10 intervalles au plus : budget de pièces des grandes villes)
	local n = math.clamp(math.floor(length / 14), 2, 8)
	local lamps = 0
	for i = 0, n do
		local s = s0 + 6 + i * length / n
		for _, sx in ipairs({ -1, 1 }) do
			local base = (R * CFrame.new(sx * (PROM - 2.2), WALK_Y, -s)).Position
			part(ave, "TreeGrate", Vector3.new(3, 0.1, 3), CFrame.new(base + Vector3.new(0, 0.05, 0)), C.Metal, M.DiamondPlate, "deco")
			-- (v9.7 NATURE97) avenue : allée de cerisiers, d'érables et de chênes (détails de près côté client)
			TownKit.Tree(ave, base, 13 + hash(i, sx) * 3, i * 7 + sx, (i % 3 == 1) and "Cherry" or (i % 3 == 2 and "Maple" or "Oak"))
		end
		if i < n then
			local sm = s + length / n / 2
			for _, sx in ipairs({ -1, 1 }) do
				if (i + (sx > 0 and 1 or 0)) % 2 == 0 then
					lamps += 1
					local base = (R * CFrame.new(sx * (PROM - 1.6), WALK_Y, -sm)).Position
					-- (vraies lumières : une sur trois, 4 au plus)
					TownKit.Lamp(ave, base, TownKit.Facing(R.RightVector * -sx), lamps % 3 == 1 and lamps <= 10)
				else
					local benchCF = R * CFrame.new(sx * (PROM - 1.8), WALK_Y, -sm) * CFrame.Angles(0, math.rad(sx * 90), 0)
					TownKit.Bench(ave, benchCF)
					TownKit.LifeSpot("SitBench", benchCF, i * 2 + (sx > 0 and 1 or 0)) -- (v9.8, CITY98) un passant peut s'y asseoir
				end
			end
		end
	end
	-- poubelles / vélos / panneau sur les trottoirs
	TownKit.Bin(ave, (R * CFrame.new(LANE_OUT + 1.6, WALK_Y, -(s0 + 20))).Position)
	TownKit.Bin(ave, (R * CFrame.new(-LANE_OUT - 1.6, WALK_Y, -(s0 + 34))).Position, Color3.fromRGB(110, 140, 200))
	TownKit.Hydrant(ave, (R * CFrame.new(-LANE_OUT - 1.6, WALK_Y, -(s0 + 12))).Position)
	TownKit.RoadSign(ave, (R * CFrame.new(LANE_OUT + 1.2, WALK_Y, -(roadEdge - 8))).Position, 0, Color3.fromRGB(60, 120, 220), "Rect")
	TownKit.RoadSign(ave, (R * CFrame.new(-LANE_OUT - 1.2, WALK_Y, -(s0 + 4))).Position, math.pi, Color3.fromRGB(220, 60, 70))
end

local function buildSideStreet(folder: Instance, geo: TownKit.Geo, slot: number)
	local st = TownKit.Model(folder, "Street_" .. slot)
	local R = radialFrame(geo, slot)
	local plazaR = WorldLayout.PLAZA_R
	local s0 = geo.StreetStart
	local roadEdge = geo.Road - ROAD_W / 2
	radialBox(st, "PedestrianZone", R, plazaR - 2, s0, -ST_OUT, ST_OUT, WALK_Y - 0.03, 1.3, C.Paving, M.Cobblestone, "solid") -- (v9.8 : 0,03 sous la place)
	radialBox(st, "Asphalt", R, s0, roadEdge + 0.5, -ST_HALF, ST_HALF, ROAD_Y, 0.7, C.Asphalt, M.Asphalt, "solid")
	for _, sx in ipairs({ -1, 1 }) do
		radialBox(st, "Sidewalk", R, s0, geo.Inner + 0.5, sx * ST_HALF, sx * ST_OUT, WALK_Y, 1.3, C.Walk, M.Pavement, "solid")
		radialBox(st, "Curb", R, s0 - 0.05, geo.Inner + 0.55, sx * (ST_HALF - 0.05), sx * (ST_HALF + 0.8), WALK_Y + 0.03, 0.4, C.Curb, M.Concrete, "deco")
		for i = 0, 2 do
			TownKit.Bollard(st, (R * CFrame.new(sx * (1.5 + i * 2.6), WALK_Y, -s0 + 0.8)).Position)
		end
	end
	-- pointillés, passage piéton, ligne d'arrêt
	local s = s0 + 4
	while s + 5 < geo.Inner - 10 do
		radialBox(st, "Dash", R, s, s + 5, -0.2, 0.2, ROAD_Y + 0.05, 0.1, C.Line, M.SmoothPlastic, "paint")
		s += 18
	end
	local zs = geo.Inner - 6
	for i = 0, 5 do
		local x = -ST_HALF + 1.4 + i * (2 * ST_HALF - 2.8) / 5
		radialBox(st, "Zebra", R, zs - 2.5, zs + 2.5, x - 0.55, x + 0.55, ROAD_Y + 0.05, 0.1, C.Line, M.SmoothPlastic, "paint")
	end
	radialBox(st, "StopLine", R, zs - 4.2, zs - 3.6, 0.2, ST_HALF - 0.4, ROAD_Y + 0.05, 0.1, C.Line, M.SmoothPlastic, "paint")
	TownKit.RoadSign(st, (R * CFrame.new(ST_HALF + 1.4, WALK_Y, -(zs - 5))).Position, geo.SlotAngle(slot), Color3.fromRGB(220, 60, 70), "Diamond")
	-- arbres d'alignement + lampadaires
	local length = geo.Inner - 8 - (s0 + 6)
	local n = math.clamp(math.floor(length / 20), 1, 7)
	for i = 0, n do
		local si = s0 + 6 + i * length / n
		for _, sx in ipairs({ -1, 1 }) do
			local base = (R * CFrame.new(sx * (ST_OUT - 1.8), WALK_Y, -si)).Position
			if (i + (sx > 0 and 1 or 0)) % 2 == 0 then
				part(st, "TreeGrate", Vector3.new(2.6, 0.1, 2.6), CFrame.new(base + Vector3.new(0, 0.05, 0)), C.Metal, M.DiamondPlate, "deco")
				TownKit.Tree(st, base, 11 + hash(slot, i) * 4, slot * 31 + i + sx, (i % 2 == 0) and "Birch" or "Oak") -- (v9.7 NATURE97)
			else
				TownKit.Lamp(st, base, TownKit.Facing(R.RightVector * -sx), false)
			end
		end
	end
	-- (v9.7, VEHICLES97) stationnement marqué des deux côtés (conduite à
	-- droite : côté +x vers l'extérieur, côté -x vers la place) ; 1 voiture
	-- serveur, les autres côté client ; camion de livraison devant les
	-- boutiques d'une des deux rues ; trottinettes / scooter sur le trottoir
	TownVehicles.ParkingRow(st, R * CFrame.new(ST_HALF - 0.05, ROAD_Y, -(s0 + length * 0.55)) * CFrame.Angles(0, math.pi / 2, 0), 3, slot * 7 + 1, 1)
	TownVehicles.ParkingRow(st, R * CFrame.new(-ST_HALF + 0.05, ROAD_Y, -(s0 + length * 0.3)) * CFrame.Angles(0, -math.pi / 2, 0), 2, slot * 7 + 2, 0)
	if slot == geo.SideR then
		TownVehicles.DeliveryVan(st, R * CFrame.new(-(ST_HALF - TownVehicles.CURB_GAP - 3.3), ROAD_Y, -(s0 + length * 0.78)) * CFrame.Angles(0, math.pi, 0))
	end
	TownVehicles.TwoWheelers(st, R * CFrame.new(ST_HALF + 1.8, WALK_Y, -(s0 + 15)) * CFrame.Angles(0, math.pi / 2, 0), 3, slot)
end

-- Immeubles des deux côtés d'une rue (façades alignées sur le trottoir)
local function frontage(folder: Instance, geo: TownKit.Geo, slot: number, edge: number, maxPerSide: number)
	local model = TownKit.Model(folder, "Frontage_" .. slot)
	local R = radialFrame(geo, slot)
	local s1 = geo.Inner - 12
	local seed = slot * 37 + 3
	for _, sx in ipairs({ -1, 1 }) do
		local s = geo.StreetStart + 5
		for _ = 1, maxPerSide do
			seed += 1
			local w = 22 + math.floor(hash(seed, 1) * 4) * 2
			if s + w > s1 then
				break
			end
			local d = 16 + math.floor(hash(seed, 2) * 3) * 2
			local floors = hash(seed, 3) < 0.45 and 3 or 2
			local p = (R * CFrame.new(sx * edge, WALK_Y, -(s + w / 2))).Position
			local out = R.RightVector * sx
			TownBuildings.RowHouse(model, CFrame.lookAt(p, p - out), w, d, floors, seed)
			geo.Reserve(p + out * (d / 2), math.sqrt((w / 2) ^ 2 + (d / 2) ^ 2) + 1)
			s += w + 2.5
		end
	end
end

----------------------------------------------------------------------
-- (v9.8, CITY98) VIE DE LA RUE : emplacements du mobilier construit côté
-- CLIENT (TownStreetLife, en flux) et chemins des passants (TownPeople).
-- 0 pièce serveur : TownKit.LifeSpot / LifePath (voir TownKit).
-- Conventions : `cf` au sol (dessus du trottoir ou de la chaussée), avant
-- du mobilier = -Z local (le côté où l'on passe / lit / s'assoit).
----------------------------------------------------------------------

-- Mobilier du trottoir intérieur du boulevard (poids) ; zone "curb" = le
-- long de la bordure (petits objets), "back" = côté pelouse (tourné vers
-- la rue)
local BOULEVARD_MIX = {
	{ "Bin", 20, "curb" },
	{ "Bench", 15, "back" },
	{ "Planter", 11, "back" },
	{ "Recycle", 8, "back" },
	{ "Mailbox", 6, "curb" },
	{ "NewsBox", 6, "curb" },
	{ "Bollards", 5, "curb" },
	{ "PhoneBooth", 3, "back" },
	{ "Vending", 4, "back" },
	{ "SpeedSign", 4, "curb" },
	{ "DogStation", 3, "back" },
	{ "", 15, "" },
}
local MIX_TOTAL = 0
for _, row in ipairs(BOULEVARD_MIX) do
	MIX_TOTAL += row[2] :: number
end

local function pickMix(h: number): (string, string)
	local x = h * MIX_TOTAL
	for _, row in ipairs(BOULEVARD_MIX) do
		x -= row[2] :: number
		if x < 0 then
			return row[1] :: string, row[3] :: string
		end
	end
	return "", ""
end

-- Ligne de l'anneau des passants (trottoir intérieur, à 3,2 de la bordure)
local RING_IN = 3.2

local function lifeBoulevard(geo: TownKit.Geo)
	local m = geo.Slots
	local A = geo.Road
	local tanH = math.tan(geo.HalfAngle)
	local hw = ROAD_W / 2
	local spot = TownKit.LifeSpot
	local rowHalf = 1.5 * TownVehicles.BAY_LENGTH
	for k = 0, m - 1 do
		local F = geo.SideFrame(k, A)
		local junction = isStreet(geo, k)
		local jw = k == 0 and LANE_OUT or ST_HALF
		local half = A * tanH
		local innerHalf = (A - hw) * tanH
		local usable = innerHalf - 10
		local hx = half * 0.25
		-- même rangée de stationnement que buildBoulevard
		local rowX: number? = nil
		if k ~= 0 then
			local cx = (hash(k, 5) - 0.5) * half * 0.9
			if junction and math.abs(cx) < jw + 12 + rowHalf then
				cx = (if cx < 0 then -1 else 1) * (jw + 12 + rowHalf)
			end
			if math.abs(cx) + rowHalf < (A - hw) * tanH - 8 then
				rowX = cx
			end
		end
		-- passage piéton au milieu du côté (face à l'allée de la parcelle, ou
		-- décalé si une rangée de stationnement est là)
		local zebraX: number? = nil
		if not junction then
			-- (côtés impairs : pas à +30, la bouche d'incendie y est)
			for _, zx in ipairs(k % 2 == 1 and { 0, -30 } or { 0, -30, 30 }) do
				if rowX == nil or math.abs(zx - (rowX :: number)) > rowHalf + 10 then
					zebraX = zx
					break
				end
			end
		end
		local zebra = zebraX ~= nil
		local zx = zebraX or 0
		if zebraX then
			spot("Zebra", F * CFrame.new(zx, ROAD_Y, 0), ROAD_W * 10)
			spot("Beacon", F * CFrame.new(zx - 7.2, WALK_Y, -hw - 1.1), k)
			spot("Beacon", F * CFrame.new(zx + 7.2, WALK_Y, hw + 1.1) * CFrame.Angles(0, math.pi, 0), k + 1)
		end
		if rowX then
			spot("ParkMeter", F * CFrame.new(rowX - rowHalf - 1.4, WALK_Y, -hw - 1.1), k)
		end
		-- trottoir intérieur : un emplacement tous les 10,5 studs
		local j = 0
		local x = -usable
		while x <= usable do
			j += 1
			local free = true
			if junction and math.abs(x) < jw + 9 then
				free = false
			elseif k % 2 == 1 and math.abs(x - (hx + 1.5)) < 5 then
				free = false
			elseif zebra and math.abs(x - zx) < 9.5 then
				free = false
			elseif rowX and math.abs(x - (rowX - rowHalf - 1.4)) < 3 then
				free = false
			end
			if free then
				local kind, zone = pickMix(hash(k * 31 + j, 7))
				if kind ~= "" then
					if zone == "curb" then
						spot(kind, F * CFrame.new(x, WALK_Y, -hw - 1.2), k * 100 + j)
					else
						spot(kind, F * CFrame.new(x, WALK_Y, -hw - WALK_W + 1.3) * CFrame.Angles(0, math.pi, 0), k * 100 + j)
					end
				end
			end
			x += 10.5
		end
		-- plaques d'égout (milieu des voies) + avaloirs le long des bordures
		for i = 1, 2 do
			local mx = (hash(k, 40 + i) - 0.5) * half * 1.2
			if not (junction and math.abs(mx) < jw + 6) and not (zebra and math.abs(mx - zx) < 8) then
				spot("Manhole", F * CFrame.new(mx, ROAD_Y, 4.8), k * 10 + i)
			end
			local dx = (i == 1 and -1 or 1) * half * (0.35 + hash(k, 44 + i) * 0.3)
			spot("Drain", F * CFrame.new(dx, ROAD_Y, hw - 0.55) * CFrame.Angles(0, math.pi, 0), k * 10 + i)
		end
		-- trottoir extérieur (côté parcelles) : abribus / colonne d'affiches
		if not junction then
			if k % 3 == 2 then
				spot("BusShelter", F * CFrame.new(-half * 0.5 - 14, WALK_Y, hw + 3.4), k)
				spot("Bin", F * CFrame.new(-half * 0.5 - 22.5, WALK_Y, hw + 1.2) * CFrame.Angles(0, math.pi, 0), k)
			elseif k % 3 == 1 then
				spot("Morris", F * CFrame.new(half * 0.5 + 12, WALK_Y, hw + 3), k)
			end
			-- panneau publicitaire sur la pelouse, derrière les arbres (1 côté sur 2)
			if k % 2 == 0 then
				local bx = (hash(k, 77) - 0.5) * half * 0.8
				local bcf = F * CFrame.new(bx, WorldLayout.GROUND_Y, -hw - WALK_W - 12) * CFrame.Angles(0, math.pi, 0)
				spot("Billboard", bcf, k)
				geo.Reserve(bcf.Position, 9)
			end
		end
	end
	-- chemin des passants : l'anneau du trottoir intérieur (polygone)
	local ring = {}
	local r = (A - hw - RING_IN) / math.cos(geo.HalfAngle)
	for k = 0, m - 1 do
		local a = geo.SlotAngle(k) + geo.HalfAngle
		table.insert(ring, geo.Origin + Vector3.new(math.sin(a) * r, WALK_Y, math.cos(a) * r))
	end
	TownKit.LifePath("Ring", ring, true)
end

-- Repère d'un objet posé côté `sx` d'une rue radiale, face à la chaussée
-- (avant -Z vers l'axe de la rue)
local function faceAxis(R: CFrame, x: number, y: number, s: number): CFrame
	local sx = if x < 0 then -1 else 1
	return R * CFrame.new(x, y, -s) * CFrame.Angles(0, sx * math.pi / 2, 0)
end

local function lifeAvenue(geo: TownKit.Geo)
	local spot = TownKit.LifeSpot
	local R = radialFrame(geo, 0)
	local s0 = geo.StreetStart
	local roadEdge = geo.Road - ROAD_W / 2
	local ringS = geo.Road - ROAD_W / 2 - RING_IN -- (l'anneau traverse l'avenue ici)
	-- pistes cyclables peintes (bord extérieur des voies) + pictogrammes
	local b0, b1 = s0 + 3, ringS - 3.5
	for _, sx in ipairs({ -1, 1 }) do
		spot("BikeLane", R * CFrame.new(sx * (LANE_OUT - 1.3), ROAD_Y, -(b0 + b1) / 2), math.floor(b1 - b0))
		-- passages piétons de l'anneau sur chaque voie
		spot("Zebra", R * CFrame.new(sx * (PROM + LANE_OUT) / 2, ROAD_Y, -ringS) * CFrame.Angles(0, math.pi / 2, 0), math.floor((LANE_OUT - PROM) * 10))
		-- feux tricolores (sur la promenade, avant la ligne d'arrêt)
		spot("TrafficLight", R * CFrame.new(sx * (PROM - 0.8), WALK_Y, -(roadEdge - 1.1)) * CFrame.Angles(0, math.pi, 0), sx > 0 and 1 or 2)
	end
	-- zone piétonne (entre la place et le début des voies) : kiosque à
	-- journaux, distributeurs, terrasse de café, cabine, gens qui discutent
	local plazaR = WorldLayout.PLAZA_R
	local pz = (plazaR + s0) / 2
	spot("Kiosk", faceAxis(R, -(AVE_OUT - 4.5), WALK_Y, pz), 1)
	spot("Vending", faceAxis(R, -(AVE_OUT - 1.5), WALK_Y, pz + 8), 3)
	spot("Terrace", faceAxis(R, AVE_OUT - 5, WALK_Y, pz - 1), 1)
	spot("PhoneBooth", faceAxis(R, AVE_OUT - 1.5, WALK_Y, pz + 9), 2)
	spot("Bin", R * CFrame.new(-(AVE_OUT - 9), WALK_Y, -(pz - 8)), 4)
	spot("Bin", R * CFrame.new(AVE_OUT - 9, WALK_Y, -(pz + 9)), 5)
	spot("Chat", R * CFrame.new(-8, WALK_Y, -(pz - 5)) * CFrame.Angles(0, 0.6, 0), 5)
	spot("Chat", R * CFrame.new(8.5, WALK_Y, -(pz + 7)) * CFrame.Angles(0, -2.2, 0), 6)
	-- trottoirs de l'avenue : petit mobilier près de la bordure (les
	-- passants marchent entre lui et les façades)
	for _, sx in ipairs({ -1, 1 }) do
		local n = 0
		local s = s0 + 9
		while s < ringS - 8 do
			n += 1
			local kinds = { "Bin", "Bollards", "Mailbox", "NewsBox", "Bin", "Planter" }
			local kind = kinds[(n + (sx > 0 and 2 or 0)) % #kinds + 1]
			if kind == "Planter" then
				spot("PlanterSmall", R * CFrame.new(sx * (LANE_OUT + 1.35), WALK_Y, -s), n)
			else
				spot(kind, faceAxis(R, sx * (LANE_OUT + 1.25), WALK_Y, s) * CFrame.Angles(0, math.pi, 0), n)
			end
			s += 19
		end
	end
	-- oriflammes sur les lampadaires de la promenade (mêmes positions que buildAvenue)
	local length = roadEdge - 6 - (s0 + 6)
	local nL = math.clamp(math.floor(length / 14), 2, 8)
	for i = 0, nL - 1 do
		local sm = s0 + 6 + i * length / nL + length / nL / 2
		for _, sx in ipairs({ -1, 1 }) do
			if (i + (sx > 0 and 1 or 0)) % 2 == 0 then
				spot("Banner", R * CFrame.new(sx * (PROM - 1.6), WALK_Y, -sm) * CFrame.Angles(0, sx * math.pi / 2, 0), i)
			end
		end
	end
	-- panneaux des noms de rue au croisement avec le boulevard
	spot("StreetName", R * CFrame.new(LANE_OUT + 4.4, WALK_Y, -(geo.Inner - 1.6)), 1)
	-- (v9.9, CITY99) poteau indicateur au carrefour (vers tous les lieux)
	spot("Direction", R * CFrame.new(-(LANE_OUT + 3.2), WALK_Y, -(geo.Inner - 5)), 330)
	-- chemins : la promenade (de la porte à la place) et la boucle des trottoirs
	local function at(x: number, s: number): Vector3
		return (R * CFrame.new(x, WALK_Y, -s)).Position
	end
	local gateS = geo.Gate - 18 -- (distance depuis le centre, sur l'axe)
	TownKit.LifePath("Promenade", { at(-2.8, gateS), at(-2.8, s0 + 2), at(2.8, s0 + 2), at(2.8, gateS) }, true)
	local walk = AVE_OUT - 3.1
	TownKit.LifePath("AvenueLoop", { at(walk, ringS - 3), at(walk, s0 - 4), at(-walk, s0 - 4), at(-walk, ringS - 3), at(-walk, ringS), at(walk, ringS) }, true)
end

local function lifeSideStreet(geo: TownKit.Geo, slot: number, name: number)
	local spot = TownKit.LifeSpot
	local R = radialFrame(geo, slot)
	local s0 = geo.StreetStart
	local ringS = geo.Road - ROAD_W / 2 - RING_IN
	local zs = geo.Inner - 6
	local length = geo.Inner - 8 - (s0 + 6)
	-- feux tricolores au passage piéton (un par sens) + passage de l'anneau
	spot("TrafficLight", R * CFrame.new(ST_HALF + 1.1, WALK_Y, -(zs - 3.9)) * CFrame.Angles(0, math.pi, 0), 3)
	spot("TrafficLight", R * CFrame.new(-ST_HALF - 1.1, WALK_Y, -(zs + 3.9)), 4)
	spot("Zebra", R * CFrame.new(0, ROAD_Y, -ringS) * CFrame.Angles(0, math.pi / 2, 0), math.floor(2 * ST_HALF * 10))
	spot("StreetName", R * CFrame.new(-(ST_OUT - 0.9), WALK_Y, -(geo.Inner - 1.6)), name)
	spot("Direction", R * CFrame.new(ST_OUT - 1.6, WALK_Y, -(geo.Inner - 5)), 330 + slot) -- (v9.9, CITY99)
	-- mobilier entre les arbres (côté immeubles) : poubelles, bornes, boîte aux lettres
	local n = math.clamp(math.floor(length / 20), 1, 7)
	for i = 0, n - 1 do
		local si = s0 + 6 + (i + 0.5) * length / n
		for _, sx in ipairs({ -1, 1 }) do
			local kinds = { "Bin", "Mailbox", "Bollards", "NewsBox", "Planter" }
			local kind = kinds[(i * 2 + (sx > 0 and 1 or 0) + slot) % #kinds + 1]
			if not (sx > 0 and math.abs(si - (s0 + 15)) < 6) then
				if kind == "Planter" then
					spot("PlanterSmall", R * CFrame.new(sx * (ST_OUT - 0.9), WALK_Y, -si), i)
				else
					spot(kind, faceAxis(R, sx * (ST_OUT - 0.8), WALK_Y, si), slot * 10 + i)
				end
			end
		end
	end
	-- horodateurs au bout des rangées de stationnement (mêmes rangées que buildSideStreet)
	spot("ParkMeter", faceAxis(R, ST_HALF + 1.1, WALK_Y, s0 + length * 0.55 - 1.5 * TownVehicles.BAY_LENGTH - 1.5), slot)
	spot("ParkMeter", faceAxis(R, -ST_HALF - 1.1, WALK_Y, s0 + length * 0.3 + TownVehicles.BAY_LENGTH + 1.5), slot + 1)
	-- plaques d'égout
	for i = 1, 3 do
		spot("Manhole", R * CFrame.new(0, ROAD_Y, -(s0 + 10 + i * length / 3.4)), slot * 10 + i)
	end
	-- étal (fleuriste / bouquiniste) dans la zone piétonne
	local pz = (WorldLayout.PLAZA_R + s0) / 2
	spot(name == 2 and "FlowerStall" or "BookStall", faceAxis(R, -(ST_OUT - 2.4), WALK_Y, pz + 3), slot)
	spot("Chat", R * CFrame.new(4, WALK_Y, -(pz - 4)) * CFrame.Angles(0, 1.2 + slot, 0), slot + 20)
	-- chemin des passants : boucle des deux trottoirs (détour autour des 2-roues)
	local function at(x: number, s: number): Vector3
		return (R * CFrame.new(x, WALK_Y, -s)).Position
	end
	local w = ST_HALF + 1.6
	TownKit.LifePath("Side" .. name, {
		at(w, s0 - 3),
		at(w, s0 + 9),
		at(ST_OUT - 1, s0 + 12),
		at(ST_OUT - 1, s0 + 18),
		at(w, s0 + 21),
		at(w, ringS),
		at(-w, ringS),
		at(-w, s0 - 3),
	}, true)
end

----------------------------------------------------------------------
-- (v9.9, CITY99) ROUTES "100x" : emplacements pour le client (TownRoads,
-- via TownStreetLife ; 0 pièce serveur), par tronçons de 40 studs au plus :
--   RoadSurface (ornières, rustines, fissures), CurbLine (caniveau + nez
--   de bordure arrondi), Pavers (dalles des trottoirs), Arrow / RoadWord /
--   GiveWay (marquages aux carrefours), Direction (poteaux indicateurs).
----------------------------------------------------------------------

local CHUNK = 40

-- Intervalles [x0, x1] privés des trous `gaps`
local function cut(x0: number, x1: number, gaps: { { number } }?): { { number } }
	local ranges = { { x0, x1 } }
	for _, gap in ipairs(gaps or {}) do
		local nextRanges = {}
		for _, r in ipairs(ranges) do
			if gap[2] <= r[1] or gap[1] >= r[2] then
				table.insert(nextRanges, r)
			else
				if gap[1] > r[1] then
					table.insert(nextRanges, { r[1], gap[1] })
				end
				if gap[2] < r[2] then
					table.insert(nextRanges, { gap[2], r[2] })
				end
			end
		end
		ranges = nextRanges
	end
	return ranges
end

-- Bande le long de x (repère `F`), découpée en tronçons : un emplacement
-- `kind` par tronçon, au point (xc, y, z), taille (longueur, sy, sz) ;
-- `turn` : repère retourné (180°) pour les bordures côté intérieur
local function chunks(kind: string, F: CFrame, x0: number, x1: number, y: number, z: number, sy: number, sz: number, seed: number, gaps: { { number } }?, turn: boolean?)
	for _, r in ipairs(cut(x0, x1, gaps)) do
		local len = r[2] - r[1]
		if len > 1 then
			local n = math.max(1, math.ceil(len / CHUNK))
			for i = 0, n - 1 do
				local a = r[1] + i * len / n
				local cf = F * CFrame.new(a + len / n / 2, y, z)
				if turn then
					cf = cf * CFrame.Angles(0, math.pi, 0)
				end
				TownKit.LifeSpot(kind, cf, seed + i * 7, Vector3.new(len / n, sy, sz))
			end
		end
	end
end

local CURB_H = WALK_Y + 0.03 - ROAD_Y -- (hauteur de la bordure au-dessus de l'asphalte)

local function roadsBoulevard(geo: TownKit.Geo)
	local m = geo.Slots
	local A = geo.Road
	local tanH = math.tan(geo.HalfAngle)
	local hw = ROAD_W / 2
	for k = 0, m - 1 do
		local F = geo.SideFrame(k, A)
		local junction = isStreet(geo, k)
		local jw = k == 0 and LANE_OUT or ST_HALF
		local gaps = junction and { { -jw - 0.9, jw + 0.9 } } or nil
		local innerHalf = (A - hw) * tanH
		-- asphalte (sans les coins en onglet)
		chunks("RoadSurface", F, -innerHalf + 2, innerHalf - 2, ROAD_Y, 0, 2, ROAD_W, k * 1000 + 1)
		-- bordures : intérieure (chaussée vers +z : repère retourné) et extérieure
		chunks("CurbLine", F, -innerHalf, innerHalf, ROAD_Y, -hw + 0.05, CURB_H, 0, k * 1000 + 2, gaps, true)
		chunks("CurbLine", F, -(A + hw) * tanH, (A + hw) * tanH, ROAD_Y, hw - 0.05, CURB_H, 0, k * 1000 + 3)
		-- dalles des trottoirs (sans la bordure)
		local wIn = WALK_W - 0.85
		chunks("Pavers", F, -(A - hw - WALK_W / 2) * tanH + 1, (A - hw - WALK_W / 2) * tanH - 1, WALK_Y, -hw - 0.85 - wIn / 2, 0, wIn, k * 1000 + 4, gaps)
		chunks("Pavers", F, -(A + hw + WALK_W / 2) * tanH + 1, (A + hw + WALK_W / 2) * tanH - 1, WALK_Y, hw + 0.85 + wIn / 2, 0, wIn, k * 1000 + 5)
	end
end

local function roadsAvenue(geo: TownKit.Geo)
	local R = radialFrame(geo, 0)
	local s0 = geo.StreetStart
	local roadEdge = geo.Road - ROAD_W / 2
	-- repère "le long de l'avenue" : X = vers l'extérieur, Z = R.X
	local function along(x: number, s: number, y: number): CFrame
		return R * CFrame.new(x, y, -s) * CFrame.Angles(0, math.pi / 2, 0)
	end
	local L = roadEdge - s0
	local F0 = along(0, s0 + L / 2, 0)
	for _, sx in ipairs({ -1, 1 }) do
		local laneC = sx * (PROM + LANE_OUT) / 2
		chunks("RoadSurface", along(laneC, s0, 0), 1, L - 1, ROAD_Y, 0, 1, LANE_OUT - PROM, sx * 11 + 5000)
		-- bordures : promenade (chaussée vers +sx) et trottoir (chaussée vers -sx)
		-- (repère "along" : Z = R.X ; la bordure regarde la chaussée par son -Z
		-- local : on retourne le repère quand la chaussée est du côté +R.X)
		chunks("CurbLine", along(sx * (PROM + 0.05), s0, 0), 0.5, L, ROAD_Y, 0, CURB_H, 0, 5100 + sx, nil, sx > 0)
		chunks("CurbLine", along(sx * (LANE_OUT - 0.05), s0, 0), 0.5, geo.Inner - s0, ROAD_Y, 0, CURB_H, 0, 5200 + sx, nil, sx < 0)
		-- (0,3 de marge côté façades : les socles des immeubles avancent un peu)
		local wS = WALK_W - 0.85 - 0.3
		chunks("Pavers", along(sx * (LANE_OUT + 0.85 + wS / 2), s0, 0), 0.5, geo.Inner - s0 - 0.5, WALK_Y, 0, 0, wS, 5300 + sx)
	end
	local _ = F0
	-- flèches : voie montante (+x, vers la porte) : gauche / droite avant la
	-- ligne d'arrêt ; voie descendante (-x, vers la place) : tout droit
	TownKit.LifeSpot("Arrow", R * CFrame.new((PROM + LANE_OUT) / 2 - 1, ROAD_Y, -(roadEdge - 10)), 6)
	TownKit.LifeSpot("Arrow", R * CFrame.new(-(PROM + LANE_OUT) / 2 + 1, ROAD_Y, -(roadEdge - 42)) * CFrame.Angles(0, math.pi, 0), 1)
	TownKit.LifeSpot("RoadWord", R * CFrame.new(-(PROM + LANE_OUT) / 2 + 1, ROAD_Y, -(s0 + 14)) * CFrame.Angles(0, math.pi, 0), 3)
end

local function roadsSideStreet(geo: TownKit.Geo, slot: number)
	local R = radialFrame(geo, slot)
	local s0 = geo.StreetStart
	local roadEdge = geo.Road - ROAD_W / 2
	local function along(x: number, s: number): CFrame
		return R * CFrame.new(x, 0, -s) * CFrame.Angles(0, math.pi / 2, 0)
	end
	local L = roadEdge - s0
	chunks("RoadSurface", along(0, s0), 1, L - 1, ROAD_Y, 0, 2, 2 * ST_HALF, slot * 1000 + 6000)
	for _, sx in ipairs({ -1, 1 }) do
		chunks("CurbLine", along(sx * (ST_HALF - 0.05), s0), 0.5, geo.Inner - s0, ROAD_Y, 0, CURB_H, 0, slot * 1000 + 6100 + sx, nil, sx < 0)
		local wS = ST_WALK - 0.85 - 0.3
		chunks("Pavers", along(sx * (ST_HALF + 0.85 + wS / 2), s0), 0.5, geo.Inner - s0 - 0.5, WALK_Y, 0, 0, wS, slot * 1000 + 6200 + sx)
	end
	-- carrefour avec le boulevard : STOP + flèches gauche / droite (voie
	-- sortante, +x), ZONE 30 à l'entrée de la zone piétonne (voie entrante)
	local zs = geo.Inner - 6
	TownKit.LifeSpot("RoadWord", R * CFrame.new(ST_HALF / 2, ROAD_Y, -(zs - 7)), 1)
	TownKit.LifeSpot("Arrow", R * CFrame.new(ST_HALF / 2, ROAD_Y, -(zs - 14)), 6)
	TownKit.LifeSpot("RoadWord", R * CFrame.new(-ST_HALF / 2, ROAD_Y, -(s0 + 12)) * CFrame.Angles(0, math.pi, 0), 3)
	TownKit.LifeSpot("Arrow", R * CFrame.new(-ST_HALF / 2, ROAD_Y, -(s0 + 22)) * CFrame.Angles(0, math.pi, 0), 1)
end

-- (v9.9, CITY99) pour TownEntrance / TownNature : même découpage en tronçons
TownStreets.Chunks = chunks

function TownStreets.Build(folder: Instance, geo: TownKit.Geo)
	local streets = Instance.new("Folder")
	streets.Name = "Streets"
	streets.Parent = folder
	buildBoulevard(streets, geo)
	buildAvenue(streets, geo)
	buildSideStreet(streets, geo, geo.SideR)
	buildSideStreet(streets, geo, geo.SideL)
	frontage(streets, geo, 0, AVE_OUT + 0.2, 4)
	frontage(streets, geo, geo.SideR, ST_OUT + 0.2, 3)
	frontage(streets, geo, geo.SideL, ST_OUT + 0.2, 3)
	-- (v9.8, CITY98) mobilier de rue + passants : emplacements pour le client
	lifeBoulevard(geo)
	lifeAvenue(geo)
	lifeSideStreet(geo, geo.SideR, 2)
	lifeSideStreet(geo, geo.SideL, 3)
	-- (v9.9, CITY99) routes réalistes (client)
	roadsBoulevard(geo)
	roadsAvenue(geo)
	roadsSideStreet(geo, geo.SideR)
	roadsSideStreet(geo, geo.SideL)
end

return TownStreets
