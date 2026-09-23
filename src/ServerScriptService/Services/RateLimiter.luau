--[[
	RateLimiter (ModuleScript)
	Emplacement : ServerScriptService > Services > RateLimiter

	Anti-spam simple : empêche un joueur d'appeler une action plus souvent
	que l'intervalle donné (protection contre les exploits qui spamment
	les RemoteEvents).
]]

local Players = game:GetService("Players")

local RateLimiter = {}

-- [Player] = { [clé] = dernière heure d'appel }
local lastCalls = {}

-- Renvoie true si l'action est autorisée, false si le joueur va trop vite
function RateLimiter.Check(player: Player, key: string, interval: number): boolean
	local now = os.clock()
	local playerCalls = lastCalls[player]
	if not playerCalls then
		playerCalls = {}
		lastCalls[player] = playerCalls
	end

	local last = playerCalls[key]
	if last and now - last < interval then
		return false
	end
	playerCalls[key] = now
	return true
end

Players.PlayerRemoving:Connect(function(player)
	lastCalls[player] = nil
end)

return RateLimiter
