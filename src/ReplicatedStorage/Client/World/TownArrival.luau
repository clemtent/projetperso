--[[
	TownArrival (ModuleScript)
	Emplacement : ReplicatedStorage > Client > World > TownArrival

	🎬 Dopamine Town : l'arrivée.
	  - Intro(...) : court survol de la ville par la caméra (~4,2 s, 1re
	    arrivée de la session seulement, passable) : on part haut au-dessus
	    de la ville, on tourne autour de la place en descendant, et on finit
	    juste DERRIÈRE l'avatar, à la porte de la ville, regard vers la place.
	    Caméra Scriptable pendant le survol, rendue à Roblox (Custom) à la fin.
	  - Guide : (v9.6) plus AUCUNE ligne ni repère à l'écran ; il suit la
	    distance jusqu'à sa porte ; la petite boussole du HUD est calculée
	    ici (Bearing).
	Rien n'est créé par image : le survol ne fait que des calculs de CFrame,
	le guide (distance) se met à jour ~4 fois / s.
]]

local RunService = game:GetService("RunService")

local TownArrival = {}

local UP = Vector3.new(0, 1, 0)
local INTRO_TIME = 4.4
local END_BACK, END_UP, END_AHEAD = 14, 7, 26

----------------------------------------------------------------------
-- Chemin du survol
----------------------------------------------------------------------

-- Chemin précalculé (une fois) : points denses + longueurs cumulées
export type Path = {
	Plaza: Vector3,
	Points: { Vector3 },
	Lengths: { number },
	Total: number,
	ApproachAt: number, -- longueur où commence la descente dans l'axe
	EndLook: Vector3,
	EndCFrame: CFrame,
}

local function flat(v: Vector3): Vector3
	return Vector3.new(v.X, 0, v.Z)
end

local APPROACH = 80 -- (studs) on arrive dans l'axe de l'avenue, depuis l'extérieur…
local APPROACH_UP = 24 -- … à cette hauteur (sous l'arche du portail : ~22+ au centre)
local ORBIT_TURN = math.rad(140)
local DENSE = 220

local function catmull(p0: Vector3, p1: Vector3, p2: Vector3, p3: Vector3, t: number): Vector3
	local t2, t3 = t * t, t * t * t
	return (p1 * 2 + (p2 - p0) * t + (p0 * 2 - p1 * 5 + p2 * 4 - p3) * t2 + (p1 * 3 - p0 - p2 * 3 + p3) * t3) * 0.5
end

-- entrance : CFrame d'arrivée (pieds), plaza : centre de la place.
-- 1) grand tour haut autour de la place (vue d'ensemble), en se
--    rapprochant ; 2) on se place dans l'axe de l'avenue, DEHORS, et on
--    glisse tout droit en descendant, à travers l'arche du portail,
--    jusque derrière l'avatar (jamais de travers dans les tours).
function TownArrival.MakePath(entrance: CFrame, plaza: Vector3): Path
	local e = entrance.Position
	local toPlaza = flat(plaza - e)
	local forward = toPlaza.Magnitude > 12 and toPlaza.Unit or flat(entrance.LookVector)
	if forward.Magnitude < 0.01 then
		forward = Vector3.new(0, 0, -1)
	end
	forward = forward.Unit
	local camEnd = e - forward * END_BACK + UP * END_UP
	local lookEnd = e + forward * END_AHEAD + UP * 3
	local approach = e - forward * (END_BACK + APPROACH) + UP * APPROACH_UP
	local rel = flat(approach - plaza)
	local radiusA = math.max(rel.Magnitude, 40)
	local angleA = math.atan2(rel.Z, rel.X)
	local startRadius = radiusA * 1.15
	local startHeight = math.max(150, radiusA * 0.45)
	-- points de contrôle
	local control: { Vector3 } = {}
	local steps = 14
	for i = 0, steps do
		local s = i / steps
		local angle = angleA + ORBIT_TURN * (1 - s)
		local radius = startRadius + (radiusA - startRadius) * s
		local height = APPROACH_UP + (startHeight - APPROACH_UP) * (1 - s ^ 2.2)
		table.insert(control, Vector3.new(plaza.X + math.cos(angle) * radius, e.Y + height, plaza.Z + math.sin(angle) * radius))
	end
	local orbitCount = #control
	for i = 1, 6 do
		table.insert(control, approach:Lerp(camEnd, i / 6))
	end
	-- (extrémités prolongées pour la spline)
	local first = control[1] * 2 - control[2]
	local last = control[#control] * 2 - control[#control - 1]
	local points: { Vector3 } = {}
	local segments = #control - 1
	for i = 0, DENSE do
		local f = i / DENSE * segments
		local k = math.min(math.floor(f), segments - 1)
		local t = f - k
		local p0 = k >= 1 and control[k] or first
		local p1 = control[k + 1]
		local p2 = control[k + 2]
		local p3 = control[k + 3] or last
		table.insert(points, catmull(p0, p1, p2, p3, t))
	end
	points[#points] = camEnd
	local lengths: { number } = { 0 }
	local total = 0
	local approachAt = 0
	local approachIndex = math.floor((orbitCount - 1) / segments * DENSE + 0.5) + 1
	for i = 2, #points do
		total += (points[i] - points[i - 1]).Magnitude
		lengths[i] = total
		if i == approachIndex then
			approachAt = total
		end
	end
	return {
		Plaza = plaza,
		Points = points,
		Lengths = lengths,
		Total = math.max(total, 1),
		ApproachAt = approachAt,
		EndLook = lookEnd,
		EndCFrame = CFrame.lookAt(camEnd, lookEnd),
	}
end

local function easeInOut(t: number): number
	return 0.5 - 0.5 * math.cos(math.pi * math.clamp(t, 0, 1))
end

-- Caméra au temps t (0..1) du survol (vitesse régulière le long du chemin)
function TownArrival.CameraAt(path: Path, t: number): CFrame
	if t >= 1 then
		return path.EndCFrame
	end
	local target = easeInOut(t) * path.Total
	local lengths, points = path.Lengths, path.Points
	-- recherche dichotomique du segment
	local lo, hi = 1, #lengths
	while hi - lo > 1 do
		local mid = (lo + hi) // 2
		if lengths[mid] <= target then
			lo = mid
		else
			hi = mid
		end
	end
	local span = lengths[hi] - lengths[lo]
	local f = span > 0 and (target - lengths[lo]) / span or 0
	local position = points[lo]:Lerp(points[hi], f)
	-- regard : la place, puis (dans l'axe) le bout de l'avenue devant l'avatar
	local blend = 0
	if target > path.ApproachAt then
		blend = easeInOut((target - path.ApproachAt) / math.max(1, path.Total - path.ApproachAt))
	end
	local look = path.Plaza:Lerp(path.EndLook, blend)
	return CFrame.lookAt(position, look)
end

----------------------------------------------------------------------
-- Survol (intro)
----------------------------------------------------------------------

export type Intro = {
	Skip: (self: Intro) -> (),
	Cancel: (self: Intro) -> (),
	IsRunning: (self: Intro) -> boolean,
	Elapsed: number,
}

-- options : Camera, Path, Duration?, OnProgress?(t), OnDone(skipped: boolean)
function TownArrival.Intro(options: any): any
	local camera: Camera = options.Camera
	local path: Path = options.Path
	local duration = options.Duration or INTRO_TIME
	local intro = { Elapsed = 0, Running = true }
	local connection: RBXScriptConnection? = nil
	local previousFov = camera.FieldOfView

	local function finish(skipped: boolean, handBack: boolean)
		if not intro.Running then
			return
		end
		intro.Running = false
		if connection then
			connection:Disconnect()
			connection = nil
		end
		pcall(function()
			camera.FieldOfView = previousFov
		end)
		if handBack then
			pcall(function()
				camera.CFrame = path.EndCFrame
			end)
		end
		local done = options.OnDone
		if done then
			local ok, err = pcall(done, skipped)
			if not ok then
				warn("[TownArrival] " .. tostring(err))
			end
		end
	end

	function intro.Skip(_self: any)
		finish(true, true)
	end
	function intro.Cancel(_self: any)
		-- (sortie de la ville pendant le survol : on ne touche plus à la caméra)
		intro.Running = false
		if connection then
			connection:Disconnect()
			connection = nil
		end
	end
	function intro.IsRunning(_self: any): boolean
		return intro.Running
	end

	camera.CameraType = Enum.CameraType.Scriptable
	camera.FieldOfView = 62
	camera.CFrame = TownArrival.CameraAt(path, 0)
	connection = RunService.RenderStepped:Connect(function(dt: number)
		if not intro.Running then
			return
		end
		intro.Elapsed += dt
		local t = intro.Elapsed / duration
		camera.CFrame = TownArrival.CameraAt(path, t)
		-- (le champ de vision se resserre un peu à la fin : effet "atterrissage")
		camera.FieldOfView = 62 + (previousFov - 62) * easeInOut((t - 0.6) / 0.4)
		local progress = options.OnProgress
		if progress then
			progress(math.clamp(t, 0, 1))
		end
		if t >= 1 then
			finish(false, true)
		end
	end)
	return intro
end

----------------------------------------------------------------------
-- Guide vers sa maison
----------------------------------------------------------------------

local Guide = {}
Guide.__index = Guide

-- v9.6 (FIXES96) : le joueur ne veut PLUS de ligne à l'écran vers sa maison.
-- L'arc lumineux (Beam) et le repère flottant "🏠 Ta maison" (toujours
-- devant, à travers les murs) sont supprimés. Le guide ne fait plus que
-- suivre la distance jusqu'à sa porte (message "voici ta maison" à
-- l'arrivée) ; la petite boussole du HUD et le bouton "🏠 Rentrer" restent.
-- (API inchangée pour TownClient : Start / Attach / Update / Stop /
-- IsActive / Destroy ; plus aucune Instance créée.)
function TownArrival.Guide(_parent: Instance): any
	local self = setmetatable({
		Target = nil :: Vector3?,
		Beam = nil, -- (toujours nil : plus d'arc)
		Active = false,
		Distance = math.huge,
	}, Guide)
	return self
end

function Guide.Build(self: any, target: Vector3)
	self.Target = target
end

function Guide.Start(self: any, character: Model?, target: Vector3)
	self:Build(target)
	self.Active = true
	self.Distance = math.huge
	self:Attach(character)
end

-- (nouveau personnage : rien à rattacher, il n'y a plus d'arc)
function Guide.Attach(_self: any, _character: Model?) end

-- ~4 fois / s : distance (à plat) jusqu'à sa porte
function Guide.Update(self: any, from: Vector3?): number
	local target = self.Target
	if not self.Active or not target or not from then
		return math.huge
	end
	local distance = (flat(target - from)).Magnitude
	self.Distance = distance
	return distance
end

function Guide.Stop(self: any)
	self.Active = false
end

function Guide.IsActive(self: any): boolean
	return self.Active
end

function Guide.Destroy(self: any)
	self:Stop()
	self.Target = nil
end

-- Angle (degrés, 0 = droit devant, + = à droite) de la cible vue de la caméra
function TownArrival.Bearing(camera: Camera, from: Vector3, target: Vector3): number
	local look = flat(camera.CFrame.LookVector)
	local to = flat(target - from)
	if look.Magnitude < 0.01 or to.Magnitude < 0.01 then
		return 0
	end
	look, to = look.Unit, to.Unit
	local cross = look.X * to.Z - look.Z * to.X
	local dot = look:Dot(to)
	return math.deg(math.atan2(cross, dot))
end

return TownArrival
