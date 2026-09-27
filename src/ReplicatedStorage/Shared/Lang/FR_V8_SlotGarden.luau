--[[
	FR_V8_SlotGarden (ModuleScript - traductions)
	Emplacement : ReplicatedStorage > Shared > Lang > FR_V8_SlotGarden

	Textes français de la machine chanceuse (Stimuli > Casino, CasinoService)
	et du jardin de Dopamine (Stimuli > Garden, GardenService).
	Clé = texte anglais exact passé à Locale.T, valeur = texte français.
]]

return {
	fr = {
		-- 🎰 Machine chanceuse (client)
		["⭐ LUCKY MACHINE ⭐"] = "⭐ MACHINE CHANCEUSE ⭐",
		["📜 Payouts"] = "📜 Gains",
		["3 alike"] = "3 identiques",
		["2 alike"] = "2 identiques",
		["%s s"] = "%s s",
		["No match: +%s · everything is free 🎁"] = "Rien d'aligné : +%s · tout est gratuit 🎁",
		["+1 in %s"] = "+1 dans %s",
		["FREE · 1 token"] = "GRATUIT · 1 jeton",
		["Good luck! 🍀"] = "Bonne chance ! 🍀",
		["NO TOKENS"] = "PLUS DE JETONS",
		["Next in %s"] = "Prochain dans %s",
		["No tokens! Next one in %s ⏳"] = "Plus de jetons ! Prochain dans %s ⏳",
		["1 free token every %s of play"] = "1 jeton gratuit toutes les %s de jeu",

		-- 🎰 Machine chanceuse (serveur)
		["The lucky machine is closed"] = "La machine chanceuse est fermée",
		["The lucky machine isn't unlocked yet"] = "La machine chanceuse n'est pas encore débloquée",
		["No tokens left! Next one in %s"] = "Plus de jetons ! Prochain dans %s",
		["🎰 %s hit the jackpot on the lucky machine (+%s)!"] = "🎰 %s a décroché le gros lot à la machine chanceuse (+%s) !",

		-- 🌻 Jardin (client)
		["🧺 Harvest all (%d)"] = "🧺 Tout cueillir (%d)",
		["🌸 Tap the flower!"] = "🌸 Touche la fleur !",
		["⏱️ Next bloom %s"] = "⏱️ Éclosion %s",
		["%s · ready in %s"] = "%s · prête dans %s",
		["The garden is resting 🌙"] = "Le jardin se repose 🌙",

		-- 🌻 Jardin (serveur)
		["The garden isn't unlocked yet"] = "Le jardin n'est pas encore débloqué",
		["Still growing... ready in %s"] = "Ça pousse encore... prête dans %s",
		["Nothing is ready yet 🌱"] = "Rien n'est encore prêt 🌱",
		["🌸 %s picked a %s in their garden (+%s)!"] = "🌸 %s a cueilli : %s dans son jardin (+%s) !",
	},
}
