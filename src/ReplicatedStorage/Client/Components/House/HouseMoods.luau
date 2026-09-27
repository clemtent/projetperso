--[[
	HouseMoods (ModuleScript)
	Emplacement : ReplicatedStorage > Client > Components > House > HouseMoods

	(v9.1) Ambiance lumineuse d'une pièce (Config.House.Moods, room.Mood) :
	un voile coloré en dégradé (Tint -> Tint2, force Amount) posé sur la
	pièce + un petit effet animé (Effect) :
	  Rays     : rayons de lumière douce qui respirent
	  Sparkles : étincelles qui scintillent
	  Hearts   : petits cœurs qui montent
	  Leaves   : feuilles qui tombent en tourbillonnant
	  Bubbles  : bulles qui montent en ondulant
	  Disco    : taches de couleur qui tournent
	  Aurora   : voiles d'aurore boréale qui ondulent
	  Rainbow  : reflet arc-en-ciel qui balaie la pièce
	Peu de Frames (≤ 14 particules), animation à 30 Hz au plus, rien
	n'est créé pendant l'animation.

	API :
	  HouseMoods.new(parent, z) -> Mood
	    mood.Frame
	    mood.Set(entry?, width, height)   (nil / Amount 0 et Effect None = rien)
	    mood.Update(dt)
	    mood.Destroy()
	  HouseMoods.Static(container, width, height, entry, z?) : aperçu fixe
	    (boutique, petites pièces de la vue d'ensemble)
]]

local HousePatterns = require(script.Parent.HousePatterns)

local HouseMoods = {}

local WHITE = Color3.new(1, 1, 1)
local Box = HousePatterns.Box
local Circle = HousePatterns.Circle
local Heart = HousePatterns.Heart
local Sparkle = HousePatterns.Sparkle
local Round = HousePatterns.Round

type Entry = { Tint: Color3?, Tint2: Color3?, Amount: number?, Effect: string?, Id: string? }

type Particle = { Frame: GuiObject, X: number, Y: number, Speed: number, Phase: number, Size: number }

export type Mood = {
	Frame: Frame,
	Set: (entry: Entry?, width: number, height: number) -> (),
	Update: (dt: number) -> (),
	Destroy: () -> (),
}

local RAINBOW = ColorSequence.new({
	ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 120, 150)),
	ColorSequenceKeypoint.new(0.2, Color3.fromRGB(255, 190, 100)),
	ColorSequenceKeypoint.new(0.4, Color3.fromRGB(255, 236, 120)),
	ColorSequenceKeypoint.new(0.6, Color3.fromRGB(140, 226, 150)),
	ColorSequenceKeypoint.new(0.8, Color3.fromRGB(130, 190, 255)),
	ColorSequenceKeypoint.new(1, Color3.fromRGB(200, 150, 255)),
})
local DISCO = {
	Color3.fromRGB(255, 90, 180),
	Color3.fromRGB(90, 200, 255),
	Color3.fromRGB(255, 226, 90),
	Color3.fromRGB(150, 255, 150),
	Color3.fromRGB(200, 120, 255),
	Color3.fromRGB(255, 150, 90),
}

local function noise(a: number, b: number): number
	local value = math.sin(a * 12.9898 + b * 78.233) * 43758.5453
	return value - math.floor(value)
end

-- Voile en dégradé (Tint en haut, Tint2 en bas)
local function veil(parent: Instance, width: number, height: number, entry: Entry, z: number): Frame
	local amount = math.clamp(tonumber(entry.Amount) or 0, 0, 0.9)
	local frame = Box(parent, 0, 0, width, height, WHITE, 1 - amount, z)
	frame.Name = "Veil"
	local gradient = Instance.new("UIGradient")
	gradient.Rotation = 90
	gradient.Color = ColorSequence.new(entry.Tint or WHITE, entry.Tint2 or entry.Tint or WHITE)
	gradient.Parent = frame
	return frame
end

-- Particules / formes de l'effet (positions relatives 0..1)
local function buildEffect(parent: Frame, width: number, height: number, entry: Entry, animated: boolean): ({ Particle }, { GuiObject })
	local particles: { Particle } = {}
	local extras: { GuiObject } = {}
	local effect = entry.Effect or "None"
	local tint = entry.Tint2 or entry.Tint or WHITE
	local function add(frame: GuiObject, x: number, y: number, speed: number, phase: number, size: number)
		table.insert(particles, { Frame = frame, X = x, Y = y, Speed = speed, Phase = phase, Size = size })
	end
	if effect == "Rays" then
		for index = 0, 2 do
			local ray = Box(parent, 0, 0, width * 0.16, height * 1.5, entry.Tint or WHITE, 0.8, 2)
			ray.AnchorPoint = Vector2.new(0.5, 0)
			ray.Position = UDim2.fromOffset(width * (0.12 + index * 0.16), -height * 0.2)
			ray.Rotation = -28
			local fade = Instance.new("UIGradient")
			fade.Rotation = 90
			fade.Transparency = NumberSequence.new(0.1, 1)
			fade.Parent = ray
			table.insert(extras, ray)
		end
	elseif effect == "Sparkles" then
		for index = 1, 12 do
			local size = 10 + noise(index, 1) * 14
			local holder = Box(parent, 0, 0, size, size, WHITE, 1, 3)
			Sparkle(holder, size / 2, size / 2, size, index % 3 == 0 and tint or WHITE, 0.1, 1)
			local scale = Instance.new("UIScale")
			scale.Parent = holder
			add(holder, noise(index, 2), noise(3, index) * 0.9, 0, noise(index, 4) * 6, size)
		end
	elseif effect == "Hearts" then
		for index = 1, 9 do
			local size = 12 + noise(index, 1) * 10
			local holder = Box(parent, 0, 0, size, size, WHITE, 1, 3)
			Heart(holder, size / 2, size / 2, size, index % 2 == 0 and Color3.fromRGB(255, 150, 200) or WHITE, 0.2, 1)
			add(holder, noise(index, 2), noise(3, index), 0.05 + noise(index, 5) * 0.05, noise(index, 4) * 6, size)
		end
	elseif effect == "Leaves" then
		for index = 1, 9 do
			local size = 12 + noise(index, 1) * 8
			local leaf = Circle(parent, 0, 0, size, size * 0.55, index % 3 == 0 and Color3.fromRGB(255, 214, 120) or Color3.fromRGB(130, 206, 120), 0.1, 3)
			add(leaf, noise(index, 2), noise(3, index), 0.05 + noise(index, 5) * 0.04, noise(index, 4) * 6, size)
		end
	elseif effect == "Bubbles" then
		for index = 1, 12 do
			local size = 8 + noise(index, 1) * 16
			local bubble = Circle(parent, 0, 0, size, size, WHITE, 0.75, 3)
			local ring = Instance.new("UIStroke")
			ring.Color = WHITE
			ring.Transparency = 0.25
			ring.Thickness = 1.5
			ring.Parent = bubble
			Circle(bubble, size * 0.3, size * 0.3, size * 0.25, size * 0.2, WHITE, 0.2, 2)
			add(bubble, noise(index, 2), noise(3, index), 0.06 + noise(index, 5) * 0.06, noise(index, 4) * 6, size)
		end
	elseif effect == "Disco" then
		for index = 1, 7 do
			local size = width * (0.12 + noise(index, 1) * 0.08)
			local spot = Circle(parent, 0, 0, size, size * 0.8, DISCO[(index - 1) % #DISCO + 1], 0.62, 3)
			add(spot, noise(index, 2), 0.2 + noise(3, index) * 0.7, 0.3 + noise(index, 5) * 0.3, noise(index, 4) * 6, size)
		end
	elseif effect == "Aurora" then
		for index = 0, 2 do
			local band = Box(parent, 0, 0, width * 1.3, height * 0.22, index == 1 and Color3.fromRGB(190, 120, 255) or Color3.fromRGB(90, 240, 180), 0.55, 2)
			band.AnchorPoint = Vector2.new(0.5, 0.5)
			Round(band)
			local fade = Instance.new("UIGradient")
			fade.Rotation = 90
			fade.Transparency = NumberSequence.new({
				NumberSequenceKeypoint.new(0, 1),
				NumberSequenceKeypoint.new(0.5, 0.2),
				NumberSequenceKeypoint.new(1, 1),
			})
			fade.Parent = band
			add(band, 0.5, 0.12 + index * 0.12, 0.4 + index * 0.15, index * 1.7, 0)
		end
	elseif effect == "Rainbow" then
		local band = Box(parent, 0, 0, width * 0.7, height * 1.6, WHITE, 0.72, 2)
		band.AnchorPoint = Vector2.new(0.5, 0.5)
		band.Rotation = 24
		local gradient = Instance.new("UIGradient")
		gradient.Color = RAINBOW
		gradient.Parent = band
		add(band, 0.5, 0.5, 0.06, 0, 0)
	end
	-- Position de départ (aperçu fixe : la seule position)
	for _, particle in ipairs(particles) do
		particle.Frame.Position = UDim2.fromOffset(particle.X * width, particle.Y * height)
		if particle.Frame.AnchorPoint == Vector2.zero then
			particle.Frame.AnchorPoint = Vector2.new(0.5, 0.5)
		end
	end
	local _ = animated
	return particles, extras
end

function HouseMoods.new(parent: Instance, z: number): Mood
	local frame = Instance.new("Frame")
	frame.Name = "Mood"
	frame.BackgroundTransparency = 1
	frame.BorderSizePixel = 0
	frame.Size = UDim2.fromScale(1, 1)
	frame.ClipsDescendants = true
	frame.ZIndex = z
	frame.Parent = parent

	local particles: { Particle } = {}
	local extras: { GuiObject } = {}
	local effect = "None"
	local key = ""
	local width, height = 100, 100
	local clock = 0
	local pending = 0

	local mood = {} :: Mood
	mood.Frame = frame

	function mood.Set(entry: Entry?, newWidth: number, newHeight: number)
		local e: Entry = entry or {}
		local newKey = string.format("%s|%d|%d", tostring(e.Id), newWidth, newHeight)
		if newKey == key then
			return
		end
		key = newKey
		width, height = newWidth, newHeight
		for _, child in ipairs(frame:GetChildren()) do
			child:Destroy()
		end
		table.clear(particles)
		table.clear(extras)
		effect = e.Effect or "None"
		local active = (tonumber(e.Amount) or 0) > 0 or effect ~= "None"
		frame.Visible = active
		if not active then
			return
		end
		veil(frame, width, height, e, 1)
		particles, extras = buildEffect(frame, width, height, e, true)
		mood.Update(0)
	end

	function mood.Update(dt: number)
		clock += dt
		pending += dt
		if dt > 0 and pending < 1 / 30 then
			return
		end
		pending = 0
		if not frame.Visible or #particles + #extras == 0 then
			return
		end
		local t = clock
		if effect == "Rays" then
			for index, ray in ipairs(extras) do
				(ray :: Frame).BackgroundTransparency = 0.78 + 0.1 * math.sin(t * 0.8 + index * 1.3)
			end
		elseif effect == "Sparkles" then
			for _, p in ipairs(particles) do
				local wave = 0.5 + 0.5 * math.sin(t * 2.2 + p.Phase)
				local scale = p.Frame:FindFirstChildOfClass("UIScale")
				if scale then
					scale.Scale = 0.4 + wave * 0.8
				end
			end
		elseif effect == "Hearts" or effect == "Bubbles" then
			for _, p in ipairs(particles) do
				local y = (p.Y - t * p.Speed) % 1.1
				local x = p.X + math.sin(t * 1.3 + p.Phase) * 0.02
				p.Frame.Position = UDim2.fromOffset(x * width, (y - 0.05) * height)
			end
		elseif effect == "Leaves" then
			for _, p in ipairs(particles) do
				local y = (p.Y + t * p.Speed) % 1.1
				local x = p.X + math.sin(t * 1.1 + p.Phase) * 0.04
				p.Frame.Position = UDim2.fromOffset(x * width, (y - 0.05) * height)
				p.Frame.Rotation = math.sin(t * 2 + p.Phase) * 50
			end
		elseif effect == "Disco" then
			for index, p in ipairs(particles) do
				local a = t * p.Speed + p.Phase
				p.Frame.Position = UDim2.fromOffset((0.5 + math.cos(a) * 0.38 * (0.6 + p.X * 0.4)) * width, (p.Y + math.sin(a * 1.3) * 0.12) * height)
				local color = DISCO[(index + math.floor(t * 1.5)) % #DISCO + 1];
				(p.Frame :: Frame).BackgroundColor3 = color
			end
		elseif effect == "Aurora" then
			for _, p in ipairs(particles) do
				p.Frame.Position = UDim2.fromOffset((0.5 + math.sin(t * 0.3 + p.Phase) * 0.12) * width, (p.Y + math.sin(t * p.Speed + p.Phase) * 0.04) * height)
				p.Frame.Rotation = math.sin(t * 0.4 + p.Phase) * 6
			end
		elseif effect == "Rainbow" then
			for _, p in ipairs(particles) do
				local x = ((t * p.Speed) % 1.6) - 0.3
				p.Frame.Position = UDim2.fromOffset(x * width, 0.5 * height)
			end
		end
	end

	function mood.Destroy()
		table.clear(particles)
		table.clear(extras)
		frame:Destroy()
	end

	return mood
end

-- Aperçu fixe (boutique, mini-pièces) : voile + effet figé
function HouseMoods.Static(container: Instance, width: number, height: number, entry: Entry?, z: number?)
	local old = container:FindFirstChild("MoodStatic")
	if old then
		old:Destroy()
	end
	if not entry or ((tonumber(entry.Amount) or 0) <= 0 and (entry.Effect or "None") == "None") then
		return
	end
	local frame = Instance.new("Frame")
	frame.Name = "MoodStatic"
	frame.BackgroundTransparency = 1
	frame.BorderSizePixel = 0
	frame.Size = UDim2.fromScale(1, 1)
	frame.ClipsDescendants = true
	frame.ZIndex = z or 1
	veil(frame, width, height, entry, 1)
	buildEffect(frame, width, height, entry, false)
	frame.Parent = container
end

return HouseMoods
