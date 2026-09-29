--[[
	GraphicsQuality (ModuleScript)
	Emplacement : ReplicatedStorage > Shared > GraphicsQuality

	v9.8 (REALISM98) 🎨 réglages "Graphismes / Mode réaliste", partagés :
	  - SERVEUR : liste des clés et des valeurs acceptées par SetSetting
	    (GameService) : GraphicsQuality.IsValid(nom, valeur) ;
	  - CLIENT : qualité "résolue" (réglages sauvegardés + appareil) que tout
	    module peut lire : GraphicsQuality.Get() et le signal .Changed.

	Réglages sauvegardés (Data.Settings, chaînes, défaut "Auto") :
	  GfxRealistic   "Auto" | "On" | "Off"          (Auto = On sur ordinateur,
	                                                 Off sur mobile / petite config)
	  GfxReflections "Auto" | "Off" | "Mirrors" | "All"
	  GfxWeather     "Auto" | "On" | "Off"
	  GfxRain        "Auto" | "Low" | "Medium" | "High"
	  GfxShadows     "Auto" | "Low" | "High"
	  GfxEffects     "Auto" | "On" | "Off"          (bloom, rayons, flou lointain)
	  GfxDetail      "Auto" | "Low" | "Medium" | "High"
	"Auto" = la valeur du préréglage (Mode réaliste ON ou OFF). Activer /
	couper le Mode réaliste remet les réglages détaillés sur "Auto".

	Qualité résolue (GraphicsQuality.Get(), table en lecture seule) :
	  {
	    Realistic: boolean,
	    Reflections: "Off" | "Mirrors" | "All",
	    Weather: boolean, Rain: "Low" | "Medium" | "High", RainScale: number,
	    Shadows: "Low" | "High", Effects: boolean,
	    Detail: "Low" | "Medium" | "High",
	    DetailScale: number,   -- 0.65 / 1 / 1.35 : multiplie les distances de flux
	    MaxMirrors: number,    -- miroirs "vivants" en même temps (0, 1 ou 2)
	    Phone: boolean, LowEnd: boolean,
	  }

	API :
	  GraphicsQuality.KEYS / .ORDER / .DEFAULT = "Auto"
	  GraphicsQuality.IsKey(nom) -> boolean
	  GraphicsQuality.IsValid(nom, valeur) -> boolean          (serveur + client)
	  GraphicsQuality.Resolve(saved, device) -> Quality          (pur, tests)
	  GraphicsQuality.Get() -> Quality
	  GraphicsQuality.Changed : Signal (Quality)
	  GraphicsQuality.DetailScale() -> number
	  GraphicsQuality.Distance(base) -> number                   (base * DetailScale)
	  GraphicsQuality.GetSaved(nom) -> string
	  GraphicsQuality.SetSaved(settings)      (client : état du serveur, Data.Settings)
	  GraphicsQuality.SetLocal(nom, valeur)   (client : choix du joueur, tout de suite)
	  GraphicsQuality.Device() -> { Phone: boolean, LowEnd: boolean }
	Pur côté serveur (aucun service client lu au chargement du module).
]]

local Signal = require(script.Parent.Signal)

local GraphicsQuality = {}

GraphicsQuality.DEFAULT = "Auto"

-- [clé] = valeurs acceptées (la 1re = "Auto")
GraphicsQuality.KEYS = {
	GfxRealistic = { "Auto", "On", "Off" },
	GfxReflections = { "Auto", "Off", "Mirrors", "All" },
	GfxWeather = { "Auto", "On", "Off" },
	GfxRain = { "Auto", "Low", "Medium", "High" },
	GfxShadows = { "Auto", "Low", "High" },
	GfxEffects = { "Auto", "On", "Off" },
	GfxDetail = { "Auto", "Low", "Medium", "High" },
}
GraphicsQuality.ORDER = { "GfxRealistic", "GfxReflections", "GfxWeather", "GfxRain", "GfxShadows", "GfxEffects", "GfxDetail" }

-- Préréglages : "Réaliste" (ordinateur) et "Standard" (= le rendu de la v9.7)
local PRESET_REAL = {
	GfxReflections = "All",
	GfxWeather = "On",
	GfxRain = "High",
	GfxShadows = "High",
	GfxEffects = "On",
	GfxDetail = "High",
}
local PRESET_STANDARD = {
	GfxReflections = "Off",
	GfxWeather = "On",
	GfxRain = "Medium",
	GfxShadows = "High",
	GfxEffects = "On",
	GfxDetail = "Medium",
}
-- (petite configuration : moins de pluie, pas d'effets, ombres simples)
local PRESET_LOW = {
	GfxReflections = "Off",
	GfxWeather = "On",
	GfxRain = "Low",
	GfxShadows = "Low",
	GfxEffects = "Off",
	GfxDetail = "Low",
}
GraphicsQuality.PRESETS = { Real = PRESET_REAL, Standard = PRESET_STANDARD, Low = PRESET_LOW }

local DETAIL_SCALE = { Low = 0.65, Medium = 1, High = 1.35 }
local RAIN_SCALE = { Low = 0.5, Medium = 1, High = 1.5 }
GraphicsQuality.DETAIL_SCALE = DETAIL_SCALE
GraphicsQuality.RAIN_SCALE = RAIN_SCALE

local VALID: { [string]: { [string]: boolean } } = {}
for key, values in pairs(GraphicsQuality.KEYS) do
	local set = {}
	for _, value in ipairs(values) do
		set[value] = true
	end
	VALID[key] = set
end

export type Quality = {
	Realistic: boolean,
	Reflections: string,
	Weather: boolean,
	Rain: string,
	RainScale: number,
	Shadows: string,
	Effects: boolean,
	Detail: string,
	DetailScale: number,
	MaxMirrors: number,
	Phone: boolean,
	LowEnd: boolean,
}
export type Device = { Phone: boolean, LowEnd: boolean }

function GraphicsQuality.IsKey(name: any): boolean
	return type(name) == "string" and VALID[name] ~= nil
end

-- Serveur (SetSetting) et client : la valeur est-elle acceptée pour cette clé ?
function GraphicsQuality.IsValid(name: any, value: any): boolean
	if type(name) ~= "string" or type(value) ~= "string" or #value > 16 then
		return false
	end
	local set = VALID[name]
	return set ~= nil and set[value] == true
end

-- Qualité finale d'après les réglages sauvegardés et l'appareil (fonction pure)
function GraphicsQuality.Resolve(saved: { [string]: any }?, device: Device?): Quality
	local s = type(saved) == "table" and saved or {}
	local dev = device or { Phone = false, LowEnd = false }
	local function read(key: string): string
		local value = s[key]
		if GraphicsQuality.IsValid(key, value) then
			return value
		end
		return GraphicsQuality.DEFAULT
	end
	local mode = read("GfxRealistic")
	local realistic
	if mode == "On" then
		realistic = true
	elseif mode == "Off" then
		realistic = false
	else
		realistic = not dev.Phone and not dev.LowEnd
	end
	local preset = realistic and PRESET_REAL or (dev.LowEnd and PRESET_LOW or PRESET_STANDARD)
	local function pick(key: string): string
		local value = read(key)
		if value == "Auto" then
			return preset[key]
		end
		return value
	end
	local reflections = pick("GfxReflections")
	local detail = pick("GfxDetail")
	local rain = pick("GfxRain")
	local maxMirrors = 0
	if reflections ~= "Off" then
		maxMirrors = (reflections == "All" and detail == "High") and 2 or 1
	end
	return {
		Realistic = realistic,
		Reflections = reflections,
		Weather = pick("GfxWeather") == "On",
		Rain = rain,
		RainScale = RAIN_SCALE[rain] or 1,
		Shadows = pick("GfxShadows"),
		Effects = pick("GfxEffects") == "On",
		Detail = detail,
		DetailScale = DETAIL_SCALE[detail] or 1,
		MaxMirrors = maxMirrors,
		Phone = dev.Phone == true,
		LowEnd = dev.LowEnd == true,
	}
end

----------------------------------------------------------------------
-- Client : état courant
----------------------------------------------------------------------

GraphicsQuality.Changed = Signal.new() -- (quality)

local saved: { [string]: string } = {}
for _, key in ipairs(GraphicsQuality.ORDER) do
	saved[key] = GraphicsQuality.DEFAULT
end
local localUntil: { [string]: number } = {} -- choix local récent : l'état du serveur est ignoré un moment
local device: Device? = nil
local current: Quality? = nil
local LOCAL_HOLD = 6 -- (s)

-- Appareil (client) : écran tactile sans souris = mobile ; qualité graphique
-- Roblox réglée à la main très bas = petite configuration
function GraphicsQuality.Device(): Device
	local cached = device
	if cached then
		return cached
	end
	local phone, lowEnd = false, false
	pcall(function()
		local UserInputService = game:GetService("UserInputService")
		phone = UserInputService.TouchEnabled == true and UserInputService.MouseEnabled ~= true
	end)
	pcall(function()
		local settings = UserSettings():GetService("UserGameSettings")
		local level = (settings :: any).SavedQualityLevel
		if typeof(level) == "EnumItem" then
			local n = tonumber(string.match(level.Name, "(%d+)$"))
			lowEnd = n ~= nil and n <= 3
		end
	end)
	local result = { Phone = phone, LowEnd = lowEnd }
	device = result
	return result
end

local function same(a: Quality, b: Quality): boolean
	for key, value in pairs(a) do
		if (b :: any)[key] ~= value then
			return false
		end
	end
	return true
end

local function refresh()
	local quality = GraphicsQuality.Resolve(saved, GraphicsQuality.Device())
	local before = current
	current = table.freeze(quality) :: any
	if before == nil or not same(before, quality) then
		GraphicsQuality.Changed:Fire(current)
	end
end

function GraphicsQuality.Get(): Quality
	local q = current
	if q == nil then
		refresh()
		q = current
	end
	return q :: Quality
end

function GraphicsQuality.DetailScale(): number
	return GraphicsQuality.Get().DetailScale
end

-- Distance de flux adaptée au réglage "Détail" (ex. 120 studs -> 78 / 120 / 162)
function GraphicsQuality.Distance(base: number): number
	return base * GraphicsQuality.Get().DetailScale
end

function GraphicsQuality.GetSaved(name: string): string
	return saved[name] or GraphicsQuality.DEFAULT
end

-- État du serveur (Data.Settings) : appliqué sauf pour un choix local récent
function GraphicsQuality.SetSaved(settings: any)
	if type(settings) ~= "table" then
		return
	end
	local now = os.clock()
	local changed = false
	for _, key in ipairs(GraphicsQuality.ORDER) do
		local value = settings[key]
		if not GraphicsQuality.IsValid(key, value) then
			value = GraphicsQuality.DEFAULT
		end
		if (localUntil[key] or 0) < now and saved[key] ~= value then
			saved[key] = value
			changed = true
		end
	end
	if changed or current == nil then
		refresh()
	end
end

-- Choix du joueur : appliqué tout de suite (la sauvegarde est faite par l'appelant)
function GraphicsQuality.SetLocal(name: string, value: string): boolean
	if not GraphicsQuality.IsValid(name, value) then
		return false
	end
	localUntil[name] = os.clock() + LOCAL_HOLD
	if saved[name] ~= value then
		saved[name] = value
		refresh()
	end
	return true
end

-- (tests) oublie l'appareil détecté / impose un appareil
function GraphicsQuality.SetDevice(dev: Device?)
	device = dev
	refresh()
end

return GraphicsQuality
