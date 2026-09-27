--[[
	WorldLink (ModuleScript)
	Emplacement : ReplicatedStorage > Client > World > WorldLink

	🚶 Dopamine Town : petit lien SANS dépendance entre les boutons de
	l'interface du clicker (pastille "🚶 Town" de la colonne centrale, bouton
	"🚶 Walk in 3D" de la fenêtre Maison) et le mode ville (TownClient, qui
	s'enregistre ici au démarrage). Si la ville n'est pas chargée, les
	boutons ne font rien (Available() = false) : rien ne casse.

	API :
	  WorldLink.Enter(options?)        options = { Slot = number? (pièce), Visit = UserId? }
	  WorldLink.Available() -> boolean
	  WorldLink.IsInTown() -> boolean
	  WorldLink.SetHandler(enter, isInTown)   (TownClient)
]]

local WorldLink = {}

local enterHandler: ((options: any) -> ())? = nil
local inTownHandler: (() -> boolean)? = nil

function WorldLink.SetHandler(enter: (options: any) -> (), isInTown: () -> boolean)
	enterHandler = enter
	inTownHandler = isInTown
end

function WorldLink.Available(): boolean
	return enterHandler ~= nil
end

function WorldLink.IsInTown(): boolean
	local handler = inTownHandler
	if not handler then
		return false
	end
	local ok, result = pcall(handler)
	return ok and result == true
end

function WorldLink.Enter(options: any?)
	local handler = enterHandler
	if not handler then
		return
	end
	local ok, err = pcall(handler, options or {})
	if not ok then
		warn("[WorldLink] " .. tostring(err))
	end
end

return WorldLink
