--[[
	Weather3D (ModuleScript)
	Emplacement : ReplicatedStorage > Client > World > Weather3D

	v9.8 (REALISM98) 🌦️ météo de Dopamine Town, côté client, AUCUN son.
	  - Cycle DÉTERMINISTE (heure du serveur : workspace:GetServerTimeNow())
	    -> tous les joueurs ont le même temps au même moment. Le temps est
	    découpé en épisodes de 10 min tirés au sort (hachage entier 32 bits,
	    identique sur PC / mobile) :
	      Clear 30 % · Cloudy 22 % · Showers 22 % · Rain 16 % · Storm 10 %
	    (jamais deux orages de suite). Chaque épisode suit un scénario doux :
	    ciel qui se couvre -> pluie fine -> pluie -> (orage) -> éclaircie
	    avec arc-en-ciel -> dégagé. Le début d'un épisode se fond dans la fin
	    du précédent (aucun saut).
	  - Pluie : fines gouttes (Parts minces, déplacées en lot 30 fois / s
	    au plus) dans une boîte autour de la caméra, ancrées au MONDE (on
	    peut marcher dessous), inclinées par le vent ; elles s'arrêtent sur
	    le sol, les toits, les auvents (grille de hauteurs par lancer de
	    rayon, en cache) et y font des éclaboussures (anneaux).
	  - Sol mouillé : routes / trottoirs / pavés de la ville plus sombres et
	    un peu brillants (Color + Reflectance, remis EXACTEMENT à l'arrêt) ;
	    flaques (ellipses sombres et réfléchissantes) qui grandissent après
	    une vraie pluie puis sèchent ; ronds de pluie dessus.
	  - Orage : ciel plus sombre (TownAtmosphere), éclairs DOUX : bref
	    voile (TownAtmosphere : ColorCorrection +0,07 au plus, jamais de
	    "flash bang") + parfois un éclair lointain dessiné (pas de Neon).
	  - Éclaircie : arc-en-ciel discret à l'opposé du soleil (le jour).
	  - Pas de pluie à l'intérieur : quand la caméra est dans une maison /
	    boutique (boîtes intérieures InteriorCF / InteriorSize des boutiques,
	    sinon plafond + murs autour par lancers de rayons, ou la sonde
	    donnée par SetIndoorProbe), les gouttes sont masquées.
	  - Réglages 🎨 (Shared/GraphicsQuality) : Météo On/Off (Off = beau temps
	    fixe, rien d'affiché), intensité de la pluie (Low / Medium / High),
	    Reflets "All" = sol mouillé et flaques plus brillants.
	Budget : ≤ 240 gouttes (High), 36 éclaboussures, 16 flaques, 8 morceaux
	d'éclair, arc-en-ciel 120 pièces seulement pendant l'éclaircie. Travail
	par image : gouttes + éclaboussures (30 Hz max, BulkMoveTo) ; le reste
	2 à 4 fois / s.

	API :
	  Weather3D.Start(opts?)  opts = { IsNight: (() -> boolean)? }
	  Weather3D.Stop()        (tout retiré, sol remis)
	  Weather3D.Step(dt)
	  Weather3D.State() -> { Kind, Phase, Cloud, Rain, Storm, Rainbow, Wet, Puddles, Flash, Indoor, Enabled }
	  Weather3D.At(t) -> même table (sans Flash / Indoor), fonction PURE du temps
	  Weather3D.FlashAt(t, storm) -> 0..1
	  Weather3D.KindOf(index) -> string   (épisode n° index)
	  Weather3D.SetIndoorProbe(fn?)       fn(position) -> boolean
	  Weather3D.SetForcedTime(t?)         (tests / rendus : heure imposée)
	  Weather3D.EPISODE (s)
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GraphicsQuality = require(ReplicatedStorage.Shared.GraphicsQuality)

local Weather3D = {}

local EPISODE = 600 -- (s) un épisode de météo
Weather3D.EPISODE = EPISODE
local KINDS = { "Clear", "Cloudy", "Showers", "Rain", "Storm" }
local WEIGHTS = { 0.30, 0.22, 0.22, 0.16, 0.10 }
Weather3D.KINDS = KINDS

-- Gouttes
local DROPS_BASE = 160 -- (Medium ; x0,5 Low ; x1,5 High)
local DROPS_MAX = 240
local BOX_R = 24 -- demi-côté de la boîte de pluie autour de la caméra
local BOX_UP, BOX_DOWN = 26, 18
local FALL_SPEED = 72
local CELL = 4 -- grille des hauteurs d'arrêt (studs)
local SPLASH_MAX = 36
local SPLASH_LIFE = 0.3
local SPLASH_RANGE = 28
local PUDDLE_MAX = 16
local PUDDLE_CELL = 15
local PUDDLE_RANGE = 46
local STEP_RATE = 1 / 30
local PARK = CFrame.new(0, 3000, 0) -- gouttes au repos (hors de vue)

local DROP_COLOR = Color3.fromRGB(196, 210, 228)
local SPLASH_COLOR = Color3.fromRGB(214, 226, 240)
local PUDDLE_COLOR = Color3.fromRGB(62, 72, 86)
local BOLT_COLOR = Color3.fromRGB(222, 230, 255)
local RAINBOW = {
	Color3.fromRGB(255, 96, 96),
	Color3.fromRGB(255, 196, 92),
	Color3.fromRGB(124, 222, 124),
	Color3.fromRGB(96, 152, 255),
	Color3.fromRGB(172, 112, 232),
}

-- Sols "durs" qui se mouillent (routes, trottoirs, pavés, dalles)
local HARD: { [Enum.Material]: boolean } = {
	[Enum.Material.Asphalt] = true,
	[Enum.Material.Concrete] = true,
	[Enum.Material.Pavement] = true,
	[Enum.Material.Cobblestone] = true,
	[Enum.Material.Slate] = true,
	[Enum.Material.Brick] = true,
	[Enum.Material.Granite] = true,
	[Enum.Material.Limestone] = true,
	[Enum.Material.Sandstone] = true,
	[Enum.Material.Basalt] = true,
	[Enum.Material.Rock] = true,
	[Enum.Material.Marble] = true,
}
Weather3D.HARD = HARD

----------------------------------------------------------------------
-- Hasard déterministe (entiers 32 bits exacts : pas de math.sin / random)
----------------------------------------------------------------------

local TWO32 = 4294967296

-- (a * b) mod 2^32, exact en double (moitiés de 16 bits)
local function mul32(a: number, b: number): number
	local aHi = math.floor(a / 65536)
	local aLo = a % 65536
	return ((aHi * b % 65536) * 65536 + aLo * b) % TWO32
end

-- Hachage d'un entier (peut être négatif ou grand) -> [0, 1)
local function hash01(n: number): number
	local h = math.floor(n) % TWO32
	h = bit32.bxor(h, bit32.rshift(h, 16))
	h = mul32(h, 0x45D9F3B)
	h = bit32.bxor(h, bit32.rshift(h, 16))
	h = mul32(h, 0x45D9F3B)
	h = bit32.bxor(h, bit32.rshift(h, 16))
	return h / TWO32
end
Weather3D.Hash = hash01

----------------------------------------------------------------------
-- Scénarios (fonctions pures de la phase 0..1 d'un épisode)
----------------------------------------------------------------------

local function clamp01(x: number): number
	return math.clamp(x, 0, 1)
end

local function smooth(x: number): number
	x = clamp01(x)
	return x * x * (3 - 2 * x)
end

-- 0 avant a, 1 après b (en douceur)
local function ramp(x: number, a: number, b: number): number
	return smooth((x - a) / (b - a))
end

-- monte de a0 à a1, reste, redescend de b0 à b1
local function plateau(x: number, a0: number, a1: number, b0: number, b1: number): number
	return ramp(x, a0, a1) * (1 - ramp(x, b0, b1))
end

type Sample = { Cloud: number, Rain: number, Storm: number, Rainbow: number }

local function profile(kind: string, p: number): Sample
	local wobble = 0.04 * math.sin(p * math.pi * 4)
	if kind == "Cloudy" then
		return { Cloud = 0.34 + 0.46 * plateau(p, 0.08, 0.3, 0.72, 0.95) + wobble, Rain = 0, Storm = 0, Rainbow = 0 }
	elseif kind == "Showers" then
		local cloud = 0.34 + 0.5 * plateau(p, 0.04, 0.24, 0.62, 0.86)
		local rain = 0.2 * plateau(p, 0.22, 0.3, 0.6, 0.66) + 0.26 * plateau(p, 0.3, 0.38, 0.52, 0.6)
		return { Cloud = cloud, Rain = rain, Storm = 0, Rainbow = plateau(p, 0.64, 0.7, 0.84, 0.92) }
	elseif kind == "Rain" then
		local cloud = 0.34 + 0.58 * plateau(p, 0.04, 0.2, 0.72, 0.9)
		local rain = 0.3 * plateau(p, 0.2, 0.27, 0.74, 0.8) + 0.55 * plateau(p, 0.27, 0.38, 0.66, 0.74)
		return { Cloud = cloud, Rain = rain, Storm = 0, Rainbow = plateau(p, 0.78, 0.83, 0.92, 0.98) }
	elseif kind == "Storm" then
		local cloud = 0.34 + 0.63 * plateau(p, 0.04, 0.18, 0.74, 0.9)
		local rain = 0.45 * plateau(p, 0.18, 0.26, 0.76, 0.82) + 0.55 * plateau(p, 0.26, 0.36, 0.64, 0.74)
		local storm = plateau(p, 0.3, 0.4, 0.6, 0.68)
		return { Cloud = cloud, Rain = rain, Storm = storm, Rainbow = plateau(p, 0.8, 0.85, 0.93, 0.99) }
	end
	return { Cloud = 0.3 + wobble, Rain = 0, Storm = 0, Rainbow = 0 }
end

-- Tirage brut d'un épisode (sans la règle "pas deux orages")
local function rawKind(index: number): string
	local r = hash01(index * 7 + 1013)
	local acc = 0
	for i, w in ipairs(WEIGHTS) do
		acc += w
		if r < acc then
			return KINDS[i]
		end
	end
	return KINDS[1]
end

function Weather3D.KindOf(index: number): string
	local kind = rawKind(index)
	if kind == "Storm" and rawKind(index - 1) == "Storm" then
		return "Rain"
	end
	return kind
end

local function blended(t: number): (string, number, Sample)
	local index = math.floor(t / EPISODE)
	local phase = (t - index * EPISODE) / EPISODE
	local kind = Weather3D.KindOf(index)
	local sample = profile(kind, phase)
	-- début d'épisode fondu avec la fin du précédent (6 % = 36 s)
	if phase < 0.06 then
		local before = profile(Weather3D.KindOf(index - 1), 1)
		local k = smooth(phase / 0.06)
		sample = {
			Cloud = before.Cloud + (sample.Cloud - before.Cloud) * k,
			Rain = before.Rain + (sample.Rain - before.Rain) * k,
			Storm = before.Storm + (sample.Storm - before.Storm) * k,
			Rainbow = before.Rainbow + (sample.Rainbow - before.Rainbow) * k,
		}
	end
	return kind, phase, sample
end

export type WeatherState = {
	Kind: string,
	Phase: number,
	Cloud: number,
	Rain: number,
	Storm: number,
	Rainbow: number,
	Wet: number,
	Puddles: number,
	Flash: number,
	Indoor: boolean,
	Enabled: boolean,
}

-- Météo à l'instant t (secondes, heure du serveur) : fonction PURE
function Weather3D.At(t: number): WeatherState
	local kind, phase, sample = blended(t)
	-- sol mouillé : suit la pluie tout de suite, sèche en ~3 min ;
	-- flaques : seulement après une vraie pluie, sèchent plus lentement
	local wet, puddles = 0, 0
	for k = 0, 24 do
		local dt = k * 10
		local _, _, past = blended(t - dt)
		wet = math.max(wet, past.Rain * 1.4 * math.exp(-dt / 150))
		puddles = math.max(puddles, clamp01((past.Rain - 0.22) / 0.5) * math.exp(-dt / 240))
	end
	return {
		Kind = kind,
		Phase = phase,
		Cloud = clamp01(sample.Cloud),
		Rain = clamp01(sample.Rain),
		Storm = clamp01(sample.Storm),
		Rainbow = clamp01(sample.Rainbow),
		Wet = clamp01(wet),
		Puddles = clamp01(puddles),
		Flash = 0,
		Indoor = false,
		Enabled = true,
	}
end

-- Éclairs : un tirage toutes les 5 s pendant l'orage ; deux pulsations
-- brèves (0,09 s de montée, ~0,3 s de descente), la 2e plus faible
local FLASH_SLOT = 5
local function pulse(x: number): number
	if x < 0 then
		return 0
	elseif x < 0.06 then
		return x / 0.06
	end
	return math.max(0, 1 - (x - 0.06) / 0.28)
end

function Weather3D.FlashAt(t: number, storm: number): (number, number?)
	if storm <= 0.3 then
		return 0, nil
	end
	local best, slotOf = 0, nil
	for back = 0, 1 do
		local slot = math.floor(t / FLASH_SLOT) - back
		if hash01(slot * 3 + 77) < 0.5 * storm then
			local at = slot * FLASH_SLOT + hash01(slot * 5 + 11) * (FLASH_SLOT - 1)
			local x = t - at
			local f = math.max(pulse(x), 0.55 * pulse(x - 0.2))
			if f > best then
				best, slotOf = f, slot
			end
		end
	end
	return clamp01(best * math.min(1, storm * 1.2)), slotOf
end

----------------------------------------------------------------------
-- Rendu (client)
----------------------------------------------------------------------

type Drop = { Part: BasePart, Seed: number, Phase: number, Speed: number, Len: number, Landed: number }
type Splash = { Part: BasePart, Age: number, Size: number }
type Puddle = { Part: BasePart, Key: string, Base: Vector3, W: number, D: number }
type WetRec = { Part: BasePart, Color: Color3, Reflectance: number }

local active = false
local options: any = {}
local folder: Folder? = nil
local drops: { Drop } = {}
local shownDrops = 0
local splashes: { Splash } = {}
local splashFree: { Splash } = {}
local puddles: { [string]: Puddle } = {}
local puddlePool: { BasePart } = {}
local heights: { [number]: number } = {}
local heightCount = 0
local wetList: { WetRec } = {}
local wetApplied = 0
local wetCursor = 0
local wetTarget = 0
local bolt: { BasePart } = {}
local boltSlot: number? = nil
local rainbowParts: { BasePart } = {}
local rainbowShown = 0
local indoorProbe: ((Vector3) -> boolean)? = nil
local shopBoxes: { { CF: CFrame, Size: Vector3 } } = {}
local forcedTime: number? = nil
local stepClock = 0
local slowClock = 0
local puddleClock = 0
local indoorClock = 0
local shopClock = 0
local state: WeatherState = Weather3D.At(0)
local indoor = false
local rayParams: any = nil
local qualityConn: any = nil

local function now(): number
	local forced = forcedTime
	if forced then
		return forced
	end
	local ok, t = pcall(function()
		return workspace:GetServerTimeNow()
	end)
	return ok and t or os.clock()
end

local function camera(): Camera?
	return workspace.CurrentCamera
end

local function newPart(name: string, size: Vector3, color: Color3, transparency: number, material: Enum.Material?): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Locked = true
	p.Size = size
	p.Color = color
	p.Material = material or Enum.Material.SmoothPlastic
	p.Transparency = transparency
	p.CFrame = PARK
	return p
end

-- Lancer de rayon vers le bas (sans la pluie ni le personnage) ; nil si rien
local function castDown(x: number, z: number, top: number): RaycastResult?
	local ok, result = pcall(function()
		local params = rayParams
		if params == nil then
			params = RaycastParams.new()
			params.FilterType = Enum.RaycastFilterType.Exclude
			rayParams = params
		end
		local list: { Instance } = {}
		if folder then
			table.insert(list, folder)
		end
		local character = Players.LocalPlayer and Players.LocalPlayer.Character
		if character then
			table.insert(list, character)
		end
		params.FilterDescendantsInstances = list
		return workspace:Raycast(Vector3.new(x, top, z), Vector3.new(0, -260, 0), params)
	end)
	if ok then
		return result
	end
	return nil
end

-- Hauteur d'arrêt des gouttes (sol / toit / auvent) : grille en cache
local function heightAt(x: number, z: number, camY: number): number
	local ix, iz = math.floor(x / CELL), math.floor(z / CELL)
	local key = ix * 65536 + iz
	local cached = heights[key]
	if cached then
		return cached
	end
	if heightCount > 900 then
		table.clear(heights)
		heightCount = 0
	end
	local hit = castDown((ix + 0.5) * CELL, (iz + 0.5) * CELL, camY + 80)
	local y = hit and hit.Position.Y or (camY - BOX_DOWN)
	heights[key] = y
	heightCount += 1
	return y
end

----------------------------------------------------------------------
-- Gouttes + éclaboussures
----------------------------------------------------------------------

local function ensureDrops(count: number)
	local parent = folder
	if not parent then
		return
	end
	while #drops < count do
		local i = #drops + 1
		local len = 1.5 + hash01(i * 13 + 5) * 1.1
		local part = newPart("RainDrop", Vector3.new(0.055, len, 0.055), DROP_COLOR, 0.42)
		part.Parent = parent
		table.insert(drops, {
			Part = part,
			Seed = i * 7919,
			Phase = hash01(i * 31 + 7),
			Speed = FALL_SPEED * (0.9 + 0.2 * hash01(i * 17 + 3)),
			Len = len,
			Landed = -1,
		})
	end
end

local function spawnSplash(position: Vector3, size: number)
	local s = table.remove(splashFree)
	if not s then
		if #splashes >= SPLASH_MAX or not folder then
			return
		end
		local part = newPart("RainSplash", Vector3.new(0.04, 0.2, 0.2), SPLASH_COLOR, 0.4)
		part.Shape = Enum.PartType.Cylinder
		part.Parent = folder
		s = { Part = part, Age = 0, Size = size }
	end
	local splash = s :: Splash
	splash.Age = 0
	splash.Size = size
	splash.Part.CFrame = CFrame.new(position + Vector3.new(0, 0.03, 0)) * CFrame.Angles(0, 0, math.pi / 2)
	table.insert(splashes, splash)
end

local function stepSplashes(dt: number)
	local i = 1
	while i <= #splashes do
		local s = splashes[i]
		s.Age += dt
		local k = s.Age / SPLASH_LIFE
		if k >= 1 then
			s.Part.CFrame = PARK
			table.insert(splashFree, s)
			table.remove(splashes, i)
		else
			local d = s.Size * (0.25 + 0.75 * k)
			s.Part.Size = Vector3.new(0.04, d, d)
			s.Part.Transparency = 0.35 + 0.65 * k
			i += 1
		end
	end
end

local function wrap(value: number, center: number, half: number): number
	local span = half * 2
	return center - half + ((value - (center - half)) % span)
end

local function stepDrops(t: number, cam: CFrame, rain: number, storm: number)
	local q = GraphicsQuality.Get()
	local want = math.floor(math.min(DROPS_MAX, DROPS_BASE * q.RainScale) * rain + 0.5)
	if indoor or not q.Weather then
		want = 0
	end
	if want > #drops then
		ensureDrops(want)
	end
	local camPos = cam.Position
	local top = camPos.Y + BOX_UP
	local height = BOX_UP + BOX_DOWN
	local windX, windZ = 3 + 9 * storm, 1.5 + 4 * storm
	-- (axe Y de la goutte le long de sa vitesse : vent + chute)
	local tilt = CFrame.Angles(-math.atan2(windZ, FALL_SPEED), 0, math.atan2(windX, FALL_SPEED))
	local parts, cframes = {}, {}
	for i = 1, #drops do
		local d = drops[i]
		local cf = PARK
		if i <= want then
			local s = t * d.Speed + d.Phase * height
			local cycle = math.floor(s / height)
			local fall = s - cycle * height
			local fallTime = fall / d.Speed
			local wx = (hash01(d.Seed + cycle * 2) - 0.5) * 2 * BOX_R + windX * fallTime
			local wz = (hash01(d.Seed + cycle * 2 + 1) - 0.5) * 2 * BOX_R + windZ * fallTime
			-- ancrée au monde : une grille de 2 x BOX_R studs repliée autour de la caméra
			local x = wrap(wx + math.floor(camPos.X / (2 * BOX_R)) * 2 * BOX_R, camPos.X, BOX_R)
			local z = wrap(wz + math.floor(camPos.Z / (2 * BOX_R)) * 2 * BOX_R, camPos.Z, BOX_R)
			local y = top - fall
			local stop = heightAt(x, z, camPos.Y)
			if y - d.Len * 0.5 > stop then
				cf = CFrame.new(x, y, z) * tilt
			elseif d.Landed ~= cycle then
				d.Landed = cycle
				local dx, dz = x - camPos.X, z - camPos.Z
				if dx * dx + dz * dz < SPLASH_RANGE * SPLASH_RANGE and stop > camPos.Y - BOX_DOWN + 0.5 then
					spawnSplash(Vector3.new(x, stop, z), 0.6 + 0.5 * hash01(d.Seed + cycle))
				end
			end
		end
		if i <= want or i <= shownDrops then
			table.insert(parts, d.Part)
			table.insert(cframes, cf)
		end
	end
	shownDrops = want
	if #parts > 0 then
		local ok = pcall(function()
			workspace:BulkMoveTo(parts, cframes, Enum.BulkMoveMode.FireCFrameChanged)
		end)
		if not ok then
			for i, part in ipairs(parts) do
				part.CFrame = cframes[i]
			end
		end
	end
end

----------------------------------------------------------------------
-- Sol mouillé (Color / Reflectance des sols durs de la ville)
----------------------------------------------------------------------

local function collectWet()
	table.clear(wetList)
	local town = workspace:FindFirstChild("DopamineTown")
	if not town then
		return
	end
	for _, d in ipairs(town:GetDescendants()) do
		if d:IsA("BasePart") and HARD[d.Material] and d.Transparency < 0.5 then
			local size = d.Size
			local up = d.CFrame.UpVector.Y
			if up > 0.9 and size.Y <= 4 and size.X * size.Z >= 24 then
				table.insert(wetList, { Part = d, Color = d.Color, Reflectance = tonumber(d.Reflectance) or 0 })
				if #wetList >= 2500 then
					break
				end
			end
		end
	end
end

local function paintWet(rec: WetRec, wet: number, gloss: number)
	local part = rec.Part
	if part.Parent == nil then
		return
	end
	part.Color = rec.Color:Lerp(rec.Color:Lerp(Color3.new(0.1, 0.11, 0.13), 0.5), 0.55 * wet)
	part.Reflectance = rec.Reflectance + gloss * wet
end

-- Peint le sol mouillé par tranches (300 pièces par appel au plus)
local function stepWet()
	if #wetList == 0 then
		return
	end
	local q = GraphicsQuality.Get()
	local gloss = q.Reflections == "All" and 0.16 or 0.07
	if wetCursor == 0 then
		if math.abs(wetTarget - wetApplied) < 0.02 then
			return
		end
		wetApplied = wetTarget
		wetCursor = 1
	end
	local last = math.min(#wetList, wetCursor + 299)
	for i = wetCursor, last do
		paintWet(wetList[i], wetApplied, gloss)
	end
	wetCursor = last < #wetList and last + 1 or 0
end

local function restoreWet()
	for _, rec in ipairs(wetList) do
		if rec.Part.Parent then
			rec.Part.Color = rec.Color
			rec.Part.Reflectance = rec.Reflectance
		end
	end
	table.clear(wetList)
	wetApplied = 0
	wetTarget = 0
	wetCursor = 0
end

----------------------------------------------------------------------
-- Flaques (grille du monde autour de la caméra, sur les sols durs)
----------------------------------------------------------------------

-- (cache par case, y compris "pas de flaque ici" : un lancer de rayon par case)
local puddleCells: { [string]: any } = {}
local puddleCellCount = 0

local function puddleLookup(ix: number, iz: number, camY: number): (Vector3?, number, number, number)
	local seed = ix * 92821 + iz * 68917
	if hash01(seed) > 0.42 then
		return nil, 0, 0, 0
	end
	local x = (ix + 0.2 + 0.6 * hash01(seed + 1)) * PUDDLE_CELL
	local z = (iz + 0.2 + 0.6 * hash01(seed + 2)) * PUDDLE_CELL
	local hit = castDown(x, z, camY + 40)
	if not hit then
		return nil, 0, 0, 0
	end
	local inst = hit.Instance
	local town = workspace:FindFirstChild("DopamineTown")
	if not (inst:IsA("BasePart") and HARD[inst.Material] and town and inst:IsDescendantOf(town)) then
		return nil, 0, 0, 0
	end
	if hit.Normal.Y < 0.95 then
		return nil, 0, 0, 0
	end
	local w = 2.6 + 3.4 * hash01(seed + 3)
	local d = w * (0.55 + 0.35 * hash01(seed + 4))
	return hit.Position, w, d, hash01(seed + 5) * math.pi
end

local function puddleAt(ix: number, iz: number, camY: number): (Vector3?, number, number, number)
	local key = ix .. ":" .. iz
	local cached = puddleCells[key]
	if cached == nil then
		if puddleCellCount > 600 then
			table.clear(puddleCells)
			puddleCellCount = 0
		end
		local pos, w, d, yaw = puddleLookup(ix, iz, camY)
		cached = pos and { pos, w, d, yaw } or false
		puddleCells[key] = cached
		puddleCellCount += 1
	end
	if cached == false then
		return nil, 0, 0, 0
	end
	return cached[1], cached[2], cached[3], cached[4]
end

local function stepPuddles(camPos: Vector3, level: number)
	local q = GraphicsQuality.Get()
	local want: { [string]: boolean } = {}
	if level > 0.03 and q.Weather then
		local cx, cz = math.floor(camPos.X / PUDDLE_CELL), math.floor(camPos.Z / PUDDLE_CELL)
		local r = math.ceil(PUDDLE_RANGE / PUDDLE_CELL)
		local count = 0
		for ix = cx - r, cx + r do
			for iz = cz - r, cz + r do
				local key = ix .. ":" .. iz
				local dx, dz = (ix + 0.5) * PUDDLE_CELL - camPos.X, (iz + 0.5) * PUDDLE_CELL - camPos.Z
				if dx * dx + dz * dz <= PUDDLE_RANGE * PUDDLE_RANGE and count < PUDDLE_MAX then
					local existing = puddles[key]
					if existing then
						want[key] = true
						count += 1
					else
						local pos, w, d, yaw = puddleAt(ix, iz, camPos.Y)
						if pos then
							local part = table.remove(puddlePool)
							if not part and folder then
								local p = newPart("Puddle", Vector3.new(1, 0.06, 1), PUDDLE_COLOR, 0.3)
								local mesh = Instance.new("SpecialMesh")
								mesh.MeshType = Enum.MeshType.Sphere
								mesh.Parent = p
								p.Parent = folder
								part = p
							end
							if part then
								part.CFrame = CFrame.new(pos + Vector3.new(0, 0.012, 0)) * CFrame.Angles(0, yaw, 0)
								puddles[key] = { Part = part, Key = key, Base = pos, W = w, D = d }
								want[key] = true
								count += 1
							end
						end
					end
				end
			end
		end
	end
	local reflect = q.Reflections == "All" and 0.38 or 0.2
	for key, puddle in pairs(puddles) do
		if want[key] then
			local k = 0.35 + 0.65 * level
			puddle.Part.Size = Vector3.new(puddle.W * k, 0.06, puddle.D * k)
			puddle.Part.Transparency = 1 - (0.72 * math.min(1, level * 1.6))
			puddle.Part.Reflectance = reflect
		else
			puddle.Part.CFrame = PARK
			table.insert(puddlePool, puddle.Part)
			puddles[key] = nil
		end
	end
end

-- Ronds de pluie sur les flaques
local function rippleOnPuddles(rain: number)
	if rain < 0.05 or indoor then
		return
	end
	for _, puddle in pairs(puddles) do
		if hash01(math.floor(os.clock() * 7) + #puddle.Key * 31 + puddle.Base.X) < rain * 0.8 then
			local a = hash01(math.floor(os.clock() * 13) + puddle.Base.Z) * math.pi * 2
			local r = hash01(math.floor(os.clock() * 11) + puddle.Base.X) * 0.35
			local offset = Vector3.new(math.cos(a) * puddle.W * r, 0.02, math.sin(a) * puddle.D * r)
			spawnSplash(puddle.Base + offset, 0.7 + 0.5 * rain)
		end
	end
end

----------------------------------------------------------------------
-- Éclair lointain (quelques morceaux fins, pas de Neon) + arc-en-ciel
----------------------------------------------------------------------

local function ensureBolt()
	if #bolt > 0 or not folder then
		return
	end
	for i = 1, 8 do
		local part = newPart("Lightning", Vector3.new(1.4, 1, 1.4), BOLT_COLOR, 1)
		part.Parent = folder
		bolt[i] = part
	end
end

local function stepBolt(t: number, flash: number, slot: number?, camPos: Vector3)
	if #bolt == 0 then
		return
	end
	if flash <= 0.02 or slot == nil or hash01(slot * 9 + 5) > 0.55 then
		if boltSlot ~= nil then
			boltSlot = nil
			for _, part in ipairs(bolt) do
				part.Transparency = 1
				part.CFrame = PARK
			end
		end
		return
	end
	if boltSlot ~= slot then
		boltSlot = slot
		local yaw = hash01(slot * 13 + 1) * math.pi * 2
		local dist = 380 + 140 * hash01(slot * 13 + 2)
		local base = camPos + Vector3.new(math.cos(yaw) * dist, 0, math.sin(yaw) * dist)
		local p = base + Vector3.new(0, 250, 0)
		local side = Vector3.new(-math.sin(yaw), 0, math.cos(yaw))
		for i, part in ipairs(bolt) do
			local nextP = base + Vector3.new(0, 250 - i * (250 / #bolt), 0) + side * ((hash01(slot * 17 + i) - 0.5) * 46)
			local length = (nextP - p).Magnitude
			part.Size = Vector3.new(1.3 - i * 0.08, length + 0.6, 1.3 - i * 0.08)
			part.CFrame = CFrame.lookAt((p + nextP) / 2, nextP) * CFrame.Angles(math.pi / 2, 0, 0)
			p = nextP
		end
	end
	for _, part in ipairs(bolt) do
		part.Transparency = 1 - 0.75 * flash
	end
end

local function sunDirection(): Vector3
	local ok, dir = pcall(function()
		return game:GetService("Lighting"):GetSunDirection()
	end)
	if ok and typeof(dir) == "Vector3" and dir.Magnitude > 0.1 then
		return dir.Unit
	end
	return Vector3.new(0.45, 0.6, 0.66).Unit
end

local function clearRainbow()
	for _, part in ipairs(rainbowParts) do
		part:Destroy()
	end
	table.clear(rainbowParts)
	rainbowShown = 0
end

local RB_DIST, RB_SEGMENTS = 700, 24
local function stepRainbow(amount: number, camPos: Vector3)
	local night = options.IsNight and options.IsNight() == true
	if amount < 0.03 or night or indoor or not GraphicsQuality.Get().Weather then
		if #rainbowParts > 0 then
			clearRainbow()
		end
		return
	end
	-- à l'opposé du soleil ; centre au plus 20° sous l'horizon (arc visible)
	local sun = sunDirection()
	local flat = Vector3.new(-sun.X, 0, -sun.Z)
	if flat.Magnitude < 0.05 then
		flat = Vector3.new(0, 0, 1)
	end
	flat = flat.Unit
	local depress = math.rad(math.min(20, math.deg(math.asin(math.clamp(sun.Y, -1, 1)))))
	local dir = (flat * math.cos(depress) - Vector3.new(0, math.sin(depress), 0)).Unit
	local center = camPos + dir * RB_DIST
	local e1 = Vector3.new(0, 1, 0):Cross(dir).Unit
	local e2 = dir:Cross(e1).Unit
	if e2.Y < 0 then
		e2 = -e2
	end
	if #rainbowParts == 0 and folder then
		for band = 1, #RAINBOW do
			for seg = 1, RB_SEGMENTS do
				local part = newPart("Rainbow", Vector3.new(1, 1, 1), RAINBOW[band], 1)
				part:SetAttribute("Band", band)
				part:SetAttribute("Seg", seg)
				part.Parent = folder
				table.insert(rainbowParts, part)
			end
		end
	end
	local parts, cframes = {}, {}
	local outer = RB_DIST * math.tan(math.rad(42))
	local bandW = RB_DIST * math.tan(math.rad(0.45))
	for _, part in ipairs(rainbowParts) do
		local band = part:GetAttribute("Band") :: number
		local seg = part:GetAttribute("Seg") :: number
		local r = outer - (band - 0.5) * bandW
		local a0 = (seg - 1) / RB_SEGMENTS * math.pi
		local a1 = seg / RB_SEGMENTS * math.pi
		local am = (a0 + a1) / 2
		local radial = e1 * math.cos(am) + e2 * math.sin(am)
		local tangent = -e1 * math.sin(am) + e2 * math.cos(am)
		local pos = center + radial * r
		local length = r * (a1 - a0) * 1.04
		if part.Size.Y ~= length then
			part.Size = Vector3.new(bandW * 1.02, length, 1)
		end
		table.insert(parts, part)
		table.insert(cframes, CFrame.fromMatrix(pos, radial, tangent))
	end
	pcall(function()
		workspace:BulkMoveTo(parts, cframes, Enum.BulkMoveMode.FireCFrameChanged)
	end)
	local transparency = 1 - 0.32 * smooth(amount)
	if math.abs(transparency - rainbowShown) > 0.01 then
		rainbowShown = transparency
		for _, part in ipairs(rainbowParts) do
			part.Transparency = transparency
		end
	end
end

----------------------------------------------------------------------
-- Intérieur ? (pas de pluie dans les maisons / boutiques)
----------------------------------------------------------------------

local function collectShops()
	table.clear(shopBoxes)
	local function scan(root: Instance?)
		if not root then
			return
		end
		for _, d in ipairs(root:GetDescendants()) do
			if d:IsA("Model") then
				local cf = d:GetAttribute("InteriorCF")
				local size = d:GetAttribute("InteriorSize")
				if typeof(cf) == "CFrame" and typeof(size) == "Vector3" then
					table.insert(shopBoxes, { CF = cf, Size = size })
				end
			end
		end
	end
	scan(workspace:FindFirstChild("DopamineTown"))
end

local function inShop(p: Vector3): boolean
	for _, box in ipairs(shopBoxes) do
		local rel = box.CF:PointToObjectSpace(p)
		if math.abs(rel.X) <= box.Size.X / 2 and math.abs(rel.Z) <= box.Size.Z / 2 and rel.Y >= -1 and rel.Y <= box.Size.Y + 0.5 then
			return true
		end
	end
	return false
end

local function castFrom(origin: Vector3, direction: Vector3): RaycastResult?
	local ok, result = pcall(function()
		local params = RaycastParams.new()
		params.FilterType = Enum.RaycastFilterType.Exclude
		local list: { Instance } = {}
		if folder then
			table.insert(list, folder)
		end
		local character = Players.LocalPlayer and Players.LocalPlayer.Character
		if character then
			table.insert(list, character)
		end
		params.FilterDescendantsInstances = list
		return workspace:Raycast(origin, direction, params)
	end)
	return ok and result or nil
end

-- Sonde par défaut : un plafond au-dessus ET des murs d'une maison sur 3 côtés
local function defaultIndoor(p: Vector3): boolean
	if inShop(p) then
		return true
	end
	local houses = workspace:FindFirstChild("TownHouses")
	if not houses then
		return false
	end
	local up = castFrom(p, Vector3.new(0, 40, 0))
	if not (up and up.Instance:IsDescendantOf(houses)) then
		return false
	end
	local walls = 0
	for _, dir in ipairs({ Vector3.new(30, 0, 0), Vector3.new(-30, 0, 0), Vector3.new(0, 0, 30), Vector3.new(0, 0, -30) }) do
		local hit = castFrom(p, dir)
		if hit and hit.Instance:IsDescendantOf(houses) then
			walls += 1
		end
	end
	return walls >= 3
end

function Weather3D.SetIndoorProbe(fn: ((Vector3) -> boolean)?)
	indoorProbe = fn
end

function Weather3D.IsIndoor(): boolean
	return indoor
end

----------------------------------------------------------------------
-- Cycle de vie
----------------------------------------------------------------------

function Weather3D.SetForcedTime(t: number?)
	forcedTime = t
	slowClock = 1e9
	puddleClock = 1e9
end

function Weather3D.State(): WeatherState
	return state
end

local function disabledState(): WeatherState
	return {
		Kind = "Clear",
		Phase = 0,
		Cloud = 0.3,
		Rain = 0,
		Storm = 0,
		Rainbow = 0,
		Wet = 0,
		Puddles = 0,
		Flash = 0,
		Indoor = indoor,
		Enabled = false,
	}
end

function Weather3D.Start(opts: any?)
	if active then
		return
	end
	active = true
	options = opts or {}
	local f = Instance.new("Folder")
	f.Name = "DopamineWeather"
	f.Parent = workspace
	folder = f
	stepClock, slowClock, puddleClock, indoorClock, shopClock = 0, 1e9, 1e9, 1e9, 0
	indoor = false
	collectWet()
	collectShops()
	ensureBolt()
	state = GraphicsQuality.Get().Weather and Weather3D.At(now()) or disabledState()
	qualityConn = GraphicsQuality.Changed:Connect(function()
		slowClock = 1e9
		puddleClock = 1e9
		wetApplied = -1 -- (repeindre avec le nouveau brillant)
	end)
end

function Weather3D.Stop()
	if not active then
		return
	end
	active = false
	if qualityConn then
		qualityConn:Disconnect()
		qualityConn = nil
	end
	restoreWet()
	clearRainbow()
	local f = folder
	folder = nil
	if f then
		f:Destroy()
	end
	table.clear(drops)
	table.clear(splashes)
	table.clear(splashFree)
	table.clear(puddles)
	table.clear(puddlePool)
	table.clear(bolt)
	table.clear(heights)
	heightCount = 0
	table.clear(puddleCells)
	puddleCellCount = 0
	shownDrops = 0
	boltSlot = nil
	state = disabledState()
end

function Weather3D.IsActive(): boolean
	return active
end

function Weather3D.Step(dt: number)
	if not active then
		return
	end
	local cam = camera()
	if not cam then
		return
	end
	local camCF = cam.CFrame
	local t = now()
	local q = GraphicsQuality.Get()
	-- météo (2 fois / s) : état + sol mouillé
	slowClock += dt
	if slowClock >= 0.5 then
		slowClock = 0
		if q.Weather then
			local s = Weather3D.At(t)
			s.Indoor = indoor
			state = s
		else
			state = disabledState()
		end
		wetTarget = state.Wet
		shopClock += 0.5
		if shopClock >= 12 then
			shopClock = 0
			collectShops()
		end
	end
	stepWet()
	-- intérieur ? (4 fois / s)
	indoorClock += dt
	if indoorClock >= 0.25 then
		indoorClock = 0
		local probe = indoorProbe
		local ok, result = pcall(function()
			if probe then
				return probe(camCF.Position) == true or inShop(camCF.Position)
			end
			return defaultIndoor(camCF.Position)
		end)
		indoor = ok and result == true
		state.Indoor = indoor
	end
	-- éclairs (chaque image pendant l'orage)
	local flash, slot = 0, nil
	if state.Storm > 0.3 and q.Weather then
		flash, slot = Weather3D.FlashAt(t, state.Storm)
	end
	state.Flash = flash
	stepBolt(t, flash, slot, camCF.Position)
	-- gouttes + éclaboussures (30 Hz au plus)
	stepClock += dt
	if stepClock >= STEP_RATE then
		local elapsed = stepClock
		stepClock = 0
		if state.Rain > 0.005 or shownDrops > 0 then
			stepDrops(t, camCF, state.Rain, state.Storm)
		end
		if #splashes > 0 then
			stepSplashes(elapsed)
		end
	end
	-- flaques + arc-en-ciel (2 fois / s)
	puddleClock += dt
	if puddleClock >= 0.5 then
		puddleClock = 0
		stepPuddles(camCF.Position, q.Weather and state.Puddles or 0)
		rippleOnPuddles(state.Rain)
		stepRainbow(state.Rainbow, camCF.Position)
	end
end

-- (tests) nombres d'objets visibles
function Weather3D.Counts(): { [string]: number }
	local p = 0
	for _ in pairs(puddles) do
		p += 1
	end
	return { Drops = shownDrops, Splashes = #splashes, Puddles = p, Wet = #wetList, Rainbow = #rainbowParts, Bolt = boltSlot and #bolt or 0 }
end

return Weather3D
