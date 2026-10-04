--[[
	FoodHold (ModuleScript)
	Emplacement : ReplicatedStorage > Client > World > FoodHold

	🍦 L'aliment TENU et MANGÉ, côté client (v11, ITEMS11), pour TOUS les
	avatars proches qui tiennent un outil "DopamineFood" (le mien et les
	autres : tout se déduit des attributs répliqués de l'outil, FoodId /
	BitesLeft / BiteAt -> chaque client voit la même chose).

	1) TENUE (capture 31) : à chaque image, le bras tient l'aliment DEBOUT
	   dans le poing, devant le ventre (R15 : épaule + coude + poignet ; R6 :
	   épaule + soudure), quelle que soit l'animation jouée (marche, course,
	   saut, assis, émote...) : FairEat.SolveHold. Apparition / disparition
	   en fondu (0,25 s), remise en place exacte des C0 à la fin.
	2) MANGER, une manière par aliment :
	   - 🍦 glace : on LÈCHE (3 fois) : le bras amène la boule aux lèvres, la
	     tête se penche et tourne un peu, une petite langue rose sort et
	     remonte le long de la boule, la boule FOND progressivement (elle
	     rapetisse vers sa base pendant le coup de langue, les vermicelles et
	     la cerise partent d'abord) ; des coulures roses descendent le long
	     du cornet avec le temps ; la dernière fois on CROQUE le cornet ;
	   - 🥤 milkshake : on SIROTE à la paille (paille aux lèvres, tête
	     baissée) : le niveau rose BAISSE dans le gobelet transparent, la
	     chantilly disparaît par couches ;
	   - 🍕🌮🌭🥖🥞🍎🍩🍭🍿 : on CROQUE : le morceau visé (le bout +X des aliments
	     couchés, le haut des autres) arrive aux lèvres, disparaît pendant la
	     mastication, et laisse une MARQUE DE DENTS (3 creux arrondis couleur
	     mie) sur le nouveau bord ; miettes.
	   Le modèle affiché est une copie locale (FoodModels.Build), posée à
	   chaque image sur la poignée de l'outil (BulkMoveTo) ; les pièces de
	   l'outil du serveur sont masquées localement (LocalTransparencyModifier)
	   tant que la copie existe. Si ce module ne tourne pas, l'outil du
	   serveur reste visible (il perd ses bouchées "BiteN" à chaque bouchée).
	Coût : au plus MAX_HOLDERS mangeurs suivis (les plus proches), rien
	au-delà de FAR studs ; ~20 à 40 pièces ancrées par aliment, aucune
	lumière, aucun son.

	API (FairFx) :
	  FoodHold.Track(character, tool)   (10 fois / s : outils tenus en vue)
	  FoodHold.Bite(character, tool)    (BiteAt a changé : un geste)
	  FoodHold.Step(dt)                 (à chaque image, avant la caméra)
	  FoodHold.Stop()                   (tout remis en place)
	  FoodHold.Spec(id) / FoodHold.Portions(id, f) / FoodHold.GestureK(t, style)  (purs, testés hors jeu)
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local FoodModels = require(ReplicatedStorage.Shared.FoodModels)
local FairEat = require(script.Parent.FairEat)

local FoodHold = {}

local FAR = 140 -- (studs) au-delà : rien (copie détruite, bras rendu)
local MAX_HOLDERS = 12
local FADE = 0.25 -- s : apparition / disparition de la tenue
local UP_T, DOWN_T = 0.32, 0.38
local HOLD_T = { bite = 0.36, lick = 0.62, sip = 0.7 }

local rgb = Color3.fromRGB
local HELD = FoodModels.HELD_SCALE -- (échelle de l'aliment tenu, comme l'outil du serveur)

----------------------------------------------------------------------
-- Manières de manger (pur)
----------------------------------------------------------------------

-- Portions : nom de pièce -> { début, fin (fraction mangée 0..1), mode }
--   "scoop" : fond vers sa base (glace, chantilly) ; "cut" : croquée
--   (rapetisse vers le reste, marque de dents ensuite) ; "level" : niveau
--   qui baisse (liquide) ; "keep" : reste jusqu'au bout.
export type Portion = { From: number, To: number, Mode: string }
export type Spec = {
	Style: string, -- "bite" | "lick" | "sip"
	Last: string?, -- manière de la DERNIÈRE bouchée (glace : "bite")
	HoldLook: string?, -- "left" : aliment couché, bout +X vers l'avant
	Axis: string, -- "Y" (debout : on mange par le haut) | "X" (couché : par le bout +X)
	Portions: { [string]: Portion },
	Marks: boolean, -- marques de dents
	Interior: Color3, -- couleur de la mie (marques)
	Drips: Color3?, -- coulures (glace)
	Aim: string?, -- pièce visée pour siroter ("Straw")
	Lean: number, -- (rad) penché vers le visage au moment de manger
	Nod: number, -- (rad) la tête se penche vers l'aliment
}

local function bites(id: string): number
	local food = Config.FoodById[id]
	return math.max(1, math.floor(food and food.Bites or 3))
end

local SPECS: { [string]: any } = {
	IceCream = { Style = "lick", Last = "bite", Interior = rgb(236, 196, 140), Drips = rgb(255, 176, 200), Lean = math.rad(22), Nod = 0.3,
		Portions = { Bite1 = { 0, 0.45, "scoop" }, Bite2 = { 0.38, 0.8, "scoop" }, Bite3 = { 0.78, 1, "cut" } } },
	Milkshake = { Style = "sip", Aim = "Straw", Lean = math.rad(10), Nod = 0.22, Marks = false,
		Portions = { Bite1 = { 0, 0.25, "scoop" }, Bite2 = { 0.2, 0.45, "scoop" }, Bite3 = { 0.4, 0.62, "scoop" }, Shake = { 0, 0.98, "level" }, Straw = { 0.99, 1, "keep" } } },
	Taco = { HoldLook = "left", Axis = "X", Interior = rgb(250, 226, 160), Lean = math.rad(16), Nod = 0.26 },
	HotDog = { HoldLook = "left", Axis = "X", Interior = rgb(250, 230, 190), Lean = math.rad(16), Nod = 0.26 },
	PizzaSlice = { Interior = rgb(255, 236, 170), Lean = math.rad(30), Nod = 0.26 },
	Churros = { Interior = rgb(250, 220, 160), Lean = math.rad(26), Nod = 0.24 },
	Crepe = { Interior = rgb(250, 226, 170), Lean = math.rad(26), Nod = 0.24 },
	CandyApple = { Interior = rgb(255, 246, 220), Lean = math.rad(28), Nod = 0.26 },
	Donut = { Interior = rgb(250, 220, 170), Lean = math.rad(28), Nod = 0.26 },
	CandyFloss = { Marks = false, Lean = math.rad(24), Nod = 0.24 },
	Popcorn = { Marks = false, Lean = math.rad(20), Nod = 0.24 },
}

local specCache: { [string]: Spec } = {}
function FoodHold.Spec(id: string): Spec
	local cached = specCache[id]
	if cached then
		return cached
	end
	local raw = SPECS[id] or {}
	local n = bites(id)
	local portions: { [string]: Portion } = {}
	if raw.Portions then
		for name, p in pairs(raw.Portions) do
			portions[name] = { From = p[1], To = p[2], Mode = p[3] }
		end
	else
		-- Bite1 .. Bite(n-1) : une bouchée chacune ; le reste : la dernière
		for k = 1, n - 1 do
			portions["Bite" .. k] = { From = (k - 1) / n, To = k / n, Mode = "cut" }
		end
	end
	local spec: Spec = {
		Style = raw.Style or "bite",
		Last = raw.Last,
		HoldLook = raw.HoldLook,
		Axis = raw.Axis or "Y",
		Portions = portions,
		Marks = raw.Marks ~= false,
		Interior = raw.Interior or rgb(250, 230, 190),
		Drips = raw.Drips,
		Aim = raw.Aim,
		Lean = raw.Lean or math.rad(28),
		Nod = raw.Nod or 0.25,
	}
	specCache[id] = spec
	return spec
end

-- Manière du geste n° `done` (1..n)
function FoodHold.StyleOf(id: string, done: number): string
	local spec = FoodHold.Spec(id)
	if spec.Last and done >= bites(id) then
		return spec.Last
	end
	return spec.Style
end

local function smooth(x: number): number
	x = math.clamp(x, 0, 1)
	return x * x * (3 - 2 * x)
end

-- Poids du geste (0 = tenue, 1 = à la bouche) et avancée de la bouchée
-- (0..1, pendant l'arrêt à la bouche) au temps t depuis la bouchée
function FoodHold.GestureK(t: number, style: string): (number, number)
	local hold = HOLD_T[style] or HOLD_T.bite
	if t < UP_T then
		return t / UP_T, 0
	elseif t < UP_T + hold then
		local u = (t - UP_T) / hold
		-- (léchouille : petit va-et-vient ; mastication : la main recule à peine)
		local wob = if style == "lick" then 0.05 * math.sin(u * math.pi * 2) else 0.05 * math.abs(math.sin(u * math.pi * 2))
		return 1 - wob, smooth(u * 1.15)
	elseif t < UP_T + hold + DOWN_T then
		return 1 - (t - UP_T - hold) / DOWN_T, 1
	end
	return 0, 1
end

-- Fraction mangée (0..1) : `done` bouchées faites, la dernière avance de `p`
function FoodHold.Eaten(id: string, done: number, p: number): number
	local n = bites(id)
	return math.clamp((done - 1 + math.clamp(p, 0, 1)) / n, 0, 1)
end

-- Échelle (0..1) de chaque portion pour une fraction mangée f
function FoodHold.Portions(id: string, f: number): { [string]: number }
	local out = {}
	for name, p in pairs(FoodHold.Spec(id).Portions) do
		local u = if p.To > p.From then (f - p.From) / (p.To - p.From) else (if f >= p.To then 1 else 0)
		out[name] = 1 - math.clamp(u, 0, 1)
	end
	return out
end

----------------------------------------------------------------------
-- Copie locale de l'aliment
----------------------------------------------------------------------

type Entry = {
	Part: BasePart,
	Name: string,
	Local: CFrame, -- repère du modèle
	Size: Vector3,
	Trans: number,
	Small: boolean,
	Last: number, -- dernière échelle écrite (-1 : jamais)
}

type Box = { Min: Vector3, Max: Vector3 }
type Mark = { Parts: { BasePart }, Locals: { CFrame }, Portion: string, Next: string? }

type Visual = {
	Id: string,
	Model: Model,
	Entries: { Entry },
	Boxes: { [string]: Box }, -- par portion (repère du modèle)
	All: Box,
	Marks: { Mark },
	Drips: { BasePart },
	Tongue: BasePart?,
	Crumbs: BasePart?,
	Emitter: ParticleEmitter?,
	HandleLocal: CFrame,
}

local function boxOf(cf: CFrame, size: Vector3): (Vector3, Vector3)
	local h = size / 2
	local r, u, l = cf.RightVector, cf.UpVector, cf.LookVector
	local e = Vector3.new(
		math.abs(r.X) * h.X + math.abs(u.X) * h.Y + math.abs(l.X) * h.Z,
		math.abs(r.Y) * h.X + math.abs(u.Y) * h.Y + math.abs(l.Y) * h.Z,
		math.abs(r.Z) * h.X + math.abs(u.Z) * h.Y + math.abs(l.Z) * h.Z
	)
	return cf.Position - e, cf.Position + e
end

local function grow(b: Box?, lo: Vector3, hi: Vector3): Box
	if not b then
		return { Min = lo, Max = hi }
	end
	return { Min = b.Min:Min(lo), Max = b.Max:Max(hi) }
end

-- (shape "Egg" : ovale = bloc + SpecialMesh "Sphere" ; une Ball Roblox reste ronde)
local function plain(parent: Instance, name: string, size: Vector3, color: Color3, shape: string?, material: Enum.Material?): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Size = size
	p.Color = color
	p.Material = material or Enum.Material.SmoothPlastic
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	if shape == "Egg" then
		local mesh = Instance.new("SpecialMesh")
		mesh.MeshType = Enum.MeshType.Sphere
		mesh.Parent = p
	end
	p.Parent = parent
	return p
end

-- Marques de dents d'une portion "cut" : 3 creux arrondis couleur mie au bord
-- de ce qui reste, côté de la portion mangée
local function buildMarks(v: Visual, spec: Spec, folder: Model)
	if not spec.Marks then
		return
	end
	local axisX = spec.Axis == "X"
	local names = {}
	for name, p in pairs(spec.Portions) do
		if p.Mode == "cut" and v.Boxes[name] then
			table.insert(names, name)
		end
	end
	table.sort(names, function(a, b)
		return spec.Portions[a].From < spec.Portions[b].From
	end)
	for i, name in ipairs(names) do
		local box = v.Boxes[name]
		-- le bord : la face de la portion tournée vers le reste (le bas, ou -X)
		local size = box.Max - box.Min
		local center = (box.Min + box.Max) / 2
		local width = if axisX then math.max(size.Y, size.Z) else math.max(size.X, size.Z)
		local acrossX = not axisX and size.X >= size.Z
		local edge = if axisX then Vector3.new(box.Min.X, center.Y + size.Y * 0.18, center.Z) else Vector3.new(center.X, box.Min.Y, center.Z)
		local d = math.clamp(width * 0.36, 0.1, 0.3)
		local mark: Mark = { Parts = {}, Locals = {}, Portion = name, Next = names[i + 1] }
		for k = -1, 1 do
			local off
			if axisX then
				off = Vector3.new(0, k * d * 0.55, 0)
			elseif acrossX then
				off = Vector3.new(k * d * 0.8, 0, 0)
			else
				off = Vector3.new(0, 0, k * d * 0.8)
			end
			-- (aliment fin, part de pizza : la marque ne dépasse pas son épaisseur)
			local thin = if axisX then math.min(d, size.Z * 1.05) elseif acrossX then math.min(d, size.Z * 1.05) else math.min(d, size.X * 1.05)
			local dentSize = if axisX then Vector3.new(d * 0.5, d, thin) elseif acrossX then Vector3.new(d, d * 0.55, thin) else Vector3.new(thin, d * 0.55, d)
			local dent = plain(folder, "BiteMark", dentSize, spec.Interior:Lerp(Color3.new(1, 1, 1), (k + 1) * 0.06), "Egg")
			table.insert(mark.Parts, dent)
			table.insert(mark.Locals, CFrame.new(edge + off))
		end
		table.insert(v.Marks, mark)
	end
end

local function buildVisual(id: string, folder: Instance): Visual?
	local model = FoodModels.Build(id, CFrame.identity, HELD)
	if not model then
		return nil
	end
	local spec = FoodHold.Spec(id)
	local v: Visual = { Id = id, Model = model, Entries = {}, Boxes = {}, All = { Min = Vector3.zero, Max = Vector3.zero }, Marks = {}, Drips = {}, HandleLocal = FoodModels.HandleLocal(id, HELD) }
	local all: Box? = nil
	for _, p in ipairs(model:GetChildren()) do
		if p:IsA("BasePart") then
			local lo, hi = boxOf(p.CFrame, p.Size)
			all = grow(all, lo, hi)
			if spec.Portions[p.Name] then
				v.Boxes[p.Name] = grow(v.Boxes[p.Name], lo, hi)
			end
			table.insert(v.Entries, { Part = p, Name = p.Name, Local = p.CFrame, Size = p.Size, Trans = p.Transparency, Small = math.max(p.Size.X, p.Size.Y, p.Size.Z) < 0.2, Last = -1 })
		end
	end
	v.All = all or v.All
	buildMarks(v, spec, model)
	if spec.Drips then
		for k = 1, 3 do
			table.insert(v.Drips, plain(model, "Drip", Vector3.new(0.07, 0.2, 0.07), spec.Drips, "Egg"))
		end
	end
	-- langue (lécher) et source des miettes / gouttes
	if spec.Style == "lick" then
		v.Tongue = plain(model, "Tongue", Vector3.new(0.2, 0.07, 0.26), rgb(232, 110, 130), "Egg")
	end
	local food = Config.FoodById[id]
	local src = plain(model, "CrumbSource", Vector3.new(0.05, 0.05, 0.05), Color3.new(1, 1, 1))
	src.Transparency = 1
	local e = Instance.new("ParticleEmitter")
	e.Name = "FoodBits"
	e.Rate = 0
	e.Lifetime = NumberRange.new(0.4, 0.8)
	e.Speed = NumberRange.new(2.5, 5)
	e.SpreadAngle = Vector2.new(70, 70)
	e.Acceleration = Vector3.new(0, -32, 0)
	e.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.12), NumberSequenceKeypoint.new(1, 0.04) })
	e.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(1, 0.4) })
	e.Color = ColorSequence.new(if spec.Drips then spec.Drips else (food and food.Crumb or rgb(236, 196, 120)))
	e.LightEmission = 0
	e.EmissionDirection = Enum.NormalId.Bottom
	e.Parent = src
	v.Crumbs = src
	v.Emitter = e
	for _, p in ipairs(model:GetDescendants()) do
		if p:IsA("BasePart") then
			p.Anchored = true
			p.CanCollide = false
			p.CanQuery = false
			p.CanTouch = false
			p.CastShadow = false
		end
	end
	model.Name = "Held_" .. id
	model.Parent = folder
	return v
end

-- Point de l'aliment (repère du MODÈLE) à amener aux lèvres pour la bouchée
-- n° done (manière `style`), d'après ce qui reste
function FoodHold.AimPoint(id: string, done: number, style: string, boxes: { [string]: Box }?, all: Box?): Vector3
	local spec = FoodHold.Spec(id)
	local B = boxes or {}
	local A = all or { Min = Vector3.new(-0.3, -0.3, -0.3), Max = Vector3.new(0.3, 1.3, 0.3) }
	if style == "sip" and spec.Aim and B[spec.Aim] then
		local b = B[spec.Aim]
		return Vector3.new((b.Min.X + b.Max.X) / 2, b.Max.Y - 0.03, (b.Min.Z + b.Max.Z) / 2)
	end
	-- portion mangée par ce geste : la première qui reste (encore > 15 %)
	local n = bites(id)
	local before = (done - 1) / n
	local left = FoodHold.Portions(id, before)
	local best: string? = nil
	for name, p in pairs(spec.Portions) do
		if p.Mode ~= "keep" and p.Mode ~= "level" and (left[name] or 0) > 0.15 and B[name] and (not best or p.From < spec.Portions[best].From) then
			best = name
		end
	end
	if spec.Axis == "X" then
		local b = if best then B[best] else A
		return Vector3.new(b.Max.X - 0.04, (b.Min.Y + b.Max.Y) / 2 + 0.08, (b.Min.Z + b.Max.Z) / 2)
	end
	if best then
		local b = B[best]
		local c = (b.Min + b.Max) / 2
		if style == "lick" then
			-- la boule : son centre (déjà un peu fondue), la langue fait le reste
			local s = FoodHold.Portions(id, before)[best] or 1
			return Vector3.new(c.X, b.Min.Y + (c.Y - b.Min.Y) * s, c.Z)
		end
		return Vector3.new(c.X, b.Max.Y - 0.05, c.Z)
	end
	return Vector3.new(0, A.Max.Y - 0.08, 0)
end

-- Pose la copie : `base` = repère du modèle (monde), f = fraction mangée,
-- lick = avancée du coup de langue (0..1) ou nil
local function poseVisual(v: Visual, base: CFrame, f: number, clock: number, head: BasePart?, lick: number?, parts: { BasePart }, cfs: { CFrame })
	local spec = FoodHold.Spec(v.Id)
	local scales = FoodHold.Portions(v.Id, f)
	for _, e in ipairs(v.Entries) do
		local s = scales[e.Name]
		local mode = spec.Portions[e.Name] and spec.Portions[e.Name].Mode or nil
		if s == nil then
			s = 1
		elseif mode == "scoop" and e.Small then
			-- (vermicelles, cerise : partent au début de la portion)
			local p = spec.Portions[e.Name]
			s = 1 - math.clamp((f - p.From) / math.max(0.01, (p.To - p.From) * 0.3), 0, 1)
		end
		local hide = s <= 0.04
		local trans = if hide then 1 else e.Trans
		if e.Part.Transparency ~= trans then
			e.Part.Transparency = trans
		end
		if not hide then
			local cf = e.Local
			if s < 0.999 and mode then
				local b = v.Boxes[e.Name]
				local anchor
				if mode == "level" then
					anchor = Vector3.new(cf.X, b.Min.Y, cf.Z)
				elseif mode == "cut" then
					anchor = if spec.Axis == "X" then Vector3.new(b.Min.X, cf.Y, cf.Z) else Vector3.new(cf.X, b.Min.Y, cf.Z)
				else
					anchor = Vector3.new((b.Min.X + b.Max.X) / 2, b.Min.Y, (b.Min.Z + b.Max.Z) / 2)
				end
				if mode == "level" then
					-- (liquide : seule la hauteur baisse ; cylindre debout -> sa taille X)
					local h = e.Size.X * s
					cf = CFrame.new(anchor.X, anchor.Y + h / 2, anchor.Z) * cf.Rotation
					if math.abs(e.Last - s) > 0.004 then
						e.Last = s
						e.Part.Size = Vector3.new(math.max(0.02, h), e.Size.Y, e.Size.Z)
					end
				else
					cf = CFrame.new(anchor + (cf.Position - anchor) * s) * cf.Rotation
					if math.abs(e.Last - s) > 0.004 then
						e.Last = s
						e.Part.Size = e.Size * math.max(0.05, s)
					end
				end
			elseif e.Last ~= 1 and e.Last ~= -1 then
				e.Last = 1
				e.Part.Size = e.Size
			end
			table.insert(parts, e.Part)
			table.insert(cfs, base * cf)
		end
	end
	-- marques de dents : sur le bord de ce qui reste
	for _, m in ipairs(v.Marks) do
		local eaten = (scales[m.Portion] or 1) <= 0.04
		local nextStarted = m.Next ~= nil and (scales[m.Next] or 1) < 0.97
		local show = eaten and not nextStarted and f < 0.999
		for i, p in ipairs(m.Parts) do
			local t = if show then 0 else 1
			if p.Transparency ~= t then
				p.Transparency = t
			end
			if show then
				table.insert(parts, p)
				table.insert(cfs, base * m.Locals[i])
			end
		end
	end
	-- coulures : sous la boule du bas, le long du cornet, qui s'allongent
	if #v.Drips > 0 then
		local b2 = v.Boxes.Bite2
		local s2 = scales.Bite2 or 0
		for k, d in ipairs(v.Drips) do
			local show = b2 ~= nil and s2 > 0.15
			local t = if show then 0 else 1
			if d.Transparency ~= t then
				d.Transparency = t
			end
			if show and b2 then
				local phase = (clock * 0.09 + k * 0.37) % 1
				local len = (0.06 + 0.26 * phase) * HELD
				local a = k * 2.1 + 0.4
				local r = (0.26 - 0.06 * phase) * HELD
				local y = b2.Min.Y + 0.02 * HELD - len / 2 - phase * 0.12 * HELD
				d.Size = Vector3.new(0.07 * HELD, len, 0.07 * HELD)
				table.insert(parts, d)
				table.insert(cfs, base * CFrame.new(math.sin(a) * r, y, math.cos(a) * r))
			end
		end
	end
	-- langue : pendant le coup de langue, devant la bouche, elle remonte
	local tongue = v.Tongue
	if tongue then
		local show = lick ~= nil and lick > 0.05 and lick < 0.95 and head ~= nil
		local t = if show then 0 else 1
		if tongue.Transparency ~= t then
			tongue.Transparency = t
		end
		if show and head and lick then
			local s = head.Size.Y / 1.2
			local u = math.sin(lick * math.pi)
			local cf = head.CFrame * CFrame.new(0, (-0.28 + 0.16 * lick) * s, -head.Size.Z * 0.5 - 0.06 * u * s) * CFrame.Angles(math.rad(-25 + 40 * lick), 0, 0)
			table.insert(parts, tongue)
			table.insert(cfs, cf)
		end
	end
end

----------------------------------------------------------------------
-- Mangeurs
----------------------------------------------------------------------

type Holder = {
	Character: Model,
	Tool: Tool?,
	Id: string,
	Rig: any,
	W: number,
	T: number?, -- temps depuis la bouchée (nil : pas de geste)
	Done: number,
	Visual: Visual?,
	Hidden: { [BasePart]: boolean },
	Seen: number,
	Spawn: number,
	Emitted: boolean?,
}

local holders: { [Model]: Holder } = {}
local folder: Folder? = nil
local clock = 0

local function ensureFolder(): Folder
	if folder and folder.Parent then
		return folder
	end
	local f = Instance.new("Folder")
	f.Name = "FoodHoldFx"
	f.Parent = workspace
	folder = f
	return f
end

local function setHidden(h: Holder, on: boolean)
	local tool = h.Tool
	if on and tool then
		for _, p in ipairs(tool:GetDescendants()) do
			if p:IsA("BasePart") and not h.Hidden[p] then
				h.Hidden[p] = true
				p.LocalTransparencyModifier = 1
			end
		end
	elseif not on then
		for p in pairs(h.Hidden) do
			if p.Parent then
				p.LocalTransparencyModifier = 0
			end
		end
		table.clear(h.Hidden)
	end
end

local function dropVisual(h: Holder)
	if h.Visual then
		h.Visual.Model:Destroy()
		h.Visual = nil
	end
	setHidden(h, false)
end

local function release(character: Model)
	local h = holders[character]
	if not h then
		return
	end
	holders[character] = nil
	dropVisual(h)
	if h.Rig then
		pcall(FairEat.Restore, h.Rig)
	end
end

local function doneOf(tool: Tool?, id: string): number
	local left = tool and tonumber(tool:GetAttribute("BitesLeft"))
	if not left then
		return 0
	end
	return math.clamp(bites(id) - math.floor(left), 0, bites(id))
end

function FoodHold.Track(character: Model, tool: Tool)
	local id = tool:GetAttribute("FoodId")
	if type(id) ~= "string" or not FoodModels.Has(id) then
		return
	end
	local h = holders[character]
	if h and h.Tool ~= tool then
		-- (nouvel aliment : on repart de zéro, la tenue continue)
		dropVisual(h)
		h.Tool = tool
		h.Id = id
		h.T = nil
		h.Done = doneOf(tool, id)
	elseif not h then
		local rig = FairEat.Rig(character)
		if not rig then
			return
		end
		h = { Character = character, Tool = tool, Id = id, Rig = rig, W = 0, T = nil, Done = doneOf(tool, id), Hidden = {}, Seen = clock, Spawn = clock }
		holders[character] = h
	end
	if h then
		h.Seen = clock
	end
end

function FoodHold.Bite(character: Model, tool: Tool)
	FoodHold.Track(character, tool)
	local h = holders[character]
	if not h or h.Tool ~= tool then
		return
	end
	h.T = 0
	h.Done = doneOf(tool, h.Id)
end

local function headOf(h: Holder): BasePart?
	local rig = h.Rig
	return rig and rig.Head
end

function FoodHold.Step(dt: number)
	clock += dt
	local camera = workspace.CurrentCamera
	local eye = if camera then camera.CFrame.Position else Vector3.zero
	-- les plus proches d'abord (au plus MAX_HOLDERS)
	local list: { Holder } = {}
	for character, h in pairs(holders) do
		if not character.Parent or not h.Rig or not h.Rig.Shoulder.Parent then
			release(character)
		else
			table.insert(list, h)
		end
	end
	local dist: { [Holder]: number } = {}
	for _, h in ipairs(list) do
		local root = h.Rig.Torso
		dist[h] = if root and root.Parent then (root.Position - eye).Magnitude else math.huge
	end
	table.sort(list, function(a, b)
		return dist[a] < dist[b]
	end)
	local parts: { BasePart } = {}
	local cfs: { CFrame } = {}
	for i, h in ipairs(list) do
		local character = h.Character
		local tool = h.Tool
		local valid = tool ~= nil and tool.Parent == character and tool:FindFirstChild("Handle") ~= nil
		if valid and tool then
			local humanoid = character:FindFirstChildOfClass("Humanoid")
			local hp = humanoid and humanoid.Health
			if type(hp) == "number" and hp <= 0 then
				valid = false
			end
		end
		local near = dist[h] <= FAR and i <= MAX_HOLDERS
		h.W = math.clamp(h.W + (if valid and near then dt else -dt) / FADE, 0, 1)
		if not near and h.W <= 0 then
			-- (loin : copie détruite, l'outil du serveur reprend)
			release(character)
		elseif not valid and h.W <= 0 then
			release(character)
		else
			-- geste en cours
			local style = FoodHold.StyleOf(h.Id, math.max(1, h.Done))
			local k, p = 0, 1
			if h.T then
				h.T += dt
				k, p = FoodHold.GestureK(h.T, style)
				if h.T > UP_T + (HOLD_T[style] or 0.4) + DOWN_T then
					h.T = nil
					k, p = 0, 1
				end
			end
			if not valid then
				k = 0
			end
			local done = h.Done
			local f = if h.T then FoodHold.Eaten(h.Id, math.max(1, done), p) else FoodHold.Eaten(h.Id, done + 1, 0)
			if done <= 0 then
				f = 0
			end
			-- copie locale
			local v = h.Visual
			if valid and not v then
				v = buildVisual(h.Id, ensureFolder())
				h.Visual = v
			end
			if v and not valid then
				dropVisual(h)
				v = nil
			end
			local spec = FoodHold.Spec(h.Id)
			local aim = FoodHold.AimPoint(h.Id, math.max(1, done), style, if v then v.Boxes else nil, if v then v.All else nil)
			-- (Aim est dans le repère du MODÈLE, comme la prise FoodModels.GRIP
			-- passée à FairEat : la poignée tournée n'intervient pas)
			local gesture: FairEat.Gesture = {
				K = k,
				Aim = aim,
				Lean = spec.Lean,
				Stand = if style == "lick" then 0.2 else (if style == "sip" then 0.04 else 0.1),
				Nod = spec.Nod,
				Roll = if style == "lick" then 0.12 * math.sin((h.T or 0) * 9) else 0,
				HoldLook = spec.HoldLook,
			}
			pcall(FairEat.Apply, h.Rig, h.W, gesture, FoodModels.GRIP)
			if v and tool then
				setHidden(h, true)
				local handle = tool:FindFirstChild("Handle")
				if handle and handle:IsA("BasePart") then
					local base = handle.CFrame * v.HandleLocal:Inverse()
					local lick = if style == "lick" and h.T and h.T >= UP_T then p else nil
					poseVisual(v, base, f, clock, headOf(h), lick, parts, cfs)
					if v.Crumbs then
						table.insert(parts, v.Crumbs)
						table.insert(cfs, base * CFrame.new(aim))
						-- miettes (croquer) / gouttes (lécher) au moment de la bouchée
						if h.T and v.Emitter and not h.Emitted and h.T >= UP_T + 0.08 then
							h.Emitted = true
							if style ~= "sip" then
								v.Emitter:Emit(if style == "lick" then 4 else 10)
							end
						end
						if not h.T then
							h.Emitted = nil
						end
					end
				end
			end
		end
	end
	if #parts > 0 then
		workspace:BulkMoveTo(parts, cfs, Enum.BulkMoveMode.FireCFrameChanged)
	end
end

function FoodHold.Stop()
	for character in pairs(holders) do
		release(character)
	end
	if folder then
		folder:Destroy()
		folder = nil
	end
end

function FoodHold.Debug(): any
	return { Holders = holders }
end

return FoodHold
