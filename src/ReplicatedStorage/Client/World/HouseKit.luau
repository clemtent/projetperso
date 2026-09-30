--[[
	HouseKit (ModuleScript)
	Emplacement : ReplicatedStorage > Client > World > HouseKit

	🚶 Dopamine Town (v9.4) : petit kit de construction des maisons 3D, dans
	le repère LOCAL d'une maison (WorldLayout) : x vers la droite du visiteur,
	y vers le haut (0 = sol de la parcelle), d = profondeur depuis la façade
	(d > 0 = dans la maison, d < 0 = jardin de devant).
	Toutes les pièces sont ancrées, CanTouch = false ; la déco (Solid = false)
	ne bloque ni les avatars ni les rayons ; petites pièces sans ombre.
	Le kit COMPTE ses pièces (kit.Stats.Count ; budget : manoir < 1200) et
	ses vraies lumières (kit.Stats.Lights <= MaxLights).

	API :
	  HouseKit.new(houseCF, folder) -> Kit
	  kit:Box(name, x0, x1, y0, y1, d0, d1, color, material?, opts?) -> BasePart
	  kit:Part(name, size, localCF, color, material?, opts?, className?) -> BasePart
	      (localCF : repère local, axe Z = -d ; voir kit.L)
	  kit.L(x, y, d) -> CFrame local ; kit:World(x, y, d) -> Vector3
	  kit:CylY / CylX / CylD (cylindres verticaux / le long de x / de d)
	  kit:Ball(name, x, y, d, diameter, color, material?, opts?)
	  kit:Slab(name, a, b, width, thick, color, material?, opts?)  (plaque
	      inclinée entre deux points a, b du plan (x fixe) : a = {y, d})
	  kit:Cone(name, x, y0, d, radius, height, sides, color, material?) (flèche
	      à N pans : toits coniques des tours)
	  kit:WallX(name, x0, x1, y0, y1, d0, d1, holes, color, material?, opts?)
	  kit:Light(part, color, range, brightness, kind?) (budget de lumières)
	  kit:Text(part, face, text, color, font?, pps?)  (SurfaceGui)
	  kit:Sub(offsetCF) -> Kit  (même dossier / compteurs, repère décalé)
]]

local HouseKit = {}
HouseKit.__index = HouseKit

local M = Enum.Material

export type Opts = {
	Solid: boolean?, -- collision + rayons (false par défaut pour la déco)
	Query: boolean?, -- rayons seulement (défaut = Solid)
	Shadow: boolean?, -- ombre portée (défaut : true pour les grosses pièces)
	T: number?, -- transparence
	Shape: Enum.PartType?,
}

-- (v10 HOUSE10) Phase = phase de construction ("Foundation" | "Walls" | "Roof" |
-- "Openings" | "Garden") notée en attribut BuildPhase sur chaque pièce créée
-- (animation de construction de CONSTRUCT10)
export type Stats = { Count: number, Lights: number, MaxLights: number, Phase: string? }

export type Kit = typeof(setmetatable({} :: {
	CF: CFrame,
	Folder: Instance,
	Stats: Stats,
	L: (x: number, y: number, d: number) -> CFrame,
}, HouseKit))

-- Hauteur du dessus de la pelouse des parcelles (TownMap) : le jardin de
-- devant est posé dessus (HouseKit.Sub)
HouseKit.LAWN = 0.45

local function localCF(x: number, y: number, d: number): CFrame
	return CFrame.new(x, y, -d)
end

function HouseKit.new(houseCF: CFrame, folder: Instance, maxLights: number?): Kit
	local self = setmetatable({
		CF = houseCF,
		Folder = folder,
		Stats = { Count = 0, Lights = 0, MaxLights = maxLights or 4 },
		L = localCF,
	}, HouseKit)
	return self
end

-- Kit décalé (même dossier, mêmes compteurs) : ex. le jardin posé sur la pelouse
function HouseKit.Sub(self: Kit, offset: CFrame, folder: Instance?): Kit
	return setmetatable({
		CF = self.CF * offset,
		Folder = folder or self.Folder,
		Stats = self.Stats,
		L = localCF,
	}, HouseKit)
end

function HouseKit.World(self: Kit, x: number, y: number, d: number): Vector3
	return self.CF * Vector3.new(x, y, -d)
end

-- Pièce au repère local `localCF` (axe Z local = -d)
function HouseKit.Part(self: Kit, name: string, size: Vector3, localCF: CFrame, color: Color3, material: Enum.Material?, opts: Opts?, className: string?): BasePart
	local o: Opts = opts or {}
	local p = Instance.new((className or "Part") :: any) :: BasePart
	p.Name = name
	p.Anchored = true
	p.Size = Vector3.new(math.max(0.05, size.X), math.max(0.05, size.Y), math.max(0.05, size.Z))
	p.CFrame = self.CF * localCF
	p.Color = color
	p.Material = material or M.SmoothPlastic
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	local solid = o.Solid == true
	p.CanCollide = solid
	p.CanQuery = if o.Query ~= nil then o.Query else solid
	p.CanTouch = false
	if o.T then
		p.Transparency = o.T
	end
	local shadow = o.Shadow
	if shadow == nil then
		-- petites pièces : pas d'ombre (performance)
		shadow = math.max(p.Size.X, p.Size.Y, p.Size.Z) > 4
	end
	p.CastShadow = shadow
	if o.Shape and p:IsA("Part") then
		(p :: Part).Shape = o.Shape
	end
	local phase = self.Stats.Phase
	if phase then
		p:SetAttribute("BuildPhase", phase)
	end
	p.Parent = self.Folder
	self.Stats.Count += 1
	return p
end

-- Boîte alignée sur la maison : x0..x1, y0..y1, d0..d1
function HouseKit.Box(self: Kit, name: string, x0: number, x1: number, y0: number, y1: number, d0: number, d1: number, color: Color3, material: Enum.Material?, opts: Opts?): BasePart
	local size = Vector3.new(math.abs(x1 - x0), math.abs(y1 - y0), math.abs(d1 - d0))
	return self:Part(name, size, CFrame.new((x0 + x1) / 2, (y0 + y1) / 2, -(d0 + d1) / 2), color, material, opts)
end

-- Cylindre vertical (pied en y0)
function HouseKit.CylY(self: Kit, name: string, x: number, y0: number, d: number, diameter: number, height: number, color: Color3, material: Enum.Material?, opts: Opts?): BasePart
	return self:Part(name, Vector3.new(height, diameter, diameter), CFrame.new(x, y0 + height / 2, -d) * CFrame.Angles(0, 0, math.pi / 2), color, material,
		HouseKit.With(opts, Enum.PartType.Cylinder))
end

-- Cylindre le long de x (centre x, y, d)
function HouseKit.CylX(self: Kit, name: string, x: number, y: number, d: number, diameter: number, length: number, color: Color3, material: Enum.Material?, opts: Opts?): BasePart
	return self:Part(name, Vector3.new(length, diameter, diameter), CFrame.new(x, y, -d), color, material, HouseKit.With(opts, Enum.PartType.Cylinder))
end

-- Cylindre le long de d (centre x, y, d) : disques face à la rue (horloges, hublots)
function HouseKit.CylD(self: Kit, name: string, x: number, y: number, d: number, diameter: number, length: number, color: Color3, material: Enum.Material?, opts: Opts?): BasePart
	return self:Part(name, Vector3.new(length, diameter, diameter), CFrame.new(x, y, -d) * CFrame.Angles(0, math.pi / 2, 0), color, material,
		HouseKit.With(opts, Enum.PartType.Cylinder))
end

function HouseKit.Ball(self: Kit, name: string, x: number, y: number, d: number, diameter: number, color: Color3, material: Enum.Material?, opts: Opts?): BasePart
	return self:Part(name, Vector3.new(diameter, diameter, diameter), CFrame.new(x, y, -d), color, material, HouseKit.With(opts, Enum.PartType.Ball))
end

function HouseKit.With(opts: Opts?, shape: Enum.PartType): Opts
	local o: any = opts and table.clone(opts) or {}
	o.Shape = shape
	return o
end

-- Plaque inclinée (toits, rampes, limons) entre a = {y, d} et b = {y, d},
-- centrée en x, largeur `width` (le long de x), épaisseur `thick` SOUS la
-- ligne a-b (le dessus de la plaque passe exactement par a et b)
function HouseKit.Slab(self: Kit, name: string, x: number, a: { number }, b: { number }, width: number, thick: number, color: Color3, material: Enum.Material?, opts: Opts?): BasePart
	local pa = Vector3.new(x, a[1], -a[2])
	local pb = Vector3.new(x, b[1], -b[2])
	local along = pb - pa
	local length = along.Magnitude
	local dir = along.Unit
	local right = Vector3.new(1, 0, 0)
	local up = dir:Cross(right)
	if up.Y < 0 then
		up = -up
	end
	local center = (pa + pb) / 2 - up * (thick / 2)
	local cf = CFrame.fromMatrix(center, right, up)
	return self:Part(name, Vector3.new(width, thick, length), cf, color, material, opts)
end

-- Même chose, mais la plaque est inclinée dans le plan (x, y) à d fixe : a = {x, y}
function HouseKit.SlabX(self: Kit, name: string, d: number, a: { number }, b: { number }, depth: number, thick: number, color: Color3, material: Enum.Material?, opts: Opts?): BasePart
	local pa = Vector3.new(a[1], a[2], -d)
	local pb = Vector3.new(b[1], b[2], -d)
	local along = pb - pa
	local dir = along.Unit
	local back = Vector3.new(0, 0, 1)
	local up = back:Cross(dir)
	if up.Y < 0 then
		up = -up
	end
	local center = (pa + pb) / 2 - up * (thick / 2)
	local cf = CFrame.fromMatrix(center, dir, up)
	return self:Part(name, Vector3.new(along.Magnitude, thick, depth), cf, color, material, opts)
end

-- Flèche à `sides` pans (toit conique) : base (rayon) en y0, pointe en y0 + height
function HouseKit.Cone(self: Kit, name: string, x: number, y0: number, d: number, radius: number, height: number, sides: number, color: Color3, material: Enum.Material?)
	local n = math.max(6, sides)
	local apothem = radius * math.cos(math.pi / n)
	local half = radius * math.sin(math.pi / n) -- demi-côté de la base
	local slant = math.sqrt(apothem * apothem + height * height)
	local center = Vector3.new(x, y0, -d)
	local apex = center + Vector3.new(0, height, 0)
	for index = 0, n - 1 do
		local angle = index / n * math.pi * 2
		local u = Vector3.new(math.cos(angle), 0, math.sin(angle)) -- vers l'extérieur
		local b = Vector3.new(-math.sin(angle), 0, math.cos(angle)) -- le long de la base
		local mid = center + u * apothem
		local m = (apex - mid).Unit
		-- chaque pan = deux coins (WedgePart) : angle droit au milieu de la base,
		-- un côté vers la pointe (Y), l'autre vers un coin de la base (-Z)
		for _, s in ipairs({ -1, 1 }) do
			local zAxis = -b * s
			local xAxis = m:Cross(zAxis)
			local pos = mid + m * (slant / 2) + b * s * (half / 2)
			self:Part(name, Vector3.new(0.3, slant, half), CFrame.fromMatrix(pos, xAxis, m, zAxis), color, material, { Shadow = true }, "WedgePart")
		end
	end
end

-- Triangle quelconque (points du repère local { x, y, d }) en deux coins
-- (WedgePart) d'épaisseur `thick`, la face "dessus" passant par les 3 points
-- (le côté `up` = direction qui doit être au-dessus, ex. le ciel pour un toit)
function HouseKit.Triangle(self: Kit, name: string, p1: { number }, p2: { number }, p3: { number }, thick: number, color: Color3, material: Enum.Material?, opts: Opts?)
	local v = { Vector3.new(p1[1], p1[2], -p1[3]), Vector3.new(p2[1], p2[2], -p2[3]), Vector3.new(p3[1], p3[2], -p3[3]) }
	-- base = plus long côté ; C = sommet opposé ; H = pied de la hauteur
	local best, bi = -1, 1
	for i = 1, 3 do
		local a, b = v[i], v[i % 3 + 1]
		local len = (b - a).Magnitude
		if len > best then
			best, bi = len, i
		end
	end
	local A, B, Cc = v[bi], v[bi % 3 + 1], v[(bi + 1) % 3 + 1]
	local ab = (B - A).Unit
	local H = A + ab * (Cc - A):Dot(ab)
	local normal = (B - A):Cross(Cc - A).Unit
	if normal.Y < 0 then
		normal = -normal
	end
	local offset = -normal * (thick / 2)
	local o: Opts = opts and table.clone(opts) or {}
	if o.Shadow == nil then
		o.Shadow = true
	end
	local height = (Cc - H).Magnitude
	if height < 0.02 then
		return
	end
	local yAxis = (Cc - H).Unit
	for _, P in ipairs({ A, B }) do
		local base = (P - H).Magnitude
		if base > 0.02 then
			local zAxis = (H - P).Unit
			local xAxis = yAxis:Cross(zAxis)
			local pos = H + (Cc - H) / 2 + (P - H) / 2 + offset
			self:Part(name, Vector3.new(thick, height, base), CFrame.fromMatrix(pos, xAxis, yAxis, zAxis), color, material, o, "WedgePart")
		end
	end
end

-- Mur plein le long de x avec des ouvertures `holes` = { { x0, x1, y0, y1 } }
function HouseKit.WallX(self: Kit, name: string, x0: number, x1: number, y0: number, y1: number, d0: number, d1: number, holes: { { number } }, color: Color3,
	material: Enum.Material?, opts: Opts?)
	local sorted = table.clone(holes)
	table.sort(sorted, function(a, b)
		return a[1] < b[1]
	end)
	local cursor = x0
	local function block(ax: number, bx: number, ay: number, by: number)
		if bx - ax < 0.05 or by - ay < 0.05 then
			return
		end
		self:Box(name, ax, bx, ay, by, d0, d1, color, material, opts)
	end
	for _, hole in ipairs(sorted) do
		local hx0, hx1 = math.max(x0, hole[1]), math.min(x1, hole[2])
		if hx1 > hx0 and hx0 >= cursor - 0.01 then
			block(cursor, hx0, y0, y1)
			block(hx0, hx1, y0, math.max(y0, hole[3]))
			block(hx0, hx1, math.min(y1, hole[4]), y1)
			cursor = hx1
		end
	end
	block(cursor, x1, y0, y1)
end

-- Mur plein le long de d (côtés, cloisons de la cage) à x0..x1, avec des
-- ouvertures `holes` = { { d0, d1, y0, y1 } }
function HouseKit.WallD(self: Kit, name: string, x0: number, x1: number, y0: number, y1: number, d0: number, d1: number, holes: { { number } }, color: Color3,
	material: Enum.Material?, opts: Opts?)
	local sorted = table.clone(holes)
	table.sort(sorted, function(a, b)
		return a[1] < b[1]
	end)
	local cursor = d0
	local function block(ad: number, bd: number, ay: number, by: number)
		if bd - ad < 0.05 or by - ay < 0.05 then
			return
		end
		self:Box(name, x0, x1, ay, by, ad, bd, color, material, opts)
	end
	for _, hole in ipairs(sorted) do
		local h0, h1 = math.max(d0, hole[1]), math.min(d1, hole[2])
		if h1 > h0 and h0 >= cursor - 0.01 then
			block(cursor, h0, y0, y1)
			block(h0, h1, y0, math.max(y0, hole[3]))
			block(h0, h1, math.min(y1, hole[4]), y1)
			cursor = h1
		end
	end
	block(cursor, d1, y0, y1)
end

-- Vraie lumière (PointLight / SpotLight), dans la limite du budget de la maison
function HouseKit.Light(self: Kit, part: BasePart, color: Color3, range: number, brightness: number, kind: string?): Light?
	local stats = self.Stats
	if stats.Lights >= stats.MaxLights then
		return nil
	end
	stats.Lights += 1
	local light = Instance.new((kind or "PointLight") :: any) :: Light
	light.Color = color
	light.Brightness = brightness
	light.Shadows = false
	;(light :: any).Range = range
	light.Parent = part
	return light
end

-- Texte sur une face (SurfaceGui)
function HouseKit.Text(_self: Kit, part: BasePart, face: Enum.NormalId, text: string, color: Color3, font: Enum.Font?, pps: number?, maxDistance: number?): TextLabel
	local gui = Instance.new("SurfaceGui")
	gui.Name = "Text"
	gui.Face = face
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = pps or 40
	gui.LightInfluence = 0.3
	gui.MaxDistance = maxDistance or 160
	gui.Parent = part
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(0.92, 0.84)
	label.Position = UDim2.fromScale(0.04, 0.08)
	label.Font = font or Enum.Font.FredokaOne
	label.TextScaled = true
	label.TextColor3 = color
	label.Text = text
	label.Parent = gui
	return label
end

return HouseKit
