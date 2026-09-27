--[[
	KeyInput (ModuleScript)
	Emplacement : ReplicatedStorage > Client > Stimuli > Gear > KeyInput

	v9.1 : le VRAI clavier du joueur appuie sur les touches du clavier du jeu.
	Une seule connexion à UserInputService.InputBegan, partagée par les
	claviers du jeu (clavier mécanique, clavier corail) :
	  - ignorée si le jeu a déjà traité la touche (gameProcessed : chat,
	    menus Roblox...) ou si une zone de texte a le focus (chat du live...) ;
	  - seulement les touches qui existent sur le clavier du jeu (lettres,
	    espace, entrée, retour arrière, maj, ctrl, alt, , . ?) ;
	  - chaque clavier inscrit ET actif (visible, aucune fenêtre ouverte)
	    enfonce la touche correspondante ; UN SEUL clic est compté par
	    appui (le clavier de plus petite priorité clique, les autres
	    s'animent seulement). Maintenir une touche ne répète pas le clic.

	API :
	  KeyInput.Register(id, { Priority = number, Active = () -> boolean,
	                          Press = (code: string, doClick: boolean) -> () })
	  KeyInput.Unregister(id)
	  KeyInput.Dispatch(code) (tests / émulateur : comme un appui réel)
]]

local UserInputService = game:GetService("UserInputService")

local KeyboardArt = require(script.Parent.KeyboardArt)

export type Entry = {
	Priority: number,
	Active: () -> boolean,
	Press: (code: string, doClick: boolean) -> (),
}

local KeyInput = {}

local entries: { [string]: Entry } = {}
local connection: RBXScriptConnection? = nil

local function sorted(): { Entry }
	local list = {}
	for _, entry in pairs(entries) do
		local ok, active = pcall(entry.Active)
		if ok and active then
			table.insert(list, entry)
		end
	end
	table.sort(list, function(a, b)
		return a.Priority < b.Priority
	end)
	return list
end

function KeyInput.Dispatch(code: string): boolean
	local list = sorted()
	for index, entry in ipairs(list) do
		local ok, err = pcall(entry.Press, code, index == 1)
		if not ok then
			warn("[KeyInput] " .. tostring(err))
		end
	end
	return #list > 0
end

local function onInput(input: InputObject, gameProcessed: boolean)
	if gameProcessed or input.UserInputType ~= Enum.UserInputType.Keyboard then
		return
	end
	local focused = nil
	pcall(function()
		focused = UserInputService:GetFocusedTextBox()
	end)
	if focused then
		return
	end
	local code = KeyboardArt.CodeFor(input.KeyCode.Name)
	if code then
		KeyInput.Dispatch(code)
	end
end

function KeyInput.Register(id: string, entry: Entry)
	entries[id] = entry
	if not connection then
		connection = UserInputService.InputBegan:Connect(onInput)
	end
end

function KeyInput.Unregister(id: string)
	entries[id] = nil
	if next(entries) == nil and connection then
		connection:Disconnect()
		connection = nil
	end
end

return KeyInput
