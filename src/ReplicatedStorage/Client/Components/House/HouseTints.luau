--[[
	HouseTints (ModuleScript)
	Emplacement : ReplicatedStorage > Client > Components > House > HouseTints

	(v9.1) Couleurs des objets posés (entry.C = id de Config.House.Tints) :
	la couleur PRINCIPALE du dessin (le groupe de teintes qui couvre le plus
	de surface : le tissu du canapé, la coque de la radio...) prend la
	couleur choisie ; ses ombres, reflets et contours suivent (même écart de
	teinte, saturation et luminosité à l'échelle). Le reste (pieds en bois,
	feuilles, blancs, gris, yeux) ne bouge pas.
	Aucune image : on recolore les Frames / UIStroke / UIGradient / textes
	d'un dessin déjà peint (HouseArt.Paint).

	API :
	  HouseTints.Get(tintId) -> Look?            entrée de la config (nil = d'origine)
	  HouseTints.Apply(root, tintId?)            recolore le dessin peint dans `root`
	  HouseTints.Mapper(itemId, tintId?) -> (Color3) -> Color3
	      transforme n'importe quelle couleur de la palette de l'objet (3D)
]]

local HouseCommon = require(script.Parent.HouseCommon)

local HouseTints = {}

type Stats = { H: number, S: number, V: number }

local MIN_SAT = 0.14 -- en dessous : blanc / gris (jamais recoloré)
local HUE_WINDOW = 0.085 -- écart de teinte du groupe principal
local STROKE_WINDOW = 0.16 -- contours (couleur tirée vers l'encre) : plus large
local BINS = 24

function HouseTints.Get(tintId: string?): HouseCommon.Look?
	if type(tintId) ~= "string" then
		return nil
	end
	return HouseCommon.TintsById[tintId]
end

local function hueDistance(a: number, b: number): number
	local d = math.abs(a - b) % 1
	return math.min(d, 1 - d)
end

-- Teinte principale d'un dessin : surfaces colorées regroupées par teinte
local function measure(root: Instance): Stats?
	local weights = table.create(BINS, 0)
	local samples: { { number } } = {}
	for _, object in ipairs(root:GetDescendants()) do
		if object:IsA("Frame") and object.BackgroundTransparency < 0.85 then
			local h, s, v = object.BackgroundColor3:ToHSV()
			if s >= MIN_SAT and v >= 0.2 then
				local size = object.Size
				local w = math.abs(size.X.Offset) + size.X.Scale * 100
				local hh = math.abs(size.Y.Offset) + size.Y.Scale * 100
				local area = math.clamp(w * hh, 4, 6000) * (1 - object.BackgroundTransparency)
				local bin = math.floor(h * BINS) % BINS + 1
				weights[bin] += area
				table.insert(samples, { h, s, v, area })
			end
		end
	end
	local best, bestWeight = 0, 0
	for bin = 1, BINS do
		-- (un groupe peut chevaucher deux cases : on les additionne avec leurs voisines)
		local left = weights[(bin - 2) % BINS + 1]
		local right = weights[bin % BINS + 1]
		local total = weights[bin] + (left + right) * 0.5
		if total > bestWeight then
			best, bestWeight = bin, total
		end
	end
	if best == 0 then
		return nil
	end
	local center = (best - 0.5) / BINS
	-- Moyenne pondérée du groupe (teinte circulaire autour du centre)
	local sumH, sumS, sumV, sumW = 0, 0, 0, 0
	for _, sample in ipairs(samples) do
		local d = sample[1] - center
		d = (d + 0.5) % 1 - 0.5
		if math.abs(d) <= 1.5 / BINS then
			sumH += d * sample[4]
			sumS += sample[2] * sample[4]
			sumV += sample[3] * sample[4]
			sumW += sample[4]
		end
	end
	if sumW <= 0 then
		return nil
	end
	return { H = (center + sumH / sumW) % 1, S = sumS / sumW, V = sumV / sumW }
end

-- Transforme une couleur du groupe principal vers la couleur choisie
local function remap(color: Color3, main: Stats, target: Stats, window: number): Color3
	local h, s, v = color:ToHSV()
	if s < MIN_SAT * 0.8 or hueDistance(h, main.H) > window then
		return color
	end
	local d = (h - main.H + 0.5) % 1 - 0.5
	local newH = (target.H + d) % 1
	local newS = math.clamp(s * target.S / math.max(0.05, main.S), 0, 1)
	-- luminosité : la couleur principale arrive pile sur la cible, les ombres
	-- (plus foncées) et les reflets (plus clairs) gardent leur écart
	local newV
	if v <= main.V then
		newV = v * target.V / math.max(0.05, main.V)
	else
		newV = target.V + (v - main.V) * (1 - target.V) / math.max(0.01, 1 - main.V)
	end
	newV = math.clamp(newV, 0, 1)
	return Color3.fromHSV(newH, newS, newV)
end

local function targetOf(tintId: string?): Stats?
	local tint = HouseTints.Get(tintId)
	local color = tint and tint.Color
	if not color then
		return nil
	end
	local h, s, v = color:ToHSV()
	return { H = h, S = s, V = v }
end

local function remapSequence(sequence: ColorSequence, main: Stats, target: Stats): ColorSequence
	local points = {}
	for _, point in ipairs(sequence.Keypoints) do
		table.insert(points, ColorSequenceKeypoint.new(point.Time, remap(point.Value, main, target, HUE_WINDOW)))
	end
	return ColorSequence.new(points)
end

-- Recolore un dessin déjà peint (rien si tintId est nil / inconnu)
function HouseTints.Apply(root: Instance, tintId: string?)
	local target = targetOf(tintId)
	if not target then
		return
	end
	local main = measure(root)
	if not main then
		return
	end
	for _, object in ipairs(root:GetDescendants()) do
		if object:IsA("Frame") then
			object.BackgroundColor3 = remap(object.BackgroundColor3, main, target, HUE_WINDOW)
		elseif object:IsA("UIStroke") then
			object.Color = remap(object.Color, main, target, STROKE_WINDOW)
		elseif object:IsA("UIGradient") then
			object.Color = remapSequence(object.Color, main, target)
		elseif object:IsA("TextLabel") then
			object.TextColor3 = remap(object.TextColor3, main, target, HUE_WINDOW)
		end
	end
end

-- Teinte principale de chaque objet (dessin peint une fois, hors écran)
local mainCache: { [string]: Stats | false } = {}
local function mainOf(itemId: string): Stats?
	local cached = mainCache[itemId]
	if cached ~= nil then
		return if cached == false then nil else cached
	end
	local item = HouseCommon.ItemsById[itemId]
	local result: Stats? = nil
	if item then
		local HouseArt = require(script.Parent.HouseArt) :: any
		local body = Instance.new("Frame")
		body.Size = UDim2.fromOffset(100, 100)
		local ok = pcall(HouseArt.Paint, body, item, true)
		if ok then
			result = measure(body)
		end
		body:Destroy()
	end
	mainCache[itemId] = result or false
	return result
end

-- Fonction de couleur pour un objet (identité si pas de couleur choisie)
function HouseTints.Mapper(itemId: string, tintId: string?): (Color3) -> Color3
	local target = targetOf(tintId)
	local main = target and mainOf(itemId) or nil
	if not target or not main then
		return function(color: Color3): Color3
			return color
		end
	end
	local t, m = target :: Stats, main :: Stats
	return function(color: Color3): Color3
		return remap(color, m, t, STROKE_WINDOW)
	end
end

return HouseTints
