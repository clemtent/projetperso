--[[
	TownFountainFx (ModuleScript)
	Emplacement : ReplicatedStorage > Client > World > TownFountainFx

	⛲ La fontaine de la place, "en mieux" (v9.8, CITY98), côté CLIENT
	(appelé par TownPlazaFx, près de la place seulement). Le serveur
	(TownPlaza) garde la fontaine elle-même (bassin, vasques, cerveau,
	particules) et publie son repère (attribut "FxFountainBase" du dossier
	Plaza). Ici :
	  - EAU VIVANTE : voile scintillant sur le bassin et les vasques
	    (transparence qui respire), ronds dans l'eau qui s'élargissent là où
	    tombent les jets ;
	  - 8 JETS EN ARC (gouttes qui filent le long d'une parabole, de la
	    bouche des poissons de bronze jusqu'au bassin) + le jet du cerveau
	    (gerbe qui monte et retombe dans la vasque haute) ;
	  - RIDEAUX D'EAU qui tombent des deux vasques (filets qui descendent) ;
	  - DÉTAILS SCULPTÉS : 12 médaillons au cerveau sur la margelle,
	    cannelures du pied, feuilles d'acanthe, têtes de poisson en bronze
	    aux buses ;
	  - des PIÈCES au fond du bassin (vœux !).
	~240 pièces, ancrées, sans collision ; animation par CFrame / propriétés
	(30 Hz au plus, rien de créé par image). Aucune lumière, aucun son.

	API (TownPlazaFx) :
	  TownFountainFx.Build(folder, base: Vector3) -> état
	  TownFountainFx.Step(état, t: number)
]]

local TownFountainFx = {}

local M = Enum.Material
local rgb = Color3.fromRGB
local UPRIGHT = CFrame.Angles(0, 0, math.rad(90))

-- Hauteurs de la fontaine serveur (au-dessus du parvis `base`, voir TownPlaza)
local BASIN_R = 13.6
local WATER_Y = 2.5
local FLOOR_Y = 0.8
local BOWL_R, BOWL_Y, BOWL_WATER_Y = 6.2, 7.0, 7.1
local UPPER_R, UPPER_WATER_Y = 3.3, 11.0
local JET_R, JET_Y = 12.3, 2.62
local NOZZLE_Y = 12.05 + 2.625 + 2.1

local WATER = rgb(170, 222, 250)
local FOAM = rgb(236, 248, 255)
local BRONZE = rgb(196, 150, 92)
local MARBLE = rgb(250, 244, 240)
local ROSE = rgb(232, 178, 188)

local JETS = 8
local DROPS = 11
local CURTAIN_LOW, CURTAIN_HIGH = 22, 12

local function newPart(parent: Instance, name: string, size: Vector3, cf: CFrame, color: Color3, material: Enum.Material?, shape: string?): BasePart
	local p = Instance.new("Part")
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
	return p
end

-- disque horizontal : dessus à `top`
local function disc(parent: Instance, name: string, center: Vector3, top: number, radius: number, t: number, color: Color3, material: Enum.Material?): BasePart
	return newPart(parent, name, Vector3.new(t, radius * 2, radius * 2), CFrame.new(center.X, top - t / 2, center.Z) * UPRIGHT, color, material, "Cyl")
end

local function hash(a: number, b: number): number
	local x = math.sin(a * 12.9898 + b * 78.233) * 43758.5453
	return x - math.floor(x)
end

-- point d'une parabole de `a` à `b` (sommet à +h au-dessus du segment)
local function arc(a: Vector3, b: Vector3, h: number, u: number): Vector3
	return a:Lerp(b, u) + Vector3.new(0, 4 * h * u * (1 - u), 0)
end

function TownFountainFx.Build(folder: Instance, base: Vector3): any
	local model = Instance.new("Model")
	model.Name = "FountainFx"
	model.Parent = folder
	local F = { Base = base, Model = model, Movers = {}, MoverFrames = {}, Jets = {}, Ripples = {}, Veils = {}, Curtains = {} }
	local function y(h: number): Vector3
		return base + Vector3.new(0, h, 0)
	end
	-- voiles scintillants (au-dessus de l'eau du serveur et de ses ronds)
	local veil = disc(model, "WaterVeil", base, base.Y + WATER_Y + 0.11, BASIN_R - 0.75, 0.04, FOAM, M.Glass)
	veil.Transparency = 0.78
	local veil2 = disc(model, "BowlVeil", base, base.Y + BOWL_WATER_Y + 0.07, BOWL_R - 0.6, 0.03, FOAM, M.Glass)
	veil2.Transparency = 0.78
	local veil3 = disc(model, "UpperVeil", base, base.Y + UPPER_WATER_Y + 0.07, UPPER_R - 0.5, 0.03, FOAM, M.Glass)
	veil3.Transparency = 0.78
	F.Veils = { veil, veil2, veil3 }
	-- pièces au fond du bassin (vœux)
	local coins = { rgb(236, 196, 90), rgb(214, 140, 80), rgb(200, 204, 212) }
	for i = 1, 36 do
		local a = hash(i, 1) * math.pi * 2
		local r = 3.2 + math.sqrt(hash(i, 2)) * 9.2
		local p = base + Vector3.new(math.sin(a) * r, 0, math.cos(a) * r)
		-- (hauteur par couleur : deux pièces qui se chevauchent ne scintillent jamais)
		local lift = (i % 3) * 0.025
		disc(model, "Coin", p, base.Y + FLOOR_Y + 0.03 + lift, 0.16 + hash(i, 3) * 0.05, 0.06 + lift, coins[i % 3 + 1], M.Metal)
	end
	-- médaillons sur la margelle (face extérieure des 12 pans) + petit cerveau en relief
	for i = 0, 11 do
		local a = (i + 0.5) / 12 * math.pi * 2
		local d = Vector3.new(math.sin(a), 0, math.cos(a))
		local p = y(1.65) + d * (BASIN_R + 0.7)
		newPart(model, "Medallion", Vector3.new(0.16, 1.3, 1.3), CFrame.lookAt(p, p + d) * CFrame.Angles(0, math.rad(90), 0), ROSE, M.Marble, "Cyl")
		for _, sx in ipairs({ -1, 1 }) do
			local side = Vector3.new(0, 1, 0):Cross(d).Unit
			newPart(model, "MedallionBrain", Vector3.new(0.34, 0.34, 0.34), CFrame.new(p + d * 0.1 + side * sx * 0.16 + Vector3.new(0, 0.05, 0)), rgb(255, 152, 198), M.SmoothPlastic, "Ball")
		end
	end
	-- cannelures du pied + feuilles d'acanthe sous l'anneau rose
	for i = 0, 11 do
		local a = i / 12 * math.pi * 2
		local d = Vector3.new(math.sin(a), 0, math.cos(a))
		local p = y(3.65) + d * 1.72
		newPart(model, "Flute", Vector3.new(0.22, 3.7, 0.22), CFrame.lookAt(p, p + d), MARBLE:Lerp(ROSE, 0.15), M.Marble)
	end
	for i = 0, 7 do
		local a = (i + 0.5) / 8 * math.pi * 2
		local d = Vector3.new(math.sin(a), 0, math.cos(a))
		local p = y(5.35) + d * 2.05
		newPart(model, "Acanthus", Vector3.new(0.9, 1.3, 0.3), CFrame.lookAt(p, p + d) * CFrame.Angles(math.rad(-18), 0, 0), rgb(236, 226, 214), M.Marble, "Egg")
	end
	-- têtes de poisson en bronze aux 8 buses + jets en arc (gouttes)
	for j = 0, JETS - 1 do
		local a = j / JETS * math.pi * 2
		local d = Vector3.new(math.sin(a), 0, math.cos(a))
		local mouth = y(JET_Y + 0.2) + d * (JET_R - 0.35)
		local head = CFrame.lookAt(mouth + d * 0.45, mouth)
		newPart(model, "FishHead", Vector3.new(0.75, 0.62, 1.0), head * CFrame.Angles(math.rad(-20), 0, 0), BRONZE, M.Metal, "Egg")
		for _, sx in ipairs({ -1, 1 }) do
			newPart(model, "FishEye", Vector3.new(0.14, 0.14, 0.14), head * CFrame.new(sx * 0.3, 0.14, -0.15), rgb(60, 44, 30), M.Metal, "Ball")
		end
		newPart(model, "FishFin", Vector3.new(0.08, 0.5, 0.5), head * CFrame.new(0, 0.36, 0.2) * CFrame.Angles(math.rad(45), 0, 0), BRONZE, M.Metal)
		local landing = y(WATER_Y + 0.05) + d * (JET_R - 5.2)
		local jet = { From = mouth - d * 0.25, To = landing, H = 2.4, Parts = {}, Phase = j * 0.13 }
		for _ = 1, DROPS do
			local drop = newPart(model, "JetDrop", Vector3.new(0.34, 0.34, 0.34), CFrame.new(mouth), WATER, M.Glass, "Ball")
			drop.Transparency = 0.3
			table.insert(jet.Parts, drop)
			table.insert(F.Movers, drop)
			table.insert(F.MoverFrames, drop.CFrame)
		end
		table.insert(F.Jets, jet)
		-- 2 ronds par point de chute (déphasés)
		for k = 0, 1 do
			-- (2e rond 0,03 plus haut : jamais deux faces confondues)
			local top = base.Y + WATER_Y + 0.17 + k * 0.03
			local ring = disc(model, "Ripple", landing, top, 0.4, 0.03, FOAM, M.Glass)
			ring.Transparency = 0.5
			table.insert(F.Ripples, { Part = ring, Center = landing, Top = top, Phase = j * 0.37 + k * 0.6 })
		end
	end
	-- gerbe du cerveau : monte puis retombe dans la vasque haute
	local top = { Parts = {}, From = y(NOZZLE_Y), Phase = 0 }
	for _ = 1, 12 do
		local drop = newPart(model, "TopDrop", Vector3.new(0.3, 0.3, 0.3), CFrame.new(top.From), WATER, M.Glass, "Ball")
		drop.Transparency = 0.35
		table.insert(top.Parts, drop)
		table.insert(F.Movers, drop)
		table.insert(F.MoverFrames, drop.CFrame)
	end
	F.Top = top
	-- rideaux d'eau : filets qui tombent du bord des vasques
	local function curtain(n: number, r: number, y0: number, y1: number, name: string)
		for k = 0, n - 1 do
			local a = (k + 0.5) / n * math.pi * 2
			local d = Vector3.new(math.sin(a), 0, math.cos(a))
			local streak = newPart(model, name, Vector3.new(0.16, 1.5, 0.16), CFrame.new(base + d * r + Vector3.new(0, y0, 0)), WATER, M.Glass)
			streak.Transparency = 0.45
			table.insert(F.Curtains, { Part = streak, Dir = d, R = r, Y0 = y0, Y1 = y1, Phase = hash(k, n) })
			table.insert(F.Movers, streak)
			table.insert(F.MoverFrames, streak.CFrame)
		end
	end
	curtain(CURTAIN_LOW, BOWL_R + 0.25, BOWL_Y - 0.1, WATER_Y + 0.4, "CurtainLow")
	curtain(CURTAIN_HIGH, UPPER_R + 0.2, UPPER_WATER_Y - 0.2, BOWL_WATER_Y + 0.3, "CurtainHigh")
	return F
end

function TownFountainFx.Step(F: any, t: number)
	if not F then
		return
	end
	local frames = F.MoverFrames
	local i = 0
	-- jets en arc : gouttes qui glissent le long de la parabole
	for _, jet in ipairs(F.Jets) do
		for k, _ in ipairs(jet.Parts) do
			i += 1
			local u = ((k - 1) / DROPS + t * 0.85 + jet.Phase) % 1
			frames[i] = CFrame.new(arc(jet.From, jet.To, jet.H, u))
		end
	end
	-- gerbe du cerveau : montée (vitesse qui baisse) puis chute dans la vasque
	local top = F.Top
	for k, _ in ipairs(top.Parts) do
		i += 1
		local u = ((k - 1) / #top.Parts + t * 0.7) % 1
		local ang = k * 2.39996
		local spread = 3.0 * math.sqrt(u)
		local h = 3.0 * math.sin(u * math.pi) - u * u * (NOZZLE_Y - UPPER_WATER_Y)
		frames[i] = CFrame.new(top.From + Vector3.new(math.cos(ang) * spread, h, math.sin(ang) * spread))
	end
	-- rideaux : chaque filet descend et recommence
	for _, c in ipairs(F.Curtains) do
		i += 1
		local u = (t * 0.9 + c.Phase) % 1
		local yy = c.Y0 + (c.Y1 - c.Y0) * (u * u * 0.6 + u * 0.4)
		frames[i] = CFrame.new(F.Base + c.Dir * (c.R + u * 0.25) + Vector3.new(0, yy, 0))
	end
	workspace:BulkMoveTo(F.Movers, frames, Enum.BulkMoveMode.FireCFrameChanged)
	-- ronds dans l'eau : s'élargissent et s'effacent
	for _, r in ipairs(F.Ripples) do
		local u = (t * 0.8 + r.Phase) % 1
		local size = 0.6 + u * 3.4
		r.Part.Size = Vector3.new(0.03, size, size)
		r.Part.Transparency = 0.45 + u * 0.55
	end
	-- voiles : la lumière "respire" sur l'eau
	for k, v in ipairs(F.Veils) do
		v.Transparency = 0.74 + math.sin(t * 1.3 + k) * 0.06
	end
end

return TownFountainFx
