--[[
	FR_HouseUI (ModuleScript)
	Emplacement : ReplicatedStorage > Shared > Lang > FR_HouseUI

	Traductions françaises de l'interface de "🏠 Ma maison" (fenêtre de la
	maison, pièce, barre d'outils d'édition, inventaire, boutique de la
	maison, bouton 🏠 de la colonne centrale).
	Clé = texte ANGLAIS exact utilisé dans le code (Locale.T("...")) ;
	valeur = texte français. Mêmes %s / %d dans les deux ("%%" = signe %).
	Les noms des objets, papiers peints, sols et tailles (Config.House) sont
	traduits par FR_House ; les textes déjà traduits ailleurs (FR_UI :
	"You need %s more Dopamine", "✔ Owned"...) ne sont pas répétés ici.
]]

return {
	fr = {
		-- Fenêtre
		["🏠 My House"] = "🏠 Ma maison",
		["Decorate your cozy room: comfort boosts ALL your gains"] = "Décore ton petit nid : le confort booste TOUS tes gains",
		["🏠 My house"] = "🏠 Ma maison",
		["%d/%d items"] = "%d/%d objets",
		["❤️ %d comfort"] = "❤️ %d de confort",
		["+%s%% Dopamine"] = "+%s %% de Dopamine",
		["✏️ Edit"] = "✏️ Modifier",
		["✅ Done"] = "✅ Terminé",
		["🛍️ Shop"] = "🛍️ Boutique",
		["👀 Preview"] = "👀 Aperçu",
		["✋ Drag to move  •  tap for options"] = "✋ Glisse pour déplacer  •  touche pour les options",
		["Your room is empty! 🥺\nBuy cute furniture to make it cozy."] = "Ta chambre est vide ! 🥺\nAchète des meubles tout mignons pour la rendre douillette.",
		["🛍️ Open the shop"] = "🛍️ Ouvrir la boutique",
		["📦 Inventory\ntap to place"] = "📦 Inventaire\ntouche pour poser",
		["Everything is placed! Buy more cute stuff in the 🛍️ Shop."] = "Tout est posé ! Achète encore plein de trucs mignons dans la 🛍️ Boutique.",
		["Your house is full! The new item waits in your inventory 📦"] = "Ta maison est pleine ! Le nouvel objet t'attend dans ton inventaire 📦",

		-- Sauvegarde automatique
		["✏️ Changes…"] = "✏️ Modifications…",
		["💾 Saving…"] = "💾 Enregistrement…",
		["Saved ✓"] = "Enregistré ✓",
		["⚠️ Not saved"] = "⚠️ Non enregistré",
		["Couldn't save your room, try again."] = "Impossible d'enregistrer ta chambre, réessaie.",

		-- Barre d'outils d'édition
		["Smaller"] = "Petit",
		["Bigger"] = "Grand",
		["Back"] = "Derrière",
		["Front"] = "Devant",
		["Store"] = "Ranger",
		["Already in front!"] = "Déjà devant !",
		["Already at the back!"] = "Déjà derrière !",
		["Buy one in the shop first!"] = "Achètes-en d'abord un dans la boutique !",
		["Your house is full (%d items)! Move into a bigger one 🏡"] = "Ta maison est pleine (%d objets) ! Emménage dans une plus grande 🏡",

		-- Boutique de la maison
		["🛍️ House shop"] = "🛍️ Boutique déco",
		["🛋️ Items"] = "🛋️ Objets",
		["🎨 Walls"] = "🎨 Murs",
		["🟫 Floors"] = "🟫 Sols",
		["🏡 Houses"] = "🏡 Maisons",
		["Wall"] = "Mur",
		["Floor"] = "Sol",
		["✨ New"] = "✨ Nouveau",
		["❤️ +%d comfort"] = "❤️ +%d de confort",
		["You already have the maximum of %s"] = "Tu as déjà le maximum de %s",
		["%s is yours!"] = "%s est à toi !",
		["🏠 New item"] = "🏠 Nouvel objet",
		["✔ Applied"] = "✔ Appliqué",
		["Apply"] = "Appliquer",
		["Applied!"] = "Appliqué !",
		["↔ x%s wide  •  up to %d items"] = "↔ largeur x%s  •  jusqu'à %d objets",
		["✔ Home"] = "✔ Chez toi",
		["🏠 You live here"] = "🏠 Tu habites ici",
		["Move in"] = "Emménager",
		["Welcome home!"] = "Bienvenue chez toi !",
		["🏡 New house!"] = "🏡 Nouvelle maison !",
	},
}
