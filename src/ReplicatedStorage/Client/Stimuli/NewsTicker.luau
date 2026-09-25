--[[
	NewsTicker (ModuleScript - stimulus)
	Emplacement : ReplicatedStorage > Client > Stimuli > NewsTicker

	Bandeau "FLASH INFO" façon chaîne d'info en continu, tout en haut :
	  - à gauche : bloc "● DIRECT" (point rouge qui clignote) + cartouche
	    blanc "FLASH INFO" en biais (qui vire au jaune "URGENT !" quand un
	    titre urgent passe) ;
	  - au centre : titres absurdes (majuscules, gras, italique) qui défilent
	    de droite à gauche, chacun précédé d'une étiquette de rubrique colorée
	    (SPORT, MÉTÉO, BOURSE, INSOLITE, POLITIQUE, SCIENCE...), séparés par
	    des losanges ; plus de 120 titres + des titres "dynamiques" qui
	    utilisent les stats du joueur en direct (Dopamine/s, renaissances,
	    cours de l'action, clics, éclairs, rang sur le serveur...) ;
	  - à droite : logo de la chaîne + horloge (deux-points qui clignotent) ;
	  - de temps en temps, un bandeau "ALERTE INFO" descend sous le ticker
	    (calque Overlay, non cliquable) avec un titre spécial.
	Survoler le bandeau à la souris le ralentit. Cliquer sur un titre =
	Interact("Headline") : le serveur limite les récompenses
	(Config.Interactions.Headline) et le "+X" confirmé (OnBonus "Headline")
	s'affiche juste sous le bandeau.
]]

local Players = game:GetService("Players")
local TextService = game:GetService("TextService")

local Locale = require(game:GetService("ReplicatedStorage").Shared.Locale)

local NewsTicker = {}
NewsTicker.Slot = "Ticker"

local HEIGHT = 30 -- hauteur du slot (pixels "design")
local LIVE_W = 78 -- bloc "● DIRECT"
local FLASH_W = 118 -- cartouche "FLASH INFO"
local LEFT_W = LIVE_W + FLASH_W + 10
local RIGHT_W = 104 -- bloc logo + horloge
local TEXT_SIZE = 18
local CHIP_TEXT_SIZE = 11
local SEPARATOR_W = 34
local SPEED = 95 -- pixels "design" par seconde
local SLOW_SPEED = 28 -- vitesse quand la souris survole le bandeau
local MAX_ITEMS = 14 -- sécurité : titres vivants au maximum
local URGENT_CHANCE = 1 / 8
local DYNAMIC_CHANCE = 0.22 -- part des titres "dynamiques" (stats du joueur)
local BREAKING_MIN, BREAKING_MAX = 70, 130 -- secondes entre deux "ALERTE INFO"
local BREAKING_TIME = 5
local BANNER_W, BANNER_H = 540, 46

-- Rubriques : texte de l'étiquette (anglais, traduit avec Locale.T) + couleur
local CATEGORIES = {
	SPORT = { Text = "SPORT", Color = Color3.fromRGB(30, 170, 80) },
	METEO = { Text = "WEATHER", Color = Color3.fromRGB(0, 160, 220) },
	BOURSE = { Text = "MARKETS", Color = Color3.fromRGB(235, 170, 0) },
	INSOLITE = { Text = "WEIRD", Color = Color3.fromRGB(150, 70, 225) },
	POLITIQUE = { Text = "POLITICS", Color = Color3.fromRGB(40, 90, 210) },
	SCIENCE = { Text = "SCIENCE", Color = Color3.fromRGB(0, 150, 140) },
	TECH = { Text = "TECH", Color = Color3.fromRGB(70, 90, 125) },
	CULTURE = { Text = "CULTURE", Color = Color3.fromRGB(230, 70, 140) },
	SANTE = { Text = "HEALTH", Color = Color3.fromRGB(110, 190, 40) },
	PEOPLE = { Text = "CELEBS", Color = Color3.fromRGB(255, 120, 30) },
	ANIMAUX = { Text = "ANIMALS", Color = Color3.fromRGB(170, 110, 50) },
	URGENT = { Text = "URGENT", Color = Color3.fromRGB(255, 210, 30) },
}

-- Titres absurdes { rubrique, texte } (déjà en majuscules), une liste par langue
local HEADLINES = {
	en = {
		{ "ANIMAUX", "THE FROGS HAVE DISAPPEARED... OR MAYBE NOT, HE'S NOT SURE" },
		{ "INSOLITE", "MAN HAS BEEN CLICKING FOR 3 DAYS, SAYS HE'S FINE" },
		{ "SANTE", "ARE COLD SHOWERS THE FUTURE? EXPERTS SHIVER" },
		{ "POLITIQUE", "PIGEON ELECTED MAYOR OF SMALL TOWN, PROMISES MORE CRUMBS" },
		{ "INSOLITE", "ALERT: MONDAY IS COMING AGAIN THIS WEEK" },
		{ "SCIENCE", "SCIENTISTS CONFIRM THE COUCH IS VERY COMFY" },
		{ "INSOLITE", "SOCK FOUND AFTER 12 YEARS ON THE RUN" },
		{ "TECH", "WI-FI GOES DOWN, FAMILY DISCOVERS THEY HAVE A BACKYARD" },
		{ "ANIMAUX", "CAT REFUSES TO GET OFF THE KEYBOARD, NEGOTIATIONS COLLAPSE" },
		{ "SCIENCE", "MOON ANNOUNCES CAREER BREAK, TIDES CONCERNED" },
		{ "SPORT", "SNAIL BREAKS WORLD SLOWNESS RECORD... FOR THE 3RD TIME" },
		{ "METEO", "CLOUDS GO ON STRIKE: SUNSHINE BY DEFAULT ALL WEEK" },
		{ "INSOLITE", "A BUTTON WAS CLICKED, NOBODY KNOWS WHY" },
		{ "BOURSE", "DOPAMINE HITS ALL-TIME HIGH, ECONOMISTS APPLAUD" },
		{ "CULTURE", "BAGUETTE NAMED ACCESSORY OF THE YEAR" },
		{ "ANIMAUX", "GOLDFISH FORGETS ITS OWN BIRTHDAY, AGAIN" },
		{ "SANTE", "RESEARCHERS ARE ADAMANT: YOU SHOULD DRINK WATER" },
		{ "TECH", "GRANDPA INVENTS THE TWO-FINGER CLICK, THE WORLD BOWS DOWN" },
		{ "INSOLITE", "OFFICE COFFEE MACHINE SUES FOR OVERWORK" },
		{ "ANIMAUX", "DUCK CROSSES THE ROAD: MOTIVE STILL UNKNOWN" },
		{ "INSOLITE", "GREEN BEANS COMPLAIN ABOUT ALWAYS BEING LEFT ON THE PLATE" },
		{ "METEO", "HAMSTER-SHAPED CLOUD SPOTTED ABOVE THE CITY" },
		{ "TECH", "EXPERT: “CLICKING IS LIKE BREATHING, BUT WITH YOUR FINGER”" },
		{ "INSOLITE", "KID ASKS “WHY?” 400 TIMES, PARENTS BOOK A VACATION" },
		{ "INSOLITE", "HOUSEPLANT WATERED TWICE IN ONE DAY, NOW IN A STATE OF SHOCK" },
		{ "SCIENCE", "SUN RISES IN THE EAST, NOBODY SURPRISED" },
		{ "SPORT", "BOUNCING LOGO GRAZES THE CORNER, NATION HOLDS ITS BREATH" },
		{ "TECH", "RECORD: 47 TABS OPEN, COMPUTER BEGS FOR MERCY" },
		{ "POLITIQUE", "PINEAPPLE PIZZA SPLITS TOWN, EMERGENCY COUNCIL MEETING CALLED" },
		{ "CULTURE", "GOLDEN STARS ARE FLEETING, PHILOSOPHERS REMIND US" },
		{ "SPORT", "HAMSTER RUNS 20 MILES IN HIS WHEEL, STILL HASN'T GOTTEN ANYWHERE" },
		{ "SPORT", "NAPPING BECOMES AN OLYMPIC SPORT, SPAIN HEAVY FAVORITE" },
		{ "INSOLITE", "FLY ENTERS LIVING ROOM: TOTAL PANIC" },
		{ "SANTE", "BUBBLE WRAP FINALLY RECOGNIZED AS THERAPY" },
		{ "TECH", "ROBOT VACUUM BECOMES SELF-AWARE, JUST WANTS TO BE LOVED" },
		{ "POLITIQUE", "POLL: 100% OF RESPONDENTS RESPONDED TO THE POLL" },
		{ "ANIMAUX", "THE FROGS ARE BACK, THEY WERE JUST ON VACATION" },
		{ "SCIENCE", "TOAST LANDS BUTTER-SIDE DOWN, SCIENTISTS STUNNED" },
		{ "METEO", "100% CHANCE OF WEATHER TOMORROW" },
		{ "INSOLITE", "BOY SAYS “5 MORE MINUTES”, IT'S 3 A.M." },
		{ "INSOLITE", "SLIPPERS GO ON STRIKE, DEMAND CLEANER FEET" },
		{ "BOURSE", "DOPAMINE MARKET GOES UP, DOWN, THEN UP AGAIN. DEVELOPING STORY" },
		{ "INSOLITE", "CONFUSED SUNFLOWER HAS BEEN STARING AT THE LIVING ROOM LAMP SINCE TUESDAY" },
		{ "METEO", "THE OCEAN REMINDS EVERYONE IT'S STILL THERE, JUST IN CASE" },
		{ "ANIMAUX", "SHEEP COUNTS HUMANS TO FALL ASLEEP, IS NOW UP TO 8 BILLION" },
		{ "INSOLITE", "UNICORN SPOTTED IN THE SUBURBS, TURNS OUT TO BE A HORSE HOLDING AN ICE CREAM CONE" },
		-- Sport
		{ "SPORT", "ROCK-PAPER-SCISSORS WORLD CUP CANCELED: EVERYONE PICKED ROCK" },
		{ "SPORT", "MARATHON RUNNER STOPS AT MILE 1 TO PET A DOG, CROWD APPROVES" },
		{ "SPORT", "CURLING VOTED CALMEST SPORT, BROOMS CELEBRATE IN SILENCE" },
		{ "SPORT", "SOCCER TEAM SCORES AN OWN GOAL OUT OF POLITENESS" },
		{ "SPORT", "FLEA SETS HIGH JUMP WORLD RECORD, DECLINES ALL INTERVIEWS" },
		{ "SPORT", "TOUR DE FRANCE ON SCOOTERS: THE PACK ARRIVES 3 WEEKS LATE" },
		{ "SPORT", "REFEREE ENDS THE GAME BY MISTAKE, HE JUST HAD THE HICCUPS" },
		{ "SPORT", "SYNCHRONIZED DUCK SWIMMING DAZZLES THE JUDGES" },
		{ "SPORT", "PING-PONG PLAYER LOSES THE BALL, MATCH ENTERS ITS 4TH HOUR" },
		-- Météo
		{ "METEO", "CODE ORANGE CONFETTI WARNING FOR THE ENTIRE NORTH" },
		{ "METEO", "IT'S RAINING CATS AND DOGS: CATS FURIOUS, DOGS DELIGHTED" },
		{ "METEO", "RAINBOW APOLOGIZES FOR FORGETTING PURPLE" },
		{ "METEO", "WIND SO STRONG AN UMBRELLA APPLIES FOR POLITICAL ASYLUM" },
		{ "METEO", "THICK FOG: MAN SEARCHES FOR HIS CAR, HE WAS SITTING IN IT" },
		{ "METEO", "HEAT WAVE: ICE CUBES ORGANIZE A PROTEST... WHICH MELTS" },
		{ "METEO", "SNOW ARRIVES, LEAVES, THEN COMES BACK: IT FORGOT ITS KEYS" },
		{ "METEO", "LIGHTNING STRIKES THE SAME PLACE TWICE, IT FORGOT ITS UMBRELLA" },
		-- Bourse
		{ "BOURSE", "BAGUETTE GOES PUBLIC, CROISSANTS NERVOUS" },
		{ "BOURSE", "BUBBLE WRAP PRICES EXPLODE, LITERALLY: POP" },
		{ "BOURSE", "TRADER MISTAKES “BUY THE DIP” FOR “BUY CHIPS AND DIP”, MARKETS APPROVE" },
		{ "BOURSE", "CARROTCOIN CRASHES AFTER RABBIT EATS EVERYTHING" },
		{ "BOURSE", "COFFEE CRASH: MONDAYS NOW OFFICIALLY IMPOSSIBLE" },
		{ "BOURSE", "ANALYSTS PREDICT A RISE, A FALL, OR BOTH AT ONCE" },
		{ "BOURSE", "CENTRAL BANK PRINTS LOYALTY POINTS BY MISTAKE" },
		{ "BOURSE", "HUG RECESSION: TEDDY BEARS LAUNCH STIMULUS PACKAGE" },
		-- Insolite
		{ "INSOLITE", "TEEN CLEANS HIS ROOM, MOM CALLS THE FIRE DEPARTMENT" },
		{ "INSOLITE", "FORK FOUND IN THE SPOON DRAWER: INVESTIGATION OPENED" },
		{ "INSOLITE", "FRIDGE MAGNET FALLS, WHOLE FAMILY IN SHOCK" },
		{ "INSOLITE", "ALARM CLOCK RINGS ON A SUNDAY, NOW WANTED BY POLICE" },
		{ "INSOLITE", "REMOTE FOUND BETWEEN TWO CUSHIONS AFTER 3-WEEK MANHUNT" },
		{ "INSOLITE", "SANDWICH LANDS HAM-SIDE DOWN, EXPERTS CALL IT A MIRACLE" },
		{ "INSOLITE", "MAN SUCCESSFULLY FOLDS A FITTED SHEET, SCIENCE HAS NO EXPLANATION" },
		{ "INSOLITE", "PEN WORKS ON THE FIRST TRY, OFFICE IN UPROAR" },
		{ "INSOLITE", "ELEVATOR “CLOSE DOOR” BUTTON HAS BEEN WORKING THIS WHOLE TIME" },
		{ "INSOLITE", "TOASTER LAUNCHES TOAST ALL THE WAY TO THE CEILING, RECORD CERTIFIED" },
		{ "INSOLITE", "LINE FINALLY STARTS MOVING, PEOPLE NO LONGER KNOW WHAT TO DO" },
		{ "INSOLITE", "BAG OF CHIPS CONTAINED MORE CHIPS THAN AIR, MANUFACTURER APOLOGIZES" },
		-- Politique
		{ "POLITIQUE", "MINISTER OF NAPS PROMISES ONE EXTRA HOUR PER DAY" },
		{ "POLITIQUE", "NEW PARTY PROPOSES REPLACING MONDAYS WITH SATURDAYS" },
		{ "POLITIQUE", "CAT COUNCIL VOTES UNANIMOUSLY FOR FREE KIBBLE" },
		{ "POLITIQUE", "HEATED DEBATE: IS A HOT DOG A SANDWICH?" },
		{ "POLITIQUE", "MAYOR OPENS A ROUNDABOUT AROUND ANOTHER ROUNDABOUT" },
		{ "POLITIQUE", "LAZY CLUB ELECTS NEW PRESIDENT... HE DIDN'T SHOW UP" },
		{ "POLITIQUE", "NEW LAW: SPOILING SHOW ENDINGS BANNED BEFORE NOON" },
		-- Science
		{ "SCIENCE", "RESEARCHERS DISCOVER WEEKENDS GO BY FASTER THAN WEEKDAYS" },
		{ "SCIENCE", "STUDY PROVES CATS IGNORE US ON PURPOSE" },
		{ "SCIENCE", "CONFIRMED: THE MOON IS NOT MADE OF CHEESE, WIDESPREAD DISAPPOINTMENT" },
		{ "SCIENCE", "SCIENTISTS CLONE A SOCK TO SOLVE THE MYSTERY OF THE MISSING PAIR" },
		{ "SCIENCE", "ASTRONAUT LEAVES HIS KEYS ON MARS, HAS TO GO BACK" },
		{ "SCIENCE", "GRAVITY TAKES A DAY OFF, EVERYONE FLOATS IN LATE" },
		{ "SCIENCE", "RESEARCHERS CONFIRM “JUST ONE EPISODE” DOES NOT EXIST" },
		{ "SCIENCE", "NEW PLANET DISCOVERED, MADE ENTIRELY OF BUBBLE WRAP" },
		-- Tech
		{ "TECH", "45-MINUTE UPDATE ADDS ONE NEW CARROT EMOJI" },
		{ "TECH", "AI ASKS FOR A COFFEE BREAK, COWORKERS UNDERSTAND" },
		{ "TECH", "RECORD: MAN READS AN ENTIRE TERMS OF SERVICE" },
		{ "TECH", "PRINTER WORKS ON THE FIRST TRY, EXPERTS REMAIN CAUTIOUS" },
		{ "TECH", "PASSWORD “1234” HACKED IN 0.2 SECONDS, OWNER SHOCKED" },
		{ "TECH", "CHARGER WORKS WITHOUT HOLDING THE CABLE AT A WEIRD ANGLE? EXPERTS DOUBTFUL" },
		{ "TECH", "COMPUTER MOUSE DEMANDS CHEESE, IT DEPARTMENT OVERWHELMED" },
		-- Culture
		{ "CULTURE", "MUSEUM DISPLAYS A “CLICK ME” BUTTON, 3 MILLION VISITORS" },
		{ "CULTURE", "4-HOUR MOVIE WITH ZERO EXPLOSIONS: AUDIENCE PEACEFULLY FALLS ASLEEP" },
		{ "CULTURE", "900-PAGE NOVEL SUMMED UP IN A SINGLE EMOJI" },
		{ "CULTURE", "SCHOOL RECORDER CONCERT POSTPONED TO PROTECT EARDRUMS" },
		{ "CULTURE", "STATUE MOVES ONE INCH TO THE LEFT, TOWN STILL TALKING ABOUT IT" },
		{ "CULTURE", "ARTIST SELLS BLANK CANVAS, BUYER ASKS FOR THE COLOR VERSION" },
		{ "CULTURE", "NEIGHBORHOOD KARAOKE BREAKS THE WRONG-NOTE RECORD" },
		-- Santé
		{ "SANTE", "DOCTORS RECOMMEND 8 HOURS OF SLEEP, PHONES RECOMMEND 3" },
		{ "SANTE", "AN APPLE A DAY KEEPS THE DOCTOR AWAY, ESPECIALLY IF YOU THROW IT HARD" },
		{ "SANTE", "STUDY: YAWNING IS CONTAGIOUS. YOU JUST YAWNED, ADMIT IT" },
		{ "SANTE", "MORNING STRETCHES FINALLY RECOGNIZED AS A FULL WORKOUT" },
		{ "SANTE", "NUTRITIONIST DECLARES FRENCH FRIES AN “HONORARY VEGETABLE”" },
		-- People
		{ "PEOPLE", "TV STAR SEARCHES FOR HER GLASSES FOR 2 HOURS (THEY'RE ON HER HEAD)" },
		{ "PEOPLE", "INTERNET'S MOST FAMOUS CAT TURNS DOWN INTERVIEW, WAS NAPPING" },
		{ "PEOPLE", "INFLUENCER POSTS HIS SOUP: 12 LIKES, 11 OF THEM FROM HIS MOM" },
		{ "PEOPLE", "SINGER FORGETS THE LYRICS TO HIS OWN SONG, CROWD WHISPERS THEM TO HIM" },
		-- Animaux
		{ "ANIMAUX", "COW REFUSES TO MOO IN PUBLIC, SAYS SHE'S WORKING ON AN ALBUM" },
		{ "ANIMAUX", "DOG ARRESTED FOR EXCESSIVE TAIL WAGGING" },
		{ "ANIMAUX", "PENGUINS WEAR TUXEDOS FOR THE 10,000TH YEAR IN A ROW" },
		{ "ANIMAUX", "SQUIRREL FORGETS WHERE HE HID HIS NUTS, AN ENTIRE FOREST GROWS" },
		{ "ANIMAUX", "PARROT REPEATS STATE SECRET, GOVERNMENT DENIES EVERYTHING" },
		{ "ANIMAUX", "TORTOISE FINALLY ARRIVES AT HIS 18TH BIRTHDAY PARTY, HE'S 80" },
		{ "ANIMAUX", "SPIDER FINALLY PAYS RENT FOR CEILING CORNER" },
		{ "ANIMAUX", "LLAMA SPITS ON FOOD CRITIC, REVIEWS ARE MIXED" },
		-- Le jeu lui-même
		{ "INSOLITE", "GOLDEN STAR SPOTTED DOWNTOWN, NOBODY HAD TIME TO CLICK IT" },
		{ "BOURSE", "GLOBAL BUBBLE WRAP SHORTAGE, ONE PLAYER UNDER SUSPICION" },
		{ "BOURSE", "LOCAL SLOT MACHINE CONFESSES: “THE HOUSE ALWAYS WINS”" },
		{ "CULTURE", "HYDRAULIC PRESS CRUSHES A MACARON, PASTRY CHEFS IN TEARS" },
		{ "PEOPLE", "STREAMER BITES INTO A STICK OF BUTTER LIVE, 40,000 VIEWERS HYPNOTIZED" },
		{ "METEO", "WINDMILL SPINS WITH NO WIND, METEOROLOGISTS BAFFLED" },
		{ "TECH", "INBOX HITS 10,000 UNREAD, ASKS FOR HELP" },
		{ "METEO", "LOCAL LIGHTNING BOLTS DEMAND MORE CLICKS" },
	},
	fr = {
		{ "ANIMAUX", "LES GRENOUILLES ONT DISPARU... OU PAS, IL N'EST PAS SÛR" },
		{ "INSOLITE", "UN HOMME CLIQUE DEPUIS 3 JOURS, IL VA BIEN" },
		{ "SANTE", "LES DOUCHES FROIDES SONT-ELLES LE FUTUR ?" },
		{ "POLITIQUE", "UN PIGEON ÉLU MAIRE D'UN PETIT VILLAGE, IL PROMET PLUS DE MIETTES" },
		{ "INSOLITE", "ALERTE : LE LUNDI ARRIVE ENCORE CETTE SEMAINE" },
		{ "SCIENCE", "DES SCIENTIFIQUES CONFIRMENT QUE LE CANAPÉ EST TRÈS CONFORTABLE" },
		{ "INSOLITE", "UNE CHAUSSETTE RETROUVÉE APRÈS 12 ANS DE CAVALE" },
		{ "TECH", "LE WIFI TOMBE EN PANNE, UNE FAMILLE DÉCOUVRE QU'ELLE A UN JARDIN" },
		{ "ANIMAUX", "UN CHAT REFUSE DE DESCENDRE DU CLAVIER, LES NÉGOCIATIONS ÉCHOUENT" },
		{ "SCIENCE", "LA LUNE ANNONCE UNE PAUSE CARRIÈRE, LES MARÉES INQUIÈTES" },
		{ "SPORT", "UN ESCARGOT BAT LE RECORD DU MONDE DE LENTEUR... POUR LA 3E FOIS" },
		{ "METEO", "LES NUAGES EN GRÈVE : SOLEIL PAR DÉFAUT TOUTE LA SEMAINE" },
		{ "INSOLITE", "UN BOUTON A ÉTÉ CLIQUÉ, PERSONNE NE SAIT POURQUOI" },
		{ "BOURSE", "LA DOPAMINE ATTEINT UN NIVEAU HISTORIQUE, LES ÉCONOMISTES APPLAUDISSENT" },
		{ "CULTURE", "UNE BAGUETTE DE PAIN ÉLUE MEILLEUR ACCESSOIRE DE L'ANNÉE" },
		{ "ANIMAUX", "UN POISSON ROUGE OUBLIE SON PROPRE ANNIVERSAIRE, ENCORE" },
		{ "SANTE", "LES CHERCHEURS SONT FORMELS : IL FAUT BOIRE DE L'EAU" },
		{ "TECH", "UN PAPY INVENTE LE CLIC À DEUX DOIGTS, LE MONDE S'INCLINE" },
		{ "INSOLITE", "LA MACHINE À CAFÉ DU BUREAU PORTE PLAINTE POUR SURMENAGE" },
		{ "ANIMAUX", "UN CANARD TRAVERSE LA ROUTE : ON NE SAIT TOUJOURS PAS POURQUOI" },
		{ "INSOLITE", "LES HARICOTS VERTS SE PLAIGNENT D'ÊTRE LAISSÉS DANS L'ASSIETTE" },
		{ "METEO", "UN NUAGE EN FORME DE HAMSTER APERÇU AU-DESSUS DE LA VILLE" },
		{ "TECH", "UN EXPERT : « CLIQUER, C'EST COMME RESPIRER, MAIS AVEC LE DOIGT »" },
		{ "INSOLITE", "UN ENFANT DEMANDE « POURQUOI ? » 400 FOIS, SES PARENTS PARTENT EN VACANCES" },
		{ "INSOLITE", "UNE PLANTE VERTE ARROSÉE DEUX FOIS LE MÊME JOUR, ELLE EST SOUS LE CHOC" },
		{ "SCIENCE", "LE SOLEIL SE LÈVE À L'EST, PERSONNE N'EST SURPRIS" },
		{ "SPORT", "UN LOGO QUI REBONDIT FRÔLE LE COIN, LE PAYS RETIENT SON SOUFFLE" },
		{ "TECH", "RECORD : 47 ONGLETS OUVERTS, L'ORDINATEUR DEMANDE PITIÉ" },
		{ "POLITIQUE", "UNE PIZZA À L'ANANAS DIVISE UN VILLAGE, LE CONSEIL MUNICIPAL SE RÉUNIT" },
		{ "CULTURE", "LES ÉTOILES DORÉES SONT ÉPHÉMÈRES, RAPPELLENT LES PHILOSOPHES" },
		{ "SPORT", "UN HAMSTER COURT 30 KM DANS SA ROUE, IL N'EST TOUJOURS ARRIVÉ NULLE PART" },
		{ "SPORT", "LA SIESTE RECONNUE SPORT OLYMPIQUE, LA FRANCE GRANDE FAVORITE" },
		{ "INSOLITE", "UNE MOUCHE ENTRE DANS LE SALON : PANIQUE GÉNÉRALE" },
		{ "SANTE", "LE PAPIER BULLE ENFIN RECONNU COMME THÉRAPIE" },
		{ "TECH", "UN ROBOT ASPIRATEUR DEVIENT CONSCIENT, IL VEUT JUSTE ÊTRE AIMÉ" },
		{ "POLITIQUE", "SONDAGE : 100 % DES PERSONNES INTERROGÉES ONT RÉPONDU AU SONDAGE" },
		{ "ANIMAUX", "LES GRENOUILLES SONT REVENUES, ELLES ÉTAIENT JUSTE EN VACANCES" },
		{ "SCIENCE", "UNE TARTINE TOMBE CÔTÉ BEURRE, LES SCIENTIFIQUES N'EN REVIENNENT PAS" },
		{ "METEO", "100 % DE CHANCES QU'IL FASSE UN TEMPS DEMAIN" },
		{ "INSOLITE", "UN GARÇON DIT « ENCORE 5 MINUTES », IL EST 3 HEURES DU MATIN" },
		{ "INSOLITE", "LES CHAUSSONS EN GRÈVE : ILS EXIGENT DES PIEDS PLUS PROPRES" },
		{ "BOURSE", "LA BOURSE DE LA DOPAMINE MONTE, DESCEND, PUIS REMONTE. AFFAIRE À SUIVRE" },
		{ "INSOLITE", "UN TOURNESOL SE TROMPE ET FIXE LA LAMPE DU SALON DEPUIS MARDI" },
		{ "METEO", "L'OCÉAN RAPPELLE QU'IL EST TOUJOURS LÀ, SI JAMAIS" },
		{ "ANIMAUX", "UN MOUTON COMPTE DES HUMAINS POUR S'ENDORMIR, IL EN EST À 8 MILLIARDS" },
		{ "INSOLITE", "UNE LICORNE APERÇUE EN BANLIEUE, C'ÉTAIT UN CHEVAL AVEC UN CORNET DE GLACE" },
		-- Sport
		{ "SPORT", "MONDIAL DE PIERRE-FEUILLE-CISEAUX ANNULÉ : TOUT LE MONDE A FAIT PIERRE" },
		{ "SPORT", "UN MARATHONIEN S'ARRÊTE AU KILOMÈTRE 2 POUR CARESSER UN CHIEN, LE PUBLIC APPROUVE" },
		{ "SPORT", "LE CURLING ÉLU SPORT LE PLUS CALME, LES BALAIS FÊTENT ÇA EN SILENCE" },
		{ "SPORT", "UNE ÉQUIPE DE FOOT MARQUE CONTRE SON CAMP PAR POLITESSE" },
		{ "SPORT", "RECORD DU MONDE DE SAUT EN HAUTEUR POUR UNE PUCE, ELLE REFUSE LES INTERVIEWS" },
		{ "SPORT", "TOUR DE FRANCE EN TROTTINETTE : LE PELOTON ARRIVE AVEC 3 SEMAINES DE RETARD" },
		{ "SPORT", "UN ARBITRE SIFFLE LA FIN DU MATCH PAR ERREUR, IL AVAIT JUSTE LE HOQUET" },
		{ "SPORT", "LA NATATION SYNCHRONISÉE DES CANARDS ÉBLOUIT LE JURY" },
		{ "SPORT", "UN JOUEUR DE PING-PONG PERD SA BALLE, LE MATCH DURE DEPUIS 4 HEURES" },
		-- Météo
		{ "METEO", "ALERTE ORANGE AUX CONFETTIS SUR TOUT LE NORD DU PAYS" },
		{ "METEO", "IL PLEUT DES CORDES, LES ALPINISTES SONT RAVIS" },
		{ "METEO", "UN ARC-EN-CIEL S'EXCUSE D'AVOIR OUBLIÉ LE VIOLET" },
		{ "METEO", "LE VENT SOUFFLE SI FORT QU'UN PARAPLUIE DEMANDE L'ASILE POLITIQUE" },
		{ "METEO", "BROUILLARD ÉPAIS : UN HOMME CHERCHE SA VOITURE, IL ÉTAIT DEDANS" },
		{ "METEO", "CANICULE : LES GLAÇONS ORGANISENT UNE MANIFESTATION... QUI FOND" },
		{ "METEO", "LA NEIGE ARRIVE, REPART, PUIS REVIENT : ELLE AVAIT OUBLIÉ SES CLÉS" },
		{ "METEO", "UN ÉCLAIR TOMBE DEUX FOIS AU MÊME ENDROIT, IL AVAIT OUBLIÉ SON PARAPLUIE" },
		-- Bourse
		{ "BOURSE", "LA BAGUETTE DE PAIN ENTRE EN BOURSE, LES CROISSANTS INQUIETS" },
		{ "BOURSE", "LE COURS DU PAPIER BULLE EXPLOSE, LITTÉRALEMENT : POP" },
		{ "BOURSE", "UN TRADER CONFOND « ACHETER » ET « ACHETER DES CHIPS », LES MARCHÉS APPRÉCIENT" },
		{ "BOURSE", "LA CRYPTO-CAROTTE S'EFFONDRE APRÈS QU'UN LAPIN A TOUT MANGÉ" },
		{ "BOURSE", "KRACH DU CAFÉ : LES LUNDIS DEVIENNENT OFFICIELLEMENT IMPOSSIBLES" },
		{ "BOURSE", "LES ANALYSTES PRÉDISENT UNE HAUSSE, UNE BAISSE, OU LES DEUX EN MÊME TEMPS" },
		{ "BOURSE", "LA BANQUE CENTRALE IMPRIME DES POINTS DE FIDÉLITÉ PAR ERREUR" },
		{ "BOURSE", "RÉCESSION DE CÂLINS : LES OURS EN PELUCHE LANCENT UN PLAN DE RELANCE" },
		-- Insolite
		{ "INSOLITE", "UN HOMME RANGE SA CHAMBRE, SA MÈRE APPELLE LES POMPIERS" },
		{ "INSOLITE", "UNE FOURCHETTE DÉCOUVERTE DANS LE TIROIR DES CUILLÈRES : ENQUÊTE OUVERTE" },
		{ "INSOLITE", "UN AIMANT DE FRIGO TOMBE, TOUTE LA FAMILLE SOUS LE CHOC" },
		{ "INSOLITE", "UN RÉVEIL SONNE UN DIMANCHE, IL EST ACTIVEMENT RECHERCHÉ" },
		{ "INSOLITE", "UNE TÉLÉCOMMANDE RETROUVÉE ENTRE DEUX COUSSINS APRÈS 3 SEMAINES DE RECHERCHES" },
		{ "INSOLITE", "UN SANDWICH TOMBE CÔTÉ JAMBON, LES EXPERTS PARLENT D'UN MIRACLE" },
		{ "INSOLITE", "UN HOMME RÉUSSIT À PLIER UN DRAP-HOUSSE, LA SCIENCE N'A PAS D'EXPLICATION" },
		{ "INSOLITE", "UN STYLO FONCTIONNE DU PREMIER COUP, LE BUREAU EST EN ÉMOI" },
		{ "INSOLITE", "LE BOUTON « FERMER LES PORTES » DE L'ASCENSEUR FONCTIONNAIT DEPUIS LE DÉBUT" },
		{ "INSOLITE", "UN GRILLE-PAIN ÉJECTE UNE TARTINE JUSQU'AU PLAFOND, RECORD HOMOLOGUÉ" },
		{ "INSOLITE", "UNE FILE D'ATTENTE AVANCE ENFIN, LES GENS NE SAVENT PLUS QUOI FAIRE" },
		{ "INSOLITE", "UN SAC DE CHIPS CONTENAIT PLUS DE CHIPS QUE D'AIR, LE FABRICANT S'EXCUSE" },
		-- Politique
		{ "POLITIQUE", "LE MINISTRE DE LA SIESTE PROMET UNE HEURE DE PLUS PAR JOUR" },
		{ "POLITIQUE", "UN NOUVEAU PARTI PROPOSE DE REMPLACER LES LUNDIS PAR DES SAMEDIS" },
		{ "POLITIQUE", "LE CONSEIL DES CHATS VOTE À L'UNANIMITÉ POUR DES CROQUETTES GRATUITES" },
		{ "POLITIQUE", "DÉBAT HOULEUX : FAUT-IL DIRE « PAIN AU CHOCOLAT » OU « CHOCOLATINE » ?" },
		{ "POLITIQUE", "UN MAIRE INAUGURE UN ROND-POINT AUTOUR D'UN AUTRE ROND-POINT" },
		{ "POLITIQUE", "LE PRÉSIDENT DU CLUB DES PARESSEUX ÉLU... MAIS IL NE S'EST PAS DÉPLACÉ" },
		{ "POLITIQUE", "LOI ADOPTÉE : IL SERA INTERDIT DE RACONTER LA FIN DES SÉRIES AVANT MIDI" },
		-- Science
		{ "SCIENCE", "DES CHERCHEURS DÉCOUVRENT QUE LE WEEK-END PASSE PLUS VITE QUE LA SEMAINE" },
		{ "SCIENCE", "UNE ÉTUDE PROUVE QUE LES CHATS NOUS IGNORENT EXPRÈS" },
		{ "SCIENCE", "C'EST CONFIRMÉ : LA LUNE N'EST PAS EN FROMAGE, DÉCEPTION GÉNÉRALE" },
		{ "SCIENCE", "DES SCIENTIFIQUES CLONENT UNE CHAUSSETTE POUR RÉSOUDRE LE MYSTÈRE DES PAIRES" },
		{ "SCIENCE", "UN ASTRONAUTE OUBLIE SES CLÉS SUR MARS, IL DOIT Y RETOURNER" },
		{ "SCIENCE", "LA GRAVITÉ PREND UN JOUR DE CONGÉ, TOUT LE MONDE EST EN RETARD" },
		{ "SCIENCE", "LES CHERCHEURS CONFIRMENT QUE « JUSTE UN ÉPISODE » N'EXISTE PAS" },
		{ "SCIENCE", "UNE NOUVELLE PLANÈTE DÉCOUVERTE, ELLE EST ENTIÈREMENT EN PAPIER BULLE" },
		-- Tech
		{ "TECH", "UNE MISE À JOUR DE 45 MINUTES AJOUTE UN NOUVEL EMOJI CAROTTE" },
		{ "TECH", "UNE INTELLIGENCE ARTIFICIELLE DEMANDE UNE PAUSE CAFÉ, SES COLLÈGUES COMPRENNENT" },
		{ "TECH", "RECORD : UN HOMME LIT ENTIÈREMENT DES CONDITIONS D'UTILISATION" },
		{ "TECH", "UNE IMPRIMANTE FONCTIONNE DU PREMIER COUP, LES EXPERTS RESTENT PRUDENTS" },
		{ "TECH", "LE MOT DE PASSE « 1234 » PIRATÉ EN 0,2 SECONDE, SON PROPRIÉTAIRE CHOQUÉ" },
		{ "TECH", "UN CHARGEUR QUI MARCHE SANS TENIR LE CÂBLE DE TRAVERS ? LES EXPERTS DOUTENT" },
		{ "TECH", "LA SOURIS D'ORDINATEUR RÉCLAME DU FROMAGE, LE SERVICE INFORMATIQUE DÉPASSÉ" },
		-- Culture
		{ "CULTURE", "UN MUSÉE EXPOSE UN BOUTON « CLIQUE-MOI », 3 MILLIONS DE VISITEURS" },
		{ "CULTURE", "UN FILM DE 4 HEURES SANS AUCUNE EXPLOSION : LE PUBLIC S'ENDORT PAISIBLEMENT" },
		{ "CULTURE", "UN ROMAN DE 900 PAGES RÉSUMÉ EN UN SEUL EMOJI" },
		{ "CULTURE", "LE CONCERT DE FLÛTE À BEC DE L'ÉCOLE REPORTÉ POUR PROTÉGER LES OREILLES" },
		{ "CULTURE", "UNE STATUE DÉMÉNAGE DE TROIS CENTIMÈTRES, LE VILLAGE EN PARLE ENCORE" },
		{ "CULTURE", "UN ARTISTE VEND UNE TOILE BLANCHE, L'ACHETEUR DEMANDE LA VERSION EN COULEUR" },
		{ "CULTURE", "LE KARAOKÉ DU QUARTIER BAT LE RECORD DE FAUSSES NOTES" },
		-- Santé
		{ "SANTE", "LES MÉDECINS RECOMMANDENT 8 HEURES DE SOMMEIL, LE TÉLÉPHONE EN RECOMMANDE 3" },
		{ "SANTE", "UNE POMME PAR JOUR ÉLOIGNE LE MÉDECIN, SURTOUT SI ON LA LANCE FORT" },
		{ "SANTE", "ÉTUDE : BÂILLER EST CONTAGIEUX. VOUS VENEZ DE BÂILLER, AVOUEZ" },
		{ "SANTE", "LES ÉTIREMENTS DU MATIN ENFIN RECONNUS COMME SPORT COMPLET" },
		{ "SANTE", "UN NUTRITIONNISTE DÉCLARE LA FRITE « LÉGUME HONORAIRE »" },
		-- People
		{ "PEOPLE", "UNE STAR DE LA TÉLÉ CHERCHE SES LUNETTES DEPUIS 2 HEURES (SUR SA TÊTE)" },
		{ "PEOPLE", "LE CHAT LE PLUS CÉLÈBRE D'INTERNET REFUSE UNE INTERVIEW, IL DORMAIT" },
		{ "PEOPLE", "UN INFLUENCEUR PUBLIE SA SOUPE : 12 LIKES, DONT 11 DE SA MÈRE" },
		{ "PEOPLE", "UN CHANTEUR OUBLIE LES PAROLES DE SA PROPRE CHANSON, LE PUBLIC LES LUI SOUFFLE" },
		-- Animaux
		{ "ANIMAUX", "UNE VACHE REFUSE DE MEUGLER EN PUBLIC, ELLE PRÉPARE UN ALBUM" },
		{ "ANIMAUX", "UN CHIEN ARRÊTÉ POUR EXCÈS DE REMUAGE DE QUEUE" },
		{ "ANIMAUX", "LES PINGOUINS PORTENT LE SMOKING POUR LA 10 000E ANNÉE CONSÉCUTIVE" },
		{ "ANIMAUX", "UN ÉCUREUIL OUBLIE OÙ IL A CACHÉ SES NOISETTES, UNE FORÊT ENTIÈRE POUSSE" },
		{ "ANIMAUX", "UN PERROQUET RÉPÈTE UN SECRET D'ÉTAT, LE GOUVERNEMENT DÉMENT" },
		{ "ANIMAUX", "UNE TORTUE ARRIVE ENFIN À LA FÊTE DE SES 18 ANS, ELLE EN A 80" },
		{ "ANIMAUX", "UNE ARAIGNÉE PAIE ENFIN SON LOYER DANS LE COIN DU PLAFOND" },
		{ "ANIMAUX", "UN LAMA CRACHE SUR UN CRITIQUE GASTRONOMIQUE, LA CRITIQUE EST MITIGÉE" },
		-- Le jeu lui-même
		{ "INSOLITE", "UNE ÉTOILE DORÉE APERÇUE EN VILLE, PERSONNE N'A EU LE TEMPS DE CLIQUER" },
		{ "BOURSE", "PÉNURIE MONDIALE DE PAPIER BULLE, UN JOUEUR SOUPÇONNÉ" },
		{ "BOURSE", "LA MACHINE À SOUS DU COIN AVOUE : « LA MAISON GAGNE TOUJOURS »" },
		{ "CULTURE", "UNE PRESSE HYDRAULIQUE ÉCRASE UN MACARON, LES PÂTISSIERS EN LARMES" },
		{ "PEOPLE", "UN STREAMER CROQUE DU BEURRE EN DIRECT, 40 000 SPECTATEURS FASCINÉS" },
		{ "METEO", "UN MOULIN À VENT TOURNE SANS VENT, LES MÉTÉOROLOGUES PERPLEXES" },
		{ "TECH", "UNE BOÎTE MAIL ATTEINT 10 000 NON LUS, ELLE DEMANDE DE L'AIDE" },
		{ "METEO", "LES ÉCLAIRS DE LA RÉGION RÉCLAMENT DES CLICS SUPPLÉMENTAIRES" },
	},
}

-- Sous-titres du bandeau "ALERTE INFO"
local BREAKING_SUBTITLES = {
	en = {
		"Our special correspondent is on the scene (he's clicking too)",
		"More details in just a moment...",
		"Experts agree: this is incredible",
		"Stay with us, we'll be right back after the break (there is no break)",
		"The newsroom is in shock, and so is the intern",
	},
	fr = {
		"Notre envoyé spécial est sur place (il clique aussi)",
		"Plus d'informations dans quelques instants...",
		"Les experts sont formels : c'est incroyable",
		"Restez avec nous, on revient après la pub (il n'y a pas de pub)",
		"La rédaction est en émoi, le stagiaire aussi",
	},
}

-- Petites réactions quand on clique sur un titre
local REACTIONS = { "😂", "🤯", "😱", "🤔", "👀", "🙃", "😮", "🧐", "📰", "😳" }

function NewsTicker.Start(ctx)
	local UIUtil = ctx.UIUtil
	local Theme = ctx.Theme
	local Format = ctx.Format
	local container: Frame = ctx.Container
	local overlay: Frame = ctx.Overlay
	local random = Random.new()

	local red = Color3.fromRGB(220, 26, 38)
	local darkRed = Color3.fromRGB(140, 8, 18)
	local navy = Color3.fromRGB(16, 22, 40)
	local yellow = Theme.Colors.Yellow
	local white = Color3.new(1, 1, 1)

	-- Police gras + italique (BuilderSans)
	local italicFont = Font.new("rbxasset://fonts/families/BuilderSans.json", Enum.FontWeight.Bold, Enum.FontStyle.Italic)
	local boldFont = Font.new("rbxasset://fonts/families/BuilderSans.json", Enum.FontWeight.ExtraBold, Enum.FontStyle.Normal)

	local function effectsOn(): boolean
		local data = ctx.State.Data
		return not (data and data.Settings and data.Settings.Effects == false)
	end

	local function frame(props: { [string]: any }): Frame
		props.BorderSizePixel = 0
		if props.BackgroundTransparency == nil and props.BackgroundColor3 == nil then
			props.BackgroundTransparency = 1
		end
		return UIUtil.Create("Frame", props)
	end

	------------------------------------------------------------------
	-- Titres "dynamiques" (utilisent l'état du joueur en direct)
	------------------------------------------------------------------
	local function data(): any
		return ctx.State.Data
	end

	local function stat(name: string): number
		local current = data()
		local stats = current and current.Stats
		return (stats and tonumber(stats[name])) or 0
	end

	local function field(name: string): number
		local current = data()
		return (current and tonumber(current[name])) or 0
	end

	local function playerName(): string
		local player = Players.LocalPlayer
		local name = player and player.DisplayName or Locale.T("SOMEONE")
		return string.upper(name)
	end

	local function big(value: number): string
		if value < 1e6 then
			return Format.WithSpaces(value)
		end
		return Format.Format(value)
	end

	-- Chaque générateur renvoie (rubrique, texte) ou nil s'il n'a rien à dire
	local DYNAMIC: { () -> (string?, string?) } = {
		function()
			return "BOURSE", Locale.T("RECORD: %s OWNS %s DOPAMINE, THE NEIGHBORS ARE WORRIED", playerName(), big(field("Dopamine")))
		end,
		function()
			local perSecond = field("PerSecond")
			if perSecond <= 0 then
				return nil
			end
			return "BOURSE", Locale.T("RECORD OUTPUT: %s DOPAMINE PER SECOND, SMILE FACTORIES RUNNING AT FULL SPEED", big(perSecond))
		end,
		function()
			return "INSOLITE", Locale.T("THE “CLICK ME” BUTTON HAS BEEN CLICKED %s TIMES, IT'S ASKING FOR A VACATION", big(stat("TotalClicks")))
		end,
		function()
			return "PEOPLE", Locale.T("EXCLUSIVE: %s HASN'T BLINKED IN 20 MINUTES", playerName())
		end,
		function()
			return "PEOPLE", Locale.T("INTERVIEW: %s CLAIMS THEY CAN “QUIT ANYTIME”", playerName())
		end,
		function()
			if not ctx.HasFeature("Stocks") then
				return nil
			end
			local stock = ctx.State.Stock
			local price = stock and tonumber(stock.Price)
			if not price then
				return nil
			end
			local symbol = tostring(stock.Symbol or "DOPA")
			return "BOURSE", Locale.T("%s STOCK TRADES AT %s, ANALYSTS PRAISE A “VERY PRETTY CURVE”", symbol, string.format("%.2f", price))
		end,
		function()
			local rebirths = field("Rebirths")
			if rebirths <= 0 then
				return "SANTE", Locale.T("%s HAS NEVER BEEN TO THE OCEAN, THE SEAGULLS ARE WORRIED", playerName())
			end
			return "SANTE", Locale.T("%s HAS BEEN TO THE OCEAN %s TIMES... AND ALWAYS COMES BACK TO CLICK", playerName(), big(rebirths))
		end,
		function()
			local current = data()
			local screen = current and current.ScreenTime
			local today = screen and tonumber(screen.Today)
			if not today or today < 60 then
				return nil
			end
			return "SANTE", Locale.T("SCREEN TIME: %s HAS SPENT %s STARING AT A BUTTON TODAY", playerName(), string.upper(Format.Time(today)))
		end,
		function()
			local count = stat("LightningClicks")
			if count <= 0 then
				return nil
			end
			return "SPORT", Locale.T("%s LIGHTNING BOLTS CAUGHT BARE-HANDED: %s IS NOW A LEGEND", big(count), playerName())
		end,
		function()
			local count = stat("BubblesPopped")
			if count <= 0 then
				return nil
			end
			return "INSOLITE", Locale.T("%s BUBBLES POPPED: BUBBLE WRAP MAKERS THANK %s", big(count), playerName())
		end,
		function()
			local count = stat("SlotSpins")
			if count <= 0 then
				return nil
			end
			return "BOURSE", Locale.T("CASINO: %s SPINS BY %s, THE HOUSE SAYS THANK YOU", big(count), playerName())
		end,
		function()
			local count = stat("EmailsRead")
			if count <= 0 then
				return nil
			end
			return "TECH", Locale.T("%s EMAILS READ BY %s, AND THERE ARE STILL MORE", big(count), playerName())
		end,
		function()
			local count = stat("Bounces")
			if count <= 0 then
				return nil
			end
			return "SPORT", Locale.T("THE LOGO HAS BOUNCED %s TIMES, IT'S DIZZY BUT STILL AIMING FOR THE CORNER", big(count))
		end,
		function()
			local ok, rank, total = pcall(ctx.State.GetServerRank)
			if not ok or type(rank) ~= "number" or type(total) ~= "number" or total < 2 then
				return nil
			end
			if rank == 1 then
				return "POLITIQUE", Locale.T("LEADERBOARD: %s IS #1 ON THE SERVER, OTHER PLAYERS DEMAND A RECOUNT", playerName())
			end
			return "POLITIQUE", Locale.T("LEADERBOARD: %s IS #%s OUT OF %s, TENSION IS RISING", playerName(), tostring(rank), tostring(total))
		end,
		function()
			local multiplier = field("RebirthMultiplier")
			if multiplier <= 1 then
				return nil
			end
			return "BOURSE", Locale.T("REBIRTH MULTIPLIER: %s, ECONOMISTS ARE BAFFLED", string.upper(Format.Multiplier(multiplier)))
		end,
		function()
			local rush = ctx.State.Rush
			if type(rush) ~= "table" or not rush.Active then
				return nil
			end
			local name = type(rush.Name) == "string" and rush.Name ~= "" and string.upper(rush.Name) or "RUSH"
			return "URGENT", Locale.T("RIGHT NOW: %s %s! EVERYONE'S CLICKING!", name, string.upper(Format.Multiplier(tonumber(rush.Multiplier) or 1)))
		end,
	}

	-- Paquets mélangés : chaque titre passe une fois avant de revenir
	local deck: { any } = {}
	local dynamicDeck: { any } = {}
	local function shuffle(list: { any })
		for i = #list, 2, -1 do
			local j = random:NextInteger(1, i)
			list[i], list[j] = list[j], list[i]
		end
	end

	local function nextDynamic(): (string?, string?)
		for _ = 1, #DYNAMIC do
			if #dynamicDeck == 0 then
				for _, generator in ipairs(DYNAMIC) do
					table.insert(dynamicDeck, generator)
				end
				shuffle(dynamicDeck)
			end
			local generator = table.remove(dynamicDeck)
			local ok, category, text = pcall(generator)
			if ok and type(category) == "string" and type(text) == "string" then
				return category, text
			end
		end
		return nil, nil
	end

	local function nextHeadline(): (string, string)
		if random:NextNumber() < DYNAMIC_CHANCE then
			local category, text = nextDynamic()
			if category and text then
				return category, text
			end
		end
		local headlines = Locale.Pick(HEADLINES)
		if #deck == 0 then
			for _, entry in ipairs(headlines) do
				table.insert(deck, entry)
			end
			shuffle(deck)
		end
		local entry = table.remove(deck) or headlines[1]
		return entry[1], entry[2]
	end

	------------------------------------------------------------------
	-- Construction du bandeau
	------------------------------------------------------------------
	local strip = frame({
		Name = "Strip",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = white,
		ZIndex = 1,
		Parent = container,
	})
	UIUtil.Gradient(strip, ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(236, 40, 52)),
		ColorSequenceKeypoint.new(0.5, red),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(170, 12, 24)),
	}), 90)
	-- Reflet en haut + liseré sombre en bas
	frame({
		Name = "TopLine",
		Size = UDim2.new(1, 0, 0, 1),
		BackgroundColor3 = white,
		BackgroundTransparency = 0.6,
		ZIndex = 6,
		Parent = container,
	})
	frame({
		Name = "BottomLine",
		Size = UDim2.new(1, 0, 0, 2),
		Position = UDim2.new(0, 0, 1, -2),
		BackgroundColor3 = darkRed,
		ZIndex = 6,
		Parent = container,
	})

	-- Zone de défilement
	local clip = frame({
		Name = "Clip",
		Size = UDim2.new(1, -(LEFT_W + RIGHT_W), 1, 0),
		Position = UDim2.fromOffset(LEFT_W, 0),
		ClipsDescendants = true,
		ZIndex = 2,
		Parent = container,
	})
	-- Bloc "● DIRECT" (bleu nuit)
	local live = frame({
		Name = "Live",
		Size = UDim2.new(0, LIVE_W, 1, 0),
		BackgroundColor3 = white,
		ZIndex = 4,
		Parent = container,
	})
	UIUtil.Gradient(live, ColorSequence.new(Color3.fromRGB(34, 44, 74), navy), 90)
	local liveDot = frame({
		Name = "LiveDot",
		Size = UDim2.fromOffset(9, 9),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0, 13, 0.5, 0),
		BackgroundColor3 = Color3.fromRGB(255, 50, 60),
		ZIndex = 6,
		Parent = live,
	})
	UIUtil.Corner(liveDot, UDim.new(1, 0))
	local liveHalo = frame({
		Size = UDim2.fromOffset(9, 9),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = liveDot.Position,
		BackgroundColor3 = Color3.fromRGB(255, 50, 60),
		BackgroundTransparency = 0.5,
		ZIndex = 5,
		Parent = live,
	})
	UIUtil.Corner(liveHalo, UDim.new(1, 0))
	local liveHaloScale = UIUtil.Create("UIScale", { Parent = liveHalo })
	local liveLabel = UIUtil.Create("TextLabel", {
		Size = UDim2.new(1, -24, 1, 0),
		Position = UDim2.fromOffset(22, 0),
		BackgroundTransparency = 1,
		Text = Locale.T("LIVE"),
		TextColor3 = white,
		TextSize = 14,
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = 6,
		Parent = live,
	})
	liveLabel.FontFace = boldFont

	-- Cartouche "FLASH INFO" (blanc, bord droit en biais)
	local flashText = Locale.T("NEWS FLASH")
	local flash = frame({
		Name = "FlashInfo",
		Position = UDim2.fromOffset(LIVE_W, 0),
		Size = UDim2.new(0, FLASH_W, 1, 0),
		BackgroundColor3 = white,
		ClipsDescendants = false,
		ZIndex = 4,
		Parent = container,
	})
	local slant = frame({
		Name = "Slant",
		Size = UDim2.fromOffset(20, HEIGHT + 20),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(1, 0, 0.5, 0),
		Rotation = 18,
		BackgroundColor3 = white,
		ZIndex = 4,
		Parent = flash,
	})
	-- Petite ombre du biais (donne du relief)
	frame({
		Size = UDim2.fromOffset(6, HEIGHT + 20),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(1, 12, 0.5, 0),
		Rotation = 18,
		BackgroundColor3 = darkRed,
		BackgroundTransparency = 0.3,
		ZIndex = 3,
		Parent = flash,
	})
	local flashLabel = UIUtil.Create("TextLabel", {
		Name = "Title",
		Size = UDim2.new(1, -4, 1, 0),
		Position = UDim2.fromOffset(8, 0),
		BackgroundTransparency = 1,
		Text = flashText,
		TextColor3 = red,
		TextSize = 18,
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = 5,
		Parent = flash,
	})
	flashLabel.FontFace = italicFont

	-- Bloc droit : logo de la chaîne + horloge
	local right = frame({
		Name = "Clock",
		Size = UDim2.new(0, RIGHT_W, 1, 0),
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.fromScale(1, 0),
		BackgroundColor3 = white,
		ZIndex = 4,
		Parent = container,
	})
	UIUtil.Gradient(right, ColorSequence.new(Color3.fromRGB(34, 44, 74), navy), 90)
	local logo = frame({
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 6, 0.5, 0),
		Size = UDim2.fromOffset(38, 18),
		BackgroundColor3 = white,
		ZIndex = 5,
		Parent = right,
	})
	UIUtil.Corner(logo, 4)
	UIUtil.Gradient(logo, ColorSequence.new(Color3.fromRGB(255, 70, 80), darkRed), 90)
	local logoLabel = UIUtil.Create("TextLabel", {
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Text = "DC24",
		TextColor3 = white,
		TextSize = 12,
		ZIndex = 6,
		Parent = logo,
	})
	logoLabel.FontFace = boldFont
	local clockLabel = UIUtil.Create("TextLabel", {
		Name = "Time",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -6, 0, 0),
		Size = UDim2.new(1, -52, 1, 0),
		BackgroundTransparency = 1,
		Font = Theme.Fonts.Mono,
		Text = "--:--",
		TextColor3 = white,
		TextSize = 15,
		TextXAlignment = Enum.TextXAlignment.Right,
		ZIndex = 6,
		Parent = right,
	})

	-- Bouton invisible qui couvre tout le bandeau (clic / survol)
	local button = UIUtil.Create("TextButton", {
		Name = "HitArea",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		AutoButtonColor = false,
		Text = "",
		ZIndex = 10,
		Parent = container,
	})

	------------------------------------------------------------------
	-- Titres qui défilent
	------------------------------------------------------------------
	local items: { any } = {}

	-- Largeur "design" d'un élément (la toile est mise à l'échelle)
	local function designWidth(guiObject: GuiObject): number
		local absHeight = container.AbsoluteSize.Y
		if absHeight <= 0 then
			return 1280
		end
		return guiObject.AbsoluteSize.X * (HEIGHT / absHeight)
	end

	local function measure(text: string, size: number): number
		local ok, result = pcall(function()
			return TextService:GetTextSize(text, size, Enum.Font.BuilderSansBold, Vector2.new(10000, HEIGHT))
		end)
		if ok and result then
			return result.X
		end
		return #text * size * 0.6
	end

	local function addItem(x: number)
		local categoryId, text = nextHeadline()
		local urgent = categoryId == "URGENT" or random:NextNumber() < URGENT_CHANCE
		local category = CATEGORIES[categoryId] or CATEGORIES.INSOLITE
		if urgent then
			category = CATEGORIES.URGENT
		end
		local chipText = Locale.T(category.Text)
		local chipW = measure(chipText, CHIP_TEXT_SIZE) + 14
		local textWidth = measure(text, TEXT_SIZE) + 10 -- un peu de marge pour l'italique
		local width = chipW + 8 + textWidth + SEPARATOR_W

		local itemFrame = frame({
			Name = "Headline",
			Size = UDim2.fromOffset(width, HEIGHT),
			Position = UDim2.fromOffset(x, 0),
			ZIndex = 2,
			Parent = clip,
		})
		local chip = frame({
			Name = "Category",
			AnchorPoint = Vector2.new(0, 0.5),
			Position = UDim2.new(0, 0, 0.5, -1),
			Size = UDim2.fromOffset(chipW, 17),
			BackgroundColor3 = category.Color,
			ZIndex = 3,
			Parent = itemFrame,
		})
		UIUtil.Corner(chip, 4)
		UIUtil.Stroke(chip, white, 1, 0.55)
		local chipLabel = UIUtil.Create("TextLabel", {
			Size = UDim2.fromScale(1, 1),
			BackgroundTransparency = 1,
			Font = Theme.Fonts.Title,
			Text = chipText,
			TextColor3 = urgent and Theme.Colors.TextDark or white,
			TextSize = CHIP_TEXT_SIZE,
			ZIndex = 4,
			Parent = chip,
		})
		local label = UIUtil.Create("TextLabel", {
			Name = "Text",
			Size = UDim2.fromOffset(textWidth, HEIGHT - 2),
			Position = UDim2.fromOffset(chipW + 8, 0),
			BackgroundTransparency = 1,
			Text = text,
			TextColor3 = urgent and yellow or white,
			TextSize = TEXT_SIZE,
			TextXAlignment = Enum.TextXAlignment.Left,
			ZIndex = 3,
			Parent = itemFrame,
		})
		label.FontFace = italicFont
		local textStroke = UIUtil.Stroke(label, darkRed, 1, 0.5)
		textStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
		UIUtil.Create("TextLabel", {
			Name = "Separator",
			Size = UDim2.fromOffset(SEPARATOR_W, HEIGHT - 2),
			Position = UDim2.fromOffset(chipW + 8 + textWidth, 0),
			BackgroundTransparency = 1,
			Font = Theme.Fonts.Title,
			Text = "◆",
			TextColor3 = Color3.fromRGB(255, 200, 200),
			TextSize = 12,
			ZIndex = 3,
			Parent = itemFrame,
		})

		table.insert(items, {
			Frame = itemFrame,
			Label = label,
			Chip = chip,
			ChipLabel = chipLabel,
			Width = width,
			X = x,
			Urgent = urgent,
			Alerted = false,
			BaseColor = urgent and yellow or white,
		})
	end

	-- Alerte "URGENT" : le cartouche clignote en jaune
	local alertUntil = 0
	local function triggerAlert()
		alertUntil = os.clock() + 2.5
		flashLabel.Text = Locale.T("URGENT!")
		ctx.Sound.Play("Notif", 0.8)
	end

	------------------------------------------------------------------
	-- Bandeau "ALERTE INFO" (descend sous le ticker, calque Overlay)
	------------------------------------------------------------------
	local banner = frame({
		Name = "BreakingNews",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, -BANNER_H - 20),
		Size = UDim2.fromOffset(BANNER_W, BANNER_H),
		Visible = false,
		ZIndex = 50,
		Parent = overlay,
	})
	-- Détruit avec le conteneur (arrêt du stimulus, détox)
	container.Destroying:Connect(function()
		banner:Destroy()
	end)
	local bannerShadow = frame({
		Size = UDim2.new(1, 6, 1, 6),
		Position = UDim2.fromOffset(-3, 4),
		BackgroundColor3 = Color3.new(0, 0, 0),
		BackgroundTransparency = 0.8,
		ZIndex = 50,
		Parent = banner,
	})
	UIUtil.Corner(bannerShadow, 10)
	local bannerBody = frame({
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = white,
		ZIndex = 51,
		Parent = banner,
	})
	UIUtil.Corner(bannerBody, 8)
	UIUtil.Gradient(bannerBody, ColorSequence.new(white, Color3.fromRGB(226, 230, 240)), 90)
	UIUtil.Stroke(bannerBody, navy, 1.5, 0.2)
	local alertBox = frame({
		Size = UDim2.new(0, 118, 1, 0),
		BackgroundColor3 = red,
		ZIndex = 52,
		Parent = bannerBody,
	})
	UIUtil.Corner(alertBox, 8)
	UIUtil.Gradient(alertBox, ColorSequence.new(white, Color3.fromRGB(190, 190, 190)), 90)
	local alertTitle = UIUtil.Create("TextLabel", {
		Size = UDim2.new(1, -8, 0, 22),
		Position = UDim2.fromOffset(4, 4),
		BackgroundTransparency = 1,
		Text = Locale.T("BREAKING"),
		TextColor3 = white,
		TextSize = 20,
		ZIndex = 53,
		Parent = alertBox,
	})
	alertTitle.FontFace = italicFont
	local alertSub = UIUtil.Create("TextLabel", {
		Size = UDim2.new(1, -8, 0, 14),
		Position = UDim2.fromOffset(4, 26),
		BackgroundTransparency = 1,
		Font = Theme.Fonts.Title,
		Text = Locale.T("NEWS ● LIVE"),
		TextColor3 = Color3.fromRGB(255, 225, 225),
		TextSize = 11,
		ZIndex = 53,
		Parent = alertBox,
	})
	local bannerHeadline = UIUtil.Label({
		Text = "",
		Font = Theme.Fonts.Title,
		TextColor3 = navy,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextWrapped = true,
		Position = UDim2.fromOffset(128, 4),
		Size = UDim2.new(1, -138, 0, 26),
		MaxTextSize = 17,
		ZIndex = 52,
		Parent = bannerBody,
	})
	bannerHeadline.FontFace = italicFont
	local bannerSub = UIUtil.Create("TextLabel", {
		Position = UDim2.fromOffset(128, 30),
		Size = UDim2.new(1, -138, 0, 12),
		BackgroundTransparency = 1,
		Font = Theme.Fonts.Body,
		Text = "",
		TextColor3 = Color3.fromRGB(100, 108, 128),
		TextSize = 11,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextTruncate = Enum.TextTruncate.AtEnd,
		ZIndex = 52,
		Parent = bannerBody,
	})
	-- Reflet qui balaie le bandeau
	local gleam = frame({
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(-0.2, 0, 0.5, 0),
		Size = UDim2.new(0, 40, 1.6, 0),
		Rotation = 20,
		BackgroundColor3 = white,
		BackgroundTransparency = 0.55,
		ZIndex = 54,
		Parent = bannerBody,
	})
	UIUtil.Create("UIGradient", {
		Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 1),
			NumberSequenceKeypoint.new(0.5, 0.2),
			NumberSequenceKeypoint.new(1, 1),
		}),
		Parent = gleam,
	})

	local bannerUntil = 0
	local bannerToken = 0
	local function showBreaking()
		if not ctx.IsAlive() then
			return
		end
		-- Titre spécial : dynamique si possible, sinon un titre du paquet
		local _, text = nextDynamic()
		if not text then
			local _, fallback = nextHeadline()
			text = fallback
		end
		bannerToken += 1
		local token = bannerToken
		bannerHeadline.Text = text or ""
		local subtitles = Locale.Pick(BREAKING_SUBTITLES)
		bannerSub.Text = subtitles[random:NextInteger(1, #subtitles)] .. " · " .. clockLabel.Text
		banner.Visible = true
		banner.Position = UDim2.new(0.5, 0, 0, -BANNER_H - 20)
		UIUtil.Tween(banner, 0.5, { Position = UDim2.new(0.5, 0, 0, HEIGHT + 4) }, Enum.EasingStyle.Back)
		gleam.Position = UDim2.new(-0.2, 0, 0.5, 0)
		UIUtil.Tween(gleam, 1.1, { Position = UDim2.new(1.2, 0, 0.5, 0) }, Enum.EasingStyle.Quad, Enum.EasingDirection.InOut)
		bannerUntil = os.clock() + BREAKING_TIME
		triggerAlert()
		task.delay(BREAKING_TIME, function()
			if token ~= bannerToken or not banner.Parent then
				return
			end
			UIUtil.Tween(banner, 0.35, { Position = UDim2.new(0.5, 0, 0, -BANNER_H - 20) }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
			task.delay(0.4, function()
				if token == bannerToken and banner.Parent then
					banner.Visible = false
				end
			end)
		end)
	end

	task.spawn(function()
		local waitTime = random:NextNumber(25, 45)
		while ctx.IsAlive() do
			local finish = os.clock() + waitTime
			while ctx.IsAlive() and os.clock() < finish do
				task.wait(1)
			end
			if not ctx.IsAlive() then
				break
			end
			showBreaking()
			waitTime = random:NextNumber(BREAKING_MIN, BREAKING_MAX)
		end
	end)

	------------------------------------------------------------------
	-- Animation (une seule connexion)
	------------------------------------------------------------------
	local speed = SPEED
	local targetSpeed = SPEED

	-- Survol à la SOURIS uniquement (MouseEnter est aussi émulé par un
	-- toucher sur mobile, sans MouseLeave fiable : le bandeau resterait lent)
	local function onHover(input: InputObject)
		if input.UserInputType == Enum.UserInputType.MouseMovement then
			targetSpeed = SLOW_SPEED
		end
	end
	ctx.Connect(button.InputBegan, onHover)
	ctx.Connect(button.InputChanged, onHover)
	ctx.Connect(button.InputEnded, function(input: InputObject)
		if input.UserInputType == Enum.UserInputType.MouseMovement then
			targetSpeed = SPEED
		end
	end)

	ctx.OnRender(function(dt: number)
		dt = math.min(dt, 0.1)
		speed += (targetSpeed - speed) * math.min(1, dt * 6)
		local clipWidth = designWidth(clip)
		local now = os.clock()

		-- Déplacement + suppression des titres sortis à gauche
		local i = 1
		while i <= #items do
			local item = items[i]
			item.X -= speed * dt
			if item.X + item.Width < -4 then
				item.Frame:Destroy()
				table.remove(items, i)
			else
				item.Frame.Position = UDim2.fromOffset(item.X, 0)
				if item.Urgent then
					-- Étiquette URGENT qui clignote
					local blink = math.floor(now * 4) % 2 == 0
					item.Chip.BackgroundColor3 = blink and yellow or white
					if not item.Alerted and item.X < clipWidth * 0.6 then
						item.Alerted = true
						triggerAlert()
					end
				end
				i += 1
			end
		end

		-- Ajout de nouveaux titres à droite
		local guard = 0
		while guard < 4 and #items < MAX_ITEMS do
			local last = items[#items]
			local edge = last and (last.X + last.Width) or clipWidth * 0.3
			if last and edge > clipWidth + 30 then
				break
			end
			addItem(edge)
			guard += 1
		end

		-- Point "en direct" : clignote + halo qui s'élargit
		local pulse = (now % 1.2) / 1.2
		liveDot.BackgroundTransparency = (math.floor(now * 2) % 2 == 0) and 0 or 0.45
		liveHaloScale.Scale = 1 + pulse * 1.4
		liveHalo.BackgroundTransparency = 0.4 + pulse * 0.6

		-- Cartouche : alerte urgente (jaune clignotant)
		if now < alertUntil then
			local blink = math.floor(now * 6) % 2 == 0
			local color = blink and yellow or white
			flash.BackgroundColor3 = color
			slant.BackgroundColor3 = color
			flashLabel.TextColor3 = blink and Theme.Colors.TextDark or red
		elseif flashLabel.Text ~= flashText then
			flashLabel.Text = flashText
			flash.BackgroundColor3 = white
			slant.BackgroundColor3 = white
			flashLabel.TextColor3 = red
		end

		-- Bandeau "ALERTE INFO" : fond rouge qui pulse
		if banner.Visible and now < bannerUntil + 0.5 then
			local blink = math.floor(now * 3) % 2 == 0
			alertBox.BackgroundColor3 = blink and red or darkRed
			alertSub.TextTransparency = blink and 0 or 0.3
		end
	end)

	-- Horloge (heure locale, deux-points qui clignotent)
	task.spawn(function()
		local colon = true
		while ctx.IsAlive() do
			local now = os.date("*t")
			if now and now.hour and now.min then
				clockLabel.Text = string.format(colon and "%02d:%02d" or "%02d %02d", now.hour, now.min)
			end
			colon = not colon
			task.wait(0.5)
		end
	end)

	------------------------------------------------------------------
	-- Clic sur un titre
	------------------------------------------------------------------
	local interaction = ctx.Config.Interactions and ctx.Config.Interactions.Headline
	local cooldown = (interaction and tonumber(interaction.Cooldown)) or 8
	local lastInteract = -math.huge
	local lastScaleX = 0.5

	ctx.Connect(button.Activated, function(input)
		-- Position X du clic (pixels réels ; milieu du bandeau par défaut)
		local px: number = clip.AbsolutePosition.X + clip.AbsoluteSize.X * 0.5
		if typeof(input) == "Instance" and input:IsA("InputObject") then
			px = input.Position.X
		end

		-- Titre sous le curseur (ou le plus proche)
		local hit, bestDistance = nil, math.huge
		for _, item in ipairs(items) do
			local absX = item.Frame.AbsolutePosition.X
			local absW = item.Frame.AbsoluteSize.X
			local distance = 0
			if px < absX then
				distance = absX - px
			elseif px > absX + absW then
				distance = px - (absX + absW)
			end
			if distance < bestDistance then
				hit, bestDistance = item, distance
			end
		end

		-- Position du clic sur la toile (échelle 0..1 de l'overlay)
		local overlayWidth = overlay.AbsoluteSize.X
		if overlayWidth > 0 then
			lastScaleX = math.clamp((px - overlay.AbsolutePosition.X) / overlayWidth, 0.05, 0.95)
		end

		ctx.Sound.Play("Click", 1.3 + random:NextNumber() * 0.2)
		if hit then
			local label = hit.Label
			label.TextColor3 = Theme.Colors.TextDark
			label.BackgroundTransparency = 0
			label.BackgroundColor3 = yellow
			label.Position = UDim2.new(label.Position.X, UDim.new(0, -3))
			UIUtil.Tween(label, 0.35, { Position = UDim2.new(label.Position.X, UDim.new(0, 0)) }, Enum.EasingStyle.Bounce)
			task.delay(0.7, function()
				if label.Parent then
					label.TextColor3 = hit.BaseColor
					UIUtil.Tween(label, 0.25, { BackgroundTransparency = 1 })
				end
			end)
		end

		-- Petite réaction sous le bandeau
		if effectsOn() then
			ctx.FloatText(overlay, UDim2.new(lastScaleX, 0, 0, 52), REACTIONS[random:NextInteger(1, #REACTIONS)], white, 30)
		end

		-- Récompense (le serveur a son propre délai ; on évite juste de spammer)
		local now = os.clock()
		if now - lastInteract >= cooldown then
			lastInteract = now
			ctx.Interact("Headline")
		end
	end)

	-- Bonus confirmé par le serveur
	ctx.OnBonus("Headline", function(payload)
		if not ctx.IsAlive() then
			return
		end
		local amount = tonumber(payload.Amount) or 0
		ctx.FloatText(overlay, UDim2.new(lastScaleX, 0, 0, 84), "+" .. Format.Format(amount), Theme.Colors.Gold, 34)
	end)
end

function NewsTicker.Stop(_ctx)
	-- Tout vit dans ctx.Container (détruit par le StimulusManager), sauf le
	-- bandeau "ALERTE INFO" (Overlay) détruit avec le conteneur ; les textes
	-- flottants de l'overlay se détruisent tout seuls.
end

return NewsTicker
