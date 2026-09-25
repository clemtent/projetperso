--[[
	FR_StimuliText (ModuleScript - dictionnaire)
	Emplacement : ReplicatedStorage > Shared > Lang > FR_StimuliText

	Traductions françaises des petits textes des stimuli NewsTicker, Email,
	PhoneNotifs et Megaphone (texte anglais exact -> texte français).
	Les gros contenus (titres, mails, notifications, mots criés...) sont
	directement dans chaque module sous forme { en = {...}, fr = {...} }.
	Garder les mêmes %s dans les deux langues, dans le même ordre.
]]

return {
	fr = {
		-- NewsTicker : habillage du bandeau
		["LIVE"] = "DIRECT",
		["NEWS FLASH"] = "FLASH INFO",
		["URGENT!"] = "URGENT !",
		["BREAKING"] = "ALERTE",
		["NEWS ● LIVE"] = "INFO ● DIRECT",
		["SOMEONE"] = "QUELQU'UN",

		-- NewsTicker : rubriques
		["WEATHER"] = "MÉTÉO",
		["MARKETS"] = "BOURSE",
		["WEIRD"] = "INSOLITE",
		["POLITICS"] = "POLITIQUE",
		["HEALTH"] = "SANTÉ",
		["CELEBS"] = "PEOPLE",
		["ANIMALS"] = "ANIMAUX",

		-- NewsTicker : titres dynamiques (stats du joueur)
		["RECORD: %s OWNS %s DOPAMINE, THE NEIGHBORS ARE WORRIED"] = "RECORD : %s POSSÈDE %s DOPAMINE, SES VOISINS INQUIETS",
		["RECORD OUTPUT: %s DOPAMINE PER SECOND, SMILE FACTORIES RUNNING AT FULL SPEED"] = "PRODUCTION RECORD : %s DOPAMINE PAR SECONDE, LES USINES À SOURIRES TOURNENT À PLEIN RÉGIME",
		["THE “CLICK ME” BUTTON HAS BEEN CLICKED %s TIMES, IT'S ASKING FOR A VACATION"] = "LE BOUTON « CLIQUE-MOI » A ÉTÉ CLIQUÉ %s FOIS, IL DEMANDE DES VACANCES",
		["EXCLUSIVE: %s HASN'T BLINKED IN 20 MINUTES"] = "EXCLUSIF : %s N'A PAS CLIGNÉ DES YEUX DEPUIS 20 MINUTES",
		["INTERVIEW: %s CLAIMS THEY CAN “QUIT ANYTIME”"] = "INTERVIEW : %s AFFIRME POUVOIR « ARRÊTER QUAND IL VEUT »",
		["%s STOCK TRADES AT %s, ANALYSTS PRAISE A “VERY PRETTY CURVE”"] = "L'ACTION %s COTE À %s, LES ANALYSTES PARLENT D'UNE « COURBE TRÈS JOLIE »",
		["%s HAS NEVER BEEN TO THE OCEAN, THE SEAGULLS ARE WORRIED"] = "%s N'EST ENCORE JAMAIS ALLÉ À L'OCÉAN, LES MOUETTES S'INQUIÈTENT",
		["%s HAS BEEN TO THE OCEAN %s TIMES... AND ALWAYS COMES BACK TO CLICK"] = "%s EST ALLÉ %s FOIS À L'OCÉAN... ET REVIENT TOUJOURS CLIQUER",
		["SCREEN TIME: %s HAS SPENT %s STARING AT A BUTTON TODAY"] = "TEMPS D'ÉCRAN : %s A PASSÉ %s DEVANT UN BOUTON AUJOURD'HUI",
		["%s LIGHTNING BOLTS CAUGHT BARE-HANDED: %s IS NOW A LEGEND"] = "%s ÉCLAIRS ATTRAPÉS À MAINS NUES : %s ENTRE DANS LA LÉGENDE",
		["%s BUBBLES POPPED: BUBBLE WRAP MAKERS THANK %s"] = "%s BULLES ÉCLATÉES : LES FABRICANTS DE PAPIER BULLE REMERCIENT %s",
		["CASINO: %s SPINS BY %s, THE HOUSE SAYS THANK YOU"] = "CASINO : %s PARTIES JOUÉES PAR %s, LA MAISON DIT MERCI",
		["%s EMAILS READ BY %s, AND THERE ARE STILL MORE"] = "%s MAILS LUS PAR %s, IL EN RESTE TOUJOURS PLUS",
		["THE LOGO HAS BOUNCED %s TIMES, IT'S DIZZY BUT STILL AIMING FOR THE CORNER"] = "LE LOGO A REBONDI %s FOIS, IL A LE TOURNIS MAIS VISE TOUJOURS LE COIN",
		["LEADERBOARD: %s IS #1 ON THE SERVER, OTHER PLAYERS DEMAND A RECOUNT"] = "CLASSEMENT : %s EST N°1 DU SERVEUR, LES AUTRES JOUEURS DEMANDENT UN RECOMPTAGE",
		["LEADERBOARD: %s IS #%s OUT OF %s, TENSION IS RISING"] = "CLASSEMENT : %s EST %sE SUR %s, LA TENSION MONTE",
		["REBIRTH MULTIPLIER: %s, ECONOMISTS ARE BAFFLED"] = "MULTIPLICATEUR DE RENAISSANCE : %s, LES ÉCONOMISTES N'Y COMPRENNENT RIEN",
		["RIGHT NOW: %s %s! EVERYONE'S CLICKING!"] = "EN CE MOMENT : %s %s ! TOUT LE MONDE CLIQUE !",

		-- Email : étiquettes de priorité
		["⚠️ SCAM?"] = "⚠️ ARNAQUE ?",
		["💗 FAMILY"] = "💗 FAMILLE",
		["💼 WORK"] = "💼 TRAVAIL",
		["✉️ PERSONAL"] = "✉️ PERSO",

		-- Email : fenêtre et cartes
		["@dopamail.com"] = "@dopamail.fr",
		["📥 Dopamail — Inbox"] = "📥 Dopamail — Boîte de réception",
		["<%s> · to me · just now"] = "<%s> · à moi · à l'instant",
		["↩️ Reply"] = "↩️ Répondre",
		["➡️ Forward"] = "➡️ Transférer",
		["🗑️ Delete"] = "🗑️ Supprimer",
		["⏰ QUICK, READ ME!"] = "⏰ VITE, LIS-MOI !",

		-- PhoneNotifs
		["now"] = "maintenant",

		-- Megaphone : cris spéciaux
		["JACKPOT!!!"] = "JACKPOT !!!",
		["IT'S RUSH TIME!!!"] = "C'EST LE RUSH !!!",
		["ACHIEVEMENT!!!"] = "SUCCÈS !!!",
		["NEW STUFF!"] = "NOUVEAUTÉ !",
	},
}
