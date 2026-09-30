--[[
	FR_V10_Race (ModuleScript)
	Emplacement : ReplicatedStorage > Shared > Lang > FR_V10_Race

	Traductions françaises de RACE10 (v10) : courses de rue (RaceService,
	RaceClient, RaceHud, RaceProps, Config.Race). Clés déjà ailleurs
	(réutilisées) : "Loading...", "Invalid request", "GO!",
	"Walk around the town first".
]]

return {
	fr = {
		-- parcours (Config.Race.Routes)
		["City circuit"] = "Circuit du centre-ville",
		["Highway sprint"] = "Sprint sur l'autoroute",
		["District loop"] = "Boucle des quartiers",
		["Night race"] = "Course de nuit",
		["Two laps around downtown"] = "Deux tours du centre-ville",
		["Flat out on the highway"] = "À fond sur l'autoroute",
		["Through every district"] = "À travers tous les quartiers",
		["The grand tour, under the stars"] = "Le grand tour, sous les étoiles",
		-- serveur
		["Finish your race first!"] = "Termine d'abord ta course !",
		["Join at the race meeting point, or from your car 🏁"] = "Inscris-toi au QG des courses, ou depuis ta voiture 🏁",
		["A race is running on this route: try another one!"] = "Une course est en cours sur ce parcours : essaie-en un autre !",
		["This route is not available"] = "Ce parcours n'est pas disponible",
		["This race is full"] = "Cette course est complète",
		["Could not start the race: %s"] = "Impossible de lancer la course : %s",
		["You left the race"] = "Tu as quitté la course",
		["You left your car: race over"] = "Tu es sorti de ta voiture : course terminée",
		["Disqualified: impossible moves"] = "Disqualifié : déplacements impossibles",
		["Back to the last checkpoint"] = "Retour à la dernière porte",
		["🏁 +%s Dopamine!"] = "🏁 +%s de Dopamine !",
		["Daily race rewards reached: records still count!"] = "Récompenses du jour atteintes : les records comptent toujours !",
		-- menu
		["🏁 Street races"] = "🏁 Courses de rue",
		["Street races"] = "Courses de rue",
		["🏁 Race HQ"] = "🏁 QG des courses",
		["Join"] = "S'inscrire",
		["Leave"] = "Quitter",
		["Races"] = "Courses",
		["Open: start a race!"] = "Libre : lance une course !",
		["%d waiting · starts in %d s"] = "%d inscrit(s) · départ dans %d s",
		["Finishing…"] = "Arrivée en cours…",
		["Race in progress…"] = "Course en cours…",
		["%d laps"] = "%d tours",
		["1 lap"] = "1 tour",
		["Sprint"] = "Sprint",
		["🏆 No record yet"] = "🏆 Pas encore de record",
		["⏱️ Your best: %s"] = "⏱️ Ton record : %s",
		["✅ You are signed up!"] = "✅ Tu es inscrit !",
		["Win Dopamine: 🥇 %d s · 🥈 %d s · 🥉 %d s of production · rewarded today: %d/%d"] = "Gagne de la Dopamine : 🥇 %d s · 🥈 %d s · 🥉 %d s de production · courses payées aujourd'hui : %d/%d",
		["AI racers fill the grid. Pass every checkpoint in order, stay on the road. F = back to the last checkpoint."] = "Des pilotes IA complètent la grille. Passe toutes les portes dans l'ordre, reste sur la route. F = retour à la dernière porte.",
		["Sign up at the 🏁 Race HQ (on foot, E) or from your car."] = "Inscris-toi au 🏁 QG des courses (à pied, E) ou depuis ta voiture.",
		["🏁 Signed up: %s"] = "🏁 Inscrit : %s",
		["%s %s · %d racers · start in %d s"] = "%s %s · %d pilote(s) · départ dans %d s",
		-- QG
		["🏆 Best laps on this server"] = "🏆 Meilleurs tours du serveur",
		["No record yet: be the first!"] = "Pas encore de record : sois le premier !",
		["🏁 %d waiting!"] = "🏁 %d inscrit(s) !",
		-- en course
		["On the grid: slot %d"] = "Sur la grille : place %d",
		["Lap %d/%d"] = "Tour %d/%d",
		["⛔ WRONG WAY"] = "⛔ MAUVAIS SENS",
		["Checkpoint %d/%d ✓"] = "Porte %d/%d ✓",
		["%s ahead: +%.1f s"] = "%s devant : +%.1f s",
		["Lead: %.1f s"] = "En tête : %.1f s",
		["🏁 Finished!"] = "🏁 Arrivé !",
		["🏁 Finish · %d m"] = "🏁 Arrivée · %d m",
		["Gate %d/%d · %d m"] = "Porte %d/%d · %d m",
		["Best lap: %s"] = "Meilleur tour : %s",
		["FINISH!"] = "ARRIVÉE !",
		-- résultats
		["Results"] = "Résultats",
		["Awesome!"] = "Génial !",
		["Out"] = "Abandon",
		["Did not finish"] = "Pas arrivé",
		["No reward: the race was not valid"] = "Pas de récompense : course non valide",
		["You finished %d%s · +%s Dopamine!"] = "Tu finis %d%s · +%s de Dopamine !",
		["You finished %d%s · daily race rewards reached"] = "Tu finis %d%s · récompenses du jour atteintes",
		["You finished %d%s"] = "Tu finis %d%s",
	},
}
