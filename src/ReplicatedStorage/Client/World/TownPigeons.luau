--[[
	TownPigeons (ModuleScript)
	Emplacement : ReplicatedStorage > Client > World > TownPigeons

	🐦 Les pigeons de la place centrale (v9.8, CITY98), "10x mieux", côté
	CLIENT (appelé par TownPlazaFx : construit avec la place, animé à 30 Hz,
	en pause au loin). 20 pigeons en 4 groupes (attributs FxFlock1..4 du
	dossier Plaza) :
	  - vrai pigeon biset (~19 pièces) : corps fuselé gris bleuté, poitrail
	    rosé, cou IRISÉ (vert + violet, reflets), tête ronde, bec sombre avec
	    cire blanche, yeux orange, ailes grises à DEUX BARRES noires, queue
	    à bande sombre, pattes rouges et doigts ;
	  - au sol : marche avec le hochement de tête typique (la tête avance
	    puis s'arrête à chaque pas), picore, se retourne, roucoule (poitrail
	    gonflé, petite pirouette), fait sa toilette ;
	  - un avatar ou un passant approche : le groupe S'ENVOLE (battements
	    rapides au décollage, plané, redressement à l'atterrissage) et se
	    pose sur les lanternes des lampadaires, la margelle de la fontaine
	    ou un autre coin de la place ; il redescend picorer plus tard ;
	  - de temps en temps, un pigeon va se percher tout seul.
	Tout est ancré, sans collision, animé par CFrame (BulkMoveTo). Aucune
	création d'instance par image. Aucun son.

	API (TownPlazaFx) :
	  TownPigeons.Build(folder, plaza) -> état   (plaza : dossier Plaza, attributs Fx…)
	  TownPigeons.Step(état, dt, avatar: Vector3?)
	  TownPigeons.Count(état) -> number
]]

local TownPigeons = {}

local M = Enum.Material
local rgb = Color3.fromRGB

local PER_FLOCK = 5
local FLEE_R = 6 -- (studs) quelqu'un plus près : envol
local FLY_SPEED = 15 -- (studs / s)
local PERCH_MIN, PERCH_MAX = 7, 16 -- (s) temps passé perché avant de redescendre

-- Pièces (repère : pieds au sol, bec vers -Z) ; genre : 0 corps, 1 tête+cou,
-- 2 aile gauche, 3 aile droite, 4 patte gauche, 5 patte droite, 6 queue
local NECK = CFrame.new(0, 0.62, -0.28)
local NECK_INV = NECK:Inverse()
local SHOULDERS = { CFrame.new(-0.2, 0.58, -0.1), CFrame.new(0.2, 0.58, -0.1) }
local SHOULDERS_INV = { SHOULDERS[1]:Inverse(), SHOULDERS[2]:Inverse() }
local HIPS = { CFrame.new(-0.08, 0.24, 0), CFrame.new(0.08, 0.24, 0) }
local HIPS_INV = { HIPS[1]:Inverse(), HIPS[2]:Inverse() }
local TAILP = CFrame.new(0, 0.46, 0.38)
local TAILP_INV = TAILP:Inverse()
-- aile repliée (au repos) / dépliée (en vol : envergure ~2 studs, corde
-- à plat) ; les barres noires suivent leur aile
local WING_FOLD = {
	CFrame.new(-0.235, 0.5, 0.12) * CFrame.Angles(math.rad(10), 0, 0),
	CFrame.new(0.235, 0.5, 0.12) * CFrame.Angles(math.rad(10), 0, 0),
}
local WING_OPEN = {
	CFrame.fromMatrix(Vector3.new(-0.62, 0.6, -0.02), Vector3.new(0, 1, 0), Vector3.new(0, 0, -1)),
	CFrame.fromMatrix(Vector3.new(0.62, 0.6, -0.02), Vector3.new(0, 1, 0), Vector3.new(0, 0, 1)),
}

type Bird = {
	Pos: Vector3,
	Yaw: number,
	Home: Vector3,
	Flock: number,
	Mode: string,
	Timer: number,
	Clock: number,
	Rng: Random,
	From: Vector3,
	To: Vector3,
	FlyTime: number,
	Arc: number,
	Perched: boolean,
	Calm: number,
	Parts: { BasePart },
	Locals: { CFrame },
	Rel: { CFrame },
	Kind: { number },
}

----------------------------------------------------------------------
-- Modèle
----------------------------------------------------------------------

local function newPart(parent: Instance, name: string, size: Vector3, color: Color3, shape: string?): BasePart
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Size = size
	p.Color = color
	p.Material = M.SmoothPlastic
	if shape == "Ball" then
		p.Shape = Enum.PartType.Ball
	elseif shape == "Egg" then
		local mesh = Instance.new("SpecialMesh")
		mesh.MeshType = Enum.MeshType.Sphere
		mesh.Parent = p
	end
	p.Parent = parent
	return p
end

-- Plumages (biset classique, plus clair, plus foncé, "écaillé")
local PLUMES = {
	{ Body = rgb(140, 148, 168), Wing = rgb(160, 166, 182), Head = rgb(104, 110, 136), Breast = rgb(170, 150, 166) },
	{ Body = rgb(176, 178, 190), Wing = rgb(196, 196, 206), Head = rgb(130, 132, 150), Breast = rgb(190, 176, 186) },
	{ Body = rgb(96, 100, 118), Wing = rgb(112, 116, 134), Head = rgb(76, 80, 98), Breast = rgb(120, 104, 120) },
	{ Body = rgb(150, 136, 128), Wing = rgb(186, 170, 156), Head = rgb(110, 100, 104), Breast = rgb(176, 150, 146) },
}

local function buildBird(parent: Instance, bird: Bird, seed: number, all: { BasePart }, frames: { CFrame })
	local plume = PLUMES[seed % 5 == 0 and 3 or (seed % 7 == 0 and 4 or (seed % 3 == 0 and 2 or 1))]
	local function add(name: string, size: Vector3, loc: CFrame, color: Color3, shape: string?, kind: number): BasePart
		local p = newPart(parent, name, size, color, shape)
		p.CFrame = CFrame.new(bird.Pos) * loc
		table.insert(bird.Parts, p)
		table.insert(bird.Locals, loc)
		table.insert(bird.Kind, kind)
		table.insert(bird.Rel, (kind == 2 or kind == 3) and WING_FOLD[kind - 1]:Inverse() * loc or loc)
		table.insert(all, p)
		table.insert(frames, p.CFrame)
		return p
	end
	-- corps fuselé (légèrement relevé vers l'avant) + poitrail
	add("Body", Vector3.new(0.5, 0.48, 0.98), CFrame.new(0, 0.44, 0.04) * CFrame.Angles(math.rad(12), 0, 0), plume.Body, "Egg", 0)
	add("Breast", Vector3.new(0.42, 0.46, 0.52), CFrame.new(0, 0.5, -0.22), plume.Breast, "Egg", 0)
	-- queue (éventail + bande sombre au bout)
	add("Tail", Vector3.new(0.3, 0.06, 0.46), CFrame.new(0, 0.44, 0.62) * CFrame.Angles(math.rad(-8), 0, 0), plume.Body, nil, 6)
	add("TailBand", Vector3.new(0.31, 0.07, 0.1), CFrame.new(0, 0.42, 0.82) * CFrame.Angles(math.rad(-8), 0, 0), rgb(46, 46, 58), nil, 6)
	-- cou irisé (vert / violet, un peu brillant) + tête + bec + cire + yeux
	local neck = add("Neck", Vector3.new(0.3, 0.34, 0.3), CFrame.new(0, 0.7, -0.3), rgb(86, 140, 116), "Egg", 1)
	neck.Reflectance = 0.25
	local patch = add("NeckPatch", Vector3.new(0.34, 0.2, 0.24), CFrame.new(0, 0.6, -0.3), rgb(132, 92, 156), "Egg", 1)
	patch.Reflectance = 0.25
	add("Head", Vector3.new(0.28, 0.28, 0.28), CFrame.new(0, 0.9, -0.42), plume.Head, "Ball", 1)
	add("Beak", Vector3.new(0.07, 0.07, 0.18), CFrame.new(0, 0.87, -0.6), rgb(52, 46, 50), "Egg", 1)
	add("Cere", Vector3.new(0.09, 0.06, 0.08), CFrame.new(0, 0.91, -0.53), rgb(236, 232, 226), "Egg", 1)
	for _, sx in ipairs({ -1, 1 }) do
		add("Eye", Vector3.new(0.075, 0.075, 0.075), CFrame.new(sx * 0.12, 0.94, -0.48), rgb(236, 120, 40), "Ball", 1)
	end
	-- ailes repliées + 2 barres noires chacune
	for i, sx in ipairs({ -1, 1 }) do
		local kind = i == 1 and 2 or 3
		add("Wing", Vector3.new(0.12, 0.32, 0.78), CFrame.new(sx * 0.235, 0.5, 0.12) * CFrame.Angles(math.rad(10), 0, 0), plume.Wing, "Egg", kind)
		add("WingBar", Vector3.new(0.04, 0.06, 0.26), CFrame.new(sx * 0.298, 0.49, 0.16) * CFrame.Angles(math.rad(10), 0, 0), rgb(40, 40, 50), nil, kind)
	end
	-- pattes rouges + doigts
	for i, sx in ipairs({ -1, 1 }) do
		local kind = i == 1 and 4 or 5
		add("Leg", Vector3.new(0.05, 0.24, 0.05), CFrame.new(sx * 0.08, 0.12, 0), rgb(214, 80, 90), nil, kind)
		add("Foot", Vector3.new(0.11, 0.03, 0.15), CFrame.new(sx * 0.08, 0.015, -0.04), rgb(200, 70, 80), nil, kind)
	end
end

----------------------------------------------------------------------
-- Lieux (sol, perchoirs)
----------------------------------------------------------------------

local function vec3Attr(folder: Instance, name: string): Vector3?
	local v = folder:GetAttribute(name)
	return typeof(v) == "Vector3" and v or nil
end

-- Perchoirs : dessus des lanternes des lampadaires de la place, margelle de
-- la fontaine (milieu de chaque pan)
local function perches(plaza: Instance): { Vector3 }
	local list = {}
	local center = vec3Attr(plaza, "FxCenter")
	local lamps = vec3Attr(plaza, "FxLamps")
	if center and lamps then
		local r, n = lamps.X, math.floor(lamps.Z)
		for i = 0, n - 1 do
			local a = (i + 0.5) / n * math.pi * 2
			local d = Vector3.new(math.sin(a), 0, math.cos(a))
			local along = Vector3.new(d.Z, 0, -d.X)
			for _, z in ipairs({ -1.9, 1.9 }) do
				-- (dessus du chapeau de la lanterne : 10,5 + 0,35 + 0,15)
				table.insert(list, center + d * r + along * z + Vector3.new(0, 11.0, 0))
			end
		end
	end
	local base = vec3Attr(plaza, "FxFountainBase")
	if base then
		for i = 0, 11 do
			local a = (i + 0.5) / 12 * math.pi * 2
			table.insert(list, base + Vector3.new(math.sin(a) * 13.5, 3.2, math.cos(a) * 13.5))
		end
	end
	return list
end

----------------------------------------------------------------------
-- Construction
----------------------------------------------------------------------

function TownPigeons.Build(folder: Instance, plaza: Instance): any
	local model = Instance.new("Model")
	model.Name = "Pigeons"
	model.Parent = folder
	local P = { List = {}, Parts = {}, Frames = {}, Homes = {}, Perches = perches(plaza), Taken = {}, Time = 0 }
	for i = 1, 4 do
		local home = vec3Attr(plaza, "FxFlock" .. i)
		if home then
			table.insert(P.Homes, home + Vector3.new(0, 0.12, 0))
		end
	end
	for h, home in ipairs(P.Homes) do
		for j = 1, PER_FLOCK do
			local rng = Random.new(h * 31 + j * 7)
			local a = rng:NextNumber(0, math.pi * 2)
			local pos = home + Vector3.new(math.cos(a), 0, math.sin(a)) * rng:NextNumber(0.6, 3.4)
			local bird: Bird = {
				Pos = pos,
				Yaw = rng:NextNumber(0, math.pi * 2),
				Home = home,
				Flock = h,
				Mode = "idle",
				Timer = rng:NextNumber(0.2, 1.5),
				Clock = 0,
				Rng = rng,
				From = pos,
				To = pos,
				FlyTime = 1,
				Arc = 3,
				Perched = false,
				Calm = 0,
				Parts = {},
				Locals = {},
				Rel = {},
				Kind = {},
			}
			buildBird(model, bird, h * 10 + j, P.Parts, P.Frames)
			table.insert(P.List, bird)
		end
	end
	return P
end

function TownPigeons.Count(P: any): number
	return P and #P.List or 0
end

----------------------------------------------------------------------
-- Comportement
----------------------------------------------------------------------

local function yawTo(from: Vector3, to: Vector3, fallback: number): number
	local d = Vector3.new(to.X - from.X, 0, to.Z - from.Z)
	if d.Magnitude < 0.05 then
		return fallback
	end
	return math.atan2(-d.X, -d.Z)
end

-- Envol vers `target` (sol ou perchoir)
local function takeOff(bird: Bird, target: Vector3, perched: boolean)
	local dist = (target - bird.Pos).Magnitude
	bird.Mode = "fly"
	bird.Clock = 0
	bird.From = bird.Pos
	bird.To = target
	bird.FlyTime = math.clamp(dist / FLY_SPEED, 0.9, 4.5) + 0.3
	bird.Arc = math.clamp(dist * 0.22, 1.5, 7) + math.max(0, target.Y - bird.Pos.Y) * 0.35
	bird.Perched = perched
	bird.Yaw = yawTo(bird.From, target, bird.Yaw)
end

-- Perchoir libre (un pigeon par perchoir) le plus proche d'un point
local function freePerch(P: any, near: Vector3, rng: Random): (Vector3?, number?)
	local best, bestI, bestD = nil, nil, math.huge
	for i, p in ipairs(P.Perches) do
		if not P.Taken[i] then
			local d = (p - near).Magnitude + rng:NextNumber(0, 14)
			if d < bestD then
				best, bestI, bestD = p, i, d
			end
		end
	end
	return best, bestI
end

local function releasePerch(P: any, bird: any)
	if bird.PerchIndex then
		P.Taken[bird.PerchIndex] = nil
		bird.PerchIndex = nil
	end
end

-- Un groupe s'envole (loin de `threat`) : moitié vers des perchoirs, moitié
-- vers un autre coin de la place
local function scare(P: any, flock: number, threat: Vector3)
	for _, bird in ipairs(P.List) do
		if bird.Flock == flock and bird.Mode ~= "fly" and not bird.Perched then
			local rng = bird.Rng
			releasePerch(P, bird)
			if rng:NextNumber() < 0.5 then
				local perch, index = freePerch(P, bird.Pos, rng)
				if perch and index then
					P.Taken[index] = true
					;(bird :: any).PerchIndex = index
					takeOff(bird, perch, true)
					continue
				end
			end
			-- sol : un autre groupe, à l'opposé de la menace
			local away = Vector3.new(bird.Pos.X - threat.X, 0, bird.Pos.Z - threat.Z)
			local best, bestScore = bird.Home, -math.huge
			for _, home in ipairs(P.Homes) do
				local score = (home - threat).Magnitude + (away.Magnitude > 0.1 and (home - bird.Pos).Unit:Dot(away.Unit) * 6 or 0)
				if score > bestScore then
					best, bestScore = home, score
				end
			end
			local a = rng:NextNumber(0, math.pi * 2)
			local target = best + Vector3.new(math.cos(a), 0, math.sin(a)) * rng:NextNumber(0.5, 3.5)
			bird.Home = best
			takeOff(bird, target, false)
		end
	end
end

local function peopleNear(): { Vector3 }
	local folder = script.Parent
	local mod = folder and folder:FindFirstChild("TownPeople")
	if not mod then
		return {}
	end
	local ok, TownPeople = pcall(require, mod)
	if ok and type(TownPeople) == "table" and type(TownPeople.Positions) == "function" then
		local ok2, list = pcall(TownPeople.Positions)
		if ok2 and type(list) == "table" then
			return list
		end
	end
	return {}
end

function TownPigeons.Step(P: any, dt: number, avatar: Vector3?)
	if not P then
		return
	end
	P.Time += dt
	-- menaces : l'avatar + les passants proches (relus 4 fois / s)
	P.PeopleClock = (P.PeopleClock or 0) - dt
	if P.PeopleClock <= 0 then
		P.PeopleClock = 0.25
		P.People = peopleNear()
	end
	local threats = P.People or {}
	local scared: { [number]: Vector3 } = {}
	for _, bird: Bird in ipairs(P.List) do
		if bird.Mode ~= "fly" and not bird.Perched and bird.Calm <= 0 and not scared[bird.Flock] then
			if avatar and (Vector3.new(bird.Pos.X - avatar.X, 0, bird.Pos.Z - avatar.Z)).Magnitude < FLEE_R and math.abs(avatar.Y - bird.Pos.Y) < 8 then
				scared[bird.Flock] = avatar
			else
				for _, q in ipairs(threats) do
					if (Vector3.new(bird.Pos.X - q.X, 0, bird.Pos.Z - q.Z)).Magnitude < FLEE_R * 0.6 then
						scared[bird.Flock] = q
						break
					end
				end
			end
		end
	end
	for flock, threat in pairs(scared) do
		scare(P, flock, threat)
	end
	local frames = P.Frames
	local index = 0
	for _, bird: Bird in ipairs(P.List) do
		local rng = bird.Rng
		bird.Timer -= dt
		bird.Clock += dt
		bird.Calm = math.max(0, bird.Calm - dt)
		local lift, pitch, roll, flap, spread = 0, 0, 0, 0, 0
		local headFwd, headPitch, legA = 0, 0, 0
		local mode = bird.Mode
		if mode == "fly" then
			local t = math.clamp(bird.Clock / bird.FlyTime, 0, 1)
			local e = t * t * (3 - 2 * t)
			local p = bird.From:Lerp(bird.To, e)
			lift = math.sin(t * math.pi) * bird.Arc
			bird.Pos = p
			-- décollage : battements rapides ; milieu : plané ; fin : on freine, ailes en avant
			local beat = t < 0.3 and 1 or (t > 0.8 and 0.8 or 0.35 + 0.25 * math.sin(bird.Clock * 3))
			flap = math.sin(bird.Clock * 38) * 1.05 * beat
			spread = 1
			pitch = t < 0.25 and 0.3 or (t > 0.8 and 0.5 or -0.05)
			roll = math.sin(bird.Clock * 2.3) * 0.08
			legA = 0.9
			if t >= 1 then
				bird.Pos = bird.To
				bird.Mode = bird.Perched and "perch" or "idle"
				bird.Timer = bird.Perched and rng:NextNumber(PERCH_MIN, PERCH_MAX) or rng:NextNumber(0.8, 2)
				bird.Calm = 1.5
				bird.Clock = 0
				-- (se tourne vers le centre de la place une fois perché)
				if bird.Perched and P.Homes[1] then
					bird.Yaw = yawTo(bird.Pos, P.Homes[bird.Flock] or P.Homes[1], bird.Yaw) + math.pi
				end
			end
		elseif mode == "walk" then
			local step = Vector3.new(-math.sin(bird.Yaw), 0, -math.cos(bird.Yaw)) * (1.3 * dt)
			local nextPos = bird.Pos + step
			-- (on ne marche pas dans un autre pigeon : on se détourne)
			local blocked = false
			for _, other: Bird in ipairs(P.List) do
				if other ~= bird and other.Mode ~= "fly" and (other.Pos - nextPos).Magnitude < 0.8 and (other.Pos - bird.Pos).Magnitude > (other.Pos - nextPos).Magnitude then
					blocked = true
					break
				end
			end
			if blocked then
				bird.Yaw += dt * 4
			elseif (nextPos - bird.Home).Magnitude > 5.5 then
				bird.Yaw = yawTo(bird.Pos, bird.Home, bird.Yaw)
			else
				bird.Pos = nextPos
			end
			-- hochement de tête : la tête avance d'un coup puis reste immobile
			local cyc = (bird.Clock * 3.2) % 1
			headFwd = cyc < 0.35 and (cyc / 0.35) * 0.1 or 0.1 - (cyc - 0.35) / 0.65 * 0.1
			legA = math.sin(bird.Clock * 3.2 * math.pi * 2) * 0.45
			lift = math.abs(math.sin(bird.Clock * 3.2 * math.pi)) * 0.03
		elseif mode == "peck" then
			headPitch = math.sin(math.clamp(bird.Clock / 0.45, 0, 1) * math.pi) * 1.45
		elseif mode == "coo" then
			-- roucoulade : poitrail gonflé (relevé), petite pirouette
			headPitch = -0.35 + math.sin(bird.Clock * 10) * 0.1
			bird.Yaw += dt * 2.2
			pitch = 0.12
		elseif mode == "preen" then
			headPitch = 0.6
			flap = math.sin(bird.Clock * 12) * 0.1
		elseif mode == "perch" then
			headPitch = math.sin(bird.Clock * 0.9) * 0.15
			lift = 0
			if bird.Timer <= 0 then
				-- on redescend picorer près de son groupe
				releasePerch(P, bird)
				local a = rng:NextNumber(0, math.pi * 2)
				takeOff(bird, bird.Home + Vector3.new(math.cos(a), 0, math.sin(a)) * rng:NextNumber(0.5, 3.5), false)
			end
		end
		if bird.Mode ~= "fly" and bird.Mode ~= "perch" and bird.Timer <= 0 then
			local r = rng:NextNumber()
			bird.Clock = 0
			if r < 0.34 then
				bird.Mode, bird.Timer = "peck", 0.45
			elseif r < 0.64 then
				bird.Mode, bird.Timer = "walk", rng:NextNumber(0.6, 1.8)
				bird.Yaw += rng:NextNumber(-0.9, 0.9)
			elseif r < 0.76 then
				bird.Mode, bird.Timer = "idle", rng:NextNumber(0.4, 1.2)
				bird.Yaw += rng:NextNumber(-1.6, 1.6)
			elseif r < 0.84 then
				bird.Mode, bird.Timer = "coo", rng:NextNumber(0.8, 1.4)
			elseif r < 0.9 then
				bird.Mode, bird.Timer = "preen", rng:NextNumber(0.8, 1.6)
			elseif r < 0.93 and bird.Calm <= 0 then
				-- (parfois un pigeon va se percher tout seul)
				local perch, pIndex = freePerch(P, bird.Pos, rng)
				if perch and pIndex then
					P.Taken[pIndex] = true
					;(bird :: any).PerchIndex = pIndex
					takeOff(bird, perch, true)
				else
					bird.Mode, bird.Timer = "idle", 1
				end
			else
				bird.Mode, bird.Timer = "idle", rng:NextNumber(0.6, 1.8)
			end
		end
		-- pose
		local root = CFrame.new(bird.Pos + Vector3.new(0, lift, 0)) * CFrame.Angles(0, bird.Yaw, 0) * CFrame.Angles(pitch, 0, roll)
		local headCF = root * CFrame.new(0, 0, -headFwd) * NECK * CFrame.Angles(-headPitch, 0, 0) * NECK_INV
		local tailCF = root * TAILP * CFrame.Angles(spread * 0.15 + (mode == "coo" and -0.3 or 0), 0, 0) * TAILP_INV
		for i = 1, #bird.Parts do
			index += 1
			local kind = bird.Kind[i]
			local loc = bird.Locals[i]
			if kind == 1 then
				frames[index] = headCF * loc
			elseif kind == 2 or kind == 3 then
				local sign = kind == 2 and 1 or -1
				-- ailes : dépliées en vol + battement autour de l'axe du corps
				local w = kind - 1
				local beat = root * SHOULDERS[w] * CFrame.Angles(0, 0, sign * flap) * SHOULDERS_INV[w]
				if spread > 0 then
					frames[index] = beat * WING_OPEN[w] * bird.Rel[i]
				else
					frames[index] = beat * loc
				end
			elseif kind == 4 or kind == 5 then
				local a = kind == 4 and legA or -legA
				if mode == "fly" then
					a = legA
				end
				frames[index] = root * HIPS[kind - 3] * CFrame.Angles(a, 0, 0) * HIPS_INV[kind - 3] * loc
			elseif kind == 6 then
				frames[index] = tailCF * loc
			else
				frames[index] = root * loc
			end
		end
	end
	workspace:BulkMoveTo(P.Parts, frames, Enum.BulkMoveMode.FireCFrameChanged)
end

return TownPigeons
