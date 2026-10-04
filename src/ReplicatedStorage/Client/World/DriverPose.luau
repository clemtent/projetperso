--[[
	DriverPose (ModuleScript)
	Emplacement : ReplicatedStorage > Client > World > DriverPose

	v11 (CARS11) 🚗 POSE DE CONDUITE des joueurs (le mien ET les autres, vus
	par chaque client) : les animations ne peuvent pas être téléversées, tout
	est procédural sur les Motor6D (on n'écrit que Motor6D.Transform, dans
	RunService.Stepped, après l'Animator ; l'animation "assis" de Roblox
	reprend la main dès qu'on arrête).
	  - MAINS SUR LE VOLANT à "10 h 10" : cinématique inverse à 2 segments
	    (épaule -> coude -> poignet) vers les points de la jante du VRAI
	    volant de la voiture (attributs WheelCF / WheelRimR de CarModels) ;
	    les mains suivent le volant qui tourne (jusqu'à ±1,2 rad, au-delà le
	    volant glisse dans les mains) ;
	  - TÊTE qui regarde dans le virage, BUSTE qui se penche avec la force
	    latérale (vitesse × lacet) ;
	  - MARCHE ARRIÈRE : fondu ~0,4 s vers "regarder derrière" : buste tourné
	    à droite, tête par-dessus l'épaule droite, bras droit posé sur le
	    dossier du passager ; retour aussi doux en repartant en avant ;
	  - R15 (IK complète) et R6 (rotations simples des épaules / du cou).
	Rien n'est répliqué ; ≤ 8 conducteurs animés, à moins de 150 studs.

	API (CarClient) :
	  DriverPose.Start(steerOf)   steerOf(carModel) -> braquage des roues (rad, + = gauche)
	  DriverPose.Stop()
	  DriverPose.Debug()          état (tests)
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local CarModels = require(ReplicatedStorage.Shared.CarModels)

local DriverPose = {}
DriverPose.RANGE = 150
DriverPose.MAX = 8
DriverPose.BLEND_TIME = 0.4 -- (s) fondu d'entrée / marche arrière
DriverPose.HAND_LIMIT = 1.2 -- (rad) au-delà, le volant tourne dans les mains

type Joint = { Motor: Motor6D, Base: CFrame, Written: CFrame? }
type Entry = {
	Character: Model,
	Humanoid: Humanoid,
	Seat: BasePart,
	Car: Model,
	R15: boolean,
	Joints: { [string]: Joint },
	Blend: number,
	Rev: number,
	Lean: number,
	Look: number,
	Leaving: boolean,
}

local entries: { [Model]: Entry } = {}
local connection: RBXScriptConnection? = nil
local scanClock = 0
local steerOf: ((Model) -> number)? = nil
local failed = false

local R15_JOINTS = {
	Root = "LowerTorso",
	Waist = "UpperTorso",
	Neck = "Head",
	RightShoulder = "RightUpperArm",
	RightElbow = "RightLowerArm",
	RightWrist = "RightHand",
	LeftShoulder = "LeftUpperArm",
	LeftElbow = "LeftLowerArm",
	LeftWrist = "LeftHand",
}
local R6_JOINTS = {
	Neck = "Torso",
	["Right Shoulder"] = "Torso",
	["Left Shoulder"] = "Torso",
}

local function carOfSeat(seat: Instance?): Model?
	if not seat or not seat:IsA("VehicleSeat") then
		return nil
	end
	local model = seat.Parent
	if model and model:IsA("Model") and model:GetAttribute("CarId") ~= nil then
		return model
	end
	return nil
end

local function collectJoints(character: Model, r15: boolean): { [string]: Joint }?
	local out: { [string]: Joint } = {}
	for name, holder in pairs(if r15 then R15_JOINTS else R6_JOINTS) do
		local part = character:FindFirstChild(holder)
		local motor = part and part:FindFirstChild(name)
		if not (motor and motor:IsA("Motor6D")) then
			return nil
		end
		out[name] = { Motor = motor, Base = motor.Transform, Written = nil }
	end
	return out
end

-- base de l'image : ce que l'Animator vient d'écrire (sinon la dernière connue)
local function readBase(j: Joint): CFrame
	local current = j.Motor.Transform
	if j.Written == nil or current ~= j.Written then
		j.Base = current
	end
	return j.Base
end

local function write(j: Joint, value: CFrame)
	j.Motor.Transform = value
	j.Written = value
end

local function release(e: Entry)
	for _, j in pairs(e.Joints) do
		if j.Motor.Parent and j.Written and j.Motor.Transform == j.Written then
			j.Motor.Transform = j.Base
		end
		j.Written = nil
	end
end

-- Repère d'une pièce posée par son Motor6D (Part1 = Part0 * C0 * T * C1⁻¹)
local function child(parentCF: CFrame, motor: Motor6D, t: CFrame): CFrame
	return parentCF * motor.C0 * t * motor.C1:Inverse()
end

-- Transform qui place Part1 au repère voulu
local function transformFor(parentCF: CFrame, motor: Motor6D, want: CFrame): CFrame
	return (parentCF * motor.C0):Inverse() * want * motor.C1
end

-- IK 2 segments (repère du HumanoidRootPart) : épaule S, cible T, longueurs
-- a (bras) / b (avant-bras), pôle (côté où plier le coude) -> coude E, poignet W
local function solveArm(S: Vector3, T: Vector3, a: number, b: number, pole: Vector3): (Vector3, Vector3)
	local toT = T - S
	local d = math.clamp(toT.Magnitude, math.abs(a - b) + 0.05, a + b - 0.02)
	local dir = if toT.Magnitude > 1e-4 then toT.Unit else Vector3.new(0, 0, -1)
	local cosA = math.clamp((a * a + d * d - b * b) / (2 * a * d), -1, 1)
	local sinA = math.sqrt(1 - cosA * cosA)
	local p = pole - dir * pole:Dot(dir)
	if p.Magnitude < 1e-4 then
		p = Vector3.new(0, -1, 0) - dir * (-dir.Y)
	end
	p = p.Unit
	local E = S + dir * (cosA * a) + p * (sinA * a)
	local W = S + dir * d
	return E, W
end

-- Repère d'un segment : son +Y va de `lo` (bout bas) vers `hi` (articulation
-- haute), son -Z du côté où se plie l'articulation suivante (`bendTo`)
local function segmentFrame(hi: Vector3, lo: Vector3, bendTo: Vector3): CFrame
	local y = hi - lo
	y = if y.Magnitude > 1e-4 then y.Unit else Vector3.yAxis
	local f = bendTo - y * bendTo:Dot(y)
	local z = if f.Magnitude > 1e-4 then -f.Unit else Vector3.zAxis
	local x = y:Cross(z)
	return CFrame.fromMatrix(Vector3.zero, x, y, z)
end

local function poseArm(e: Entry, side: string, upperCF: CFrame, target: Vector3, pole: Vector3, weight: number)
	local js = e.Joints
	local sh, el, wr = js[side .. "Shoulder"], js[side .. "Elbow"], js[side .. "Wrist"]
	local bS, bE, bW = readBase(sh), readBase(el), readBase(wr)
	-- longueurs (repères des pièces : avatars de toutes tailles)
	local a = (sh.Motor.C1.Position - el.Motor.C0.Position).Magnitude
	local b = (el.Motor.C1.Position - wr.Motor.C0.Position).Magnitude
	if a < 0.1 or b < 0.1 then
		return
	end
	local S = (upperCF * sh.Motor.C0).Position
	local E, W = solveArm(S, target, a, b, pole)
	-- bras : +Y de l'épaule vers le haut du segment, plié vers l'avant-bras
	local rotU = segmentFrame(S, E, W - E)
	local upperArm = CFrame.new(S) * rotU * CFrame.new(-sh.Motor.C1.Position)
	-- (épaule exactement à S : décalage par le point d'attache C1)
	upperArm = upperArm * CFrame.new(0, 0, 0)
	local tS = transformFor(upperCF, sh.Motor, upperArm)
	tS = tS - tS.Position -- (rotation seule : jamais d'étirement)
	local armCF = child(upperCF, sh.Motor, tS)
	local Eact = (armCF * el.Motor.C0).Position
	local rotL = segmentFrame(Eact, W, -(rotU.LookVector))
	local lowerArm = CFrame.new(Eact) * rotL * CFrame.new(-el.Motor.C1.Position)
	local tE = transformFor(armCF, el.Motor, lowerArm)
	tE = tE - tE.Position
	if weight >= 0.999 then
		write(sh, tS)
		write(el, tE)
	else
		write(sh, bS:Lerp(tS, weight))
		write(el, bE:Lerp(tE, weight))
	end
	write(wr, bW:Lerp(CFrame.Angles(0, 0, 0), weight * 0.6))
end

local function stepEntry(e: Entry, dt: number)
	local character, car = e.Character, e.Car
	local root = character:FindFirstChild("HumanoidRootPart")
	local carRoot = car.PrimaryPart
	if not (root and root:IsA("BasePart") and carRoot) then
		return
	end
	-- état de la voiture : braquage, marche arrière, force latérale
	local look = carRoot.CFrame.LookVector
	local vel = carRoot.AssemblyLinearVelocity
	local speed = vel:Dot(look)
	local yaw = carRoot.AssemblyAngularVelocity.Y
	local steer = 0
	if steerOf then
		local ok, value = pcall(steerOf, car)
		steer = if ok and type(value) == "number" then value else 0
	end
	local reversing = speed < -1.2 and not e.Leaving
	local k = math.clamp(dt / DriverPose.BLEND_TIME, 0, 1)
	e.Rev += ((if reversing then 1 else 0) - e.Rev) * math.clamp(dt / 0.18, 0, 1) * (if reversing then 0.7 else 1)
	e.Rev = math.clamp(e.Rev, 0, 1)
	e.Blend = math.clamp(e.Blend + (if e.Leaving then -k else k), 0, 1)
	local lean = math.clamp(-speed * yaw * 0.0045, -0.2, 0.2)
	e.Lean += (lean - e.Lean) * math.clamp(dt * 4, 0, 1)
	e.Look += (math.clamp(steer * 1.1, -0.5, 0.5) - e.Look) * math.clamp(dt * 3, 0, 1)
	local w = e.Blend
	local rev = e.Rev * w
	local wheelAngle = CarModels.SteeringWheelAngle(steer)
	local js = e.Joints
	if e.R15 then
		-- chaîne dans le repère du HumanoidRootPart (même image que la voiture)
		local rootJ, waist, neck = js.Root, js.Waist, js.Neck
		local bRoot, bWaist, bNeck = readBase(rootJ), readBase(waist), readBase(neck)
		local lower = child(CFrame.identity, rootJ.Motor, bRoot)
		-- buste : penché dans le virage, tourné à droite en marche arrière
		local tWaist = bWaist * CFrame.Angles(0.04 * w, -0.5 * rev, e.Lean * w)
		write(waist, tWaist)
		local upper = child(lower, waist.Motor, tWaist)
		-- tête : regarde dans le virage, par-dessus l'épaule droite en marche arrière
		write(neck, bNeck * CFrame.Angles(0.05 * rev, (e.Look * (1 - e.Rev) - 0.85 * e.Rev) * w, 0))
		-- volant (repère de la voiture -> repère du HumanoidRootPart)
		local wheelCF = car:GetAttribute("WheelCF")
		local rimR = tonumber(car:GetAttribute("WheelRimR")) or 0.62
		local rootInv = root.CFrame:Inverse()
		local handAngle = math.clamp(wheelAngle, -DriverPose.HAND_LIMIT, DriverPose.HAND_LIMIT)
		local gripL, gripR, toDriver
		if typeof(wheelCF) == "CFrame" then
			local wheel = rootInv * car:GetPivot() * wheelCF * CFrame.Angles(0, 0, handAngle)
			local s60, c60 = math.sin(math.rad(60)), math.cos(math.rad(60))
			toDriver = -wheel.LookVector
			gripL = (wheel * CFrame.new(-rimR * s60, rimR * c60, 0)).Position + toDriver * 0.22
			gripR = (wheel * CFrame.new(rimR * s60, rimR * c60, 0)).Position + toDriver * 0.22
		else
			-- (pas de volant connu : mains devant, à hauteur de poitrine)
			gripL = (upper * CFrame.new(-0.5, -0.1, -1.6)).Position
			gripR = (upper * CFrame.new(0.5, -0.1, -1.6)).Position
		end
		-- marche arrière : main droite sur le dossier du passager (à droite, un peu derrière)
		local back = (upper * CFrame.new(2.1, 0.55, 0.45)).Position
		gripR = gripR:Lerp(back, e.Rev)
		poseArm(e, "Left", upper, gripL, Vector3.new(-0.55, -1, 0.25), w)
		poseArm(e, "Right", upper, gripR, Vector3.new(0.55, -1, 0.25 + 0.6 * e.Rev), w)
	else
		-- R6 : bras levés vers le volant, tête
		local sR, sL, neck = js["Right Shoulder"], js["Left Shoulder"], js.Neck
		local bR, bL, bN = readBase(sR), readBase(sL), readBase(neck)
		local handAngle = math.clamp(wheelAngle, -DriverPose.HAND_LIMIT, DriverPose.HAND_LIMIT) * 0.25
		write(sR, bR:Lerp(CFrame.Angles(0, 0, 1.25 - handAngle - 0.6 * e.Rev), w))
		write(sL, bL:Lerp(CFrame.Angles(0, 0, -1.25 - handAngle), w))
		write(neck, bN * CFrame.Angles(0, 0, (e.Look * (1 - e.Rev) - 0.9 * e.Rev) * w))
	end
end

local function scan()
	local camera = workspace.CurrentCamera
	local camPos = camera and camera.CFrame.Position
	local seen: { [Model]: boolean } = {}
	local count = 0
	for _, player in ipairs(Players:GetPlayers()) do
		local character = player.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		local root = character and character:FindFirstChild("HumanoidRootPart")
		if character and humanoid and root and root:IsA("BasePart") and humanoid.Health > 0 then
			local car = carOfSeat(humanoid.SeatPart)
			local near = camPos == nil or (root.Position - camPos).Magnitude < DriverPose.RANGE
			if car and near and count < DriverPose.MAX then
				count += 1
				seen[character] = true
				local e = entries[character]
				if e and (e.Car ~= car or e.Leaving) then
					release(e)
					entries[character] = nil
					e = nil
				end
				if not e then
					local r15 = humanoid.RigType == Enum.HumanoidRigType.R15
					local joints = collectJoints(character, r15)
					if joints then
						entries[character] = {
							Character = character,
							Humanoid = humanoid,
							Seat = humanoid.SeatPart :: BasePart,
							Car = car,
							R15 = r15,
							Joints = joints,
							Blend = 0,
							Rev = 0,
							Lean = 0,
							Look = 0,
							Leaving = false,
						}
					end
				end
			end
		end
	end
	for character, e in pairs(entries) do
		if not seen[character] then
			-- (descendu / trop loin : on rend la main tout de suite)
			release(e)
			entries[character] = nil
		end
	end
end

local function onStepped(_time: number, dt: number)
	if failed then
		return
	end
	local ok, err = pcall(function()
		scanClock += dt
		if scanClock >= 0.25 then
			scanClock = 0
			scan()
		end
		for character, e in pairs(entries) do
			if not character.Parent or e.Humanoid.SeatPart ~= e.Seat then
				release(e)
				entries[character] = nil
			else
				stepEntry(e, math.min(dt, 0.1))
			end
		end
	end)
	if not ok then
		failed = true
		warn("[DriverPose] " .. tostring(err))
		for _, e in pairs(entries) do
			pcall(release, e)
		end
		table.clear(entries)
	end
end

function DriverPose.Start(steerProvider: ((Model) -> number)?)
	steerOf = steerProvider
	if connection then
		return
	end
	failed = false
	connection = RunService.Stepped:Connect(onStepped)
end

function DriverPose.Stop()
	if connection then
		connection:Disconnect()
		connection = nil
	end
	for _, e in pairs(entries) do
		pcall(release, e)
	end
	table.clear(entries)
end

-- (tests / émulateur)
function DriverPose.Debug(): any
	return {
		Entries = entries,
		Step = onStepped,
		Scan = scan,
		SolveArm = solveArm,
		StepEntry = stepEntry,
	}
end

return DriverPose
