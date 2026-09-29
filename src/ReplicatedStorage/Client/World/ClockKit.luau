--[[
	ClockKit (ModuleScript)
	Emplacement : ReplicatedStorage > Client > World > ClockKit

	🕰️ Dopamine Town (v9.9, SHOPS99) : de VRAIES horloges pour la ville
	(mairie, MégaDopa, boutiques, place), construites côté client.
	  - cadran réaliste : fond crème légèrement dégradé (SurfaceGui peu
	    sensible à la lumière : le cadran reste lisible et doucement
	    « rétroéclairé » la nuit, sans aucune vraie lumière), anneau des
	    minutes (60 traits, les heures plus épais), chiffres romains
	    (IIII comme les vraies horloges) ou arabes, petite marque ;
	  - aiguilles en 3D : heures et minutes en acier noirci avec pointe en
	    losange, trotteuse rouge avec contrepoids, cache-axe doré ;
	  - L'HEURE RÉELLE : workspace:GetServerTimeNow() (même instant pour
	    tout le monde) affichée à l'heure locale du joueur (os.date) ; la
	    trotteuse avance d'un cran chaque seconde avec un petit rebond,
	    les minutes et les heures glissent en continu ;
	  - styles : "Tower" (cadran posé sur une façade existante : pas de
	    boîtier), "Wall" (horloge murale : boîtier, verre bombé),
	    "Station" (horloge de gare suspendue à deux faces dos à dos).
	Aucune lumière, aucun son, aucun Neon. ~10 pièces par face.

	API :
	  ClockKit.Build(parent, frame, diameter, opts?) -> Clock
	    frame : CFrame au CENTRE de la surface du cadran, LookVector = vers
	            celui qui regarde (sortant du mur), UpVector = haut du cadran
	    opts  : { Style = "Tower" | "Wall" | "Station", Numerals = "Roman" |
	              "Arabic", Dial = Color3, Case = Color3, CaseMaterial =
	              Enum.Material, Brand = string?, MaxDistance = number,
	              Name = string }
	  ClockKit.Update(clock, now?)   pose les aiguilles (now = temps serveur)
	  ClockKit.Angles(now) -> (heure, minute, seconde) en radians
	  ClockKit.Destroy(clock)
]]

local ClockKit = {}

local M = Enum.Material
local rgb = Color3.fromRGB

export type Clock = {
	Model: Model,
	Parts: { BasePart },
	Offsets: { CFrame },
	Hands: { number }, -- 1 heures, 2 minutes, 3 secondes (par pièce)
	Depths: { number }, -- avancée de chaque pièce vers le regard
	Faces: { CFrame },
	FacePart: { number }, -- index de la face de chaque pièce
	Pos: Vector3,
	Diameter: number,
	Last: number,
}

local ROMAN = { "I", "II", "III", "IIII", "V", "VI", "VII", "VIII", "IX", "X", "XI", "XII" }

local function part(parent: Instance, name: string, size: Vector3, cf: CFrame, color: Color3, material: Enum.Material?, shape: Enum.PartType?): BasePart
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
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	if shape then
		p.Shape = shape
	end
	p.Parent = parent
	return p
end

-- Cylindre dont l'axe suit le Z local de `cf` (disques face au regard)
local function disc(parent: Instance, name: string, cf: CFrame, diameter: number, depth: number, color: Color3, material: Enum.Material?): BasePart
	return part(parent, name, Vector3.new(depth, diameter, diameter), cf * CFrame.Angles(0, math.rad(90), 0), color, material, Enum.PartType.Cylinder)
end

-- Heure locale (du joueur) de l'instant serveur `now`
function ClockKit.Angles(now: number): (number, number, number)
	local whole = math.floor(now)
	local frac = now - whole
	local t = os.date("*t", whole) :: any
	local hour = tonumber(t.hour) or 0
	local minute = tonumber(t.min) or 0
	local second = tonumber(t.sec) or 0
	-- trotteuse : un cran par seconde, 0,14 s de mouvement avec un léger rebond
	local k = math.clamp(frac / 0.14, 0, 1)
	local ease = 1 + 2.2 * (k - 1) ^ 3 + 1.2 * (k - 1) ^ 2
	if k >= 1 then
		ease = 1
	end
	local s = second - 1 + ease
	local m = minute + (second + frac) / 60
	local h = (hour % 12) + m / 60
	return h / 12 * math.pi * 2, m / 60 * math.pi * 2, s / 60 * math.pi * 2
end

-- Cadran (SurfaceGui sur une pièce invisible juste devant la surface)
local function dialGui(carrier: BasePart, opts: { [string]: any }, diameter: number)
	local pps = math.clamp(420 / diameter, 20, 400)
	local gui = Instance.new("SurfaceGui")
	gui.Name = "Dial"
	gui.Face = Enum.NormalId.Front
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = pps
	gui.LightInfluence = 0.35
	gui.Brightness = 1
	gui.MaxDistance = opts.MaxDistance or 300
	gui.Parent = carrier
	local px = diameter * pps
	local face = Instance.new("Frame")
	face.Name = "Face"
	face.Size = UDim2.fromScale(1, 1)
	face.BackgroundColor3 = opts.Dial or rgb(250, 244, 226)
	face.BorderSizePixel = 0
	face.Parent = gui
	local round = Instance.new("UICorner")
	round.CornerRadius = UDim.new(0.5, 0)
	round.Parent = face
	local grad = Instance.new("UIGradient")
	grad.Color = ColorSequence.new(Color3.new(1, 1, 1), rgb(226, 220, 204))
	grad.Rotation = 70
	grad.Parent = face
	-- anneau extérieur (chemin de fer)
	local ring = Instance.new("Frame")
	ring.Name = "ChapterRing"
	ring.AnchorPoint = Vector2.new(0.5, 0.5)
	ring.Position = UDim2.fromScale(0.5, 0.5)
	ring.Size = UDim2.fromScale(0.9, 0.9)
	ring.BackgroundTransparency = 1
	ring.Parent = face
	local rc = Instance.new("UICorner")
	rc.CornerRadius = UDim.new(0.5, 0)
	rc.Parent = ring
	local stroke = Instance.new("UIStroke")
	stroke.Color = rgb(40, 36, 44)
	stroke.Thickness = math.max(1, px * 0.006)
	stroke.Parent = ring
	local ink = rgb(30, 28, 36)
	for i = 0, 59 do
		local a = i / 60 * math.pi * 2
		local hourMark = i % 5 == 0
		local r = hourMark and 0.425 or 0.43
		local tick = Instance.new("Frame")
		tick.Name = "Tick"
		tick.AnchorPoint = Vector2.new(0.5, 0.5)
		tick.BorderSizePixel = 0
		tick.BackgroundColor3 = ink
		tick.Position = UDim2.fromScale(0.5 + math.sin(a) * r, 0.5 - math.cos(a) * r)
		tick.Size = hourMark and UDim2.fromScale(0.018, 0.06) or UDim2.fromScale(0.006, 0.03)
		tick.Rotation = math.deg(a)
		tick.Parent = face
	end
	local roman = opts.Numerals ~= "Arabic"
	for i = 1, 12 do
		local a = i / 12 * math.pi * 2
		local r = 0.33
		local l = Instance.new("TextLabel")
		l.Name = "Numeral"
		l.AnchorPoint = Vector2.new(0.5, 0.5)
		l.BackgroundTransparency = 1
		l.Position = UDim2.fromScale(0.5 + math.sin(a) * r, 0.5 - math.cos(a) * r)
		l.Size = UDim2.fromScale(roman and 0.16 or 0.12, 0.11)
		l.Font = roman and Enum.Font.Merriweather or Enum.Font.GothamBold
		l.TextScaled = true
		l.Text = roman and ROMAN[i] or tostring(i)
		l.TextColor3 = ink
		l.Parent = face
	end
	if opts.Brand then
		local b = Instance.new("TextLabel")
		b.Name = "Brand"
		b.AnchorPoint = Vector2.new(0.5, 0.5)
		b.BackgroundTransparency = 1
		b.Position = UDim2.fromScale(0.5, 0.68)
		b.Size = UDim2.fromScale(0.36, 0.06)
		b.Font = Enum.Font.Merriweather
		b.TextScaled = true
		b.Text = tostring(opts.Brand)
		b.TextColor3 = rgb(120, 100, 80)
		b.Parent = face
	end
end

-- Aiguille : liste de { pièce, repère dans le repère de l'aiguille }
local function hand(model: Model, list: { any }, kind: number, name: string, length: number, width: number, tail: number, thick: number, color: Color3, tip: number?)
	local shaft = part(model, name, Vector3.new(width, length + tail, thick), CFrame.new(), color, M.Metal)
	table.insert(list, { shaft, kind, CFrame.new(0, (length - tail) / 2, 0) })
	if tip then
		-- pointe en losange (bloc tourné de 45°)
		local d = part(model, name .. "Tip", Vector3.new(tip, tip, thick), CFrame.new(), color, M.Metal)
		table.insert(list, { d, kind, CFrame.new(0, length * 0.8, 0) * CFrame.Angles(0, 0, math.rad(45)) })
	end
end

function ClockKit.Build(parent: Instance, frame: CFrame, diameter: number, opts: { [string]: any }?): Clock
	local o = opts or {}
	local style = o.Style or "Wall"
	local model = Instance.new("Model")
	model.Name = o.Name or "Clock"
	local D = diameter
	local thick = math.clamp(D * 0.012, 0.03, 0.1)
	local gap = math.max(0.02, D * 0.004)
	local faces: { CFrame } = {}
	if style == "Station" then
		local depth = math.max(0.3, D * 0.16)
		disc(model, "Case", frame * CFrame.new(0, 0, depth / 2), D * 1.12, depth, o.Case or rgb(46, 48, 58), o.CaseMaterial or M.Metal)
		table.insert(faces, frame)
		table.insert(faces, frame * CFrame.new(0, 0, depth) * CFrame.Angles(0, math.pi, 0))
		-- potence : tige + collier
		local top = frame * CFrame.new(0, D * 0.56, depth / 2)
		part(model, "Hanger", Vector3.new(0.12, math.max(0.6, D * 0.3), 0.12), top * CFrame.new(0, math.max(0.6, D * 0.3) / 2, 0), o.Case or rgb(46, 48, 58), M.Metal)
		disc(model, "Collar", top * CFrame.new(0, 0.05, 0) * CFrame.Angles(math.rad(90), 0, 0), 0.34, 0.14, rgb(200, 170, 90), M.Metal)
	elseif style == "Wall" then
		local depth = math.max(0.12, D * 0.12)
		disc(model, "Case", frame * CFrame.new(0, 0, depth / 2), D * 1.1, depth, o.Case or rgb(60, 44, 34), o.CaseMaterial or M.Wood)
		table.insert(faces, frame)
	else
		table.insert(faces, frame)
	end
	local list: { any } = {}
	local facePart: { number } = {}
	for index, f in ipairs(faces) do
		-- (support invisible du cadran, 0,02 devant la surface)
		local carrier = part(model, "DialCarrier", Vector3.new(D * 0.98, D * 0.98, 0.02), f * CFrame.new(0, 0, -0.03), Color3.new(1, 1, 1))
		carrier.Transparency = 1
		dialGui(carrier, o, D * 0.98)
		local before = #list
		local ink = rgb(26, 24, 30)
		hand(model, list, 1, "HourHand", D * 0.25, D * 0.04, D * 0.06, thick, ink, D * 0.075)
		hand(model, list, 2, "MinuteHand", D * 0.38, D * 0.026, D * 0.07, thick, ink, D * 0.05)
		hand(model, list, 3, "SecondHand", D * 0.41, math.max(0.02, D * 0.01), D * 0.12, thick * 0.7, rgb(206, 40, 44))
		local weight = part(model, "SecondWeight", Vector3.new(D * 0.05, D * 0.05, thick * 0.7), CFrame.new(), rgb(206, 40, 44), M.Metal, Enum.PartType.Cylinder)
		weight.Size = Vector3.new(thick * 0.7, D * 0.05, D * 0.05)
		table.insert(list, { weight, 3, CFrame.new(0, -D * 0.09, 0) * CFrame.Angles(0, math.rad(90), 0) })
		for k = before + 1, #list do
			facePart[k] = index
		end
		-- cache-axe doré (devant les trois aiguilles)
		local hub = -(0.04 + gap * 4 + thick * 3.2)
		disc(model, "Hub", f * CFrame.new(0, 0, hub), D * 0.05, thick, rgb(214, 178, 96), M.Metal)
		if style ~= "Tower" then
			local lens = disc(model, "Lens", f * CFrame.new(0, 0, hub - thick - gap * 2), D * 1.0, 0.03, rgb(230, 240, 250), M.Glass)
			lens.Transparency = 0.86
			lens.Reflectance = 0.15
		end
	end
	local parts, offsets, hands, depths = {}, {}, {}, {}
	for k, entry in ipairs(list) do
		parts[k] = entry[1]
		hands[k] = entry[2]
		offsets[k] = entry[3]
		-- profondeur de chaque aiguille vers le regard (heures au fond, trotteuse devant)
		depths[k] = 0.04 + gap * entry[2] + thick * (entry[2] - 0.5)
		facePart[k] = facePart[k] or 1
	end
	model.Parent = parent
	-- repères des faces « vus de devant » : +X = droite du regard, +Z = vers le regard
	local fronts: { CFrame } = {}
	for i, f in ipairs(faces) do
		fronts[i] = f * CFrame.Angles(0, math.pi, 0)
	end
	local clock: Clock = {
		Model = model,
		Parts = parts,
		Offsets = offsets,
		Hands = hands,
		Depths = depths,
		Faces = fronts,
		FacePart = facePart,
		Pos = frame.Position,
		Diameter = D,
		Last = -1,
	}
	ClockKit.Update(clock)
	return clock
end

local function serverNow(): number
	local ok, t = pcall(function()
		return workspace:GetServerTimeNow()
	end)
	if ok and type(t) == "number" and t > 1e8 then
		return t
	end
	return os.time()
end

function ClockKit.Update(clock: Clock, now: number?)
	if not clock.Model.Parent then
		return
	end
	local t = now or serverNow()
	local h, m, s = ClockKit.Angles(t)
	local angles = { h, m, s }
	local frames = table.create(#clock.Parts)
	for k = 1, #clock.Parts do
		-- (vu de devant, sens horaire = rotation de -angle autour du Z du repère)
		frames[k] = clock.Faces[clock.FacePart[k]] * CFrame.new(0, 0, clock.Depths[k]) * CFrame.Angles(0, 0, -angles[clock.Hands[k]]) * clock.Offsets[k]
	end
	workspace:BulkMoveTo(clock.Parts, frames, Enum.BulkMoveMode.FireCFrameChanged)
	clock.Last = t
end

function ClockKit.Destroy(clock: Clock)
	clock.Model:Destroy()
end

return ClockKit
