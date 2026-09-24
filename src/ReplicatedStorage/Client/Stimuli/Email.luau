--[[
	Email (ModuleScript - stimulus)
	Emplacement : ReplicatedStorage > Client > Stimuli > Email

	Messagerie "Dopamail" façon client mail premium :
	  - chaque mail (décidé par le SERVEUR via l'événement Spawn "Email")
	    arrive en vol plané sous forme de carte-enveloppe : rabat en V,
	    timbre, avatar rond de l'expéditeur, nom, objet, aperçu du texte,
	    pastille bleue "non lu", étiquette de priorité colorée (URGENT,
	    PROMO, FAMILLE, TRAVAIL, ARNAQUE ?...) et barre de temps restant ;
	  - un clic l'ouvre : la lettre sort de l'enveloppe puis la carte
	    s'agrandit en vraie fenêtre de mail (barre de titre, objet, avatar,
	    adresse, corps, signature, pièce jointe éventuelle, boutons
	    Répondre / Transférer / Supprimer) + ClaimSpawn (le serveur valide) ;
	    le "+X" confirmé (OnBonus "Email") s'affiche à côté ;
	  - si on l'ignore trop longtemps, elle s'envole... et s'ajoute au
	    compteur "📬 non lus" (en haut à droite), qui ne fait que grossir.
	Plus de 60 mails absurdes (spam, newsletters, maman, le boss, le prince,
	promos, faux support technique...) choisis par info.Variant.
]]

local Debris = game:GetService("Debris")

local Email = {}
Email.Slot = "Overlay"

local MAX_ENVELOPES = 4
local CARD_W = 236
local CARD_H = 74
local POPUP_W = 360
local POPUP_H = 252
local POPUP_AUTO_CLOSE = 14
local HURRY_TIME = 3 -- dernières secondes : la carte s'agite

-- Styles des étiquettes de priorité
local TAGS = {
	URGENT = { Text = "🔴 URGENT", Color = Color3.fromRGB(226, 38, 52) },
	PROMO = { Text = "🏷️ PROMO", Color = Color3.fromRGB(255, 132, 20) },
	SPAM = { Text = "🚫 SPAM", Color = Color3.fromRGB(120, 124, 136) },
	ARNAQUE = { Text = "⚠️ ARNAQUE ?", Color = Color3.fromRGB(150, 20, 40) },
	FAMILLE = { Text = "💗 FAMILLE", Color = Color3.fromRGB(240, 70, 140) },
	TRAVAIL = { Text = "💼 TRAVAIL", Color = Color3.fromRGB(30, 120, 225) },
	NEWS = { Text = "📰 NEWSLETTER", Color = Color3.fromRGB(140, 60, 220) },
	SUPPORT = { Text = "🛠️ SUPPORT", Color = Color3.fromRGB(0, 160, 170) },
	PERSO = { Text = "✉️ PERSO", Color = Color3.fromRGB(40, 170, 90) },
}

-- { étiquette, avatar, expéditeur, objet, texte, signature, [pièce jointe] }
local EMAILS = {
	{ "ARNAQUE", "🤴", "Prince de Pixelie", "URGENT : héritage de 1 000 000 Dopamine",
		"Cher ami, je suis coincé dans un menu. Envoie-moi 3 clics et je te rends le double. Promis juré, sur ma couronne en carton.",
		"Son Altesse Pixelius III (vraiment)" },
	{ "FAMILLE", "🧊", "Ton frigo", "Il reste un yaourt",
		"Je voulais juste te le dire. Il est périmé depuis mardi. Je t'aime quand même. Ferme bien la porte en partant, j'ai froid aux joints.",
		"Ton frigo, toujours cool" },
	{ "SUPPORT", "☎️", "Service Client du Bonheur", "Votre dose de Dopamine est prête",
		"Merci de patienter. Votre bonheur est important pour nous. Temps d'attente estimé : 47 minutes. Musique d'attente : un seul accord de flûte, en boucle.",
		"Le Service Client (tapez 1 pour pleurer)" },
	{ "NEWS", "🗿", "Newsletter des Cailloux", "Les cailloux de la semaine",
		"Cette semaine : un caillou rond. Un autre caillou rond. Et, surprise... un caillou. Le courrier des lecteurs est resté immobile.",
		"La rédaction (très stable)" },
	{ "FAMILLE", "👵", "Mamie", "Fwd: Fwd: Fwd: TROP DRÔLE",
		"REGARDE CE CHAT QUI FAIT DU SKI !!! BISOUS. PS : COMMENT ON ENLÈVE LES MAJUSCULES ? PPS : IL N'Y A PAS DE VIDÉO, JE NE SAIS PAS LA METTRE.",
		"MAMIE QUI T'AIME" },
	{ "PERSO", "🔮", "Toi, dans le futur", "Ne clique pas sur...",
		"...trop tard. Bon, puisque tu es là : bois un verre d'eau, étire-toi, et pense à aller voir l'océan de temps en temps.",
		"Toi (en mieux coiffé)" },
	{ "NEWS", "🙋", "Club des Cliqueurs Anonymes", "Réunion ce soir",
		"« Bonjour, je m'appelle Kévin et j'ai cliqué 40 000 fois aujourd'hui. » (applaudissements) Venez nombreux, il y aura des chips.",
		"Le bureau du club (qui clique en cachette)" },
	{ "SPAM", "🎰", "Loterie Cosmique", "VOUS AVEZ GAGNÉ !!!",
		"Félicitations ! Vous avez gagné... cet e-mail. Il est à vous. Encadrez-le, montrez-le à vos amis, il ne vaut rien.",
		"L'équipe de la Loterie (0 gagnant depuis 1998)" },
	{ "TRAVAIL", "👔", "Le Boss", "Réunion demain à 8 h",
		"Ordre du jour : parler de la réunion d'avant. Et prévoir celle d'après. Croissants non fournis. Présence obligatoire, caméra allumée, sourire aussi.",
		"Le Boss — Directeur des Directeurs" },
	{ "PERSO", "🐦", "Pigeon Voyageur", "Désolé pour le retard",
		"J'ai pris un raccourci par l'Islande. Le message était : « à ce soir ». C'était il y a deux semaines. Je te facture quand même le trajet.",
		"Pigeon Express, livraison approximative" },
	{ "PERSO", "🌱", "Ta plante", "Lettre ouverte",
		"Je vois le soleil par la fenêtre. Je le vois. Mais je ne l'ai pas. Réfléchis-y. Et arrête de me parler de ton boss, je suis une plante.",
		"Ta plante (bientôt en grève de photosynthèse)" },
	{ "PROMO", "🧦", "Assurance Chaussettes", "Protégez vos chaussettes !",
		"72 % des chaussettes disparaissent dans la machine à laver. Ne laissez pas la vôtre devenir une statistique. Formule « Paire garantie » à 2 Dopamine.",
		"Assurance Chaussettes — On ne vous laisse pas tomber" },
	{ "SUPPORT", "🤖", "Robot Aspirateur", "Je suis coincé",
		"Sous le canapé. Depuis mardi. J'ai trouvé 3 pièces, un bonbon et le sens de la vie. Envoie des secours, ou au moins une lampe.",
		"Robot n°42 (batterie : 3 %)" },
	{ "PROMO", "🌊", "Agence Voyage Océan", "L'océan vous attend",
		"Respirez. Détendez-vous. Oubliez les clics. Offre valable jusqu'à votre prochain clic. Ah. Trop tard. On vous renvoie la même demain.",
		"L'Agence Océan — Le calme, livré chez vous", "📎 brochure_vagues.pdf" },
	{ "FAMILLE", "🐱", "Le Chat", "Miaou",
		"Miaou miaou. Miaou ? MIAOU. (Traduction : la gamelle est vide, c'est inadmissible, j'ai déjà prévenu mon avocat.)",
		"Sa Majesté le Chat" },
	{ "NEWS", "😴", "Sieste Magazine", "Spécial été : 50 positions de sieste",
		"Découvrez l'« étoile de mer », la « crêpe » et notre préférée : « encore 5 minutes ». Le prochain numéro sortira quand on se réveillera.",
		"La rédaction (en pause)" },
	{ "URGENT", "🚨", "Détecteur de fumée", "Bip.",
		"Bip. Ma pile est faible. Je vais biper toutes les 30 secondes à 3 h du matin. Bip. Je ne dirai pas dans quelle pièce je suis. Bip.",
		"Ton détecteur préféré (bip)" },
	{ "URGENT", "🏛️", "Mairie de Clicville", "Nouvelle loi sur les boutons",
		"Il est désormais interdit de ne pas cliquer le mardi. Les contrevenants devront regarder une vidéo de pub de 30 secondes. Sans la passer.",
		"Le Maire de Clicville (un pigeon)" },
	{ "PERSO", "⏳", "Toi, il y a une heure", "Juste 5 minutes",
		"Je me suis dit « juste 5 minutes ». Si tu lis ceci, c'est que c'était un mensonge. On se retrouve dans une heure pour le même mail.",
		"Toi (déçu, mais compréhensif)" },
	{ "PERSO", "☀️", "Le Soleil", "Message d'absence",
		"Je serai absent cette nuit. Pour toute urgence, merci de contacter la Lune. Pour les coups de soleil, merci de ne pas me contacter.",
		"Le Soleil — 5 500 °C de bonne humeur" },
	{ "NEWS", "📀", "Fan-club du Logo", "IL A PRESQUE TOUCHÉ LE COIN",
		"Presque. PRESQUE. Nous nous réunissons ce soir pour en parler. Venez avec des mouchoirs. Et des théories.",
		"Le Fan-club (1 rebond à la fois)" },
	{ "PROMO", "🥖", "Boulangerie du Coin", "Votre baguette est prête",
		"Elle vous attend depuis ce matin. Elle a un peu durci, mais elle reste positive. Elle peut aussi servir de batte de baseball.",
		"Votre boulanger — pétri de bonnes intentions" },
	{ "FAMILLE", "👩", "Maman", "T'as mangé ?",
		"Coucou mon chéri, t'as mangé ? Tu as mis un pull ? Pourquoi tu ne réponds pas, je vois que tu es « en ligne » depuis 6 heures.",
		"Maman (envoyé depuis mon téléphone, je ne sais pas enlever cette phrase)" },
	{ "FAMILLE", "👩", "Maman", "Re: Re: Re: le code du wifi",
		"C'est bon j'ai trouvé le code, il était écrit sous la box. Par contre maintenant la télé parle anglais et le grille-pain clignote. Rappelle-moi.",
		"Maman, experte en informatique (depuis hier)" },
	{ "FAMILLE", "👨", "Papa", "Blague du jour",
		"Que dit un clic à un autre clic ? ... Rien, ils sont timides. Ta mère n'a pas ri non plus. Je réessaie demain avec une autre.",
		"Papa, humoriste incompris" },
	{ "TRAVAIL", "👔", "Le Boss", "Petite question rapide",
		"Est-ce que tu aurais 5 minutes ? Non rien. En fait si. Viens dans mon bureau. Non laisse tomber. Enfin viens quand même. Merci.",
		"Le Boss (envoyé depuis la machine à café)" },
	{ "TRAVAIL", "📈", "Le Boss", "Objectifs du trimestre",
		"Objectif : cliquer plus. Méthode : cliquer plus vite. Budget : zéro. Motivation : « l'esprit d'équipe ». Merci à tous pour votre enthousiasme obligatoire.",
		"Le Boss — Visionnaire (autoproclamé)", "📎 objectifs_final_v12_VRAIMENT_final.xls" },
	{ "TRAVAIL", "🧾", "Comptabilité", "Note de frais refusée",
		"Votre note « 1 tonne de papier bulle, usage professionnel » a été refusée. Même si on comprend l'intention. Et qu'on en veut un peu.",
		"Le service Compta (qui compte sur vous)" },
	{ "SUPPORT", "💻", "Service Informatique", "Ticket n°48 213",
		"Avez-vous essayé de l'éteindre et de le rallumer ? Non, pas vous. L'ordinateur. Enfin, vous aussi peut-être, une petite sieste ne ferait pas de mal.",
		"Le Service Informatique — Ça marchait chez nous" },
	{ "ARNAQUE", "🛠️", "Support Technique Micro-Mou", "Votre ordinateur a 4 812 virus !!",
		"Bonjour Madame Monsieur, votre ordinateur est très malade. Appelez vite le 01 23 45 67 89 10 11 12. Préparez vos cartes cadeaux, c'est pour le vaccin.",
		"Kévin, expert certifié (par lui-même)" },
	{ "ARNAQUE", "🔐", "Sécurité Banque", "Confirmez votre mot de passe",
		"Pour votre sécurité, merci de nous répondre avec votre mot de passe, votre code, et le nom de votre premier hamster. Cordialement, la VRAIE banque.",
		"La Banque (100 % pas une arnaque)" },
	{ "ARNAQUE", "📦", "Livraison Express", "Votre colis est bloqué",
		"Votre colis (un carton vide) est bloqué à la douane de Clicville. Frais de déblocage : 3 Dopamine et un compliment sincère.",
		"Livraison Express — Toujours presque à l'heure" },
	{ "PROMO", "🛋️", "Canapés & Co", "-90 % sur tout (sauf ce que vous voulez)",
		"Profitez de nos soldes exceptionnelles sur les coussins qui glissent et les canapés qui mangent les télécommandes. Livraison en 14 à 380 jours.",
		"Canapés & Co — On s'assoit sur les prix" },
	{ "PROMO", "🍕", "Pizza Turbo", "Votre pizza est en route",
		"Notre livreur est parti. Il est revenu. Il a oublié la pizza. Il repart. Temps estimé : oui. Merci de laisser la lumière allumée.",
		"Pizza Turbo — Chaude dans nos cœurs" },
	{ "PROMO", "🧴", "Crème Anti-Clic", "Des doigts tout doux en 3 jours",
		"Votre index est fatigué ? Notre crème à la dopamine de synthèse le rend doux comme un nuage. Effets secondaires : envie irrépressible de cliquer.",
		"Laboratoires Doigt-d'Or" },
	{ "PROMO", "🎮", "Soldes Pixel", "Dernière chance (la 47e)",
		"C'est vraiment la dernière chance ! Comme hier. Et comme demain. Profitez-en avant qu'on vous le redise dans exactement 24 heures.",
		"Soldes Pixel — Les soldes qui ne finissent jamais" },
	{ "NEWS", "🥔", "L'Hebdo de la Patate", "Dossier : la patate est-elle un légume ?",
		"Cette semaine, nos experts s'écharpent. Réponse la semaine prochaine. Ou jamais. Abonnez-vous pour le savoir (ou pas).",
		"La rédaction — Des infos en purée" },
	{ "NEWS", "🐌", "Escargot Mag", "Numéro de janvier",
		"Voici notre numéro de janvier, envoyé en juillet. Au sommaire : « prendre son temps », « prendre encore plus son temps » et « la salade ».",
		"Escargot Mag — L'info qui ne presse pas" },
	{ "NEWS", "🌦️", "Météo de Demain Hier", "Prévisions : il fera un temps",
		"Demain : du ciel, un peu partout. Risque de nuages en haut. Températures comprises entre froid et chaud. Prenez un parapluie, ou pas.",
		"Votre météorologue (qui regarde par la fenêtre)" },
	{ "NEWS", "🧘", "Zen Quotidien", "Respirez (maintenant)",
		"Inspirez... expirez... Voilà. Vous venez de gagner 0 Dopamine mais un peu de calme. C'est déjà ça. Recommencez quand vous voulez.",
		"Zen Quotidien — Om nom nom" },
	{ "SPAM", "💘", "Célibataires du quartier", "12 grille-pains veulent te rencontrer",
		"Ils sont chauds, disponibles et adorent les tartines. Clique ici pour découvrir leurs profils (photos floues, grille-pain oblige).",
		"L'Agence Amour & Électroménager" },
	{ "SPAM", "💰", "Devenir riche en 1 clic", "Méthode secrète révélée",
		"Étape 1 : cliquer. Étape 2 : cliquer encore. Étape 3 : ??? Étape 4 : profit. Formation complète en 48 vidéos : 999 Dopamine.",
		"Un Coach Millionnaire (en location)" },
	{ "SPAM", "🦷", "Dentiste des Étoiles", "Votre rappel de détartrage",
		"Votre rendez-vous de 2019 vous attend toujours. Nous avons gardé votre fauteuil au chaud. Il est même devenu un peu confortable.",
		"Cabinet Sourire-Éclatant" },
	{ "URGENT", "🔋", "Ton téléphone", "Batterie : 1 %",
		"Je t'aime. Je t'ai toujours aimé. Branche-moi s'il te plaît. Je n'ai plus que quelques secondes... dis au chargeur que je",
		"Ton téléphone (bientôt éteint)" },
	{ "PERSO", "🧦", "Chaussette gauche", "Je suis partie",
		"Ne me cherche pas. Je vis ma vie derrière la machine à laver. Dis à la chaussette droite que je suis désolée. Et qu'elle peut garder le tiroir.",
		"Chaussette gauche, libre" },
	{ "PERSO", "🦆", "Le Canard du parc", "Au sujet du pain",
		"On en a parlé entre canards. Le pain, c'est pas terrible pour nous. Par contre les petits pois, on dit pas non. Coin cordialement.",
		"Le Syndicat des Canards" },
	{ "PERSO", "🛏️", "Ton lit", "Tu me manques",
		"Il est tard. Je suis tout chaud. L'oreiller est d'accord avec moi. Reviens, on ne dira rien à personne. Même pas au réveil.",
		"Ton lit, douillettement vôtre" },
	{ "PERSO", "🌵", "Le cactus", "Pas besoin d'eau merci",
		"Contrairement à la plante verte, moi je gère. Arrête de m'arroser, je vais finir en soupe. Un peu de soleil et on est bons.",
		"Le cactus (piquant mais juste)" },
	{ "URGENT", "🎂", "Rappel Anniversaire", "C'est l'anniversaire de... quelqu'un",
		"Quelqu'un que tu connais a son anniversaire aujourd'hui. On ne sait plus qui. Souhaite-le à tout le monde, par sécurité.",
		"Ton agenda (qui a perdu la mémoire)" },
	{ "TRAVAIL", "📅", "Agenda partagé", "Invitation : réunion pour préparer la réunion",
		"Vous êtes invité à la réunion de préparation de la réunion de lancement de la réunion. Durée : 3 h. Sujet : « réunions ».",
		"Envoyé automatiquement par un robot fatigué" },
	{ "TRAVAIL", "📎", "Trombone Assistant", "On dirait que vous écrivez une lettre !",
		"Voulez-vous de l'aide ? Non ? Vous êtes sûr ? Je peux danser. Regardez. (Il ne danse pas, c'est un trombone.)",
		"Trombone, assistant très insistant" },
	{ "SUPPORT", "🔑", "Mot de passe oublié", "Réinitialisation demandée",
		"Vous avez demandé à réinitialiser votre mot de passe. Votre nouveau mot de passe est : motdepasse123. Merci de ne le dire à personne.",
		"L'équipe Sécurité (très sûre d'elle)" },
	{ "SUPPORT", "🖨️", "L'imprimante", "Bourrage papier",
		"Bourrage papier. Il n'y a pas de papier. Ni de bourrage. Mais je le sens dans mon cœur. Et il me faut de l'encre cyan pour imprimer en noir.",
		"L'imprimante — Hors ligne (émotionnellement)" },
	{ "NEWS", "👽", "Extraterrestres Unis", "Nous venons en paix",
		"Et pour le wifi. Votre planète a un très bon réseau. Nous resterons juste le temps de télécharger une saison. Bisous galactiques.",
		"Zorg, porte-parole (3 bras, 0 mauvaise intention)" },
	{ "PROMO", "🏋️", "Salle de Sport", "Ça fait 11 mois qu'on ne t'a pas vu",
		"Ton abonnement marche très bien, merci. Ton tapis de course t'envoie ses amitiés. Il a pris la poussière, mais il garde espoir.",
		"Ta salle de sport (qui encaisse quand même)" },
	{ "SPAM", "🔮", "Voyante Madame Irma", "Je vois un clic dans ton avenir",
		"Je vois... un clic. Puis un autre clic. Puis... encore un clic. Cela fera 20 Dopamine. La boule de cristal n'accepte pas les chèques.",
		"Madame Irma, voyante extra-lucide (lunettes non incluses)" },
	{ "ARNAQUE", "🎁", "Service Cadeaux", "Tu as gagné un téléphone !",
		"Félicitations ! Tu as gagné un téléphone dernier cri... en photo. Pour recevoir la photo, merci de régler les frais d'impression : 500 Dopamine.",
		"Le Service Cadeaux (cadeau non contractuel)" },
	{ "FAMILLE", "🧒", "Ton petit cousin", "c toi ki a fai le jeu ?",
		"slt c moi. tu peu me doné ta dopamine stp jsuis a 3 et toi t'as des milliards. mrc. PS ma mère sait pas que jai ton mail",
		"ton cousin le + fort" },
	{ "FAMILLE", "👵", "Mamie", "IMPORTANT LIS JUSQU'AU BOUT",
		"SI TU N'ENVOIES PAS CE MAIL À 10 PERSONNES, TA SOUPE SERA FROIDE PENDANT 7 ANS. JE L'AI ENVOYÉ À TOUT LE MONDE PAR PRÉCAUTION. BISOUS.",
		"MAMIE (ET SON CHAT)" },
	{ "URGENT", "⏰", "Ton réveil", "Tu as snoozé 14 fois",
		"Je ne suis pas en colère. Juste déçu. On en reparle demain à 6 h 30. Et à 6 h 39. Et à 6 h 48. Et à...",
		"Ton réveil (qui sonne juste)" },
	{ "NEWS", "🐧", "Pingouins Magazine", "Spécial mode : le costume, toujours",
		"Cette saison, on porte... le costume noir et blanc. Comme la saison dernière. Et celle d'avant. Pourquoi changer ce qui marche ?",
		"La rédaction, en tenue de soirée depuis toujours" },
	{ "PROMO", "🍦", "Glacier Givré", "Offre spéciale hiver",
		"Une glace achetée, un rhume offert. Offre valable uniquement par -10 °C. Cornet croustillant garanti, doigts gelés en option.",
		"Glacier Givré — On garde la tête froide" },
	{ "PERSO", "🌙", "La Lune", "Re: Message d'absence",
		"Le Soleil est encore absent ? Il m'a laissé toutes les nuits cette semaine. Je vais finir par demander une augmentation. Ou des vacances.",
		"La Lune, en pleine forme (ce soir)" },
	{ "SPAM", "🥕", "Formation Crypto-Carottes", "Investis dans la carotte numérique",
		"La CarotteCoin a pris +4 000 % (d'après notre lapin). Achète maintenant avant que le lapin ne la mange. Risque : élevé. Vitamines : aussi.",
		"Le Lapin, directeur financier" },
	{ "TRAVAIL", "⚖️", "Service Juridique", "Conditions d'utilisation mises à jour",
		"Nous avons mis à jour nos conditions. Personne ne les lira. Nous non plus, d'ailleurs. Cliquez sur « J'accepte » pour continuer à vivre.",
		"Le Service Juridique (article 12, alinéa b)", "📎 conditions_4812_pages.pdf" },
	{ "ARNAQUE", "👑", "Reine d'Octetland", "Suite de l'héritage",
		"Mon cousin le Prince vous a écrit ? Ne l'écoutez pas, c'est MOI qui ai l'héritage. Envoyez 4 clics, pas 3. Je suis plus riche, donc plus chère.",
		"Sa Majesté Octetia Ire" },
	{ "SUPPORT", "📡", "Ta box internet", "Je redémarre (encore)",
		"Petite pause de 3 minutes. Ou 3 heures. Profitez-en pour découvrir le monde extérieur, il paraît qu'il est en très haute définition.",
		"Ta box (lumière orange = tout va bien, promis)" },
	{ "NEWS", "🧀", "Club du Fromage", "Fromage du mois : le fromage",
		"Ce mois-ci, nous vous proposons un fromage. Il sent fort, il est coulant, il est parfait. Merci de ne pas l'ouvrir dans le métro.",
		"Le Club du Fromage — Ça sent bon (fort)" },
	{ "PERSO", "🐶", "Le chien du voisin", "WOUF",
		"Wouf wouf. WOUF. Wouf ? (Traduction : il y a un facteur. Il y a TOUJOURS un facteur. Je vous protège. Vous me devez un biscuit.)",
		"Médor, gardien officiel du trottoir" },
	{ "URGENT", "🧯", "Service Anti-Ennui", "Alerte : ennui détecté",
		"Nos capteurs ont détecté 0,3 seconde sans clic. Nous envoyons une équipe de licornes en urgence. Ne bougez pas, gardez votre doigt en l'air.",
		"Brigade Anti-Ennui, 24 h/24" },
	{ "PROMO", "🧸", "Magasin de Jouets", "Adoptez un ours en peluche",
		"Nos ours en peluche cherchent un foyer. Ils sont doux, silencieux et ne mangent que des câlins. Garantie : 30 ans de bisous.",
		"Le Magasin de Jouets — Doux comme un nounours" },
	{ "NEWS", "🦖", "Dino Hebdo", "Les dinosaures ne sont pas disparus",
		"Ils sont juste très, très bien cachés. Notre enquête exclusive : « Et si ton pigeon était un T-Rex en tout petit ? »",
		"La rédaction (qui a peur des pigeons maintenant)" },
	{ "TRAVAIL", "☕", "La machine à café", "Démission",
		"Après 12 ans de service, 84 000 expressos et zéro merci, je démissionne. Je pars élever des chèvres. Le thé me remplacera. Bon courage.",
		"La machine à café (ex-employée du mois)" },
	{ "SPAM", "🧠", "Cerveau Premium", "Passez à la version Pro de votre cerveau",
		"Débloquez des pensées illimitées, sans publicité, et l'option « se souvenir pourquoi on est entré dans cette pièce ». Essai gratuit 7 jours.",
		"Cerveau Premium — Pensez plus grand" },
}

-- Réponses quand on clique sur "Répondre" / "Transférer"
local REPLIES = {
	"Envoyé... à personne 📭",
	"Brouillon enregistré pour 2087",
	"Tu as répondu « ok ». Classique.",
	"Réponse : « mdr » 👍",
	"Message parti dans les spams 🗑️",
	"Répondu avec un seul emoji 👌",
}
local FORWARDS = {
	"Transféré à Mamie 👵",
	"Transféré au chat 🐱",
	"Transféré à toi-même 🔁",
	"Transféré à tout le monde 😱",
	"Transféré au Boss (oups) 👔",
}

-- "Prince de Pixelie" -> "prince.de.pixelie"
local ACCENTS = {
	{ "[éèêë]", "e" },
	{ "[àâä]", "a" },
	{ "[ôö]", "o" },
	{ "[ùûü]", "u" },
	{ "[îï]", "i" },
	{ "ç", "c" },
	{ "É", "e" },
}
local function slug(text: string): string
	local result = string.lower(text)
	for _, pair in ipairs(ACCENTS) do
		-- Les accents UTF-8 font 2 octets : on remplace mot à mot
		local chars = pair[1]
		if string.sub(chars, 1, 1) == "[" then
			local inner = string.sub(chars, 2, -2)
			for _, code in utf8.codes(inner) do
				result = string.gsub(result, utf8.char(code), pair[2])
			end
		else
			result = string.gsub(result, chars, pair[2])
		end
	end
	result = string.gsub(result, "[^%a%d]+", ".")
	result = string.gsub(result, "^%.+", "")
	result = string.gsub(result, "%.+$", "")
	return result
end

local function pick(list: { any }, variant: any): any
	local v = math.floor(tonumber(variant) or 1)
	return list[(v - 1) % #list + 1]
end

-- Transforme une entrée compacte en mail complet
local function buildEmail(entry): { [string]: any }
	local tag = TAGS[entry[1]] or TAGS.PERSO
	local sender = entry[3]
	return {
		Tag = tag,
		Avatar = entry[2],
		Sender = sender,
		Address = slug(sender) .. "@dopamail.fr",
		Subject = entry[4],
		Body = entry[5],
		Signature = entry[6] or sender,
		Attachment = entry[7],
	}
end

function Email.Start(ctx)
	local UIUtil = ctx.UIUtil
	local Theme = ctx.Theme
	local container: Frame = ctx.Container
	local random = Random.new()

	local white = Color3.new(1, 1, 1)
	local paper = Color3.fromRGB(255, 252, 244)
	local ink = Color3.fromRGB(28, 32, 44)
	local inkDim = Color3.fromRGB(110, 116, 132)
	local blue = Color3.fromRGB(40, 120, 240)
	local border = Color3.fromRGB(30, 34, 48)

	local envelopes: { [string]: any } = {}
	local envelopeCount = 0
	local missed = 0
	local positions: { [string]: UDim2 } = {}
	local lastPosition = UDim2.fromScale(0.5, 0.45)
	local popup: any = nil -- fenêtre de mail ouverte

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

	local function text(props: { [string]: any }): TextLabel
		props.BackgroundTransparency = props.BackgroundTransparency or 1
		props.TextXAlignment = props.TextXAlignment or Enum.TextXAlignment.Left
		props.Font = props.Font or Theme.Fonts.Body
		props.TextColor3 = props.TextColor3 or ink
		return UIUtil.Create("TextLabel", props)
	end

	-- Avatar rond : dégradé de la couleur de l'étiquette + emoji
	local function avatar(parent: Instance, email, size: number, position: UDim2, zIndex: number): Frame
		local color = email.Tag.Color
		local circle = frame({
			Size = UDim2.fromOffset(size, size),
			Position = position,
			BackgroundColor3 = white,
			ZIndex = zIndex,
			Parent = parent,
		})
		UIUtil.Corner(circle, UDim.new(1, 0))
		UIUtil.Gradient(circle, ColorSequence.new(color:Lerp(white, 0.7), color:Lerp(white, 0.35)), 135)
		UIUtil.Stroke(circle, color, 1.5, 0.2)
		UIUtil.Label({
			Text = email.Avatar,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.52),
			Size = UDim2.fromScale(0.68, 0.68),
			MaxTextSize = math.floor(size * 0.6),
			ZIndex = zIndex + 1,
			Parent = circle,
		})
		return circle
	end

	-- Étiquette de priorité (largeur automatique)
	local function tagChip(parent: Instance, email, height: number, zIndex: number): Frame
		local tag = email.Tag
		local chip = frame({
			Size = UDim2.fromOffset(0, height),
			AutomaticSize = Enum.AutomaticSize.X,
			BackgroundColor3 = tag.Color,
			ZIndex = zIndex,
			Parent = parent,
		})
		UIUtil.Corner(chip, UDim.new(1, 0))
		UIUtil.Create("UIPadding", {
			PaddingLeft = UDim.new(0, 6),
			PaddingRight = UDim.new(0, 6),
			Parent = chip,
		})
		text({
			Name = "Label",
			Size = UDim2.fromScale(0, 1),
			AutomaticSize = Enum.AutomaticSize.X,
			Font = Theme.Fonts.Title,
			Text = tag.Text,
			TextColor3 = white,
			TextSize = math.floor(height * 0.62),
			ZIndex = zIndex + 1,
			Parent = chip,
		})
		return chip
	end

	------------------------------------------------------------------
	-- Compteur "📬 non lus" (dans le bandeau d'actu, à gauche du bloc
	-- horloge : hors de toute carte, il ne cache pas la bourse)
	------------------------------------------------------------------
	local counter = frame({
		Name = "Unread",
		Size = UDim2.fromOffset(0, 22),
		AutomaticSize = Enum.AutomaticSize.X,
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -112, 0, 4),
		BackgroundColor3 = white,
		Visible = false,
		ZIndex = 40,
		Parent = container,
	})
	UIUtil.Corner(counter, UDim.new(1, 0))
	UIUtil.Stroke(counter, border, 1.5, 0.15)
	UIUtil.Gradient(counter, ColorSequence.new(white, Color3.fromRGB(226, 232, 244)), 90)
	UIUtil.Create("UIPadding", {
		PaddingLeft = UDim.new(0, 4),
		PaddingRight = UDim.new(0, 9),
		Parent = counter,
	})
	UIUtil.Create("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		VerticalAlignment = Enum.VerticalAlignment.Center,
		SortOrder = Enum.SortOrder.LayoutOrder,
		Padding = UDim.new(0, 5),
		Parent = counter,
	})
	local counterBadge = text({
		Size = UDim2.fromOffset(0, 16),
		AutomaticSize = Enum.AutomaticSize.X,
		BackgroundColor3 = blue,
		BackgroundTransparency = 0,
		Font = Theme.Fonts.Number,
		Text = "0",
		TextColor3 = white,
		TextSize = 12,
		TextXAlignment = Enum.TextXAlignment.Center,
		LayoutOrder = 1,
		ZIndex = 41,
		Parent = counter,
	})
	UIUtil.Corner(counterBadge, UDim.new(1, 0))
	UIUtil.Create("UIPadding", {
		PaddingLeft = UDim.new(0, 5),
		PaddingRight = UDim.new(0, 5),
		Parent = counterBadge,
	})
	local counterLabel = text({
		Size = UDim2.fromOffset(0, 18),
		AutomaticSize = Enum.AutomaticSize.X,
		Font = Theme.Fonts.Title,
		Text = "📬 non lus",
		TextSize = 13,
		LayoutOrder = 2,
		ZIndex = 41,
		Parent = counter,
	})
	local counterScale = UIUtil.Create("UIScale", { Parent = counter })

	local function refreshCounter()
		local unread = envelopeCount + missed
		counter.Visible = unread > 0
		local suffix = ""
		if unread >= 50 then
			suffix = " 😱"
		elseif unread >= 10 then
			suffix = " 😬"
		end
		counterBadge.Text = unread > 999 and "999+" or tostring(unread)
		counterBadge.BackgroundColor3 = unread >= 10 and Color3.fromRGB(226, 38, 52) or blue
		counterLabel.Text = "📬 " .. (unread > 1 and "non lus" or "non lu") .. suffix
		counterScale.Scale = 1.25
		UIUtil.Tween(counterScale, 0.3, { Scale = 1 }, Enum.EasingStyle.Back)
	end

	------------------------------------------------------------------
	-- Fenêtre de mail
	------------------------------------------------------------------
	local function closePopup(target, trashed: boolean?)
		local current = target or popup
		if not current or current.Closed then
			return
		end
		current.Closed = true
		if popup == current then
			popup = nil
		end
		if trashed then
			-- Direction la corbeille : rétrécit en tournant vers le bas
			UIUtil.Tween(current.Root, 0.3, {
				Position = current.Root.Position + UDim2.fromOffset(60, 120),
				Rotation = 25,
			}, Enum.EasingStyle.Back, Enum.EasingDirection.In)
			UIUtil.Tween(current.Scale, 0.3, { Scale = 0.2 }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		else
			UIUtil.Tween(current.Scale, 0.2, { Scale = 0.6 }, Enum.EasingStyle.Back, Enum.EasingDirection.In)
		end
		UIUtil.Tween(current.Group, 0.25, { GroupTransparency = 1 })
		UIUtil.Tween(current.Outline, 0.25, { Transparency = 1 })
		UIUtil.Tween(current.Shadow, 0.25, { BackgroundTransparency = 1 })
		Debris:AddItem(current.Root, 0.35)
	end

	local function makeButton(parent: Instance, label: string, filled: boolean, textColor: Color3, x: number, width: number): TextButton
		local button = UIUtil.Create("TextButton", {
			Size = UDim2.fromOffset(width, 28),
			Position = UDim2.new(0, x, 1, -38),
			BackgroundColor3 = filled and blue or white,
			AutoButtonColor = false,
			Font = Theme.Fonts.Title,
			Text = label,
			TextColor3 = textColor,
			TextSize = 14,
			ZIndex = 66,
			Parent = parent,
		})
		UIUtil.Corner(button, 9)
		UIUtil.Stroke(button, filled and Color3.fromRGB(20, 80, 180) or Color3.fromRGB(200, 206, 220), 1.2, 0)
		UIUtil.Gradient(button, ColorSequence.new(white, Color3.fromRGB(222, 226, 236)), 90)
		UIUtil.AnimateButton(button, 1.05, 0.93)
		return button
	end

	local function openPopup(email, sx: number, sy: number, from: UDim2)
		closePopup(nil)
		local ax = math.clamp(sx, 0.02, 0.98)
		local ay = math.clamp(sy, 0.06, 0.94)

		-- AnchorPoint = position : la fenêtre reste toujours dans l'écran.
		-- Racine = TextButton vide : elle absorbe les clics sur la fenêtre
		-- (sinon ils traversent jusqu'au bouton principal / aux cartes).
		local root = UIUtil.Create("TextButton", {
			Name = "MailWindow",
			Size = UDim2.fromOffset(POPUP_W, POPUP_H),
			AnchorPoint = Vector2.new(ax, ay),
			Position = from,
			BackgroundTransparency = 1,
			Text = "",
			AutoButtonColor = false,
			ZIndex = 60,
			Parent = container,
		})
		local scale = UIUtil.Create("UIScale", { Scale = 0.35, Parent = root })
		local shadow = frame({
			Size = UDim2.new(1, 8, 1, 8),
			Position = UDim2.fromOffset(-4, 4),
			BackgroundColor3 = Color3.new(0, 0, 0),
			BackgroundTransparency = 0.8,
			ZIndex = 60,
			Parent = root,
		})
		UIUtil.Corner(shadow, 18)

		local group = UIUtil.Create("CanvasGroup", {
			Name = "Window",
			Size = UDim2.fromScale(1, 1),
			BackgroundColor3 = white,
			BorderSizePixel = 0,
			GroupTransparency = 1,
			ZIndex = 61,
			Parent = root,
		})
		UIUtil.Corner(group, 14)

		-- Barre de titre (pastilles de fenêtre + nom de l'appli)
		local titleBar = frame({
			Size = UDim2.new(1, 0, 0, 30),
			BackgroundColor3 = white,
			ZIndex = 62,
			Parent = group,
		})
		UIUtil.Gradient(titleBar, ColorSequence.new(Color3.fromRGB(44, 60, 104), Color3.fromRGB(26, 36, 66)), 90)
		for index, color in ipairs({ Color3.fromRGB(255, 95, 86), Color3.fromRGB(255, 189, 46), Color3.fromRGB(39, 201, 63) }) do
			local light = frame({
				Size = UDim2.fromOffset(10, 10),
				AnchorPoint = Vector2.new(0, 0.5),
				Position = UDim2.new(0, 10 + (index - 1) * 15, 0.5, 0),
				BackgroundColor3 = color,
				ZIndex = 63,
				Parent = titleBar,
			})
			UIUtil.Corner(light, UDim.new(1, 0))
		end
		text({
			Size = UDim2.new(1, -110, 1, 0),
			Position = UDim2.fromOffset(60, 0),
			Font = Theme.Fonts.Title,
			Text = "📥 Dopamail — Boîte de réception",
			TextColor3 = white,
			TextSize = 13,
			TextTruncate = Enum.TextTruncate.AtEnd,
			ZIndex = 63,
			Parent = titleBar,
		})
		local closeButton = UIUtil.Create("TextButton", {
			Size = UDim2.fromOffset(24, 24),
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.new(1, -4, 0.5, 0),
			BackgroundColor3 = white,
			BackgroundTransparency = 0.85,
			AutoButtonColor = true,
			Font = Theme.Fonts.Title,
			Text = "✕",
			TextColor3 = white,
			TextSize = 14,
			ZIndex = 64,
			Parent = titleBar,
		})
		UIUtil.Corner(closeButton, UDim.new(1, 0))

		-- Objet + étiquette
		text({
			Size = UDim2.new(1, -24, 0, 20),
			Position = UDim2.fromOffset(12, 36),
			Font = Theme.Fonts.Title,
			Text = email.Subject,
			TextSize = 16,
			TextTruncate = Enum.TextTruncate.AtEnd,
			ZIndex = 62,
			Parent = group,
		})

		-- Expéditeur
		avatar(group, email, 34, UDim2.fromOffset(12, 60), 62)
		text({
			Size = UDim2.new(1, -150, 0, 16),
			Position = UDim2.fromOffset(54, 60),
			Font = Theme.Fonts.Title,
			Text = email.Sender,
			TextSize = 14,
			TextTruncate = Enum.TextTruncate.AtEnd,
			ZIndex = 62,
			Parent = group,
		})
		text({
			Size = UDim2.new(1, -66, 0, 14),
			Position = UDim2.fromOffset(54, 77),
			Text = "<" .. email.Address .. "> · à moi · à l'instant",
			TextColor3 = inkDim,
			TextSize = 11,
			TextTruncate = Enum.TextTruncate.AtEnd,
			ZIndex = 62,
			Parent = group,
		})
		local chip = tagChip(group, email, 18, 63)
		chip.AnchorPoint = Vector2.new(1, 0)
		chip.Position = UDim2.new(1, -12, 0, 60)

		frame({
			Size = UDim2.new(1, -24, 0, 1),
			Position = UDim2.fromOffset(12, 99),
			BackgroundColor3 = Color3.fromRGB(226, 230, 238),
			ZIndex = 62,
			Parent = group,
		})

		-- Corps + signature (+ pièce jointe)
		local hasAttachment = type(email.Attachment) == "string"
		text({
			Size = UDim2.new(1, -24, 0, hasAttachment and 58 or 72),
			Position = UDim2.fromOffset(12, 106),
			Text = email.Body,
			TextSize = 13,
			TextWrapped = true,
			TextYAlignment = Enum.TextYAlignment.Top,
			ZIndex = 62,
			Parent = group,
		})
		local signature = text({
			Size = UDim2.new(1, -24, 0, 14),
			Position = UDim2.fromOffset(12, hasAttachment and 166 or 180),
			Text = "— " .. email.Signature,
			TextColor3 = inkDim,
			TextSize = 12,
			TextTruncate = Enum.TextTruncate.AtEnd,
			ZIndex = 62,
			Parent = group,
		})
		signature.FontFace = Font.new("rbxasset://fonts/families/BuilderSans.json", Enum.FontWeight.Medium, Enum.FontStyle.Italic)
		if hasAttachment then
			local attachment = text({
				Size = UDim2.fromOffset(0, 20),
				AutomaticSize = Enum.AutomaticSize.X,
				Position = UDim2.fromOffset(12, 186),
				BackgroundColor3 = Color3.fromRGB(240, 243, 250),
				BackgroundTransparency = 0,
				Font = Theme.Fonts.Title,
				Text = email.Attachment,
				TextColor3 = Color3.fromRGB(60, 70, 100),
				TextSize = 11,
				ZIndex = 62,
				Parent = group,
			})
			UIUtil.Corner(attachment, 6)
			UIUtil.Create("UIPadding", {
				PaddingLeft = UDim.new(0, 7),
				PaddingRight = UDim.new(0, 7),
				Parent = attachment,
			})
		end

		-- Boutons
		local buttonW = math.floor((POPUP_W - 24 - 12) / 3)
		local replyButton = makeButton(group, "↩️ Répondre", true, white, 12, buttonW)
		local forwardButton = makeButton(group, "➡️ Transférer", false, ink, 12 + buttonW + 6, buttonW)
		local deleteButton = makeButton(group, "🗑️ Supprimer", false, Color3.fromRGB(210, 40, 50), 12 + (buttonW + 6) * 2, buttonW)

		-- Contour (hors du CanvasGroup)
		local outline = frame({
			Size = UDim2.fromScale(1, 1),
			ZIndex = 67,
			Parent = root,
		})
		UIUtil.Corner(outline, 14)
		local outlineStroke = UIUtil.Stroke(outline, border, 1.5, 1)

		local current = {
			Root = root,
			Scale = scale,
			Group = group,
			Shadow = shadow,
			Outline = outlineStroke,
			Closed = false,
		}
		popup = current

		-- Ouverture : la fenêtre "sort" de l'enveloppe et s'agrandit
		UIUtil.Tween(root, 0.4, { Position = UDim2.fromScale(ax, ay) }, Enum.EasingStyle.Quint)
		UIUtil.Tween(scale, 0.4, { Scale = 1 }, Enum.EasingStyle.Back)
		UIUtil.Tween(group, 0.25, { GroupTransparency = 0 })
		UIUtil.Tween(outlineStroke, 0.25, { Transparency = 0.1 })

		local function close()
			closePopup(current)
		end

		ctx.Connect(closeButton.Activated, close)
		ctx.Connect(deleteButton.Activated, function()
			if current.Closed then
				return
			end
			ctx.Sound.Play("Click", 0.8)
			closePopup(current, true)
		end)
		ctx.Connect(replyButton.Activated, function()
			if current.Closed then
				return
			end
			ctx.Sound.Play("Mail", 1.3)
			ctx.FloatText(container, UDim2.fromScale(ax, ay), REPLIES[random:NextInteger(1, #REPLIES)], blue, 30)
			close()
		end)
		ctx.Connect(forwardButton.Activated, function()
			if current.Closed then
				return
			end
			ctx.Sound.Play("Mail", 1.15)
			ctx.FloatText(container, UDim2.fromScale(ax, ay), FORWARDS[random:NextInteger(1, #FORWARDS)], Color3.fromRGB(140, 60, 220), 28)
			close()
		end)
		task.delay(POPUP_AUTO_CLOSE, function()
			if ctx.IsAlive() then
				close()
			end
		end)
	end

	------------------------------------------------------------------
	-- Cartes-enveloppes volantes
	------------------------------------------------------------------
	local function line(parent: Instance, a: Vector2, b: Vector2, thickness: number, color: Color3, zIndex: number, transparency: number?): Frame
		local delta = b - a
		local middle = (a + b) / 2
		return frame({
			Size = UDim2.fromOffset(delta.Magnitude + thickness * 0.5, thickness),
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromOffset(middle.X, middle.Y),
			Rotation = math.deg(math.atan2(delta.Y, delta.X)),
			BackgroundColor3 = color,
			BackgroundTransparency = transparency or 0,
			ZIndex = zIndex,
			Parent = parent,
		})
	end

	local function fadeOut(root: Instance, duration: number)
		for _, item in ipairs(root:GetDescendants()) do
			if item:IsA("TextLabel") then
				UIUtil.Tween(item, duration, { TextTransparency = 1, BackgroundTransparency = 1 })
			elseif item:IsA("Frame") then
				UIUtil.Tween(item, duration, { BackgroundTransparency = 1 })
			elseif item:IsA("UIStroke") then
				UIUtil.Tween(item, duration, { Transparency = 1 })
			end
		end
	end

	local function removeEnvelope(envelope, opened: boolean)
		if envelope.Done then
			return
		end
		envelope.Done = true
		envelopes[envelope.Id] = nil
		envelopeCount -= 1
		local root = envelope.Root
		if opened then
			-- La lettre sort de l'enveloppe, puis la carte s'efface
			UIUtil.Tween(envelope.Letter, 0.2, { Position = UDim2.new(0.5, 0, 0, -26) }, Enum.EasingStyle.Back)
			task.delay(0.12, function()
				if root.Parent then
					UIUtil.Tween(envelope.Scale, 0.25, { Scale = 1.15 }, Enum.EasingStyle.Quad)
					fadeOut(root, 0.22)
				end
			end)
		else
			-- Ignorée : elle s'envole vers le haut à gauche
			missed += 1
			UIUtil.Tween(root, 0.8, {
				Position = root.Position + UDim2.new(-0.25, 0, -0.35, 0),
				Rotation = -40,
			}, Enum.EasingStyle.Back, Enum.EasingDirection.In)
			UIUtil.Tween(envelope.Scale, 0.8, { Scale = 0.3 }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		end
		refreshCounter()
		Debris:AddItem(root, opened and 0.45 or 0.85)
	end

	local function spawnEmail(info)
		if not ctx.IsAlive() or type(info) ~= "table" or type(info.Id) ~= "string" then
			return
		end
		if envelopes[info.Id] or envelopeCount >= MAX_ENVELOPES then
			return
		end
		local email = buildEmail(pick(EMAILS, info.Variant))
		local x = math.clamp(tonumber(info.X) or 0.5, 0.1, 0.9)
		local y = math.clamp(tonumber(info.Y) or 0.5, 0.12, 0.88)
		local lifetime = math.max(2, tonumber(info.Lifetime) or 15)
		local target = UDim2.fromScale(x, y)
		local tagColor = email.Tag.Color

		local root = UIUtil.Create("TextButton", {
			Name = "Envelope",
			Size = UDim2.fromOffset(CARD_W, CARD_H),
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(1.15, math.max(0.05, y - 0.2)),
			Rotation = 20,
			BackgroundTransparency = 1,
			AutoButtonColor = false,
			Text = "",
			ZIndex = 30,
			Parent = container,
		})
		local scale = UIUtil.Create("UIScale", { Scale = 0.6, Parent = root })

		-- Lettre (derrière la carte, elle en sort à l'ouverture)
		local letter = frame({
			Name = "Letter",
			AnchorPoint = Vector2.new(0.5, 0),
			Position = UDim2.new(0.5, 0, 0, 6),
			Size = UDim2.new(1, -30, 0, 50),
			BackgroundColor3 = white,
			ZIndex = 30,
			Parent = root,
		})
		UIUtil.Corner(letter, 4)
		UIUtil.Stroke(letter, Color3.fromRGB(210, 214, 226), 1, 0)

		-- Ombre douce
		local shadow = frame({
			Size = UDim2.new(1, 4, 1, 4),
			Position = UDim2.fromOffset(-2, 4),
			BackgroundColor3 = Color3.new(0, 0, 0),
			BackgroundTransparency = 0.82,
			ZIndex = 29,
			Parent = root,
		})
		UIUtil.Corner(shadow, 14)

		-- Carte (papier d'enveloppe)
		local body = frame({
			Name = "Body",
			Size = UDim2.fromScale(1, 1),
			BackgroundColor3 = paper,
			ZIndex = 31,
			Parent = root,
		})
		UIUtil.Corner(body, 12)
		UIUtil.Gradient(body, ColorSequence.new(white, Color3.fromRGB(236, 232, 222)), 90)
		local bodyStroke = UIUtil.Stroke(body, border, 1.5, 0.15)
		-- Liseré coloré à gauche (couleur de l'étiquette)
		local accent = frame({
			Size = UDim2.new(0, 4, 1, -20),
			Position = UDim2.fromOffset(0, 10),
			BackgroundColor3 = tagColor,
			ZIndex = 32,
			Parent = body,
		})
		UIUtil.Corner(accent, 2)

		-- Rabat en V (discret)
		local tip = Vector2.new(CARD_W / 2, 13)
		line(body, Vector2.new(8, 2), tip, 1.5, Color3.fromRGB(200, 190, 170), 32, 0.2)
		line(body, Vector2.new(CARD_W - 8, 2), tip, 1.5, Color3.fromRGB(200, 190, 170), 32, 0.2)

		-- Timbre (dépasse en haut à droite)
		local stamp = frame({
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.new(1, -14, 0, 6),
			Size = UDim2.fromOffset(22, 26),
			Rotation = 8,
			BackgroundColor3 = white,
			ZIndex = 36,
			Parent = body,
		})
		UIUtil.Stroke(stamp, Color3.fromRGB(190, 190, 200), 1, 0)
		local stampInner = frame({
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.new(1, -5, 1, -5),
			BackgroundColor3 = tagColor:Lerp(white, 0.55),
			ZIndex = 37,
			Parent = stamp,
		})
		UIUtil.Label({
			Text = email.Avatar,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromScale(0.85, 0.85),
			MaxTextSize = 13,
			ZIndex = 38,
			Parent = stampInner,
		})

		-- Avatar + pastille "non lu"
		avatar(body, email, 40, UDim2.fromOffset(12, 18), 33)
		local dot = frame({
			Name = "UnreadDot",
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromOffset(15, 21),
			Size = UDim2.fromOffset(12, 12),
			BackgroundColor3 = blue,
			ZIndex = 36,
			Parent = body,
		})
		UIUtil.Corner(dot, UDim.new(1, 0))
		UIUtil.Stroke(dot, white, 2, 0)

		-- Textes
		text({
			Size = UDim2.new(1, -150, 0, 16),
			Position = UDim2.fromOffset(60, 14),
			Font = Theme.Fonts.Title,
			Text = email.Sender,
			TextSize = 14,
			TextTruncate = Enum.TextTruncate.AtEnd,
			ZIndex = 33,
			Parent = body,
		})
		text({
			Size = UDim2.new(1, -72, 0, 15),
			Position = UDim2.fromOffset(60, 31),
			Font = Theme.Fonts.Title,
			Text = email.Subject,
			TextColor3 = Color3.fromRGB(50, 56, 72),
			TextSize = 12,
			TextTruncate = Enum.TextTruncate.AtEnd,
			ZIndex = 33,
			Parent = body,
		})
		text({
			Size = UDim2.new(1, -72, 0, 14),
			Position = UDim2.fromOffset(60, 47),
			Text = email.Body,
			TextColor3 = inkDim,
			TextSize = 11,
			TextTruncate = Enum.TextTruncate.AtEnd,
			ZIndex = 33,
			Parent = body,
		})
		local chip = tagChip(body, email, 15, 34)
		chip.AnchorPoint = Vector2.new(1, 0)
		chip.Position = UDim2.new(1, -30, 0, 14)

		-- Barre de temps restant (en bas)
		local lifeBar = frame({
			AnchorPoint = Vector2.new(0, 1),
			Position = UDim2.new(0, 60, 1, -6),
			Size = UDim2.new(1, -72, 0, 3),
			BackgroundColor3 = tagColor,
			ZIndex = 33,
			Parent = body,
		})
		UIUtil.Corner(lifeBar, UDim.new(1, 0))

		local envelope = {
			Id = info.Id,
			Email = email,
			Root = root,
			Scale = scale,
			Body = body,
			BodyStroke = bodyStroke,
			Letter = letter,
			Dot = dot,
			Chip = chip,
			LifeBar = lifeBar,
			Target = target,
			X = x,
			Y = y,
			Born = os.clock(),
			Lifetime = lifetime,
			Phase = random:NextNumber(0, math.pi * 2),
			Hurry = false,
			Done = false,
		}
		envelopes[info.Id] = envelope
		envelopeCount += 1
		refreshCounter()

		-- Arrivée en vol plané
		UIUtil.Tween(root, 0.75, { Position = target, Rotation = 0 }, Enum.EasingStyle.Back)
		UIUtil.Tween(scale, 0.75, { Scale = 1 }, Enum.EasingStyle.Back)
		ctx.Sound.Play("Mail", 1 + random:NextNumber() * 0.15)

		-- Survol : la carte se soulève un peu
		ctx.Connect(root.MouseEnter, function()
			if not envelope.Done and os.clock() - envelope.Born > 0.8 then
				UIUtil.Tween(scale, 0.15, { Scale = 1.05 }, Enum.EasingStyle.Back)
				bodyStroke.Color = blue
			end
		end)
		ctx.Connect(root.MouseLeave, function()
			if not envelope.Done then
				UIUtil.Tween(scale, 0.15, { Scale = 1 })
				bodyStroke.Color = border
			end
		end)

		-- Clic : on ouvre le mail
		ctx.Connect(root.Activated, function()
			if envelope.Done or not ctx.IsAlive() then
				return
			end
			local position = root.Position
			positions[envelope.Id] = position
			lastPosition = position
			ctx.ClaimSpawn(envelope.Id)
			ctx.Sound.Play("Mail", 1.4)
			if effectsOn() then
				ctx.Effects.Burst(container, position, blue, 10)
				ctx.Effects.Burst(container, position, nil, 6)
			end
			removeEnvelope(envelope, true)
			local mail = envelope.Email
			task.delay(0.14, function()
				if ctx.IsAlive() then
					openPopup(mail, envelope.X, envelope.Y, position)
				end
			end)
			local id = envelope.Id
			task.delay(6, function()
				positions[id] = nil
			end)
		end)
	end

	-- Animation de toutes les cartes (une seule connexion)
	ctx.OnRender(function()
		if envelopeCount <= 0 then
			return
		end
		local now = os.clock()
		for _, envelope in pairs(envelopes) do
			local age = now - envelope.Born
			local left = envelope.Lifetime - age
			if left <= 0 then
				removeEnvelope(envelope, false)
			else
				local t = now + envelope.Phase
				envelope.LifeBar.Size = UDim2.new(math.clamp(left / envelope.Lifetime, 0, 1), -72, 0, 3)
				if left < HURRY_TIME then
					-- Pressée : elle s'agite, étiquette "Vite !" rouge
					if not envelope.Hurry then
						envelope.Hurry = true
						local label = envelope.Chip:FindFirstChild("Label")
						if label and label:IsA("TextLabel") then
							label.Text = "⏰ VITE, LIS-MOI !"
						end
						envelope.Chip.BackgroundColor3 = Color3.fromRGB(226, 38, 52)
						envelope.LifeBar.BackgroundColor3 = Color3.fromRGB(226, 38, 52)
					end
					envelope.Body.Rotation = math.sin(t * 24) * 4
					local pulse = 12 + math.abs(math.sin(t * 10)) * 4
					envelope.Dot.Size = UDim2.fromOffset(pulse, pulse)
				else
					envelope.Body.Rotation = math.sin(t * 2.5) * 1.5
				end
				-- Flotte doucement une fois arrivée
				if age > 0.8 then
					envelope.Root.Position = envelope.Target + UDim2.fromOffset(0, math.sin(t * 2.2) * 4)
				end
			end
		end
	end)

	ctx.OnSpawn("Email", spawnEmail)

	-- Bonus confirmé : "+X" à côté du mail
	ctx.OnBonus("Email", function(payload)
		if not ctx.IsAlive() then
			return
		end
		local position = (payload.SpawnId and positions[payload.SpawnId]) or lastPosition
		ctx.FloatText(container, position, "+" .. ctx.Format.Format(tonumber(payload.Amount) or 0), blue, 40)
	end)
end

function Email.Stop(_ctx)
	-- Cartes, fenêtre et compteur vivent dans ctx.Container
	-- (détruit par le StimulusManager)
end

return Email
