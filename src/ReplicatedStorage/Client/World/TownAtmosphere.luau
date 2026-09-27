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
	Travail : Step(dt) met à jour l'heure 1 fois / s (5 fois / s pendant un
	fondu), rien d'autre par image.

	API : TownAtmosphere.Apply(saved) / Restore(saved) / Step(dt) /
	      SetNight(on) / IsNight()
	saved = { Lighting = {}, Effects = {}, Moved = {} } (table de TownClient)
]]

local Lighting = game:GetService("Lighting")

local TownAtmosphere = {}

local CYCLE_PERIOD = 16 * 60 -- (s) aller-retour du soleil
local DAY_CLOCK, DAY_SWING = 13.4, 3.2 -- 10,2 h .. 16,6 h
local NIGHT_CLOCK = 21.3
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
TownAtmosphere.DAY = DAY
TownAtmosphere.NIGHT = NIGHT
TownAtmosphere.EFFECTS = EFFECTS
local EFFECT_ORDER = { "Atmosphere", "ColorCorrection", "Bloom", "SunRays", "DepthOfField" }

local active = false
local created: { Instance } = {}
local effects: { [string]: Instance } = {}
local clouds: Clouds? = nil
local night = false
local mix = 0 -- 0 = jour, 1 = nuit (fondu)
local elapsed = 0
local clockTimer = 0
local mixTimer = 0

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

-- Heure du soleil : cycle doux le jour, nuit fixe ; mélangée pendant le fondu
local function clockNow(): number
	local day = DAY_CLOCK + DAY_SWING * math.sin(elapsed / CYCLE_PERIOD * math.pi * 2)
	local m = smooth(mix)
	return day + (NIGHT_CLOCK - day) * m
end

local function applyMix()
	local m = smooth(mix)
	for key, dayValue in pairs(DAY) do
		set(Lighting, key, lerp(dayValue, NIGHT[key], m))
	end
	for name, spec in pairs(EFFECTS) do
		local instance = effects[name]
		if instance then
			for key, dayValue in pairs(spec.Day) do
				set(instance, key, lerp(dayValue, (spec.Night :: any)[key], m))
			end
		end
	end
	local cloud = clouds
	if cloud then
		set(cloud, "Color", Color3.fromRGB(255, 255, 255):Lerp(Color3.fromRGB(90, 96, 140), m))
		set(cloud, "Cover", lerp(0.52, 0.4, m))
	end
	set(Lighting, "ClockTime", clockNow())
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
	mix = night and 1 or 0
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
	applyMix()
end

function TownAtmosphere.Restore(saved: any)
	if not active then
		return
	end
	active = false
	for _, instance in ipairs(created) do
		pcall(instance.Destroy, instance)
	end
	table.clear(created)
	table.clear(effects)
	clouds = nil
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
	return night
end

-- (tests) valeur du fondu jour -> nuit
function TownAtmosphere.Mix(): number
	return mix
end

function TownAtmosphere.Step(dt: number)
	if not active then
		return
	end
	elapsed += dt
	local target = night and 1 or 0
	if mix ~= target then
		mixTimer += dt
		if mixTimer >= 0.2 then
			local step = mixTimer / FADE_TIME
			mixTimer = 0
			if mix < target then
				mix = math.min(target, mix + step)
			else
				mix = math.max(target, mix - step)
			end
			applyMix()
		end
		return
	end
	clockTimer += dt
	if clockTimer >= 1 then
		clockTimer = 0
		set(Lighting, "ClockTime", clockNow())
	end
end

return TownAtmosphere
