--[[
	TownFountainFx (ModuleScript)
	Emplacement : ReplicatedStorage > Client > World > TownFountainFx

	⛲ La fontaine de la place, côté CLIENT (appelé par TownPlazaFx, près de
	la place seulement). Le serveur (TownPlaza) garde la pierre (bassin,
	vasques, cerveau, eau) et publie son repère (attribut "FxFountainBase" du
	dossier Plaza).
	v11 (PARK11) — "les fontaines sont nulles" : l'eau en perles et en
	bâtons (v9.8) est remplacée par de la VRAIE eau (FountainKit) :
	  - 8 VEINES D'EAU continues en arc, de la bouche des poissons de bronze
	    jusqu'au bassin (elles s'affinent, scintillent, des paquets clairs
	    filent dessus), ronds et écume là où elles tombent ;
	  - NAPPES qui débordent des deux vasques (voile circulaire avec filets
	    qui descendent, couronne d'écume au pied) ;
	  - gerbe du cerveau qui monte et s'ouvre en couronne ;
	  - reflets qui scintillent sur l'eau, pièces au fond ;
	  - DÉTAILS SCULPTÉS : médaillons au cerveau sur la margelle, cannelures
	    du pied, feuilles d'acanthe, têtes de poisson en bronze.
	Côté client seulement, on éteint localement les anciens effets du
	serveur (cylindres de verre "Curtain", ronds fixes, particules en
	paillettes) : ils feraient double emploi.
	Ancré, sans collision ; animation ≤ 30 Hz, rien de créé par image.
	Aucune lumière, aucun son.

	API (TownPlazaFx) :
	  TownFountainFx.Build(folder, base: Vector3) -> état
	  TownFountainFx.Step(état, t: number)
]]

local FountainKit = require(script.Parent.FountainKit)

local TownFountainFx = {}

local M = Enum.Material
local rgb = Color3.fromRGB

-- Hauteurs de la fontaine serveur (au-dessus du parvis `base`, voir TownPlaza)
local BASIN_R = 13.6
local WATER_Y = 2.5
local FLOOR_Y = 0.8
local BOWL_R, BOWL_Y, BOWL_WATER_Y = 6.2, 7.0, 7.1
local UPPER_R, UPPER_Y, UPPER_WATER_Y = 3.3, 10.9, 11.0
local JET_R, JET_Y = 12.3, 2.62
local NOZZLE_Y = 12.05 + 2.625 + 2.1

local BRONZE = rgb(196, 150, 92)
local MARBLE = rgb(250, 244, 240)
local ROSE = rgb(232, 178, 188)

local JETS = 8

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

local function disc(parent: Instance, name: string, center: Vector3, top: number, radius: number, t: number, color: Color3, material: Enum.Material?): BasePart
	return newPart(parent, name, Vector3.new(t, radius * 2, radius * 2), CFrame.new(center.X, top - t / 2, center.Z) * CFrame.Angles(0, 0, math.rad(90)), color, material, "Cyl")
end

local function hash(a: number, b: number): number
	local x = math.sin(a * 12.9898 + b * 78.233) * 43758.5453
	return x - math.floor(x)
end

-- La fontaine du serveur (dossier Plaza) dont le parvis est en `base`
local function serverFountain(base: Vector3): Instance?
	local town = workspace:FindFirstChild("DopamineTown")
	if not town then
		return nil
	end
	for _, d in ipairs(town:GetDescendants()) do
		if d.Name == "Fountain" and d:IsA("Model") then
			local water = d:FindFirstChild("Water")
			if water and water:IsA("BasePart") and Vector3.new(water.Position.X - base.X, 0, water.Position.Z - base.Z).Magnitude < 2 then
				return d
			end
		end
	end
	return nil
end

-- Éteint (localement) les anciens effets d'eau du serveur
local function quietServerWater(base: Vector3): number
	local model = serverFountain(base)
	if not model then
		return 0
	end
	local n = 0
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("ParticleEmitter") then
			d.Enabled = false
			n += 1
		elseif d:IsA("BasePart") and (d.Name == "Curtain" or d.Name == "Ripple") then
			d.Transparency = 1
			n += 1
		end
	end
	return n
end

function TownFountainFx.Build(folder: Instance, base: Vector3): any
	local model = Instance.new("Model")
	model.Name = "FountainFx"
	model.Parent = folder
	local W = FountainKit.Water(model)
	local F = { Base = base, Model = model, Water = W, Quiet = 0 }
	local function y(h: number): Vector3
		return base + Vector3.new(0, h, 0)
	end
	local ok, n = pcall(quietServerWater, base)
	F.Quiet = ok and n or 0
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
	-- têtes de poisson en bronze aux 8 buses + VEINES D'EAU en arc
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
		FountainKit.Stream(W, mouth - d * 0.3, landing, 2.4, 0.3, 0.22, j * 0.13, 1.6)
	end
	-- NAPPES : vasque basse -> bassin, vasque haute -> vasque basse
	local center = CFrame.new(base)
	FountainKit.Sheet(W, center, BOWL_R + 0.05, BOWL_Y + 0.05, BOWL_R + 0.45, 0.5, BOWL_R + 0.62, WATER_Y, 28)
	FountainKit.Sheet(W, center, UPPER_R + 0.05, UPPER_Y + 0.05, UPPER_R + 0.35, 0.35, UPPER_R + 0.5, BOWL_WATER_Y, 18)
	-- gerbe du cerveau (couronne, sans retombée à travers la mascotte)
	FountainKit.Plume(W, y(NOZZLE_Y - 0.3), 3.2, 0.4)
	-- reflets sur les trois eaux
	FountainKit.Glints(W, base, base.Y + WATER_Y + 0.02, BASIN_R - 1.2, 14)
	FountainKit.Glints(W, base, base.Y + BOWL_WATER_Y + 0.02, BOWL_R - 0.8, 5)
	FountainKit.Glints(W, base, base.Y + UPPER_WATER_Y + 0.02, UPPER_R - 0.6, 3)
	return F
end

function TownFountainFx.Step(F: any, t: number)
	if not F or not F.Water then
		return
	end
	FountainKit.StepWater(F.Water, t)
end

return TownFountainFx
