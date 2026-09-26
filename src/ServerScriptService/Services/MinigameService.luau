--[[
	MinigameService (ModuleScript)
	Emplacement : ServerScriptService > Services > MinigameService

	🕹️ Arcade : mini-jeux, tickets et duels entre joueurs.
	(squelette : rempli dans la v8)
]]

local MinigameService = {}

local services

function MinigameService:Init(allServices)
	services = allServices
end

function MinigameService:Start() end

return MinigameService
