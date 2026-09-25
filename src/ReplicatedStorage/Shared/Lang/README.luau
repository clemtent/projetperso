--[[
	Lang (dossier de traductions) — ModuleScript d'exemple
	Emplacement : ReplicatedStorage > Shared > Lang > README

	Chaque ModuleScript de ce dossier renvoie une table
	{ fr = { ["Texte anglais exact"] = "Texte français" } }.
	Locale.luau les fusionne toutes. Pour traduire une nouvelle phrase,
	ajoute simplement une ligne dans le fichier de la bonne zone.
]]

return { fr = {} }
