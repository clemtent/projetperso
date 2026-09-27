--[[
	TownArrival (ModuleScript)
	Emplacement : ReplicatedStorage > Client > World > TownArrival

	🎬 Dopamine Town : l'arrivée.
	  - Intro(...) : court survol de la ville par la caméra (~4,2 s, 1re
	    arrivée de la session seulement, passable) : on part haut au-dessus
	    de la ville, on tourne autour de la place en descendant, et on finit
	    juste DERRIÈRE l'avatar, à la porte de la ville, regard vers la place.
	    Caméra Scriptable pendant le survol, rendue à Roblox (Custom) à la fin.
	  - Guide : un arc lumineux (Beam) de l'avatar jusqu'à SA porte + un
	    repère "🏠 Ta maison" au-dessus, jusqu'à ce qu'on y soit ; la
	    boussole du HUD est calculée ici (Bearing).
	Rien n'est créé par image : le survol ne fait que des calculs de CFrame,
	le guide se met à jour ~4 fois / s.
]]

local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Locale = require(ReplicatedStorage.Shared.Locale)

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

local BEAM_COLOR = ColorSequence.new({
	ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 120, 190)),
	ColorSequenceKeypoint.new(0.5, Color3.fromRGB(255, 214, 120)),
	ColorSequenceKeypoint.new(1, Color3.fromRGB(150, 220, 255)),
})
local BEAM_ALPHA = NumberSequence.new({
	NumberSequenceKeypoint.new(0, 0.85),
	NumberSequenceKeypoint.new(0.12, 0.25),
	NumberSequenceKeypoint.new(0.88, 0.15),
	NumberSequenceKeypoint.new(1, 0.1),
})
-- (axe X de l'attache vers le haut : l'arc monte au lieu de traverser les murs)
local AXIS_UP = CFrame.fromMatrix(Vector3.zero, Vector3.new(0, 1, 0), Vector3.new(1, 0, 0))

function TownArrival.Guide(parent: Instance): any
	local self = setmetatable({
		Parent = parent,
		Anchor = nil :: BasePart?,
		Target = nil :: Attachment?,
		Source = nil :: Attachment?,
		Beam = nil :: Beam?,
		Marker = nil :: BillboardGui?,
		Active = false,
		Distance = math.huge,
	}, Guide)
	return self
end

function Guide.Build(self: any, target: Vector3)
	local anchor = self.Anchor
	if not anchor then
		local part = Instance.new("Part")
		part.Name = "HomeGuide"
		part.Anchored = true
		part.CanCollide = false
		part.CanQuery = false
		part.CanTouch = false
		part.CastShadow = false
		part.Transparency = 1
		part.Size = Vector3.new(1, 1, 1)
		part.Parent = self.Parent
		anchor = part
		self.Anchor = part
		local attachment = Instance.new("Attachment")
		attachment.Name = "GuideEnd"
		attachment.CFrame = AXIS_UP
		attachment.Parent = part
		self.Target = attachment
		-- repère au-dessus de la porte
		local marker = Instance.new("BillboardGui")
		marker.Name = "HomeMarker"
		marker.Size = UDim2.fromOffset(160, 66)
		marker.StudsOffsetWorldSpace = Vector3.new(0, 15, 0)
		marker.AlwaysOnTop = true
		marker.LightInfluence = 0
		marker.MaxDistance = 2000
		marker.Adornee = part
		local pill = Instance.new("TextLabel")
		pill.Name = "Pill"
		pill.AnchorPoint = Vector2.new(0.5, 0)
		pill.Position = UDim2.fromScale(0.5, 0)
		pill.Size = UDim2.fromOffset(152, 36)
		pill.BackgroundColor3 = Color3.fromRGB(255, 96, 160)
		pill.Font = Enum.Font.FredokaOne
		pill.TextSize = 20
		pill.TextColor3 = Color3.new(1, 1, 1)
		pill.Text = Locale.T("🏠 Your house")
		pill.Parent = marker
		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(1, 0)
		corner.Parent = pill
		local stroke = Instance.new("UIStroke")
		stroke.Color = Color3.new(1, 1, 1)
		stroke.Thickness = 3
		stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
		stroke.Parent = pill
		-- petite flèche vers le bas (carré tourné, moitié cachée par la pastille)
		local tip = Instance.new("Frame")
		tip.Name = "Tip"
		tip.AnchorPoint = Vector2.new(0.5, 0.5)
		tip.Position = UDim2.new(0.5, 0, 0, 38)
		tip.Size = UDim2.fromOffset(17, 17)
		tip.Rotation = 45
		tip.BackgroundColor3 = Color3.fromRGB(255, 96, 160)
		tip.BorderSizePixel = 0
		tip.ZIndex = 0
		tip.Parent = marker
		marker.Parent = part
		self.Marker = marker
	end
	(anchor :: BasePart).CFrame = CFrame.new(target + Vector3.new(0, 1.5, 0))
end

function Guide.Start(self: any, character: Model?, target: Vector3)
	self:Build(target)
	self.Active = true
	self.Distance = math.huge
	self:Attach(character)
	if self.Marker then
		self.Marker.Enabled = true
	end
end

-- (nouveau personnage : l'arc repart de lui)
function Guide.Attach(self: any, character: Model?)
	if self.Source then
		self.Source:Destroy()
		self.Source = nil
	end
	if self.Beam then
		self.Beam:Destroy()
		self.Beam = nil
	end
	if not self.Active or not character then
		return
	end
	local root = character:FindFirstChild("HumanoidRootPart")
	if not root or not root:IsA("BasePart") then
		return
	end
	local source = Instance.new("Attachment")
	source.Name = "TownGuideStart"
	source.CFrame = CFrame.new(0, -2.6, -2) * AXIS_UP
	source.Parent = root
	self.Source = source
	local beam = Instance.new("Beam")
	beam.Name = "HomeBeam"
	beam.Attachment0 = source
	beam.Attachment1 = self.Target
	beam.Color = BEAM_COLOR
	beam.Transparency = BEAM_ALPHA
	beam.LightEmission = 0.6
	beam.LightInfluence = 0
	beam.FaceCamera = true
	beam.Segments = 48
	beam.Width0 = 0.9
	beam.Width1 = 2.4
	beam.CurveSize0 = 10
	beam.CurveSize1 = -10
	beam.Parent = self.Anchor
	self.Beam = beam
end

-- ~4 fois / s : hauteur de l'arc selon la distance ; renvoie la distance
function Guide.Update(self: any, from: Vector3?): number
	local anchor = self.Anchor
	if not self.Active or not anchor or not from then
		return math.huge
	end
	local distance = (flat(anchor.Position - from)).Magnitude
	self.Distance = distance
	local beam = self.Beam
	if beam then
		local curve = math.clamp(distance * 0.3, 3, 55)
		beam.CurveSize0 = curve
		beam.CurveSize1 = -curve
	end
	return distance
end

function Guide.Stop(self: any)
	self.Active = false
	if self.Beam then
		self.Beam:Destroy()
		self.Beam = nil
	end
	if self.Source then
		self.Source:Destroy()
		self.Source = nil
	end
	if self.Marker then
		self.Marker.Enabled = false
	end
end

function Guide.IsActive(self: any): boolean
	return self.Active
end

function Guide.Destroy(self: any)
	self:Stop()
	if self.Anchor then
		self.Anchor:Destroy()
		self.Anchor = nil
	end
	self.Marker = nil
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
