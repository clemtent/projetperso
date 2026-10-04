--[[
	FR_V11_Race (ModuleScript)
	Emplacement : ReplicatedStorage > Shared > Lang > FR_V11_Race

	Traductions françaises de RACE11 (v11) : courses de rue 20x (nouveaux
	parcours, nitro, fantôme, médailles, XP et rangs, spectateur, page de
	stats, classement). Clés déjà ailleurs (réutilisées) : "Gold", "Silver",
	"Bronze", "Diamond", "Races", "Time", "Results", "NEW RECORD!",
	"VICTORY!", "🏆 Leaderboard", et toutes celles de FR_V10_Race.
]]

return {
	fr = {
		-- parcours (Config.Race.Routes)
		["Ring road Grand Prix"] = "Grand Prix de la ceinture",
		["One fast lap of the ring avenue"] = "Un tour rapide de l'avenue de ceinture",
		["Warehouse circuit"] = "Circuit des entrepôts",
		["Three tight laps among the lofts"] = "Trois tours serrés entre les lofts",
		["Highway endurance"] = "Endurance sur l'autoroute",
		["The whole highway loop, nitro ready"] = "Toute la boucle de l'autoroute, nitro prête",
		-- rangs (Config.Race.Ranks)
		["Platinum"] = "Platine",
		-- menu
		["🏁 Races"] = "🏁 Courses",
		["📊 My stats"] = "📊 Mes stats",
		["%d corners"] = "%d virages",
		["%d gates"] = "%d portes",
		["%d wins"] = "%d victoires",
		["Beat the medal times to earn XP!"] = "Bats les temps des médailles pour gagner de l'XP !",
		["🏆 Server record"] = "🏆 Record du serveur",
		["Best laps on this server"] = "Meilleurs tours du serveur",
		["👁️ Watch"] = "👁️ Regarder",
		["AI racers fill the grid. Gates in order · F = last gate · Shift/N = nitro (charge it by drifting and drafting)."] =
			"Des pilotes IA complètent la grille. Portes dans l'ordre · F = dernière porte · Maj/N = nitro (recharge-la en dérapant et dans l'aspiration).",
		["Next: %s at %s XP"] = "Prochain palier : %s à %s XP",
		["Top rank! A star every 2000 XP"] = "Rang maximum ! Une étoile tous les 2000 XP",
		["Wins"] = "Victoires",
		["Podiums"] = "Podiums",
		["Win rate"] = "Victoires (%)",
		["Overtakes"] = "Dépassements",
		["Best drift"] = "Meilleur dérapage",
		["Distance"] = "Distance",
		["Routes with a time"] = "Parcours chronométrés",
		["📈 Your last races (place)"] = "📈 Tes dernières courses (place)",
		["No race yet: your curve starts with the first one!"] = "Pas encore de course : ta courbe commence avec la première !",
		["Route"] = "Parcours",
		["Best"] = "Record",
		["🏎️ Drivers on this server"] = "🏎️ Pilotes du serveur",
		["No driver yet: race to appear here!"] = "Aucun pilote pour l'instant : cours pour apparaître ici !",
		-- course
		["charge: drift / draft"] = "recharge : dérapage / aspiration",
		["Lead"] = "En tête",
		["Last lap: %s"] = "Dernier tour : %s",
		["Lap"] = "Tour",
		["Lap %d: %s"] = "Tour %d : %s",
		["🏁 FINAL LAP"] = "🏁 DERNIER TOUR",
		["🔥 NITRO!"] = "🔥 NITRO !",
		["Stop watching"] = "Arrêter",
		["👁️ Watching the race: ◀ ▶ to switch driver"] = "👁️ Tu regardes la course : ◀ ▶ pour changer de pilote",
		-- résultats
		["Pilot"] = "Pilote",
		["Gap"] = "Écart",
		["Best lap"] = "Meilleur tour",
		["🔁 Race again"] = "🔁 Rejouer",
		["RANK UP!"] = "RANG SUPÉRIEUR !",
		["BEST LAP!"] = "MEILLEUR TOUR !",
		["Gold medal"] = "Médaille d'or",
		["Silver medal"] = "Médaille d'argent",
		["Bronze medal"] = "Médaille de bronze",
		["No medal"] = "Pas de médaille",
		["Bronze: %s"] = "Bronze : %s",
		["%d overtakes"] = "%d dépassements",
		["drift %s"] = "dérapage %s",
		-- serveur
		["💎 First gold medal on this route: +1 diamond!"] = "💎 Première médaille d'or sur ce parcours : +1 diamant !",
	},
}
