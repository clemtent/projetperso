--[[
	FR_V8_PressDVD (ModuleScript - traductions)
	Emplacement : ReplicatedStorage > Shared > Lang > FR_V8_PressDVD

	Textes ajoutés en v8 par les stimuli Presse, DVD, Flash info et Messagerie
	(les gros contenus — titres, mails, paliers — sont dans les modules
	eux-mêmes, avec Locale.Pick).
]]

return {
	fr = {
		-- Presse
		["TURBO"] = "TURBO",
		["SAFETY"] = "SÉCURITÉ",

		-- Flash info : titres dynamiques
		["LUCKY MACHINE: %s FREE SPINS BY %s, THE MACHINE NEEDS A NAP"] = "MACHINE PORTE-BONHEUR : %s TOURS GRATUITS PAR %s, LA MACHINE A BESOIN D'UNE SIESTE",
		["HISTORIC: THE LOGO HIT THE CORNER %s TIMES AND %s SAW IT LIVE"] = "HISTORIQUE : LE LOGO A TOUCHÉ LE COIN %s FOIS ET %s L'A VU EN DIRECT",
		["INDUSTRY: %s THINGS CRUSHED BY %s, THE PRESS ASKS FOR A DAY OFF"] = "INDUSTRIE : %s OBJETS ÉCRASÉS PAR %s, LA PRESSE DEMANDE UN JOUR DE REPOS",
		["GARDENING: %s FLOWERS HARVESTED BY %s, THE BEES WANT A RAISE"] = "JARDINAGE : %s FLEURS RÉCOLTÉES PAR %s, LES ABEILLES RÉCLAMENT UNE AUGMENTATION",
		["ARCADE: %s WINS %s GAMES, THE HIGH-SCORE TABLE IS SHAKING"] = "ARCADE : %s GAGNE %s PARTIES, LE TABLEAU DES SCORES TREMBLE",
		["ARCADE: %s HAS %s TICKETS, THE PRIZE COUNTER IS NERVOUS"] = "ARCADE : %s A %s TICKETS, LE COMPTOIR DES LOTS EST NERVEUX",

		-- Messagerie (client mail)
		["Compose"] = "Écrire",
		["Search"] = "Rechercher",
		["Starred"] = "Favoris",
		["Sent"] = "Envoyés",
		["Spam"] = "Spams",
		["Trash"] = "Corbeille",
		["🚫 Spam"] = "🚫 Spam",
		["%d unread"] = "%d non lus",
		["%d min"] = "%d min",
		["💾 Storage: 99% full"] = "💾 Stockage : plein à 99 %",
		["🎉 Inbox zero! Enjoy it, it won't last."] = "🎉 Boîte vide ! Profites-en, ça ne va pas durer.",
		["⚠️ Careful: this looks like a scam. Never share your password!"] = "⚠️ Attention : ça ressemble à une arnaque. Ne donne jamais ton mot de passe !",
		["🚫 This looks like spam. We're not judging."] = "🚫 Ça ressemble à un spam. On ne juge pas.",
	},
}
