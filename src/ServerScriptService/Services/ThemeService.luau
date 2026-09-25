--[[
	ThemeService (ModuleScript)
	Emplacement : ServerScriptService > Services > ThemeService

	Thèmes (fonds d'écran, Config.Themes), gardés pour toujours (même après
	l'océan). Un thème est possédé s'il a été acheté avec la Dopamine
	(data.Themes.Owned), si c'est un thème Premium et que le joueur est VIP,
	ou si le joueur possède le Game Pass du thème (vérifié par
	MonetizationService). RemoteFunction ThemeShop ("buy" | "equip", themeId).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local NumberFormatter = require(ReplicatedStorage.Shared.NumberFormatter)
local Net = require(ReplicatedStorage.Shared.Net)
local RateLimiter = require(script.Parent.RateLimiter)

local ThemeService = {}

local services

local DEFAULT_THEME = Config.ThemesById.Classic and "Classic" or (Config.Themes[1] and Config.Themes[1].Id) or "Classic"

local function isValidNumber(value): boolean
	return type(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge
end

function ThemeService:Init(allServices)
	services = allServices
end

-- Le joueur possède-t-il ce thème (achat, VIP ou Game Pass) ?
function ThemeService:Owns(player: Player, themeId: string): boolean
	local theme = Config.ThemesById[themeId]
	if not theme then
		return false
	end
	local data = services.DataService:GetData(player)
	if data and data.Themes.Owned[themeId] == true then
		return true
	end
	if theme.Premium and services.MonetizationService:IsVIP(player) then
		return true
	end
	return services.MonetizationService:OwnsThemePass(player, themeId)
end

-- État envoyé au client : { Owned = { [id] = true }, Equipped = id }
function ThemeService:GetState(player: Player)
	local owned = {}
	for _, theme in ipairs(Config.Themes) do
		if self:Owns(player, theme.Id) then
			owned[theme.Id] = true
		end
	end
	-- Le thème équipé n'est pas effacé des données s'il n'est plus possédé
	-- (vérification des Game Passes pas encore finie) : on affiche juste le thème par défaut.
	local data = services.DataService:GetData(player)
	local equipped = data and data.Themes.Equipped
	if type(equipped) ~= "string" or not owned[equipped] then
		equipped = DEFAULT_THEME
	end
	return { Owned = owned, Equipped = equipped }
end

-- Texte dans la langue du joueur
local function T(player: Player, text: string, ...): string
	return services.GameService:T(player, text, ...)
end

local function onThemeShop(player: Player, action: any, themeId: any)
	if not RateLimiter.Check(player, "ThemeShop", 0.2) then
		return false, T(player, "Slow down!")
	end
	local data = services.DataService:GetData(player)
	if not data or not services.GameService:IsReady(player) then
		return false, T(player, "Loading...")
	end
	if type(action) ~= "string" or type(themeId) ~= "string" or #themeId > 64 then
		return false, T(player, "Invalid request")
	end
	local theme = Config.ThemesById[themeId]
	if not theme then
		return false, T(player, "Unknown theme")
	end
	local themes = data.Themes
	local name = T(player, theme.Name)

	if action == "buy" then
		if ThemeService:Owns(player, themeId) then
			return false, T(player, "You already own this theme")
		end
		local cost = theme.Cost
		if cost == nil then
			if theme.Premium then
				return false, T(player, "This theme is unlocked with Robux (or the VIP pass)")
			end
			return false, T(player, "This theme is unlocked with Robux")
		end
		if not isValidNumber(cost) or cost < 0 then
			return false, T(player, "Theme unavailable")
		end
		if data.Dopamine < cost then
			return false, T(player, "Not enough %s", Config.Game.CurrencyName)
		end
		data.Dopamine -= cost
		themes.Owned[themeId] = true
		themes.Equipped = themeId -- équipé tout de suite
		data.Stats.ThemesBought += 1
		services.GameService:SendState(player)
		return true, T(player, "%s %s theme bought! (%s)", theme.Icon, name, NumberFormatter.Format(cost))
	elseif action == "equip" then
		if not ThemeService:Owns(player, themeId) then
			return false, T(player, "You don't own this theme")
		end
		themes.Equipped = themeId
		services.GameService:SendState(player)
		return true, T(player, "%s %s theme equipped", theme.Icon, name)
	end
	return false, T(player, "Invalid request")
end

-- Commande de test /theme (Studio) : donne et équipe un thème
function ThemeService:DebugGrant(player: Player, themeId: string): boolean
	local data = services.DataService:GetData(player)
	if not data or not Config.ThemesById[themeId] then
		return false
	end
	data.Themes.Owned[themeId] = true
	data.Themes.Equipped = themeId
	services.GameService:MarkDirty(player)
	return true
end

-- Corrige une sauvegarde abîmée (thème supprimé de la config...)
function ThemeService:PlayerReady(player: Player, data)
	local themes = data.Themes
	for id, value in pairs(themes.Owned) do
		if value ~= true or type(id) ~= "string" or not Config.ThemesById[id] then
			themes.Owned[id] = nil
		end
	end
	themes.Owned[DEFAULT_THEME] = true
	if type(themes.Equipped) ~= "string" or not Config.ThemesById[themes.Equipped] then
		themes.Equipped = DEFAULT_THEME
	end
end

function ThemeService:Start()
	Net.Function("ThemeShop").OnServerInvoke = onThemeShop
end

return ThemeService
