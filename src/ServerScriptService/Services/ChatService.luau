--[[
	ChatService (ModuleScript)
	Emplacement : ServerScriptService > Services > ChatService

	Texte TAPÉ par le joueur (chat du live, mails écrits) : obligatoirement
	passé par le filtre de Roblox (TextService) avant d'être affiché, même
	au joueur lui-même.

	RemoteFunction "FilterText" (purpose, text) -> (ok, résultat | message)
	  purpose : "Live" (message du chat du live) ou "Mail" (mail écrit)
	  résultat : { Text = texte filtré pour CE joueur, Topics = { sujets } }
	  Les sujets (ChatTopics.Detect, sur le texte brut) servent aux faux
	  spectateurs / correspondants pour répondre "en fonction de ce qu'il a
	  dit". Le texte brut n'est jamais renvoyé ni montré à personne.
	Anti-spam : 1 message / 1,2 s (live), 1 / 2 s (mail) ; longueur limitée.
	Si le filtre échoue (panne Roblox), le message n'est PAS affiché.
]]

local TextService = game:GetService("TextService")

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared.Net)
local ChatTopics = require(Shared.ChatTopics)

local RateLimiter = require(script.Parent.RateLimiter)

local ChatService = {}

local services = nil

local PURPOSES = {
	Live = { MaxLength = 120, Interval = 1.2 },
	Mail = { MaxLength = 400, Interval = 2 },
}

function ChatService:Init(allServices)
	services = allServices
end

local function T(player: Player, text: string, ...): string
	local game = services and services.GameService
	if game and game.T then
		return game:T(player, text, ...)
	end
	return string.format(text, ...)
end

-- Nettoie le texte reçu : caractères de contrôle retirés, espaces réduits
local function clean(text: string, maxLength: number): string
	text = string.gsub(text, "[%c]", " ")
	text = string.gsub(text, "%s+", " ")
	text = string.gsub(text, "^%s+", "")
	text = string.gsub(text, "%s+$", "")
	if utf8.len(text) == nil then
		return "" -- UTF-8 invalide : refusé
	end
	if (utf8.len(text) :: number) > maxLength then
		local cut = utf8.offset(text, maxLength + 1)
		if cut then
			text = string.sub(text, 1, cut - 1)
		end
	end
	return text
end

local function onFilter(player: Player, purpose: any, text: any)
	local settings = type(purpose) == "string" and PURPOSES[purpose] or nil
	if not settings or type(text) ~= "string" then
		return false, T(player, "Invalid message")
	end
	if #text > settings.MaxLength * 4 then
		return false, T(player, "Message too long")
	end
	if not RateLimiter.Check(player, "FilterText_" .. purpose, settings.Interval) then
		return false, T(player, "Slow down a little!")
	end
	local cleaned = clean(text, settings.MaxLength)
	if cleaned == "" then
		return false, T(player, "Invalid message")
	end
	local topics = ChatTopics.Detect(cleaned)
	local ok, filtered = pcall(function()
		local result = TextService:FilterStringAsync(cleaned, player.UserId, Enum.TextFilterContext.PublicChat)
		return result:GetNonChatStringForUserAsync(player.UserId)
	end)
	if not ok or type(filtered) ~= "string" then
		return false, T(player, "Message could not be sent, try again")
	end
	return true, { Text = filtered, Topics = topics }
end

function ChatService:Start()
	Net.Function("FilterText").OnServerInvoke = onFilter
end

return ChatService
