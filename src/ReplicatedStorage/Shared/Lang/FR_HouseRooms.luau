--[[
	FR_HouseRooms (ModuleScript)
	Emplacement : ReplicatedStorage > Shared > Lang > FR_HouseRooms

	Traductions françaises de la maison à plusieurs pièces (vue d'ensemble
	de l'immeuble, mode rangement, choix du type de pièce, onglets des
	pièces, éditeur : annuler / rétablir, aimant, dupliquer, envoyer dans
	une autre pièce).
	Clé = texte ANGLAIS exact utilisé dans le code (Locale.T("...")) ;
	valeur = texte français. Mêmes %s / %d dans les deux ("%%" = signe %).
]]

return {
	fr = {
		-- Bandeau, vue d'ensemble
		["%d/%d rooms"] = "%d/%d pièces",
		["+%s%%"] = "+%s %%",
		["↔️ Arrange"] = "↔️ Ranger",
		["⬅ House"] = "⬅ Maison",
		["👆 Tap a room to decorate it"] = "👆 Touche une pièce pour la décorer",
		["✋ Drag a room onto another spot  •  tap it for options"] = "✋ Glisse une pièce vers une autre place  •  touche-la pour les options",
		["New room"] = "Nouvelle pièce",
		["🔀 Swap"] = "🔀 Échanger",
		["📍 Move here"] = "📍 Mettre ici",

		-- Achat / type de pièce, menu d'une pièce
		["🏗️ New room  •  💧 %s"] = "🏗️ Nouvelle pièce  •  💧 %s",
		["Room %d/%d — its favourite items give ✨ +%s%% comfort"] = "Pièce %d/%d — ses objets préférés donnent ✨ +%s %% de confort",
		["New room!"] = "Nouvelle pièce !",
		["🏠 New room"] = "🏠 Nouvelle pièce",
		["🔄 Change room type"] = "🔄 Changer le type de pièce",
		["Free! Items stay where they are  •  favourites give ✨ +%s%% comfort"] = "Gratuit ! Les objets restent en place  •  les préférés donnent ✨ +%s %% de confort",
		["✓ Current"] = "✓ Actuel",
		["Drag the room onto another spot to move it"] = "Glisse la pièce vers une autre place pour la déplacer",
		["🚪 Go inside"] = "🚪 Entrer",
		["🔄 Change type"] = "🔄 Changer de type",

		-- Pièce
		["This room is empty! 🥺\nPlace cute furniture to make it cozy."] = "Cette pièce est vide ! 🥺\nPose des meubles tout mignons pour la rendre douillette.",
		["✏️ Decorate"] = "✏️ Décorer",
		["This room is full! The new item waits in your inventory 📦"] = "Cette pièce est pleine ! Le nouvel objet t'attend dans l'inventaire 📦",
		["This room is full (%d items)! Decorate another room 🏡"] = "Cette pièce est pleine (%d objets) ! Décore une autre pièce 🏡",

		-- Éditeur
		["Copy"] = "Copier",
		["Send"] = "Envoyer",
		["Smaller  ( - )"] = "Plus petit  ( - )",
		["Bigger  ( + )"] = "Plus grand  ( + )",
		["Send backward  ( Page Down )"] = "Derrière  ( Page suiv. )",
		["Bring forward  ( Page Up )"] = "Devant  ( Page préc. )",
		["Duplicate  ( Ctrl+D )"] = "Dupliquer  ( Ctrl+D )",
		["Send to another room"] = "Envoyer dans une autre pièce",
		["Store in inventory  ( Delete )"] = "Ranger dans l'inventaire  ( Suppr )",
		["↩️ Undo"] = "↩️ Annuler",
		["↪️ Redo"] = "↪️ Rétablir",
		["🧲 Snap: on"] = "🧲 Aimant : oui",
		["🧲 Snap: off"] = "🧲 Aimant : non",
		["🧲 Items now snap to the grid"] = "🧲 Les objets s'aimantent à la grille",
		["🧲 Free placement"] = "🧲 Placement libre",
		["No other copy in your inventory: buy one in the shop!"] = "Plus d'exemplaire dans ton inventaire : achètes-en un à la boutique !",
		["Buy another room first! 🏡"] = "Achète d'abord une autre pièce ! 🏡",
		["Some items are already used in another room"] = "Certains objets sont déjà utilisés dans une autre pièce",
		["%s sent to %s"] = "%s envoyé dans : %s",

		-- Envoyer dans une autre pièce
		["🚪 Send %s to…"] = "🚪 Envoyer %s dans…",
		["It lands on a free spot of that room"] = "Il sera posé à une place libre de cette pièce",
		["🚫 Full"] = "🚫 Pleine",
		["✨ Favourite"] = "✨ Préféré",
	},
}
