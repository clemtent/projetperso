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
local INTRO_TIME = 4.2
local END_BACK, END_UP, END_AHEAD = 14, 7, 26

----------------------------------------------------------------------
-- Chemin du survol
----------------------------------------------------------------------

export type Path = {
	Plaza: Vector3,
	Entrance: Vector3,
	StartAngle: number,
	EndAngle: number,
	StartRadius: number,
	EndRadius: number,
	StartHeight: number,
	BaseY: number,
	EndLook: Vector3,
	EndCFrame: CFrame,
}

local function flat(v: Vector3): Vector3
	return Vector3.new(v.X, 0, v.Z)
end

-- entrance : CFrame d'arrivée (pieds), plaza : centre de la place
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
	local rel = flat(camEnd - plaza)
	local endRadius = math.max(rel.Magnitude, 4)
	local endAngle = math.atan2(rel.Z, rel.X)
	return {
		Plaza = plaza,
		Entrance = e,
		-- (on part de l'autre côté de la place : un bon tiers de tour)
		StartAngle = endAngle + math.rad(150),
		EndAngle = endAngle,
		StartRadius = math.max(endRadius * 0.85, 150),
		EndRadius = endRadius,
		StartHeight = math.max(150, endRadius * 0.7),
		BaseY = e.Y,
		EndLook = lookEnd,
		EndCFrame = CFrame.lookAt(camEnd, lookEnd),
	}
end

local function easeInOut(t: number): number
	return 0.5 - 0.5 * math.cos(math.pi * math.clamp(t, 0, 1))
end

-- Caméra au temps t (0..1) du survol
function TownArrival.CameraAt(path: Path, t: number): CFrame
	if t >= 1 then
		return path.EndCFrame
	end
	local u = easeInOut(t)
	local angle = path.StartAngle + (path.EndAngle - path.StartAngle) * u
	local radius = path.StartRadius + (path.EndRadius - path.StartRadius) * u
	-- (reste haut longtemps, descend à la fin)
	local height = path.StartHeight + (END_UP - path.StartHeight) * (u ^ 1.7)
	local position = Vector3.new(path.Plaza.X + math.cos(angle) * radius, path.BaseY + height, path.Plaza.Z + math.sin(angle) * radius)
	local lookBlend = u ^ 2.4
	local look = path.Plaza:Lerp(path.EndLook, lookBlend)
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
		marker.Size = UDim2.fromOffset(190, 78)
		marker.StudsOffsetWorldSpace = Vector3.new(0, 15, 0)
		marker.AlwaysOnTop = true
		marker.LightInfluence = 0
		marker.MaxDistance = 2000
		marker.Adornee = part
		local pill = Instance.new("TextLabel")
		pill.Name = "Pill"
		pill.AnchorPoint = Vector2.new(0.5, 0)
		pill.Position = UDim2.fromScale(0.5, 0)
		pill.Size = UDim2.fromOffset(180, 42)
		pill.BackgroundColor3 = Color3.fromRGB(255, 96, 160)
		pill.Font = Enum.Font.FredokaOne
		pill.TextSize = 24
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
		tip.Position = UDim2.new(0.5, 0, 0, 44)
		tip.Size = UDim2.fromOffset(20, 20)
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
	source.CFrame = CFrame.new(0, -1.5, 0) * AXIS_UP
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
	beam.Width0 = 0.5
	beam.Width1 = 1.6
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
