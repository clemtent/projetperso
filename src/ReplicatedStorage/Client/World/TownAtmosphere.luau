--[[
	TownAtmosphere (ModuleScript)
	Emplacement : ReplicatedStorage > Client > World > TownAtmosphere

	🌤️ Dopamine Town : ambiance réaliste (côté client, remise EXACTEMENT à
	la sortie).
	  - Lighting : soleil d'après-midi chaud, ombres nettes, lumière
	    ambiante douce, reflets d'environnement (Lighting.Technology n'est
	    pas modifiable par un script : on garde celle du lieu) ;
	  - Atmosphere (brume de distance, halo du soleil), ciel Roblox par
	    défaut (Sky sans textures : soleil, lune, étoiles), nuages (Clouds
	    dans Terrain), ColorCorrection, SunRays, Bloom doux, léger flou de
	    profondeur au loin ;
	  - jour / nuit : suit le réglage ⚙️ "Mode sombre" du joueur (nuit
	    étoilée, lampadaires) ; le jour, lent cycle du soleil (matin ->
	    fin d'après-midi -> matin, 16 min), jamais la nuit par surprise ;
	    passage jour <-> nuit en fondu (~2,5 s) ;
	  - AUCUN son.
	v9.8 (REALISM98) 🌦️ météo + 🎨 réglages "Graphismes / Mode réaliste" :
	  - la météo de Weather3D (cycle commun à tous les joueurs) s'ajoute au
	    jour / nuit : ciel couvert (soleil plus faible, ombres douces, plus
	    de lumière ambiante, nuages Cover / Density / couleur), pluie (brume
	    Atmosphere plus dense, couleurs un peu désaturées, sols qui
	    brillent : EnvironmentSpecularScale), orage (plus sombre, lampadaires
	    allumés), éclairs DOUX : ColorCorrection +0,07 au plus (jamais
	    au-delà de +0,08), nuages éclaircis un instant ;
	  - Graphismes : Effets Off = Bloom / SunRays / flou lointain coupés ;
	    Ombres Low = GlobalShadows coupé ; Mode réaliste = matières un peu
	    plus riches (reflets d'environnement +0,08, ombres un peu plus
	    nettes) ;
	  - démarre / arrête Weather3D (pluie, flaques, sol mouillé) et les
	    miroirs (Reflections.Acquire("Town") / Release).
	v9.9 (REALISM99) 🕐 "Heure du jour" (Graphismes, clé GfxTime, pour CE
	joueur seulement : Lighting est local) :
	  - Auto : comme avant (nuit = réglage ⚙️ "Mode sombre"), mais le lent
	    cycle du soleil suit l'heure du SERVEUR (même soleil pour tous) ;
	  - Jour : plein jour fixe (12 h 50) ; Nuit : nuit étoilée ;
	  - Coucher de soleil : 17 h 50, lumière dorée douce (table SUNSET :
	    Brightness ≤ 1,3, pas d'éblouissement), brume orangée, lampadaires
	    allumés ;
	  - fondus doux (~2,5 s) entre les 4 ; la météo s'ajoute par-dessus ;
	    tout est remis à la sortie (les clés de Lighting sont sauvegardées).
	Travail : Step(dt) : Weather3D.Step, éclairage recalculé 2 fois / s
	(5 fois / s pendant un fondu), l'éclair seul à chaque image.

	API : TownAtmosphere.Apply(saved) / Restore(saved) / Step(dt) /
	      SetNight(on) / IsNight() / Weather() -> état de Weather3D
	      TimeMode() -> "Auto" | "Day" | "Sunset" | "Night" ; Dusk() -> 0..1
	saved = { Lighting = {}, Effects = {}, Moved = {} } (table de TownClient)
]]

local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GraphicsQuality = require(ReplicatedStorage.Shared.GraphicsQuality)

-- (v9.8) modules du même dossier, chargés en pcall : la ville marche sans eux
local function optional(name: string): any
	local module = script.Parent:FindFirstChild(name)
	if module and module:IsA("ModuleScript") then
		local ok, result = pcall(require, module)
		if ok and type(result) == "table" then
			return result
		end
		warn("[TownAtmosphere] " .. name .. " : " .. tostring(result))
	end
	return nil
end
local Weather3D = optional("Weather3D")
local Reflections = optional("Reflections")

local TownAtmosphere = {}

local CYCLE_PERIOD = 16 * 60 -- (s) aller-retour du soleil
local DAY_CLOCK, DAY_SWING = 13.4, 3.2 -- 10,2 h .. 16,6 h
local NIGHT_CLOCK = 21.3
local NOON_CLOCK = 12.85 -- (v9.9) "Jour" : plein jour fixe
local SUNSET_CLOCK = 17.85 -- (v9.9) "Coucher de soleil" : soleil bas, doré
local FADE_TIME = 2.5

-- Réglages de Lighting (jour / nuit) : mêmes clés dans les deux
-- v9.6 (FIXES96) "FLASH BANG" en vrai Roblox (Future / ShadowMap) : la v9.4
-- cumulait Brightness 3 + ExposureCompensation positive + ColorShift_Top
-- presque blanc (s'AJOUTE à la lumière du soleil) + reflets d'environnement
-- à 1 (plastique lisse / verre / métal qui éblouissent) + halo Atmosphere
-- (Glare 0.45, Haze 1.4) + Bloom de nuit à seuil bas (0.95 : chaque pièce
-- Neon devenait un phare). Valeurs douces et naturelles (tableau avant /
-- après dans le rapport v9.6) :
local DAY: { [string]: any } = {
	Brightness = 1.8, -- (3)
	Ambient = Color3.fromRGB(72, 70, 80), -- (96, 92, 106) intérieurs moins "cramés"
	OutdoorAmbient = Color3.fromRGB(118, 116, 126), -- (132, 128, 142)
	ColorShift_Top = Color3.fromRGB(46, 38, 30), -- (255, 238, 220) léger ton chaud, plus un 2e soleil
	ColorShift_Bottom = Color3.fromRGB(0, 0, 0), -- (40, 32, 48)
	EnvironmentDiffuseScale = 0.45, -- (1)
	EnvironmentSpecularScale = 0.35, -- (1) plus de reflets aveuglants
	ExposureCompensation = -0.15, -- (+0.15)
	ShadowSoftness = 0.25, -- (0.18)
	FogColor = Color3.fromRGB(206, 214, 228),
}
local NIGHT: { [string]: any } = {
	Brightness = 0.9, -- (1.4)
	Ambient = Color3.fromRGB(40, 40, 58), -- (58, 56, 88)
	OutdoorAmbient = Color3.fromRGB(62, 66, 100), -- (78, 82, 128)
	ColorShift_Top = Color3.fromRGB(22, 26, 46), -- (170, 184, 255)
	ColorShift_Bottom = Color3.fromRGB(0, 0, 0), -- (20, 16, 40)
	EnvironmentDiffuseScale = 0.3, -- (0.7)
	EnvironmentSpecularScale = 0.3, -- (1)
	ExposureCompensation = -0.1, -- (+0.35)
	ShadowSoftness = 0.35, -- (0.3)
	FogColor = Color3.fromRGB(34, 38, 68),
}
-- (v9.9) coucher de soleil : chaud et DOUX (Brightness 1,25 < jour 1,8)
local SUNSET: { [string]: any } = {
	Brightness = 1.25,
	Ambient = Color3.fromRGB(78, 62, 72),
	OutdoorAmbient = Color3.fromRGB(138, 108, 110),
	ColorShift_Top = Color3.fromRGB(72, 42, 20),
	ColorShift_Bottom = Color3.fromRGB(0, 0, 0),
	EnvironmentDiffuseScale = 0.4,
	EnvironmentSpecularScale = 0.33,
	ExposureCompensation = -0.1,
	ShadowSoftness = 0.3,
	FogColor = Color3.fromRGB(232, 176, 150),
}
-- (fixés une fois, sans fondu)
local FIXED: { [string]: any } = {
	GlobalShadows = true,
	GeographicLatitude = 38,
	FogStart = 800,
	FogEnd = 4000,
	ClockTime = DAY_CLOCK,
}

-- Effets : valeurs jour / nuit (v9.6 : halo, bloom et rayons très adoucis)
local EFFECTS = {
	Atmosphere = {
		Class = "Atmosphere",
		-- (Glare 0.45 -> 0.1, Haze 1.4 -> 0.7, Density 0.3 -> 0.26)
		Day = { Density = 0.26, Offset = 0.2, Color = Color3.fromRGB(206, 206, 220), Decay = Color3.fromRGB(106, 112, 134), Glare = 0.1, Haze = 0.7 },
		-- (Haze 1.1 -> 0.6)
		Night = { Density = 0.32, Offset = 0.1, Color = Color3.fromRGB(62, 68, 108), Decay = Color3.fromRGB(30, 28, 62), Glare = 0, Haze = 0.6 },
	},
	ColorCorrection = {
		Class = "ColorCorrectionEffect",
		-- (Brightness 0.01 -> -0.02, Contrast 0.08 -> 0.05)
		Day = { Saturation = 0.06, Contrast = 0.05, Brightness = -0.02, TintColor = Color3.fromRGB(255, 250, 244) },
		-- (Brightness 0.02 -> -0.03)
		Night = { Saturation = 0, Contrast = 0.06, Brightness = -0.03, TintColor = Color3.fromRGB(226, 230, 255) },
	},
	Bloom = {
		Class = "BloomEffect",
		-- (0.35 / 28 / 1.3 -> seules les vraies sources de lumière fleurissent)
		Day = { Intensity = 0.2, Size = 18, Threshold = 1.8 },
		-- (0.8 / 32 / 0.95 = le "flash" de nuit -> 0.3 / 20 / 1.5)
		Night = { Intensity = 0.3, Size = 20, Threshold = 1.5 },
	},
	SunRays = {
		Class = "SunRaysEffect",
		-- (0.07 / 0.55)
		Day = { Intensity = 0.04, Spread = 0.35 },
		Night = { Intensity = 0, Spread = 0.2 },
	},
	DepthOfField = {
		Class = "DepthOfFieldEffect",
		Day = { FarIntensity = 0.12, FocusDistance = 70, InFocusRadius = 90, NearIntensity = 0 },
		Night = { FarIntensity = 0.16, FocusDistance = 60, InFocusRadius = 80, NearIntensity = 0 },
	},
}
-- (v9.9) effets au coucher de soleil (mêmes clés que Day)
local SUNSET_FX: { [string]: { [string]: any } } = {
	Atmosphere = { Density = 0.3, Offset = 0.15, Color = Color3.fromRGB(236, 172, 142), Decay = Color3.fromRGB(138, 88, 112), Glare = 0.22, Haze = 1.0 },
	ColorCorrection = { Saturation = 0.1, Contrast = 0.05, Brightness = -0.02, TintColor = Color3.fromRGB(255, 236, 218) },
	Bloom = { Intensity = 0.22, Size = 20, Threshold = 1.7 },
	SunRays = { Intensity = 0.05, Spread = 0.4 },
	DepthOfField = { FarIntensity = 0.14, FocusDistance = 65, InFocusRadius = 85, NearIntensity = 0 },
}
TownAtmosphere.DAY = DAY
TownAtmosphere.NIGHT = NIGHT
TownAtmosphere.SUNSET = SUNSET
TownAtmosphere.SUNSET_FX = SUNSET_FX
TownAtmosphere.EFFECTS = EFFECTS
local EFFECT_ORDER = { "Atmosphere", "ColorCorrection", "Bloom", "SunRays", "DepthOfField" }

-- v9.8 🌦️ météo : cibles "ciel couvert" (k = couverture), "pluie" (r), "orage" (s)
local OVERCAST = {
	OutdoorAmbient = Color3.fromRGB(134, 136, 146),
	FogColor = Color3.fromRGB(172, 178, 190),
	AtmoColor = Color3.fromRGB(184, 190, 200),
	AtmoDecay = Color3.fromRGB(122, 128, 142),
	Tint = Color3.fromRGB(236, 242, 255),
	Clouds = Color3.fromRGB(172, 176, 186),
}
local STORM = {
	OutdoorAmbient = Color3.fromRGB(96, 100, 114),
	Clouds = Color3.fromRGB(112, 116, 130),
}
local FLASH_CC = 0.07 -- éclair : ColorCorrection.Brightness en plus (doux)
local FLASH_CC_MAX = 0.08 -- plafond absolu (pas de "flash bang")
TownAtmosphere.FLASH_CC_MAX = FLASH_CC_MAX

local active = false
local created: { Instance } = {}
local effects: { [string]: Instance } = {}
local clouds: Clouds? = nil
local night = false
local mix = 0 -- 0 = jour, 1 = nuit (fondu)
local dusk = 0 -- (v9.9) 0 = jour, 1 = coucher de soleil (fondu)
local elapsed = 0
local clockTimer = 0
local mixTimer = 0
local ccBase = 0 -- ColorCorrection.Brightness sans éclair
local cloudBase = Color3.new(1, 1, 1) -- couleur des nuages sans éclair
local lastFlash = 0
local weatherWarned = false
local qualityConn: any = nil

local function lerp(a: any, b: any, t: number): any
	if typeof(a) == "Color3" then
		return (a :: Color3):Lerp(b, t)
	elseif type(a) == "number" then
		return a + (b - a) * t
	end
	return t < 0.5 and a or b
end

local function set(instance: Instance, key: string, value: any)
	pcall(function()
		(instance :: any)[key] = value
	end)
end

local function smooth(t: number): number
	return t * t * (3 - 2 * t)
end

----------------------------------------------------------------------
-- v9.6 : lampes de la ville allumées LA NUIT seulement. Le serveur
-- (TownKit) marque ses vraies lumières "NightOnly" et les verres de
-- lanterne "NightGlow" : le jour, lumières éteintes et verre mat
-- (SmoothPlastic) au lieu de Neon ; remis tels quels à la sortie.
-- (DescendantAdded : pièces qui arrivent plus tard avec le streaming)
----------------------------------------------------------------------

local lightSaved: { [Instance]: boolean } = {}
local glowSaved: { [Instance]: Enum.Material } = {}
local lampsOn = false
local townConnection: RBXScriptConnection? = nil

local function trackLamp(d: Instance)
	if d:IsA("Light") then
		if d:GetAttribute("NightOnly") == true then
			if lightSaved[d] == nil then
				lightSaved[d] = (d :: Light).Enabled
			end
			(d :: Light).Enabled = lampsOn
		end
	elseif d:IsA("BasePart") and d:GetAttribute("NightGlow") == true then
		if glowSaved[d] == nil then
			glowSaved[d] = (d :: BasePart).Material
		end
		(d :: BasePart).Material = lampsOn and Enum.Material.Neon or Enum.Material.SmoothPlastic
	end
end

local function setLamps(on: boolean)
	if lampsOn == on then
		return
	end
	lampsOn = on
	for light in pairs(lightSaved) do
		if light.Parent then
			(light :: Light).Enabled = on
		end
	end
	for part in pairs(glowSaved) do
		if part.Parent then
			(part :: BasePart).Material = on and Enum.Material.Neon or Enum.Material.SmoothPlastic
		end
	end
end

local function watchLamps()
	local town = workspace:FindFirstChild("DopamineTown")
	if not town then
		return
	end
	for _, d in ipairs(town:GetDescendants()) do
		trackLamp(d)
	end
	townConnection = town.DescendantAdded:Connect(trackLamp)
end

local function restoreLamps()
	if townConnection then
		townConnection:Disconnect()
		townConnection = nil
	end
	for light, enabled in pairs(lightSaved) do
		if light.Parent then
			(light :: Light).Enabled = enabled
		end
	end
	for part, material in pairs(glowSaved) do
		if part.Parent then
			(part :: BasePart).Material = material
		end
	end
	table.clear(lightSaved)
	table.clear(glowSaved)
end

-- (tests) lampes allumées ?
function TownAtmosphere.LampsOn(): boolean
	return lampsOn
end

-- (v9.9) réglage "Heure du jour" de ce joueur
local function timeMode(): string
	local ok, mode = pcall(function()
		return GraphicsQuality.Get().TimeOfDay
	end)
	if ok and (mode == "Day" or mode == "Sunset" or mode == "Night") then
		return mode
	end
	return "Auto"
end

-- Nuit voulue : réglage "Heure du jour", sinon "Mode sombre" (Auto)
local function wantNight(): boolean
	local mode = timeMode()
	if mode == "Night" then
		return true
	elseif mode == "Day" or mode == "Sunset" then
		return false
	end
	return night
end

-- Temps du cycle du soleil (Auto) : l'heure du serveur (même soleil pour tous)
local function cycleTime(): number
	local ok, t = pcall(function()
		return workspace:GetServerTimeNow()
	end)
	if ok and type(t) == "number" then
		return t
	end
	return elapsed
end

-- Heure du soleil : cycle doux le jour (Auto) ou midi fixe (Jour), coucher
-- de soleil, nuit fixe ; mélangée pendant les fondus
local function clockNow(): number
	local day
	if timeMode() == "Day" then
		day = NOON_CLOCK
	else
		day = DAY_CLOCK + DAY_SWING * math.sin(cycleTime() / CYCLE_PERIOD * math.pi * 2)
	end
	day += (SUNSET_CLOCK - day) * smooth(dusk)
	local m = smooth(mix)
	return day + (NIGHT_CLOCK - day) * m
end

-- (v9.8) état de la météo (beau temps si Weather3D est absent)
local function weatherState(): any
	if Weather3D and Weather3D.IsActive() then
		return Weather3D.State()
	end
	return { Cloud = 0.3, Rain = 0, Storm = 0, Wet = 0, Flash = 0, Enabled = false }
end

-- Valeurs finales = jour / nuit (fondu) + météo + réglages 🎨
local function applyMix()
	local m = smooth(mix)
	local w = weatherState()
	local q = GraphicsQuality.Get()
	-- couverture : 0 = ciel dégagé, 1 = tout gris
	local k = smooth(math.clamp((w.Cloud - 0.35) / 0.6, 0, 1))
	local r, s = w.Rain, w.Storm
	local d = smooth(dusk)
	local L: { [string]: any } = {}
	for key, dayValue in pairs(DAY) do
		L[key] = lerp(lerp(dayValue, SUNSET[key], d), NIGHT[key], m)
	end
	L.Brightness *= 1 - 0.3 * k - 0.15 * s
	L.OutdoorAmbient = (L.OutdoorAmbient :: Color3):Lerp(OVERCAST.OutdoorAmbient, 0.55 * k * (1 - m)):Lerp(STORM.OutdoorAmbient, 0.6 * s * (1 - m))
	L.ColorShift_Top = (L.ColorShift_Top :: Color3):Lerp(Color3.new(0, 0, 0), k)
	L.ShadowSoftness = lerp(L.ShadowSoftness, 0.8, k)
	L.EnvironmentSpecularScale += 0.28 * w.Wet
	L.ExposureCompensation -= 0.1 * s
	L.FogColor = (L.FogColor :: Color3):Lerp(OVERCAST.FogColor, k * (1 - m))
	if q.Realistic then
		L.EnvironmentSpecularScale += 0.08
		L.EnvironmentDiffuseScale += 0.1
		L.ShadowSoftness = math.max(0.12, L.ShadowSoftness - 0.05)
	end
	for key, value in pairs(L) do
		set(Lighting, key, value)
	end
	set(Lighting, "GlobalShadows", q.Shadows ~= "Low")
	for name, spec in pairs(EFFECTS) do
		local instance = effects[name]
		if instance then
			local E: { [string]: any } = {}
			local sunsetFx = SUNSET_FX[name] or spec.Day
			for key, dayValue in pairs(spec.Day) do
				E[key] = lerp(lerp(dayValue, sunsetFx[key], d), (spec.Night :: any)[key], m)
			end
			if name == "Atmosphere" then
				E.Density += 0.14 * r + 0.05 * k
				E.Haze += 1.3 * r
				E.Glare *= 1 - k
				E.Color = (E.Color :: Color3):Lerp(OVERCAST.AtmoColor, k * (1 - m))
				E.Decay = (E.Decay :: Color3):Lerp(OVERCAST.AtmoDecay, k * (1 - m))
			elseif name == "ColorCorrection" then
				E.Saturation -= 0.18 * k
				E.Contrast += 0.02 * s
				E.Brightness -= 0.02 * s
				E.TintColor = (E.TintColor :: Color3):Lerp(OVERCAST.Tint, 0.6 * k)
				ccBase = E.Brightness
				E.Brightness = ccBase + math.min(FLASH_CC * lastFlash, FLASH_CC_MAX)
			elseif name == "SunRays" then
				E.Intensity *= 1 - k
			end
			for key, value in pairs(E) do
				set(instance, key, value)
			end
			-- Graphismes > Effets : halo, rayons, flou lointain
			if name == "Bloom" or name == "SunRays" or name == "DepthOfField" then
				set(instance, "Enabled", q.Effects)
			end
		end
	end
	local cloud = clouds
	if cloud then
		local color = Color3.fromRGB(255, 255, 255):Lerp(OVERCAST.Clouds, k):Lerp(STORM.Clouds, s)
		cloudBase = color:Lerp(Color3.fromRGB(90, 96, 140), m)
		set(cloud, "Color", cloudBase:Lerp(Color3.new(1, 1, 1), 0.5 * lastFlash))
		local cover = w.Enabled and (0.25 + 0.7 * w.Cloud) or 0.52
		set(cloud, "Cover", lerp(cover, math.max(0.4, cover - 0.1), m))
		set(cloud, "Density", 0.5 + 0.45 * math.clamp(w.Cloud, 0, 1))
	end
	set(Lighting, "ClockTime", clockNow())
	-- (orage : les lampadaires s'allument aussi le jour)
	-- (v9.9 : et au coucher de soleil)
	setLamps(m >= 0.5 or s > 0.55 or d >= 0.5)
end

-- (v9.8) éclair : seulement la ColorCorrection et les nuages, à chaque image
local function applyFlash(flash: number)
	local cc = effects.ColorCorrection
	if cc then
		set(cc, "Brightness", ccBase + math.min(FLASH_CC * flash, FLASH_CC_MAX))
	end
	local cloud = clouds
	if cloud then
		set(cloud, "Color", cloudBase:Lerp(Color3.new(1, 1, 1), 0.5 * flash))
	end
end

local function remember(saved: any, key: string)
	if saved.Lighting[key] ~= nil then
		return
	end
	local ok, current = pcall(function()
		return (Lighting :: any)[key]
	end)
	if ok then
		saved.Lighting[key] = current
	end
end

local function terrain(): Instance?
	local ok, result = pcall(function()
		return workspace:FindFirstChildOfClass("Terrain")
	end)
	return ok and result or nil
end

function TownAtmosphere.Apply(saved: any)
	if active then
		return
	end
	active = true
	elapsed = 0
	clockTimer = 0
	mixTimer = 0
	mix = wantNight() and 1 or 0
	dusk = timeMode() == "Sunset" and 1 or 0
	lampsOn = mix >= 0.5
	-- 1) valeurs actuelles gardées (remise exacte)
	for key in pairs(DAY) do
		remember(saved, key)
	end
	for key in pairs(FIXED) do
		remember(saved, key)
	end
	-- 2) effets / ciels du lieu mis de côté
	for _, child in ipairs(Lighting:GetChildren()) do
		if child:IsA("PostEffect") then
			table.insert(saved.Effects, { Instance = child, Enabled = child.Enabled })
			child.Enabled = false
		elseif child:IsA("Sky") or child:IsA("Atmosphere") then
			table.insert(saved.Moved, { Instance = child, Parent = Lighting })
			child.Parent = nil
		end
	end
	local ground = terrain()
	if ground then
		for _, child in ipairs(ground:GetChildren()) do
			if child:IsA("Clouds") then
				table.insert(saved.Moved, { Instance = child, Parent = ground })
				child.Parent = nil
			end
		end
	end
	-- 3) nos réglages
	for key, value in pairs(FIXED) do
		set(Lighting, key, value)
	end
	local sky = Instance.new("Sky")
	sky.Name = "DopamineTownSky"
	-- (textures par défaut de Roblox : aucun identifiant à charger)
	set(sky, "SunAngularSize", 11)
	set(sky, "MoonAngularSize", 9)
	set(sky, "StarCount", 3000)
	set(sky, "CelestialBodiesShown", true)
	sky.Parent = Lighting
	table.insert(created, sky)
	for _, name in ipairs(EFFECT_ORDER) do
		local spec = EFFECTS[name]
		local ok, instance = pcall(function()
			local i = Instance.new(spec.Class :: any)
			i.Name = "DopamineTown" .. name
			return i
		end)
		if ok and instance then
			for key, value in pairs(spec.Day) do
				set(instance, key, value)
			end
			instance.Parent = Lighting
			effects[name] = instance
			table.insert(created, instance)
		end
	end
	if ground then
		local ok, cloud = pcall(function()
			local c = Instance.new("Clouds")
			c.Name = "DopamineTownClouds"
			c.Cover = 0.52
			c.Density = 0.62
			c.Color = Color3.fromRGB(255, 255, 255)
			return c
		end)
		if ok and cloud then
			cloud.Parent = ground
			clouds = cloud
			table.insert(created, cloud)
		end
	end
	watchLamps()
	-- v9.8 🌦️ météo + 🪞 miroirs (pcall : une erreur n'empêche pas la ville)
	lastFlash = 0
	if Weather3D then
		local okW, errW = pcall(Weather3D.Start, {
			IsNight = function()
				return mix >= 0.5
			end,
		})
		if not okW then
			warn("[TownAtmosphere] Weather3D.Start : " .. tostring(errW))
		end
	end
	if Reflections then
		local okR, errR = pcall(Reflections.Acquire, "Town")
		if not okR then
			warn("[TownAtmosphere] Reflections : " .. tostring(errR))
		end
	end
	-- Graphismes changés en ville : appliqués tout de suite
	qualityConn = GraphicsQuality.Changed:Connect(function()
		if active then
			applyMix()
		end
	end)
	applyMix()
end

function TownAtmosphere.Restore(saved: any)
	if not active then
		return
	end
	active = false
	if qualityConn then
		qualityConn:Disconnect()
		qualityConn = nil
	end
	if Weather3D then
		pcall(Weather3D.Stop)
	end
	if Reflections then
		pcall(Reflections.Release, "Town")
	end
	lastFlash = 0
	for _, instance in ipairs(created) do
		pcall(instance.Destroy, instance)
	end
	table.clear(created)
	table.clear(effects)
	clouds = nil
	restoreLamps()
	for key, value in pairs(saved.Lighting) do
		set(Lighting, key, value)
	end
	for _, effect in ipairs(saved.Effects) do
		pcall(function()
			(effect.Instance :: any).Enabled = effect.Enabled
		end)
	end
	for _, entry in ipairs(saved.Moved) do
		pcall(function()
			entry.Instance.Parent = entry.Parent
		end)
	end
end

function TownAtmosphere.SetNight(on: boolean)
	night = on == true
end

function TownAtmosphere.IsNight(): boolean
	return wantNight()
end

-- (v9.9) réglage "Heure du jour" et fondu du coucher de soleil (tests)
function TownAtmosphere.TimeMode(): string
	return timeMode()
end
function TownAtmosphere.Dusk(): number
	return dusk
end

-- (tests) valeur du fondu jour -> nuit
function TownAtmosphere.Mix(): number
	return mix
end

-- (v9.8) météo en cours (Weather3D.State() ; beau temps sans Weather3D)
function TownAtmosphere.Weather(): any
	return weatherState()
end

function TownAtmosphere.Step(dt: number)
	if not active then
		return
	end
	elapsed += dt
	-- v9.8 🌦️ pluie, flaques, éclairs (Weather3D) : une seule alerte en cas d'erreur
	if Weather3D then
		local okW, errW = pcall(Weather3D.Step, dt)
		if not okW and not weatherWarned then
			weatherWarned = true
			warn("[TownAtmosphere] Weather3D.Step : " .. tostring(errW))
		end
		local flash = Weather3D.State().Flash or 0
		if flash > 0 or lastFlash > 0 then
			lastFlash = flash
			applyFlash(flash)
		end
	end
	local target = wantNight() and 1 or 0
	local duskTarget = timeMode() == "Sunset" and 1 or 0
	if mix ~= target or dusk ~= duskTarget then
		mixTimer += dt
		if mixTimer >= 0.2 then
			local step = mixTimer / FADE_TIME
			mixTimer = 0
			if mix < target then
				mix = math.min(target, mix + step)
			else
				mix = math.max(target, mix - step)
			end
			if dusk < duskTarget then
				dusk = math.min(duskTarget, dusk + step)
			else
				dusk = math.max(duskTarget, dusk - step)
			end
			applyMix()
		end
		return
	end
	-- heure du soleil + météo : 2 fois / s (changements lents)
	clockTimer += dt
	if clockTimer >= 0.5 then
		clockTimer = 0
		applyMix()
	end
end

return TownAtmosphere
