--[[
	Locale (ModuleScript)
	Emplacement : ReplicatedStorage > Shared > Locale

	Traduction du jeu. La langue de référence du code est l'ANGLAIS :
	on écrit Locale.T("Click me!") et le joueur francophone voit
	"Clique-moi !".

	- Langue détectée automatiquement : français si la langue Roblox du
	  joueur commence par "fr" (fr-fr, fr-ca...), sinon anglais.
	- Le joueur peut forcer la langue dans ⚙️ (réglage "Language" :
	  "Auto" | "en" | "fr", sauvegardé côté serveur).
	- Traductions françaises : chaque ModuleScript du dossier Shared > Lang
	  renvoie { fr = { ["English text"] = "Texte français", ... } }.
	  Une phrase sans traduction reste en anglais (jamais d'erreur).
	- Textes avec valeurs : Locale.T("+%s per click", Format(value))
	  (string.format est appliqué APRÈS la traduction : garde les mêmes %s).
	- Gros contenus (titres, mails, chat...) : Locale.Pick({ en = {...}, fr = {...} }).

	Serveur : Locale.TFor(Locale.ForPlayer(player), "text", ...).
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local Locale = {}

Locale.Languages = { "en", "fr" }
Locale.Default = "en"

local dictionaries: { [string]: { [string]: string } }? = nil
local currentLanguage: string? = nil
local listeners = {}

-- Charge (une fois) tous les dictionnaires du dossier Lang
local function getDictionaries(): { [string]: { [string]: string } }
	local loaded = dictionaries
	if loaded then
		return loaded
	end
	local merged = { fr = {} }
	local folder = script.Parent:FindFirstChild("Lang")
	if folder then
		for _, child in ipairs(folder:GetChildren()) do
			if child:IsA("ModuleScript") then
				local ok, result = pcall(require, child)
				if ok and type(result) == "table" then
					for lang, entries in pairs(result) do
						if type(entries) == "table" then
							merged[lang] = merged[lang] or {}
							for source, translated in pairs(entries) do
								merged[lang][source] = translated
							end
						end
					end
				else
					warn("[Locale] Dictionnaire invalide : " .. child:GetFullName(), result)
				end
			end
		end
	end
	dictionaries = merged
	return merged
end

-- "fr-fr" / "fr_CA" / "fr" -> "fr" ; tout le reste -> "en"
function Locale.Detect(localeId: string?): string
	if type(localeId) == "string" and string.lower(string.sub(localeId, 1, 2)) == "fr" then
		return "fr"
	end
	return "en"
end

-- Réglage "Auto" | "en" | "fr" + langue Roblox -> langue finale
function Locale.Resolve(setting: string?, localeId: string?): string
	if setting == "en" or setting == "fr" then
		return setting
	end
	return Locale.Detect(localeId)
end

-- Langue d'un joueur (serveur) : réglage sauvegardé sinon langue Roblox
function Locale.ForPlayer(player: Player, setting: string?): string
	return Locale.Resolve(setting, player.LocaleId)
end

-- Langue actuelle (client) : détectée au premier appel
function Locale.GetLanguage(): string
	local lang = currentLanguage
	if lang then
		return lang
	end
	local detected = Locale.Default
	if RunService:IsClient() then
		local player = Players.LocalPlayer
		if player then
			detected = Locale.Detect(player.LocaleId)
		end
	end
	currentLanguage = detected
	return detected
end

-- Change la langue (client). Les fonctions abonnées avec OnChanged sont appelées.
function Locale.SetLanguage(lang: string)
	if lang ~= "en" and lang ~= "fr" then
		return
	end
	if currentLanguage == lang then
		return
	end
	currentLanguage = lang
	for _, callback in ipairs(listeners) do
		task.spawn(callback, lang)
	end
end

function Locale.OnChanged(callback: (string) -> ())
	table.insert(listeners, callback)
end

function Locale.IsFrench(): boolean
	return Locale.GetLanguage() == "fr"
end

-- Traduit un texte anglais dans la langue `lang`, puis applique string.format
function Locale.TFor(lang: string, text: string, ...): string
	local result = text
	if lang ~= "en" then
		local dict = getDictionaries()[lang]
		local translated = dict and dict[text]
		if type(translated) == "string" then
			result = translated
		end
	end
	if select("#", ...) > 0 then
		local ok, formatted = pcall(string.format, result, ...)
		if ok then
			return formatted
		end
		local okSource, formattedSource = pcall(string.format, text, ...)
		return okSource and formattedSource or result
	end
	return result
end

-- Traduit dans la langue actuelle (client)
function Locale.T(text: string, ...): string
	return Locale.TFor(Locale.GetLanguage(), text, ...)
end

-- Choisit la version de la langue actuelle dans { en = x, fr = y }
function Locale.Pick(variants, lang: string?)
	if type(variants) ~= "table" then
		return variants
	end
	local chosen = variants[lang or Locale.GetLanguage()]
	if chosen == nil then
		chosen = variants.en
	end
	return chosen
end

return Locale
