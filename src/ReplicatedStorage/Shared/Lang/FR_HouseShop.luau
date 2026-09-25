--[[
	FR_HouseShop (ModuleScript)
	Emplacement : ReplicatedStorage > Shared > Lang > FR_HouseShop

	Traductions françaises de la boutique de la maison (House/HouseShop) :
	onglet 🚪 Pièces, onglet 🏡 Maisons (bâtiments, grille des pièces),
	murs / sols par pièce, badges ✨ des objets préférés.
	Clé = texte ANGLAIS exact utilisé dans le code (Locale.T("...")) ;
	valeur = texte français. Mêmes %s / %d dans les deux ("%%" = signe %).
	Les textes déjà traduits ailleurs (FR_HouseUI, FR_UI, FR_Server) ne sont
	pas répétés ici.
]]

return {
	fr = {
		-- Onglets
		["🚪 Rooms"] = "🚪 Pièces",

		-- Objets : préférés de la pièce ouverte
		["%s Favourites"] = "%s Préférés",
		["✨ +%s comfort"] = "✨ +%s confort",
		["MAX ✓"] = "MAX ✓",

		-- Murs / sols par pièce
		["🎨 Walls of this room:"] = "🎨 Murs de cette pièce :",
		["🟫 Floor of this room:"] = "🟫 Sol de cette pièce :",
		["🏠 Open a room, or pick one here:"] = "🏠 Ouvre une pièce, ou choisis-la ici :",
		["Open a room to change its walls and floor"] = "Ouvre une pièce pour changer ses murs et son sol",

		-- Pièces
		["%s %s  •  %d/%d rooms"] = "%s %s  •  %d/%d pièces",
		["Next room: %s"] = "Prochaine pièce : %s",
		["🏠 Full house! Move to a bigger one 🏡"] = "🏠 Maison pleine ! Passe à plus grand 🏡",
		["✨ Items a room loves give +%s%% comfort there"] = "✨ Les objets préférés d'une pièce y donnent +%s %% de confort",
		["✨ Loves (+%s%%):"] = "✨ Préférés (+%s %%) :",
		["🏡 Bigger house"] = "🏡 Plus grande maison",
		["New room: %s!"] = "Nouvelle pièce : %s !",
		["🚪 New room!"] = "🚪 Nouvelle pièce !",

		-- Maisons
		["🏢 1 floor × %d rooms"] = "🏢 1 étage × %d pièces",
		["🏢 %d floors × %d rooms"] = "🏢 %d étages × %d pièces",
		["🛋️ up to %d items / room"] = "🛋️ %d objets max / pièce",
		["🏠 Home • %d/%d rooms"] = "🏠 Chez toi • %d/%d pièces",
		["⚠️ Too many rooms (max %d)"] = "⚠️ Trop de pièces (max %d)",
	},
}
