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
			part(parent, name, Vector3.new(len + 2 * g, thick, math.abs(z1 - z0)), cf * CFrame.new((r[1] + r[2]) / 2, top - thick / 2, (z0 + z1) / 2), color, material, profile)
		end
	end
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
		strip(side, "EdgeLine", F, -(A + edgeZ) * tanH, (A + edgeZ) * tanH, edgeZ - 0.18, edgeZ + 0.18, ROAD_Y + 0.05, 0.1, C.Line, M.SmoothPlastic, "deco")
		strip(side, "EdgeLine", F, -(A - edgeZ) * tanH, (A - edgeZ) * tanH, -edgeZ - 0.18, -edgeZ + 0.18, ROAD_Y + 0.05, 0.1, C.Line, M.SmoothPlastic, "deco", innerGaps)
		-- ligne médiane en pointillés (arrêtée avant les coins et les croisements)
		local limit = A * tanH - 10
		local x = -limit
		while x + 5 <= limit do
			local cx = x + 2.5
			if not (junction and math.abs(cx) < jw + 5) then
				part(side, "Dash", Vector3.new(6, 0.1, 0.4), F * CFrame.new(cx, ROAD_Y + 0.05, 0), C.Line, M.SmoothPlastic, "deco")
			end
			x += 18
		end
		if junction then
			if k == 0 then
				-- passage piéton : de la place d'accueil à la promenade de l'avenue
				for i = 0, 7 do
					local z = -hw + 1.6 + i * (ROAD_W - 3.2) / 7
					part(side, "Zebra", Vector3.new(12, 0.1, 1.1), F * CFrame.new(0, ROAD_Y + 0.05, z), C.Line, M.SmoothPlastic, "deco")
				end
			else
				-- flèches de tourne-à-gauche / droite : simple ligne "cédez" pointillée
				for i = -3, 3 do
					part(side, "Yield", Vector3.new(1.6, 0.1, 0.4), F * CFrame.new(i * 2.4, ROAD_Y + 0.05, -hw + 3), C.Line, M.SmoothPlastic, "deco")
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
	part(parent, name, Vector3.new(math.abs(x1 - x0), thick, math.abs(s1 - s0)), R * CFrame.new((x0 + x1) / 2, top - thick / 2, -(s0 + s1) / 2), color, material, profile)
end

local function buildAvenue(folder: Instance, geo: TownKit.Geo)
	local ave = TownKit.Model(folder, "Avenue")
	local R = radialFrame(geo, 0)
	local plazaR = WorldLayout.PLAZA_R
	local s0 = geo.StreetStart
	local roadEdge = geo.Road - ROAD_W / 2
	-- zone piétonne entre la place et le début des voies
	radialBox(ave, "PedestrianZone", R, plazaR - 2, s0, -AVE_OUT, AVE_OUT, WALK_Y, 1.3, C.Paving, M.Cobblestone, "solid")
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
		radialBox(ave, "StopLine", R, roadEdge - 2.4, roadEdge - 1.8, sx * (PROM + 0.4), sx * (LANE_OUT - 0.4), ROAD_Y + 0.05, 0.1, C.Line, M.SmoothPlastic, "deco")
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
					TownKit.Bench(ave, R * CFrame.new(sx * (PROM - 1.8), WALK_Y, -sm) * CFrame.Angles(0, math.rad(sx * 90), 0))
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
	radialBox(st, "PedestrianZone", R, plazaR - 2, s0, -ST_OUT, ST_OUT, WALK_Y, 1.3, C.Paving, M.Cobblestone, "solid")
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
		radialBox(st, "Dash", R, s, s + 5, -0.2, 0.2, ROAD_Y + 0.05, 0.1, C.Line, M.SmoothPlastic, "deco")
		s += 18
	end
	local zs = geo.Inner - 6
	for i = 0, 5 do
		local x = -ST_HALF + 1.4 + i * (2 * ST_HALF - 2.8) / 5
		radialBox(st, "Zebra", R, zs - 2.5, zs + 2.5, x - 0.55, x + 0.55, ROAD_Y + 0.05, 0.1, C.Line, M.SmoothPlastic, "deco")
	end
	radialBox(st, "StopLine", R, zs - 4.2, zs - 3.6, 0.2, ST_HALF - 0.4, ROAD_Y + 0.05, 0.1, C.Line, M.SmoothPlastic, "deco")
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
end

return TownStreets
