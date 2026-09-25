--[[
	FR_Server (ModuleScript)
	Emplacement : ReplicatedStorage > Shared > Lang > FR_Server

	Traductions françaises des textes envoyés par le SERVEUR (notifications,
	réponses des RemoteFunctions, quêtes, commandes de test...).
	Clé = texte ANGLAIS exact utilisé dans ServerScriptService ; valeur =
	texte français. Garde les mêmes %s / %d, dans le même ordre.
]]

return {
	fr = {
		-- Messages communs
		["Slow down!"] = "Doucement !",
		["Loading..."] = "Chargement en cours...",
		["Invalid request"] = "Requête invalide",
		["Not enough %s"] = "Pas assez de %s",

		-- Sauvegarde (DataService)
		["⚠️ Saving is unavailable: your progress won't be saved."] = "⚠️ Sauvegarde indisponible : ta progression ne sera pas enregistrée.",

		-- Améliorations, océan, hors-ligne (GameService)
		["Unknown upgrade"] = "Amélioration inconnue",
		["Max level reached"] = "Niveau maximum atteint",
		["🌊 Breathe... Permanent earnings %s"] = "🌊 Respire... Gains permanents %s",
		["✨ New: %s %s!"] = "✨ Nouveau : %s %s !",
		["%s %s level %d"] = "%s %s niveau %d",
		["🌊 %s went to the ocean (x%s)"] = "🌊 %s est allé(e) à l'océan (x%s)",
		["😴 Welcome back! +%s %s earned while you were away"] = "😴 Bon retour ! +%s %s gagnée hors-ligne",

		-- Quêtes et succès
		["QUEST COMPLETE!"] = "QUÊTE TERMINÉE !",
		["ACHIEVEMENT UNLOCKED!"] = "SUCCÈS DÉBLOQUÉ !",

		-- Machine à sous (CasinoService)
		["The casino is closed"] = "Le casino est fermé",
		["The slot machine isn't unlocked yet"] = "La machine à sous n'est pas encore débloquée",
		["Invalid bet"] = "Mise invalide",
		["The machine is still spinning..."] = "La machine tourne encore...",
		["You need at least %s %s"] = "Il faut au moins %s %s",
		["🎰 %s won x%s on the slot machine!"] = "🎰 %s a gagné x%s à la machine à sous !",

		-- Boutique d'objets (CosmeticService)
		["The shop isn't unlocked yet"] = "La boutique n'est pas encore débloquée",
		["Unknown item"] = "Objet inconnu",
		["Invalid item"] = "Objet invalide",
		["You already own this item"] = "Tu as déjà cet objet",
		["%s %s bought! (%s)"] = "%s %s acheté ! (%s)",
		["You don't own this item"] = "Tu ne possèdes pas cet objet",
		["%s %s equipped"] = "%s %s équipé",
		["%s %s removed"] = "%s %s retiré",

		-- Cadeau quotidien (DailyRewardService)
		["The calendar isn't unlocked yet"] = "Le calendrier n'est pas encore débloqué",
		["Already claimed today, come back tomorrow!"] = "Déjà récupéré aujourd'hui, reviens demain !",
		["Day %d: +%s %s!"] = "Jour %d : +%s %s !",

		-- Coffre mystère (LootService)
		["The mystery chest isn't unlocked yet"] = "Le coffre mystère n'est pas encore débloqué",
		["No chests to open, be patient..."] = "Aucun coffre à ouvrir, patience...",
		["📦 %s opened a %s chest (+%s)!"] = "📦 %s a ouvert un coffre %s (+%s) !",

		-- Logo DVD (DVDService)
		["📀 PERFECT CORNER! +%s"] = "📀 COIN PARFAIT ! +%s",
		["📀 %s hit the PERFECT CORNER!"] = "📀 %s a touché le COIN PARFAIT !",

		-- Dopamine Rush (EventService)
		["⚡ %s extended by %s s!"] = "⚡ %s prolongé de %s s !",
		["⚡ %s: x%s for %s s!"] = "⚡ %s : x%s pendant %s s !",

		-- Bourse (StockService)
		["The stock market isn't unlocked yet"] = "La bourse n'est pas encore débloquée",
		["📈 Bought %s %s share(s)"] = "📈 %s action(s) %s achetée(s)",
		["You don't own any shares"] = "Tu n'as aucune action",
		["profit +%s"] = "bénéfice +%s",
		["loss -%s"] = "perte -%s",
		["💰 Sold for %s (%s)"] = "💰 Vendu pour %s (%s)",

		-- Thèmes (ThemeService)
		["Unknown theme"] = "Thème inconnu",
		["You already own this theme"] = "Tu as déjà ce thème",
		["This theme is unlocked with Robux"] = "Ce thème s'obtient avec des Robux",
		["This theme is unlocked with Robux (or the VIP pass)"] = "Ce thème s'obtient avec des Robux (ou le pass VIP)",
		["Theme unavailable"] = "Thème indisponible",
		["%s %s theme bought! (%s)"] = "%s Thème %s acheté ! (%s)",
		["You don't own this theme"] = "Tu ne possèdes pas ce thème",
		["%s %s theme equipped"] = "%s Thème %s équipé",

		-- Boutique Robux (MonetizationService)
		["%s %s theme"] = "%s Thème %s",
		["💎 Thank you! %s unlocked!"] = "💎 Merci ! %s débloqué !",
		["💎 Thank you! %s %s: +%s %s"] = "💎 Merci ! %s %s : +%s %s",
		["💎 Thank you! %s %s active (%d min left)"] = "💎 Merci ! %s %s actif (%d min restantes)",
		["🎉 %s is treating the whole server to a Dopamine Rush!"] = "🎉 %s offre un Dopamine Rush à tout le serveur !",
		["💎 Thank you! %s Rush started for the whole server!"] = "💎 Merci ! %s Rush lancé pour tout le serveur !",

		-- Commandes de test (DebugService, Studio uniquement)
		["Invalid amount"] = "Montant invalide",
		["Dopamine Rush started!"] = "Dopamine Rush lancé !",
		["A Rush is already running"] = "Un Rush est déjà en cours",
		["Daily gift available"] = "Cadeau quotidien disponible",
		["💾 Saved!"] = "💾 Sauvegardé !",
		["💾 Couldn't save (see the Output)"] = "💾 Sauvegarde impossible (voir la sortie)",
		["Corner in ~2 seconds..."] = "Coin dans ~2 secondes...",
		["You need at least one DVD logo"] = "Il faut au moins un logo DVD",
		["Everything unlocked!"] = "Tout est débloqué !",
		["Unknown type: %s"] = "Type inconnu : %s",
		["Too many %s objects on screen"] = "Trop d'objets %s à l'écran",
		["%s object sent"] = "Objet %s envoyé",
		["🌊 Free detox"] = "🌊 Détox gratuite",
		["Chests added"] = "Coffres ajoutés",
		["Data reset"] = "Données remises à zéro",
		["Unknown pass: %s"] = "Pass inconnu : %s",
		["Couldn't toggle this pass"] = "Impossible de changer ce pass",
		["Pass %s enabled"] = "Pass %s activé",
		["Pass %s disabled"] = "Pass %s désactivé",
		["Usage: /boost <mult 1-1000> <seconds>"] = "Usage : /boost <mult 1-1000> <secondes>",
		["Boost x%s for %d s"] = "Boost x%s pendant %d s",
		["Unknown theme: %s"] = "Thème inconnu : %s",
		["Theme %s given and equipped"] = "Thème %s donné et équipé",
		["Usage: /offline <seconds 1-%s>"] = "Usage : /offline <secondes 1-%s>",
		["Nothing earned (no production or away < %s s)"] = "Rien gagné (production nulle ou absence < %s s)",
		["Offline simulated: +%s %s"] = "Hors-ligne simulé : +%s %s",
		["Usage: /lang <auto|en|fr>"] = "Usage : /lang <auto|en|fr>",
		["🌐 Language: %s (takes effect after rejoining)"] = "🌐 Langue : %s (appliquée au prochain lancement)",
		["/give /rush /daily /save /corner /unlockall /spawn <%s> /detox /chest /reset /pass <id> /boost <mult> <seconds> /theme <id> /offline <seconds> /lang <auto|en|fr>"] = "/give /rush /daily /save /corner /unlockall /spawn <%s> /detox /chest /reset /pass <id> /boost <mult> <secondes> /theme <id> /offline <secondes> /lang <auto|en|fr>",
		["Unknown command. %s"] = "Commande inconnue. %s",
		["Invalid command"] = "Commande invalide",
		["(already run)"] = "(déjà exécutée)",
		["Error: %s"] = "Erreur : %s",
		["Test commands are only available in Studio"] = "Commandes de test disponibles uniquement dans Studio",
		["Invalid argument"] = "Argument invalide",
	},
}
