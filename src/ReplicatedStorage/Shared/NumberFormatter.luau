--[[
	NumberFormatter (ModuleScript)
	Emplacement : ReplicatedStorage > Shared > NumberFormatter

	Formate les grands nombres : 1 234 -> "1.23K", 5 600 000 -> "5.6M", etc.
]]

local NumberFormatter = {}

-- Suffixes : K = mille, M = million, B = milliard, T = billion, puis notation anglaise courte
local SUFFIXES = { "", "K", "M", "B", "T", "Qa", "Qi", "Sx", "Sp", "Oc", "No", "Dc", "UDc", "DDc", "TDc", "QaDc", "QiDc", "SxDc", "SpDc", "OcDc", "NoDc", "Vg" }

-- Retire les zéros inutiles : "1.50" -> "1.5", "2.00" -> "2"
local function trimZeros(text: string): string
	if string.find(text, "%.") then
		text = string.gsub(text, "0+$", "")
		text = string.gsub(text, "%.$", "")
	end
	return text
end

-- Format court avec suffixe (ex. 1.23M)
function NumberFormatter.Format(value: number, decimals: number?): string
	decimals = decimals or 2
	if value ~= value then
		return "0" -- NaN
	end
	if value == math.huge then
		return "∞"
	end

	local sign = value < 0 and "-" or ""
	value = math.abs(value)

	if value < 1000 then
		-- Petits nombres : entier, ou une décimale si < 10 (ex. 2.5)
		if value < 10 and value % 1 ~= 0 then
			return sign .. trimZeros(string.format("%.1f", math.floor(value * 10) / 10))
		end
		return sign .. tostring(math.floor(value))
	end

	local tier = math.floor(math.log10(value) / 3)
	-- Corrige les petites erreurs d'arrondi de log10 (ex. 999.999...)
	if value / (10 ^ (tier * 3)) >= 1000 then
		tier += 1
	elseif value / (10 ^ (tier * 3)) < 1 then
		tier -= 1
	end
	if tier >= #SUFFIXES then
		-- Au-delà des suffixes connus : notation scientifique
		return sign .. string.format("%.2e", value)
	end

	local scaled = value / (10 ^ (tier * 3))
	-- On tronque (au lieu d'arrondir) pour ne jamais afficher plus que ce qu'on a
	local factor = 10 ^ (decimals :: number)
	-- (petite marge : 1e29 / 1e27 donne 99.9999999 en virgule flottante)
	scaled = math.floor(scaled * factor + 1e-6) / factor
	return sign .. trimZeros(string.format("%." .. tostring(decimals) .. "f", scaled)) .. SUFFIXES[tier + 1]
end

-- Format avec séparateurs de milliers (ex. 1 234 567), pour les petits nombres
function NumberFormatter.WithSpaces(value: number): string
	local text = tostring(math.floor(value))
	local result = string.reverse(text)
	result = string.gsub(result, "(%d%d%d)", "%1 ")
	result = string.reverse(result)
	return (string.gsub(result, "^%s+", ""))
end

-- Durée en secondes -> "1h 05m", "4m 12s", "9s"
function NumberFormatter.Time(seconds: number): string
	seconds = math.max(0, math.floor(seconds))
	local h = math.floor(seconds / 3600)
	local m = math.floor((seconds % 3600) / 60)
	local s = seconds % 60
	if h > 0 then
		return string.format("%dh %02dm", h, m)
	elseif m > 0 then
		return string.format("%dm %02ds", m, s)
	end
	return string.format("%ds", s)
end

-- Multiplicateur lisible : 2 -> "x2", 1.5 -> "x1.5"
function NumberFormatter.Multiplier(value: number): string
	if value >= 1000 then
		return "x" .. NumberFormatter.Format(value)
	end
	return "x" .. trimZeros(string.format("%.2f", value))
end

return NumberFormatter
