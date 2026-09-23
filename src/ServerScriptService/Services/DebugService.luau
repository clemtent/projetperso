--[[
	DebugService (ModuleScript)
	Emplacement : ServerScriptService > Services > DebugService

	Commandes de TEST, actives UNIQUEMENT dans Roblox Studio (jamais dans le
	jeu publié). Tape-les dans le chat pendant un test "Play" :
	  /rush        -> lance un Dopamine Rush
	  /golden      -> fait apparaître un objet doré
	  /give 1e6    -> donne de la Dopamine (ici 1 million)
	  /corner      -> le logo DVD touchera un coin dans ~2 secondes
	  /daily       -> rend la récompense quotidienne à nouveau disponible
	  /save        -> force une sauvegarde
]]

local RunService = game:GetService("RunService")

local DebugService = {}

local services

function DebugService:Init(allServices)
	services = allServices
end

function DebugService:PlayerReady(player: Player)
	if not RunService:IsStudio() then
		return
	end

	player.Chatted:Connect(function(message: string)
		local command, argument = string.match(string.lower(message), "^/(%a+)%s*(%S*)")
		if not command then
			return
		end

		if command == "rush" then
			services.EventService:StartRush()
		elseif command == "golden" then
			services.EventService:SpawnGolden(player)
		elseif command == "give" then
			local amount = tonumber(argument) or 1e6
			services.GameService:AddDopamine(player, amount, false)
		elseif command == "corner" then
			services.DVDService:DebugCorner(player)
		elseif command == "daily" then
			local data = services.DataService:GetData(player)
			data.Daily.LastDay = 0
			services.GameService:MarkDirty(player)
		elseif command == "save" then
			local ok = services.DataService:SaveAsync(player)
			services.GameService:Notify(player, { Type = "Info", Text = ok and "💾 Sauvegardé !" or "💾 Sauvegarde impossible (voir la sortie)" })
			return
		else
			return
		end
		services.GameService:Notify(player, { Type = "Info", Text = "🛠️ Commande de test : /" .. command })
	end)
end

return DebugService
