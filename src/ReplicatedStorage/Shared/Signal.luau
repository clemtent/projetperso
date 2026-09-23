--[[
	Signal (ModuleScript)
	Emplacement : ReplicatedStorage > Shared > Signal

	Petit système d'événements (comme un BindableEvent, mais sans copier les
	tables passées en argument). Utilisé côté client pour prévenir l'interface
	qu'un nouvel état est arrivé.
]]

local Signal = {}
Signal.__index = Signal

export type Connection = { Disconnect: (self: Connection) -> () }

function Signal.new()
	return setmetatable({ _listeners = {} }, Signal)
end

-- Ajoute une fonction appelée à chaque :Fire(...)
function Signal:Connect(callback: (...any) -> ())
	local listeners = self._listeners
	local entry = { Callback = callback }
	table.insert(listeners, entry)

	return {
		Disconnect = function()
			local index = table.find(listeners, entry)
			if index then
				table.remove(listeners, index)
			end
		end,
	}
end

-- Appelle toutes les fonctions connectées (chacune dans son propre thread)
function Signal:Fire(...)
	for _, entry in ipairs(table.clone(self._listeners)) do
		task.spawn(entry.Callback, ...)
	end
end

return Signal
