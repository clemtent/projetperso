--[[
	LiveStream (ModuleScript - stimulus)
	Emplacement : ReplicatedStorage > Client > Stimuli > LiveStream

	Faux live "ASMR mukbang" (slot L3, 384x268, en bas à gauche), façon
	vraie appli de streaming (v8 : tout est redessiné en Frames) :
	  - en-tête : avatar dessiné avec anneau "en direct", pseudo certifié,
	    titre du live (catégorie, qualité, durée qui défile) et bouton
	    "Suivre" ;
	  - la vidéo, filmée comme une vraie webcam : mur de studio (mousse
	    acoustique, ruban LED, étagère, néon), la streameuse DESSINÉE
	    (cheveux, casque à oreilles de chat lumineuses, yeux avec iris et
	    reflets, sourcils et bouche expressifs : sourire, bouche grande
	    ouverte, mâche, "O" étonné, bouche de chat, parle), deux bras
	    articulés (épaule / coude / main) qui prennent la nourriture avec
	    des baguettes, boivent un bubble tea, font un cœur avec les mains
	    ou saluent ; la table (set de table, assiette, bol de nouilles
	    fumant, bubble tea, micro "moumoute") ;
	  - l'habillage du live : cadre caméra (coins de visée), vignettage,
	    pastilles "● LIVE" + spectateurs + likes, barre "objectif
	    d'abonnés" qui se remplit (et fête l'objectif atteint), alertes
	    de dons animées ;
	  - améliorations : "StreamStudio" ajoute ring light (1), LED
	    arc-en-ciel (2), micro pro sur bras articulé (3), lumières bokeh
	    (5), qualité 4K (7) ; "Followers" fait monter les spectateurs,
	    accélère le chat et pose des trophées sur l'étagère (5 / 10 / 15) ;
	  - bouton "Suivre" : si ClientState.Data.LiveFollowed est faux,
	    Interact("Follow") (récompense unique par partie), puis "✔ Abonné"
	    et les dons commencent ;
	  - dons : OnSpawn("Donation") affiche une alerte dorée dans la vidéo,
	    cliquable -> ClaimSpawn ; OnBonus("Donation" / "Follow") fait
	    flotter le gain ;
	  - Feature "LiveChat" : colonne de chat (avatars à initiale, badges
	    🛡️ modo / 💎 abonné / 👑 VIP, emotes en grand, message épinglé,
	    champ "Envoyer un message", raids) qui réagit à tout ce qui se
	    passe. Les lignes du chat sont RECYCLÉES (réserve fixe) ;
	  - Feature "Butter" : un bloc de beurre brillant. Clic = son "Crunch",
	    traces de dents, éclats, "+X" = gain par clic x ClickFraction,
	    Interact("Butter") limité côté client à MaxPerSecond.
	Performance : UNE seule boucle de rendu (repas, chat, raids, particules
	recyclées...) qui se met en pause quand le live n'est pas visible.
]]

local TweenService = game:GetService("TweenService")

local Locale = require(game:GetService("ReplicatedStorage").Shared.Locale)

local LiveStream = {}
LiveStream.Slot = "L3"

----------------------------------------------------------------------
-- Disposition (pixels "design"). Tout découle de la taille du slot L3
-- (voir Client > Slots) : la carte est rentrée de 2 px, la vidéo et le
-- chat se calent sur la largeur de la carte (Scale), la scène de la vidéo
-- est placée depuis le haut de la vidéo et depuis son centre horizontal.
----------------------------------------------------------------------
local SLOT_W, SLOT_H = 384, 268 -- = Slots.Definitions.L3
local CARD_W, CARD_H = SLOT_W - 4, SLOT_H - 4 -- 380 x 264
local PAD = 8 -- marge intérieure de la carte (côtés et bas)
local HEADER_H = 46 -- en-tête : avatar, pseudo, titre, Suivre
local HEADER_MID = HEADER_H / 2 -- ligne centrale de l'en-tête
local VIDEO_X, VIDEO_Y = PAD, HEADER_H
local VIDEO_H = CARD_H - VIDEO_Y - PAD -- 210
local CHAT_W = 138 -- colonne de chat (Feature "LiveChat")
local GAP = 6 -- espace entre la vidéo et le chat
local FOLLOW_W, FOLLOW_H = 100, 30 -- bouton "Suivre"
local VIDEO_RADIUS = 12 -- coins arrondis de la vidéo (repris par la table)
local TABLE_Y = VIDEO_H - 60 -- haut de la table dans la vidéo (150)
local PLATE_Y = TABLE_Y + 16 -- centre de l'assiette (166)
local FOOD_Y = PLATE_Y - 5 -- les aliments posés dans l'assiette
-- La streameuse : cadre de 120 x 120 dont le bas est caché par la table
local STREAMER_Y = TABLE_Y + 6 -- bas du cadre de la streameuse (156)
local BODY_TOP = STREAMER_Y - 120 -- haut du cadre (36)
local HEAD_Y = BODY_TOP + 44 -- centre de la tête (80)
local MOUTH_Y = HEAD_Y + 18 -- bouche (98)
local SHOULDER_Y = BODY_TOP + 88 -- épaules (124)
local SHOULDER_X = 36 -- épaules : centre +- 36
local UPPER_LEN, FORE_LEN = 27, 26 -- bras et avant-bras
local BUTTER_X = 0.85 -- position (Scale) du beurre sur la table
local BUTTER_Y = TABLE_Y + 28 -- bas de la coupelle de beurre (178)
local MIC_LEFT = 24 -- micro "moumoute" : pixels depuis le bord gauche
local CUP_X, CUP_BASE = -57, TABLE_Y + 8 -- bubble tea (derrière, à gauche)
local BOWL_X, BOWL_BASE = 60, TABLE_Y + 9 -- bol de nouilles (derrière, à droite)
local GOAL_Y, GOAL_H = VIDEO_H - 22, 15 -- barre "objectif d'abonnés"
local MAX_HEARTS = 7
local CHAT_POOL = 14 -- lignes de chat recyclées
local PARTICLES = 10 -- miettes / éclats recyclés
local BUTTER_BITES = 8 -- bouchées avant qu'il ne reste plus rien

local FOODS = { "🍗", "🍤", "🥟", "🍣", "🍙", "🌭", "🍔", "🍕", "🍩", "🥐", "🍪", "🧁", "🌮", "🍡", "🥪", "🍟" }
local FOOD_OFFSETS = { -28, -10, 10, 28 }

local CRUNCH_WORDS = {
	en = { "CRUNCH!", "YUM", "CHOMP!", "*crunch*", "SLURP", "CRACK!", "NOM NOM", "CRISP!", "MMMH", "SCRUNCH" },
	fr = { "CRUNCH !", "MIAM", "CROC !", "*crounch*", "SLURP", "CRAC !", "NOM NOM", "CRISP !", "MMMH", "SCROUNCH" },
}
local BUTTER_WORDS = {
	en = { "CRONCH!", "*CRONCH*", "CRACK!", "SCRONCH", "CRUNCH!!" },
	fr = { "CROUNCH !", "*CROUNCH*", "CRAC !", "SCRONCH", "CRUNCH !!" },
}
local POP_COLORS = {
	Color3.fromRGB(255, 214, 40),
	Color3.fromRGB(255, 90, 160),
	Color3.fromRGB(0, 210, 255),
	Color3.fromRGB(255, 255, 255),
	Color3.fromRGB(130, 255, 120),
}
local HEARTS = { "❤️", "💜", "💖", "😍", "🔥", "👏", "✨" }

local HOST = "MangeTout_ASMR"

----------------------------------------------------------------------
-- Chat : pseudos, rôles et messages (tout est inventé)
----------------------------------------------------------------------
local NAMES = {
	"Kevin_du_75", "xX_Nugget_Xx", "Mamie_Gaming", "LeChatDuVoisin", "BaguetteMan", "Tartiflette99",
	"MrPatate", "Choupette", "DarkSasuke42", "Poulet_Braisé", "Zinzin_78", "Croquette", "SushiLover",
	"Tonton_Jean", "Lulu_ASMR", "PatateDouce", "Bichon_Fou", "Crêpe_Party", "Moustache_Pro",
	"Raclette4Life", "Gratin2Pâtes", "Ninja_du_Dimanche", "Fromage_Fou", "LaTeteDansLeFrigo",
	"Pépito_Gamer", "Mimi_Chaussette", "Cornichon_Royal", "Tata_Brioche", "Loulou_Pixel", "CaptainKebab",
	"Nuage_Rose", "Petit_Pois", "Madeleine_Proust", "Framboise_Zen", "Cacahuète42", "Le_Roi_du_Gouda",
	"Pingouin_Timide", "Chocapic_Fan", "Sardine_Club", "Biscotte_Ninja", "Yaourt_Nature", "Mister_Frites",
	"Poney_Magique", "Tomate_Cerise", "Kiwi_Sauvage", "Doudou_77", "Licorne_Fatiguée", "Bretzel_Boss",
	"Céleri_Rave", "Nutella_Addict",
}
-- Modérateurs (badge 🛡️) : toujours les mêmes, comme sur un vrai live
local MODS = { Tonton_Jean = true, Lulu_ASMR = true, Moustache_Pro = true, Madeleine_Proust = true }
local NAME_COLORS = { "#FF6B9A", "#6BD5FF", "#FFD34D", "#9DFF6B", "#C38BFF", "#FF9F45", "#5CFFD1", "#FF7AF0", "#7AA2FF", "#FFB3C7" }

local MESSAGES = {
	en = {
		"W", "+1", "insane", "what is this stream", "that crunch was perfect", "again!!", "i'm hungry now",
		"she's eating at 3am??", "first", "quality ASMR", "YUM", "so satisfying",
		"watching this instead of studying", "lmao", "the sound 🤤", "hi mom if you see this",
		"she didn't even chew", "so good", "respect", "where's the sauce??", "GG",
		"who's been here since the start?", "dropped my snack", "5 stars", "my favorite part", "L",
		"is she gonna finish the plate??", "love the headset", "i'm on a diet 😭", "the mic 😳", "snack time",
		"we want fries!", "i can hear the crunch from here", "come eat at my place", "ratio", "falling asleep 😴",
		"the ring light 😍", "that hoodie is so cute", "has anyone seen my glasses?",
		"i was supposed to sleep 2h ago", "better than a movie", "pretty sure my teacher watches too",
		"how many of us are here?", "chat is wild tonight", "hello from Texas ☀️", "hi from London 👋",
		"greetings from Toronto ❄️", "love from Napa Valley 🍷", "eating chips at the same time",
		"can we get a cheese mukbang?", "next stream: fondue 🧀", "this is my nightly ritual",
		"she's so good at this", "how does her stomach not hurt??", "i want a fluffy mic too",
		"this is so relaxing", "my cat is watching with me 🐈", "i'm in class shh 🤫", "lol", "lmfao", "fr", "real",
		"i like every crunch", "who else eats in front of the screen?", "the sound is hypnotic",
		"staying till the end", "we vibing", "can't wait for tomorrow", "sharing this with my friends",
		"my daily dose of dopamine", "click click click", "forgot why i came here", "another plate!!",
		"what's the song?", "audio is perfect", "do you guys hear that??", "i'm not ready", "so yummy",
		"she has fancy taste", "best streamer ever", "notifs on 🔔", "i should be doing homework...",
		"have you tried pickles?", "team fries 🍟", "team nuggets", "what time is it where you are?",
		"been smiling at my screen for 10 min", "i can smell it from here", "chat is moving too fast 😵",
		"who wants a bite?", "it's my birthday today 🎂", "happy birthday!!", "volume on max",
		"my neighbors can hear the crunch", "stream of the year", "i'm addicted",
	},
	fr = {
		"W", "+1", "incroyable", "c'est quoi ce live", "le crunch était parfait", "encore !!",
		"j'ai faim maintenant", "elle mange à 3h du mat ?", "premier", "ASMR de qualité", "MIAM",
		"c'est tellement satisfaisant", "je regarde au lieu de réviser", "mdr", "le son 🤤",
		"maman si tu vois ça coucou", "elle a même pas mâché", "trop bien", "respect", "et la sauce ??", "GG",
		"qui est là depuis le début ?", "j'ai lâché mon goûter", "5 étoiles", "mon moment préféré", "L",
		"elle va finir l'assiette ??", "le casque est trop beau", "je suis au régime 😭", "le micro 😳",
		"c'est l'heure du goûter", "on veut des frites !", "j'entends le crunch d'ici", "reviens manger chez moi",
		"ratio", "je m'endors 😴", "le ring light 😍", "trop chou le sweat", "quelqu'un a vu mes lunettes ?",
		"je devais dormir il y a 2h", "c'est mieux qu'un film", "ma prof regarde aussi je crois",
		"on est combien là ?", "le chat est chaud ce soir", "bonjour de Marseille ☀️", "coucou de Lyon 👋",
		"salut de Montréal ❄️", "bisous de Bordeaux 🍷", "je mange des chips en même temps",
		"on peut avoir un mukbang raclette ?", "prochain live : fondue 🧀", "c'est mon rituel du soir",
		"elle est trop forte", "comment elle a pas mal au ventre ??", "moi aussi je veux un micro moumoute",
		"ça me détend trop", "mon chat regarde avec moi 🐈", "je suis en cours chut 🤫", "lol", "ptdr", "j'avoue",
		"grave", "je like chaque crunch", "qui mange devant l'écran aussi ?", "le bruit est hypnotisant",
		"je reste jusqu'à la fin", "on est bien là", "vivement demain", "je partage à mes potes",
		"c'est ma dose de dopamine", "clique clique clique", "j'ai oublié pourquoi j'étais là",
		"encore une assiette !!", "c'est quoi la musique ?", "le son est parfait", "vous entendez ça ??",
		"jsuis pas prêt", "trop mims", "elle a des goûts de luxe", "c'est la meilleure streameuse",
		"notif activée 🔔", "je devrais faire mes devoirs...", "t'as essayé les cornichons ?", "team frites 🍟",
		"team nuggets", "il est quelle heure chez vous ?", "10 minutes que je souris devant mon écran",
		"ça sent bon d'ici", "le chat va trop vite 😵", "qui veut un bout ?", "c'est mon anniv aujourd'hui 🎂",
		"joyeux anniv !!", "j'ai mis le son à fond", "mes voisins entendent le crunch", "live de l'année",
		"je suis addict",
	},
}
-- Messages uniquement composés d'emotes (affichés en plus gros)
local EMOTE_MESSAGES = {
	"🔥🔥🔥", "😭😭😭", "🤤🤤🤤", "💜💜💜", "👏👏👏", "😂😂", "🥪🥪🥪", "🍟🍟", "👀", "💯💯",
	"😍😍", "🤯", "🙌🙌", "✨✨✨", "🎉🎉🎉", "🧈🧈", "🍔🍕🌭", "😋😋", "💖", "🥺👉👈",
}
local EAT_REACTIONS = {
	en = {
		"CRUNCH 🔥", "the sound 🤤🤤", "YESSS", "YUM", "another one!", "W crunch", "ASMR 🔊", "that bite 😳",
		"she ate it all in one go", "that crunch went right through me", "crispiness approved ✅", "10/10 sound",
		"i got chills", "more more more", "this sound should be illegal",
	},
	fr = {
		"CRUNCH 🔥", "le son 🤤🤤", "OUIIII", "MIAM", "encore une !", "W crunch", "ASMR 🔊", "cette bouchée 😳",
		"elle a tout mangé d'un coup", "le crunch m'a traversé", "croustillant validé ✅", "10/10 le bruit",
		"j'ai frissonné", "encore encore encore", "ce son devrait être interdit",
	},
}
local BUTTER_REACTIONS = {
	en = {
		"*CRONCH*", "the butter 😭😭", "CRONCH 🧈", "BUTTER ASMR 🔊", "who bites into butter??", "the butter sound 🤤",
		"this should be illegal", "CRUNCHY BUTTER", "*cronch cronch*", "the butter screamed", "BUTTER > everything",
		"whose idea was the butter 😭", "salted or unsalted??", "more butter!!",
	},
	fr = {
		"*CROUNCH*", "le beurre 😭😭", "CROUNCH 🧈", "ASMR BEURRE 🔊", "qui croque du beurre ??", "le son du beurre 🤤",
		"c'est illégal ça", "BEURRE CROUSTILLANT", "*crounch crounch*", "le beurre a crié", "BEURRE > tout",
		"qui a eu l'idée du beurre 😭", "demi-sel ou doux ??", "encore le beurre !!",
	},
}
local DONATION_REACTIONS = {
	en = {
		"THANKS FOR THE DONO 💸", "the boss 🤑", "GG on the dono!!", "so generous", "W donator", "i wanna donate too",
		"party time 🎉", "patron of the stream", "it's raining cash 💵", "you're the best",
		"respect to the donator 🙏", "💸💸💸",
	},
	fr = {
		"MERCI POUR LE DON 💸", "le boss 🤑", "GG le don !!", "quel généreux", "W donateur",
		"moi aussi je veux donner", "c'est la fête 🎉", "le mécène du live", "pluie de billets 💵",
		"t'es le meilleur", "respect au donateur 🙏", "💸💸💸",
	},
}
local FOLLOW_REACTIONS = {
	en = {
		"welcome!! 💜", "a new follower 🎉", "W follow", "welcome to the team", "we're a family here",
		"finally followed 😤", "donations are open!!", "💜💜💜",
	},
	fr = {
		"bienvenue !! 💜", "un nouvel abonné 🎉", "W follow", "bienvenue dans la team", "on est une famille ici",
		"enfin abonné 😤", "les dons sont ouverts !!", "💜💜💜",
	},
}
local BIG_GAIN_REACTIONS = {
	en = {
		"BIG GAINS 🤑", "you're rich now", "lend me some dopamine pls", "numbers going up 📈", "that's huge", "💰💰💰",
		"so lucky 🍀", "let's celebrate 🎉", "the counter is going crazy", "you're unstoppable",
	},
	fr = {
		"GROS GAIN 🤑", "t'es riche maintenant", "prête-moi de la dopamine stp", "les chiffres montent 📈",
		"c'est énorme", "💰💰💰", "quelle chance 🍀", "on fête ça 🎉", "le compteur s'affole", "t'arrêtes plus",
	},
}
local RAID_MESSAGES = {
	en = {
		"RAID 🎉🎉", "raid incoming!!", "💜 RAID 💜", "hello chat!!", "hi everyone 👋", "we heard about the crunch",
		"is this where the butter is?", "RAIDDDD 🚨", "coming through 🏃", "hey team!!",
	},
	fr = {
		"RAID 🎉🎉", "on vient en raid !!", "💜 RAID 💜", "bonjour le chat !!", "coucou tout le monde 👋",
		"on a entendu parler du crunch", "c'est ici le beurre ?", "RAIDDDD 🚨", "on débarque 🏃", "salut la team !!",
	},
}
local MOD_MESSAGES = {
	en = {
		"be nice pls 🛡️", "no spamming in chat!", "respect the streamer 💜", "stay hydrated 💧",
		"don't forget to follow 💜", "don't talk with your mouth full... oh wait",
	},
	fr = {
		"restez gentils svp 🛡️", "pas de spam dans le chat !", "on respecte la streameuse 💜", "hydratez-vous 💧",
		"pensez à suivre la chaîne 💜", "on parle pas la bouche pleine... ah si en fait",
	},
}
local HOST_MESSAGES = {
	en = {
		"thanks for being here 💜", "what should i taste next?", "is the audio good?", "shh... ASMR 🤫",
		"follow for more 💜", "still hungry", "who's eating with me?", "hi newcomers 👋",
	},
	fr = {
		"merci d'être là 💜", "vous voulez que je goûte quoi ?", "le son est bon ?", "chut... ASMR 🤫",
		"abonnez-vous 💜", "j'ai encore faim", "qui mange avec moi ?", "coucou les nouveaux 👋",
	},
}
local DONATION_LINES = {
	en = { "just donated!", "sent you a tip!", "bought a round!", "dropped some cash!" },
	fr = { "a fait un don !", "t'envoie un pourboire !", "offre une tournée !", "a lâché un billet !" },
}
-- Réactions aux notifications du joueur
local JACKPOT_REACTIONS = {
	en = { "JACKPOT?!", "JACKPOT 🤑🤑🤑", "THE DVD CORNER!!!" },
	fr = { "JACKPOT ?!", "JACKPOT 🤑🤑🤑", "le coin du DVD !!!" },
}
local RUSH_REACTIONS = {
	en = { "RUSH!!! 🚀", "everybody click!!", "it's rush time 🔥" },
	fr = { "RUSH !!! 🚀", "tout le monde clique !!", "c'est le rush 🔥" },
}
local ACHIEVEMENT_REACTIONS = {
	en = { "GG on the achievement 🏆", "achievement unlocked 👏", "too good 🏆" },
	fr = { "GG pour le succès 🏆", "succès débloqué 👏", "trop fort 🏆" },
}
local UNLOCK_REACTIONS = {
	en = { "new upgrade 👀", "what even is that??", "this is getting out of hand 😂" },
	fr = { "nouvelle amélioration 👀", "c'est quoi ce truc ??", "ça devient n'importe quoi 😂" },
}
-- Le chat réclame le beurre / l'abonnement
local BUTTER_NAGS = {
	en = { "bite the butter!!", "THE BUTTER 🧈", "click the butter 👀", "where's the butter?" },
	fr = { "croque le beurre !!", "LE BEURRE 🧈", "clique sur le beurre 👀", "il est où le beurre ?" },
}
local FOLLOW_NAGS = {
	en = { "follow!!", "hit Follow 💜", "why aren't you following?" },
	fr = { "abonne-toi !!", "clique sur Suivre 💜", "pourquoi t'es pas abonné ?" },
}

-- Arcs (yeux fermés, sourire, arceau du casque) : on cache une moitié du
-- contour d'un cercle avec un dégradé de transparence
local LOWER_ARC = NumberSequence.new({
	NumberSequenceKeypoint.new(0, 1),
	NumberSequenceKeypoint.new(0.5, 1),
	NumberSequenceKeypoint.new(0.56, 0),
	NumberSequenceKeypoint.new(1, 0),
})
local UPPER_ARC = NumberSequence.new({
	NumberSequenceKeypoint.new(0, 0),
	NumberSequenceKeypoint.new(0.46, 0),
	NumberSequenceKeypoint.new(0.52, 1),
	NumberSequenceKeypoint.new(1, 1),
})

-- Palette de la streameuse (originale : cheveux prune, sweat rose, casque "chat")
local WHITE = Color3.new(1, 1, 1)
local SKIN = Color3.fromRGB(255, 220, 196)
local SKIN_SHADE = Color3.fromRGB(242, 184, 160)
local HAIR = Color3.fromRGB(70, 46, 96)
local HAIR_LIGHT = Color3.fromRGB(132, 96, 170)
local HOODIE = Color3.fromRGB(255, 160, 196)
local HOODIE_DARK = Color3.fromRGB(222, 104, 152)
local INK = Color3.fromRGB(46, 28, 52)
local IRIS_TOP = Color3.fromRGB(150, 96, 210)
local IRIS_BOTTOM = Color3.fromRGB(70, 36, 120)
local PHONES = Color3.fromRGB(58, 48, 82)
local PHONES_GLOW = Color3.fromRGB(255, 130, 210)
local CHAT_BG = Color3.fromRGB(24, 20, 36)

-- Mesures et couleurs de la mise en page (hors de Start : limite de variables locales)
local AVATAR = 36
local AVATAR_X = PAD + AVATAR / 2 + 2
local TEXT_X = PAD + AVATAR + 10
local RIGHT_BLOCK = PAD + 2 + FOLLOW_W + 8
local FOLLOW_COLOR = Color3.fromRGB(145, 70, 255)
local FOLLOWED_COLOR = Color3.fromRGB(62, 56, 84)
local RING = 112
local PRO_X, PRO_Y = -54, 100 -- capsule du micro (centre)
local BUTTER_W, BUTTER_H = 42, 27
local BUTTON_W, BUTTON_H = 62, 50 -- zone cliquable (coupelle + bloc)
local HINT_Y = BUTTON_H - 6 - BUTTER_H - 3 -- bas de l'indice (juste au-dessus du beurre)
local CRUMB_COLORS = { Color3.fromRGB(230, 170, 90), Color3.fromRGB(250, 210, 140), Color3.fromRGB(200, 130, 70) }
local BUTTER_COLORS = { Color3.fromRGB(255, 226, 96), Color3.fromRGB(255, 246, 190), Color3.fromRGB(245, 200, 70) }
local TITLE_H = 22
local PINNED_Y, PINNED_H = TITLE_H + 4, 30
local INPUT_H = 20
local LIST_Y = PINNED_Y + PINNED_H + 3
local LIST_H = VIDEO_H - LIST_Y - INPUT_H - 8
local LED_RAINBOW = ColorSequence.new({
	ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 80, 160)),
	ColorSequenceKeypoint.new(0.25, Color3.fromRGB(255, 200, 60)),
	ColorSequenceKeypoint.new(0.5, Color3.fromRGB(80, 220, 255)),
	ColorSequenceKeypoint.new(0.75, Color3.fromRGB(160, 100, 255)),
	ColorSequenceKeypoint.new(1, Color3.fromRGB(255, 80, 160)),
})
local LED_WARM = ColorSequence.new(Color3.fromRGB(255, 120, 190), Color3.fromRGB(255, 160, 210))
local SLEEVE = ColorSequence.new({
	ColorSequenceKeypoint.new(0, HOODIE),
	ColorSequenceKeypoint.new(0.78, HOODIE:Lerp(HOODIE_DARK, 0.35)),
	ColorSequenceKeypoint.new(0.8, HOODIE_DARK),
	ColorSequenceKeypoint.new(1, HOODIE_DARK),
})
local BOKEH_COLORS = { Color3.fromRGB(255, 200, 120), Color3.fromRGB(255, 140, 220), Color3.fromRGB(140, 220, 255), Color3.fromRGB(200, 170, 255) }

----------------------------------------------------------------------
-- Petites fonctions utilitaires
----------------------------------------------------------------------
local function escape(text: string): string
	text = string.gsub(text, "&", "&amp;")
	text = string.gsub(text, "<", "&lt;")
	text = string.gsub(text, ">", "&gt;")
	return text
end

local function pick<T>(list: { T }, random: Random): T
	return list[random:NextInteger(1, #list)]
end

local function hexColor(hex: string): Color3
	return Color3.fromRGB(tonumber(string.sub(hex, 2, 3), 16) or 255, tonumber(string.sub(hex, 4, 5), 16) or 255, tonumber(string.sub(hex, 6, 7), 16) or 255)
end

-- Rapprochement exponentiel (indépendant des images par seconde)
local function approach(current: number, target: number, speed: number, dt: number): number
	return current + (target - current) * (1 - math.exp(-speed * dt))
end

function LiveStream.Start(ctx)
	type Eye = { Open: Frame, Sclera: Frame, Iris: Frame, Lash: Frame, Happy: Frame, Relaxed: Frame, Brow: Frame, X: number, Side: number }
	local UI = ctx.UIUtil
	local Theme = ctx.Theme
	local Format = ctx.Format
	local random = Random.new()

	-- Textes dans la langue du joueur (choisis une fois au démarrage)
	local TXT = {
		crunchWords = Locale.Pick(CRUNCH_WORDS) :: { string },
		butterWords = Locale.Pick(BUTTER_WORDS) :: { string },
		messages = Locale.Pick(MESSAGES) :: { string },
		eatReactions = Locale.Pick(EAT_REACTIONS) :: { string },
		butterReactions = Locale.Pick(BUTTER_REACTIONS) :: { string },
		donationReactions = Locale.Pick(DONATION_REACTIONS) :: { string },
		followReactions = Locale.Pick(FOLLOW_REACTIONS) :: { string },
		bigGainReactions = Locale.Pick(BIG_GAIN_REACTIONS) :: { string },
		raidMessages = Locale.Pick(RAID_MESSAGES) :: { string },
		modMessages = Locale.Pick(MOD_MESSAGES) :: { string },
		hostMessages = Locale.Pick(HOST_MESSAGES) :: { string },
		donationLines = Locale.Pick(DONATION_LINES) :: { string },
		jackpotReactions = Locale.Pick(JACKPOT_REACTIONS) :: { string },
		rushReactions = Locale.Pick(RUSH_REACTIONS) :: { string },
		achievementReactions = Locale.Pick(ACHIEVEMENT_REACTIONS) :: { string },
		unlockReactions = Locale.Pick(UNLOCK_REACTIONS) :: { string },
		butterNags = Locale.Pick(BUTTER_NAGS) :: { string },
		followNags = Locale.Pick(FOLLOW_NAGS) :: { string },
	}

	local function effectsOn(): boolean
		local data = ctx.State.Data
		return not (data and data.Settings and data.Settings.Effects == false)
	end

	local function followers(): number
		return tonumber(ctx.GetLevel("Followers")) or 0
	end

	local function studio(): number
		return tonumber(ctx.GetLevel("StreamStudio")) or 0
	end

	local function hasChat(): boolean
		return ctx.HasFeature("LiveChat") == true
	end

	local function hasButter(): boolean
		return ctx.HasFeature("Butter") == true
	end

	local function isFollowedOnServer(): boolean
		local data = ctx.State.Data
		return data ~= nil and data.LiveFollowed == true
	end

	-- Cadre sans bordure (+ coin arrondi optionnel)
	local function box(props: { [string]: any }, radius: (number | UDim)?): Frame
		props.BorderSizePixel = 0
		local frame = UI.Create("Frame", props)
		if radius then
			UI.Corner(frame, radius)
		end
		return frame
	end

	local function round(props: { [string]: any }): Frame
		return box(props, UDim.new(1, 0))
	end

	local function text(props: { [string]: any }): TextLabel
		props.BackgroundTransparency = props.BackgroundTransparency or 1
		props.BorderSizePixel = 0
		props.Font = props.Font or Theme.Fonts.Body
		props.TextColor3 = props.TextColor3 or WHITE
		return UI.Create("TextLabel", props)
	end

	-- Cadre centré sur (x, y), en pixels du parent
	local function at(props: { [string]: any }, x: number, y: number, w: number, h: number): { [string]: any }
		props.AnchorPoint = Vector2.new(0.5, 0.5)
		props.Position = UDim2.fromOffset(x, y)
		props.Size = UDim2.fromOffset(w, h)
		return props
	end

	-- Idem, mais x est compté depuis le CENTRE du parent (la vidéo change
	-- de largeur quand le chat apparaît)
	local function atC(props: { [string]: any }, x: number, y: number, w: number, h: number): { [string]: any }
		props.AnchorPoint = props.AnchorPoint or Vector2.new(0.5, 0.5)
		props.Position = UDim2.new(0.5, x, 0, y)
		props.Size = UDim2.fromOffset(w, h)
		return props
	end

	local function grad(guiObject: Instance, top: Color3, bottom: Color3, rotation: number?): UIGradient
		return UI.Gradient(guiObject, ColorSequence.new(top, bottom), rotation or 90)
	end

	-- Contour circulaire dont on ne garde que le haut ou le bas
	local function arc(props: { [string]: any }, color: Color3, thickness: number, sequence: NumberSequence): (Frame, UIStroke)
		props.BackgroundTransparency = 1
		local f = round(props)
		local stroke = UI.Stroke(f, color, thickness, 0)
		UI.Create("UIGradient", { Rotation = 90, Transparency = sequence, Parent = stroke })
		return f, stroke
	end

	-- Calque transparent plein cadre (ZIndex relatifs entre frères)
	local function layer(name: string, zIndex: number, parent: Instance): Frame
		return box({ Name = name, Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, ZIndex = zIndex, Parent = parent })
	end

	-- Membre (bras, avant-bras) : capsule tournée de (x1, y1) à (x2, y2),
	-- x compté depuis le centre de la vidéo. Le haut du cadre est du côté
	-- (x1, y1) : un dégradé Rotation 90 va du début vers la fin du membre.
	local function setLimb(limb: GuiObject, x1: number, y1: number, x2: number, y2: number, thickness: number)
		local dx, dy = x2 - x1, y2 - y1
		local length = math.sqrt(dx * dx + dy * dy)
		limb.Position = UDim2.new(0.5, (x1 + x2) / 2, 0, (y1 + y2) / 2)
		limb.Size = UDim2.fromOffset(thickness, length + thickness * 0.7)
		limb.Rotation = math.deg(math.atan2(-dx, dy))
	end

	------------------------------------------------------------------
	-- Carte
	------------------------------------------------------------------
	local card = box({
		Name = "Card",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.new(1, -4, 1, -4),
		BackgroundColor3 = Color3.fromRGB(22, 18, 32),
		Parent = ctx.Container,
	}, 16)
	grad(card, Color3.fromRGB(44, 34, 66), Color3.fromRGB(17, 14, 26))
	local cardStroke = UI.Stroke(card, WHITE, 2)
	local strokeGradient = UI.Gradient(cardStroke, ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 90, 170)),
		ColorSequenceKeypoint.new(0.5, Color3.fromRGB(150, 90, 255)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(80, 200, 255)),
	}), 0)

	-- Taille de la vidéo : toute la largeur de la carte, moins le chat s'il est là
	local function videoSize(chat: boolean): UDim2
		local inset = VIDEO_X * 2 + (chat and (CHAT_W + GAP) or 0)
		return UDim2.new(1, -inset, 0, VIDEO_H)
	end

	------------------------------------------------------------------
	-- En-tête : avatar "en direct", pseudo, titre du live, Suivre
	------------------------------------------------------------------
	local header = box({
		Name = "Header",
		Size = UDim2.new(1, 0, 0, HEADER_H),
		BackgroundTransparency = 1,
		ZIndex = 5,
		Parent = card,
	})

	-- Avatar : anneau dégradé qui tourne + mini portrait dessiné
	local avatarRing = round(at({ Name = "Avatar", BackgroundColor3 = WHITE, ZIndex = 1, Parent = header }, AVATAR_X, HEADER_MID - 1, AVATAR, AVATAR))
	local ringGradient = UI.Gradient(avatarRing, ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 60, 90)),
		ColorSequenceKeypoint.new(0.5, Color3.fromRGB(255, 120, 200)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(255, 180, 60)),
	}), 45)
	do
		local avatarGap = round(at({ BackgroundColor3 = Color3.fromRGB(30, 24, 44), ZIndex = 2, Parent = avatarRing }, AVATAR / 2, AVATAR / 2, AVATAR - 4, AVATAR - 4))
		local avatarFace = round(at({ BackgroundColor3 = Color3.fromRGB(255, 196, 222), ZIndex = 3, ClipsDescendants = true, Parent = avatarGap }, (AVATAR - 4) / 2, (AVATAR - 4) / 2, AVATAR - 7, AVATAR - 7))
		do
			local s = AVATAR - 7 -- 29
			grad(avatarFace, Color3.fromRGB(255, 214, 234), Color3.fromRGB(250, 160, 200))
			box(at({ BackgroundColor3 = HAIR, ZIndex = 3, Parent = avatarFace }, s / 2, s / 2 + 3, 22, 26), 9)
			box(at({ BackgroundColor3 = SKIN, ZIndex = 4, Parent = avatarFace }, s / 2, s / 2 + 5, 16, 16), UDim.new(0.48, 0))
			box(at({ BackgroundColor3 = HAIR, ZIndex = 5, Parent = avatarFace }, s / 2, s / 2 - 3, 20, 8), 4)
			for _, x in ipairs({ -3.5, 3.5 }) do
				round(at({ BackgroundColor3 = INK, ZIndex = 6, Parent = avatarFace }, s / 2 + x, s / 2 + 5, 2.5, 3))
				round(at({ BackgroundColor3 = Color3.fromRGB(255, 120, 150), BackgroundTransparency = 0.4, ZIndex = 6, Parent = avatarFace }, s / 2 + x * 1.6, s / 2 + 8, 4, 2))
			end
			round(at({ BackgroundColor3 = Color3.fromRGB(190, 70, 100), ZIndex = 6, Parent = avatarFace }, s / 2, s / 2 + 9.5, 4, 2))
			-- Casque (petits écouteurs roses)
			for _, x in ipairs({ -9, 9 }) do
				box(at({ BackgroundColor3 = PHONES_GLOW, ZIndex = 6, Parent = avatarFace }, s / 2 + x, s / 2 + 4, 4, 8), 2)
			end
		end
	end
	-- Étiquette "LIVE" sous l'avatar
	local avatarLive = text({
		Name = "LiveTag",
		Text = "LIVE",
		Font = Theme.Fonts.Title,
		TextSize = 8,
		BackgroundColor3 = Color3.fromRGB(235, 35, 60),
		BackgroundTransparency = 0,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromOffset(AVATAR_X, HEADER_MID + AVATAR / 2 - 1),
		Size = UDim2.fromOffset(26, 11),
		ZIndex = 4,
		Parent = header,
	})
	UI.Corner(avatarLive, 4)
	UI.Stroke(avatarLive, Color3.fromRGB(30, 24, 44), 1.5)

	-- Pseudo + titre du live : de l'avatar jusqu'au bouton Suivre
	text({
		Name = "Streamer",
		Text = "<b>" .. HOST .. '</b> <font color="#5CC8FF">✔</font>',
		RichText = true,
		Font = Theme.Fonts.Title,
		TextSize = 14,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextTruncate = Enum.TextTruncate.AtEnd,
		Position = UDim2.fromOffset(TEXT_X, 5),
		Size = UDim2.new(1, -(TEXT_X + RIGHT_BLOCK), 0, 18),
		ZIndex = 5,
		Parent = header,
	})
	local streamTitle = Locale.T("ASMR mukbang")
	local subtitleLabel = text({
		Name = "Title",
		Text = "🍤 " .. streamTitle,
		RichText = true,
		TextSize = 11,
		TextColor3 = Color3.fromRGB(196, 186, 228),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextTruncate = Enum.TextTruncate.AtEnd,
		Position = UDim2.fromOffset(TEXT_X, 24),
		Size = UDim2.new(1, -(TEXT_X + RIGHT_BLOCK), 0, 15),
		ZIndex = 5,
		Parent = header,
	})

	-- Bouton Suivre
	local followButton = UI.Create("TextButton", {
		Name = "Follow",
		Text = Locale.T("💜 Follow"),
		Font = Theme.Fonts.Title,
		TextSize = 14,
		TextColor3 = WHITE,
		BackgroundColor3 = FOLLOW_COLOR,
		AutoButtonColor = false,
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -(PAD + 2), 0, HEADER_MID),
		Size = UDim2.fromOffset(FOLLOW_W, FOLLOW_H),
		BorderSizePixel = 0,
		ZIndex = 5,
		Parent = header,
	})
	UI.Corner(followButton, UDim.new(1, 0))
	local followGradient = UI.Gradient(followButton, ColorSequence.new(WHITE, Color3.fromRGB(205, 190, 230)), 90)
	local followStroke = UI.Stroke(followButton, Color3.fromRGB(210, 180, 255), 1.5, 0.3)
	UI.AnimateButton(followButton, 1.06, 0.9)
	-- Reflet qui passe sur le bouton tant qu'on n'est pas abonné
	local followShine = box({
		Name = "Shine",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = WHITE,
		BackgroundTransparency = 0.55,
		ZIndex = 6,
		Parent = followButton,
	}, UDim.new(1, 0))
	local followShineGradient = UI.Create("UIGradient", {
		Rotation = 20,
		Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 1),
			NumberSequenceKeypoint.new(0.42, 1),
			NumberSequenceKeypoint.new(0.5, 0.3),
			NumberSequenceKeypoint.new(0.58, 1),
			NumberSequenceKeypoint.new(1, 1),
		}),
		Offset = Vector2.new(-1, 0),
		Parent = followShine,
	})

	------------------------------------------------------------------
	-- Vidéo : calques du fond vers l'avant
	------------------------------------------------------------------
	local video = box({
		Name = "Video",
		Position = UDim2.fromOffset(VIDEO_X, VIDEO_Y),
		Size = videoSize(hasChat()),
		BackgroundColor3 = WHITE,
		ClipsDescendants = true,
		ZIndex = 2,
		Parent = card,
	}, VIDEO_RADIUS)
	UI.Gradient(video, ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(58, 40, 104)),
		ColorSequenceKeypoint.new(0.5, Color3.fromRGB(128, 78, 150)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(214, 124, 150)),
	}), 90)

	local wallLayer = layer("Wall", 1, video)
	local lightLayer = layer("Lights", 2, video)
	local streamerLayer = layer("StreamerLayer", 3, video)
	local tableLayer = layer("TableLayer", 4, video)
	local propsLayer = layer("Props", 5, video)
	local armsLayer = layer("Arms", 6, video)
	local fxLayer = layer("FX", 7, video)
	local overlayLayer = layer("Overlay", 8, video)
	local alertLayer = layer("Alerts", 9, video)

	------------------------------------------------------------------
	-- Mur du studio
	------------------------------------------------------------------
	local ledGradient: UIGradient, trophy: Frame, trophyGradient: UIGradient, neonSign: TextLabel
	do
		-- Rayures verticales très douces (papier peint)
		for i = 1, 7 do
			box({
				Position = UDim2.new((i - 0.5) / 7, 0, 0, 0),
				Size = UDim2.new(0, 8, 1, 0),
				BackgroundColor3 = WHITE,
				BackgroundTransparency = 0.96,
				ZIndex = 1,
				Parent = wallLayer,
			})
		end

		-- Ruban LED en haut du mur (arc-en-ciel qui défile avec le studio) + halo
		local led = box({
			Name = "LED",
			Position = UDim2.fromOffset(0, 1),
			Size = UDim2.new(1, 0, 0, 3),
			BackgroundColor3 = WHITE,
			ZIndex = 2,
			Parent = wallLayer,
		})
		ledGradient = UI.Gradient(led, LED_WARM, 0)
		local ledGlow = box({
			Position = UDim2.fromOffset(0, 4),
			Size = UDim2.new(1, 0, 0, 34),
			BackgroundColor3 = Color3.fromRGB(255, 180, 235),
			BackgroundTransparency = 0.25,
			ZIndex = 1,
			Parent = wallLayer,
		})
		local glowGradient = UI.Gradient(ledGlow, ColorSequence.new(WHITE), 90)
		glowGradient.Transparency = NumberSequence.new(0.55, 1)

		-- Panneau de mousse acoustique (à gauche)
		local foam = box({
			Name = "Foam",
			Position = UDim2.fromOffset(9, 32),
			Size = UDim2.fromOffset(42, 42),
			BackgroundColor3 = Color3.fromRGB(30, 20, 48),
			BackgroundTransparency = 0.3,
			ZIndex = 2,
			Parent = wallLayer,
		}, 3)
		for row = 0, 2 do
			for col = 0, 2 do
				local tile = box({
					Position = UDim2.fromOffset(2 + col * 13.3, 2 + row * 13.3),
					Size = UDim2.fromOffset(11.5, 11.5),
					BackgroundColor3 = WHITE,
					ZIndex = 2,
					Parent = foam,
				}, 2)
				-- Pyramides alternées (le dégradé tourne d'un carreau à l'autre)
				UI.Gradient(tile, ColorSequence.new(Color3.fromRGB(96, 70, 140), Color3.fromRGB(44, 30, 72)), (row + col) % 2 == 0 and 45 or 225)
			end
		end

		-- Étagère à droite : plante, livres, trophée (niveau "Abonnés")
		local shelf = box({
			Name = "Shelf",
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.new(1, -8, 0, 76),
			Size = UDim2.fromOffset(62, 4),
			BackgroundColor3 = WHITE,
			ZIndex = 3,
			Parent = wallLayer,
		}, 2)
		grad(shelf, Color3.fromRGB(210, 150, 110), Color3.fromRGB(130, 84, 60))
		-- Plante en pot
		local pot = box({ AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.fromOffset(11, 0), Size = UDim2.fromOffset(13, 11), BackgroundColor3 = WHITE, ZIndex = 4, Parent = shelf }, 3)
		grad(pot, Color3.fromRGB(255, 170, 140), Color3.fromRGB(220, 110, 90))
		for i, rotation in ipairs({ -38, -12, 14, 40 }) do
			local leaf = box({
				AnchorPoint = Vector2.new(0.5, 1),
				Position = UDim2.new(0.5, (i - 2.5) * 3, 0, 2),
				Size = UDim2.fromOffset(6, 15 + (i % 2) * 3),
				Rotation = rotation,
				BackgroundColor3 = WHITE,
				ZIndex = 3,
				Parent = pot,
			}, UDim.new(1, 0))
			grad(leaf, Color3.fromRGB(130, 230, 140), Color3.fromRGB(50, 150, 90))
		end
		-- Livres
		for i, spec in ipairs({ { 24, 15, Color3.fromRGB(120, 180, 255) }, { 29, 18, Color3.fromRGB(255, 214, 90) }, { 34, 13, Color3.fromRGB(180, 120, 255) } }) do
			local book = box({ AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.fromOffset(spec[1], 0), Size = UDim2.fromOffset(4.5, spec[2]), BackgroundColor3 = spec[3], ZIndex = 4, Parent = shelf }, 1)
			if i == 3 then
				book.Rotation = 12
				book.Position = UDim2.fromOffset(spec[1] + 1, 0)
			end
		end
		-- Trophée de créatrice (argent 5 / or 10 / diamant 15)
		trophy = box({ Name = "Award", AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.fromOffset(50, 0), Size = UDim2.fromOffset(17, 21), BackgroundColor3 = WHITE, Visible = false, ZIndex = 4, Parent = shelf }, 2)
		trophyGradient = grad(trophy, Color3.fromRGB(240, 240, 250), Color3.fromRGB(150, 150, 170), 45)
		local trophyInner = box(at({ BackgroundColor3 = Color3.fromRGB(40, 30, 60), ZIndex = 4, Parent = trophy }, 8.5, 9, 11, 12), 2)
		text({ Text = "♥", Font = Theme.Fonts.Title, TextSize = 9, TextColor3 = Color3.fromRGB(255, 90, 140), Size = UDim2.fromScale(1, 1), ZIndex = 5, Parent = trophyInner })

		-- Enseigne néon "miam" (à droite, grésille)
		neonSign = text({
			Name = "Neon",
			Text = Locale.T("yum ♥"),
			Font = Enum.Font.FredokaOne,
			TextSize = 16,
			TextColor3 = Color3.fromRGB(255, 130, 210),
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.new(1, -10, 0, 38),
			Size = UDim2.fromOffset(62, 22),
			Rotation = -5,
			ZIndex = 3,
			Parent = wallLayer,
		})
		local neonStroke = UI.Stroke(neonSign, Color3.fromRGB(255, 210, 245), 1.5, 0.35)
		neonStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
	end

	-- Lumières bokeh floues (studio niveau 5)
	local bokehGroup = layer("Bokeh", 2, wallLayer)
	local bokeh: { { Frame: Frame, Phase: number, Base: number } } = {}
	for i, spec in ipairs({ { 0.2, 40, 16 }, { 0.33, 58, 10 }, { 0.62, 30, 14 }, { 0.78, 62, 11 }, { 0.12, 96, 12 }, { 0.9, 104, 15 } }) do
		local dot = round({
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.new(spec[1], 0, 0, spec[2]),
			Size = UDim2.fromOffset(spec[3], spec[3]),
			BackgroundColor3 = BOKEH_COLORS[(i - 1) % #BOKEH_COLORS + 1],
			BackgroundTransparency = 0.7,
			ZIndex = 1,
			Parent = bokehGroup,
		})
		UI.Stroke(dot, BOKEH_COLORS[(i - 1) % #BOKEH_COLORS + 1], 1, 0.5)
		table.insert(bokeh, { Frame = dot, Phase = random:NextNumber(0, math.pi * 2), Base = 0.72 })
	end

	------------------------------------------------------------------
	-- Lumières derrière la streameuse : halo doux + ring light (studio 1)
	------------------------------------------------------------------
	local softGlow: Frame, ringGroup: Frame, ringHaloStroke: UIStroke, ringStroke: UIStroke
	do
		softGlow = round(atC({ Name = "Glow", BackgroundColor3 = Color3.fromRGB(255, 226, 240), BackgroundTransparency = 0.84, ZIndex = 1, Parent = lightLayer }, 0, HEAD_Y + 6, 150, 150))
		ringGroup = layer("RingLight", 2, lightLayer)
		box(atC({ Name = "Pole", AnchorPoint = Vector2.new(0.5, 0), BackgroundColor3 = Color3.fromRGB(40, 36, 52), ZIndex = 1, Parent = ringGroup }, 0, HEAD_Y + RING / 2, 4, 60))
		local ringHalo = round(atC({ Name = "Halo", BackgroundTransparency = 1, ZIndex = 1, Parent = ringGroup }, 0, HEAD_Y, RING + 10, RING + 10))
		ringHaloStroke = UI.Stroke(ringHalo, Color3.fromRGB(255, 220, 245), 10, 0.75)
		local ringLight = round(atC({ Name = "Ring", BackgroundColor3 = Color3.fromRGB(255, 245, 250), BackgroundTransparency = 0.9, ZIndex = 2, Parent = ringGroup }, 0, HEAD_Y, RING, RING))
		ringStroke = UI.Stroke(ringLight, WHITE, 6, 0.05)
		UI.Gradient(ringStroke, ColorSequence.new(WHITE, Color3.fromRGB(255, 226, 246)), 90)
		-- Petites LED sur l'anneau
		for i = 0, 11 do
			local angle = i / 12 * math.pi * 2
			round(at({ BackgroundColor3 = Color3.fromRGB(255, 250, 230), BackgroundTransparency = 0.2, ZIndex = 3, Parent = ringLight }, RING / 2 + math.cos(angle) * RING / 2, RING / 2 + math.sin(angle) * RING / 2, 2.5, 2.5))
		end
	end

	------------------------------------------------------------------
	-- La streameuse (dessinée en formes, cadre de 120 x 120)
	------------------------------------------------------------------
	local streamer = box({
		Name = "Streamer",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 0, STREAMER_Y),
		Size = UDim2.fromOffset(120, 120),
		BackgroundTransparency = 1,
		ZIndex = 1,
		Parent = streamerLayer,
	})

	do
		-- Cheveux (arrière) : longs, tombent derrière les épaules
		local backHair = box(at({ Name = "BackHair", BackgroundColor3 = WHITE, ZIndex = 1, Parent = streamer }, 60, 60, 72, 84), 26)
		grad(backHair, HAIR_LIGHT:Lerp(HAIR, 0.4), HAIR:Lerp(Color3.new(0, 0, 0), 0.25))
		-- Cou
		box(at({ Name = "Neck", BackgroundColor3 = SKIN_SHADE, ZIndex = 2, Parent = streamer }, 60, 74, 15, 16), 5)
		-- Sweat à capuche
		local torso = box(at({ Name = "Torso", BackgroundColor3 = WHITE, ZIndex = 3, Parent = streamer }, 60, 106, 96, 60), 26)
		UI.Gradient(torso, ColorSequence.new({
			ColorSequenceKeypoint.new(0, HOODIE:Lerp(WHITE, 0.2)),
			ColorSequenceKeypoint.new(0.55, HOODIE),
			ColorSequenceKeypoint.new(1, HOODIE_DARK),
		}), 90)
		-- Capuche autour du cou
		local hood = box(at({ Name = "Hood", BackgroundColor3 = WHITE, ZIndex = 4, Parent = streamer }, 60, 82, 54, 15), 7)
		grad(hood, HOODIE_DARK:Lerp(WHITE, 0.15), HOODIE_DARK)
		box(at({ BackgroundColor3 = SKIN_SHADE, ZIndex = 4, Parent = hood }, 27, 4, 20, 7), 4)
		-- Cordons + embouts
		for _, x in ipairs({ 53, 67 }) do
			box({ AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.fromOffset(x, 86), Size = UDim2.fromOffset(2, 15), BackgroundColor3 = Color3.fromRGB(250, 246, 255), ZIndex = 5, Parent = streamer }, 1)
			box(at({ BackgroundColor3 = Color3.fromRGB(200, 200, 220), ZIndex = 5, Parent = streamer }, x, 102, 3, 4), 1)
		end
	end
	-- Motif sur le sweat
	text({
		Text = "♥",
		Font = Theme.Fonts.Title,
		TextSize = 13,
		TextColor3 = WHITE,
		TextTransparency = 0.1,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromOffset(60, 112),
		Size = UDim2.fromOffset(14, 14),
		ZIndex = 5,
		Parent = streamer,
	})
	-- Mèches qui tombent DEVANT les épaules
	for _, x in ipairs({ 31, 89 }) do
		local lock = box(at({ Name = "FrontLock", BackgroundColor3 = WHITE, ZIndex = 6, Parent = streamer }, x, 86, 14, 24), 7)
		grad(lock, HAIR:Lerp(HAIR_LIGHT, 0.3), HAIR)
	end

	-- Tête (support qui tourne : tout ce qui est dedans bouge avec).
	-- Pas de ClipsDescendants ici : le découpage ne marche pas sur un
	-- objet tourné, les yeux fermés sont donc des formes à part.
	local head = box(at({ Name = "Head", BackgroundTransparency = 1, ZIndex = 7, Parent = streamer }, 60, 44, 64, 64))
	local function part(props: { [string]: any }, x: number, y: number, w: number, h: number, radius: (number | UDim)?): Frame
		props.Parent = props.Parent or head
		return box(at(props, x, y, w, h), radius)
	end

	-- Casque : écouteurs (derrière les mèches), arceau et oreilles de chat
	local cupStrokes: { UIStroke } = {}
	local earGlows: { Frame } = {}
	local eyes: { Eye } = {}
	local blushes: { Frame } = {}
	local smile: Frame, catMouth: Frame, mouth: Frame, teeth: Frame, tongue: Frame
	do
		for _, x in ipairs({ 14, 50 }) do
			-- Oreilles de chat (losanges, la moitié basse est cachée par les cheveux)
			local ear = part({ Name = "CatEar", BackgroundColor3 = PHONES, Rotation = 45, ZIndex = 1 }, x, -1, 16, 16, 3)
			earGlows[#earGlows + 1] = part({ Name = "EarGlow", BackgroundColor3 = PHONES_GLOW, ZIndex = 2, Parent = ear }, 7, 7, 8, 8, 2)
		end
		local face = part({ Name = "Face", BackgroundColor3 = WHITE, ZIndex = 3 }, 32, 34, 50, 49, UDim.new(0.46, 0))
		grad(face, SKIN, SKIN_SHADE)
		-- Frange : calotte + mèches pointues
		local cap = part({ Name = "Bangs", BackgroundColor3 = WHITE, ZIndex = 6 }, 32, 13, 60, 27, 13)
		grad(cap, HAIR_LIGHT:Lerp(HAIR, 0.35), HAIR)
		for _, spec in ipairs({ { 13, 22, 11, 15, 28 }, { 24, 24, 11, 16, 10 }, { 40, 24, 11, 16, -10 }, { 51, 22, 11, 15, -28 }, { 32, 23, 8, 12, 0 } }) do
			local tip = part({ Name = "Fringe", BackgroundColor3 = WHITE, Rotation = spec[5], ZIndex = 6 }, spec[1], spec[2], spec[3], spec[4], 5)
			grad(tip, HAIR:Lerp(HAIR_LIGHT, 0.25), HAIR)
		end
		-- Mèches sur les côtés du visage
		for _, x in ipairs({ 7, 57 }) do
			local side = part({ Name = "SideLock", BackgroundColor3 = WHITE, ZIndex = 6 }, x, 38, 11, 42, 5)
			grad(side, HAIR:Lerp(HAIR_LIGHT, 0.2), HAIR)
		end
		part({ Name = "HairShine", BackgroundColor3 = HAIR_LIGHT:Lerp(WHITE, 0.4), BackgroundTransparency = 0.25, Rotation = -12, ZIndex = 7 }, 20, 7, 15, 3.5, 2)
		-- Barrette étoile
		text({ Text = "★", Font = Theme.Fonts.Title, TextSize = 10, TextColor3 = Color3.fromRGB(255, 226, 110), AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromOffset(49, 14), Size = UDim2.fromOffset(10, 10), Rotation = 15, ZIndex = 8, Parent = head })
		-- Arceau (haut d'un cercle)
		local band = round(at({ Name = "Band", BackgroundTransparency = 1, ZIndex = 8, Parent = head }, 32, 30, 68, 64))
		local bandStroke = UI.Stroke(band, WHITE, 5, 0)
		UI.Create("UIGradient", { Rotation = 90, Color = ColorSequence.new(PHONES:Lerp(WHITE, 0.25), PHONES), Transparency = UPPER_ARC, Parent = bandStroke })
		for _, x in ipairs({ -1, 65 }) do
			local cup = part({ Name = "Cup", BackgroundColor3 = WHITE, ZIndex = 9 }, x, 36, 13, 23, 6)
			grad(cup, PHONES:Lerp(WHITE, 0.2), PHONES)
			table.insert(cupStrokes, UI.Stroke(cup, PHONES_GLOW, 1.5, 0.1))
			part({ BackgroundColor3 = PHONES_GLOW, ZIndex = 10, Parent = cup }, 6.5, 11.5, 4, 11, 2)
		end

		-- Yeux : ouverts (blanc, iris, pupille, reflets, cils) / fermés contents (∩) / fermés détendus (◡)
		-- (eyes : déclaré plus haut)
		for i, x in ipairs({ 21, 43 }) do
			local side = i == 1 and -1 or 1
			local open = part({ Name = "Eye", BackgroundTransparency = 1, ZIndex = 4 }, x, 37, 14, 15)
			local sclera = part({ Name = "White", BackgroundColor3 = WHITE, ZIndex = 4, Parent = open }, 7, 8, 11, 12, UDim.new(1, 0))
			local iris = part({ Name = "Iris", BackgroundColor3 = WHITE, ZIndex = 5, Parent = sclera }, 5.5, 6.5, 8.5, 9.5, UDim.new(1, 0))
			grad(iris, IRIS_TOP, IRIS_BOTTOM)
			part({ Name = "Pupil", BackgroundColor3 = Color3.fromRGB(30, 14, 40), ZIndex = 6, Parent = iris }, 4.25, 5, 4, 5, UDim.new(1, 0))
			part({ Name = "Shine", BackgroundColor3 = WHITE, ZIndex = 7, Parent = iris }, 2.8, 3, 3.2, 3.2, UDim.new(1, 0))
			part({ Name = "Shine2", BackgroundColor3 = WHITE, BackgroundTransparency = 0.2, ZIndex = 7, Parent = iris }, 6, 7, 1.6, 1.6, UDim.new(1, 0))
			-- Cils du haut + petit trait au coin extérieur
			local lash = part({ Name = "Lash", BackgroundColor3 = INK, Rotation = side * 8, ZIndex = 8, Parent = open }, 7, 2.5, 13, 2, 1)
			part({ BackgroundColor3 = INK, Rotation = side * 35, ZIndex = 8, Parent = lash }, side > 0 and 14 or 0, 0, 5, 2, 1)
			local happy = arc(at({ Name = "Happy", Visible = false, ZIndex = 5, Parent = head }, x, 39, 11, 10), INK, 2, UPPER_ARC)
			local relaxed = arc(at({ Name = "Closed", Visible = false, ZIndex = 5, Parent = head }, x, 34, 12, 10), INK, 2, LOWER_ARC)
			local brow = part({ Name = "Brow", BackgroundColor3 = HAIR:Lerp(HAIR_LIGHT, 0.2), ZIndex = 7 }, x, 27, 9, 1.8, 1)
			eyes[i] = { Open = open, Sclera = sclera, Iris = iris, Lash = lash, Happy = happy, Relaxed = relaxed, Brow = brow, X = x, Side = side }
		end
		-- Joues, nez
		-- (blushes : déclaré plus haut)
		for _, x in ipairs({ 15, 49 }) do
			table.insert(blushes, part({ Name = "Blush", BackgroundColor3 = Color3.fromRGB(255, 120, 150), BackgroundTransparency = 0.5, ZIndex = 4 }, x, 46, 10, 5, UDim.new(1, 0)))
		end
		part({ Name = "Nose", BackgroundColor3 = SKIN_SHADE:Lerp(Color3.fromRGB(200, 120, 110), 0.45), ZIndex = 4 }, 32, 45, 3, 2, 1)
		-- Bouches : sourire (◡), bouche de chat (ω), bouche ouverte (dents + langue)
		smile = arc(at({ Name = "Smile", ZIndex = 5, Parent = head }, 32, 47, 10, 9), Color3.fromRGB(150, 50, 70), 1.8, LOWER_ARC)
		catMouth = box(at({ Name = "CatMouth", BackgroundTransparency = 1, Visible = false, ZIndex = 5, Parent = head }, 32, 50, 12, 6))
		for _, x in ipairs({ 3, 9 }) do
			arc(at({ ZIndex = 5, Parent = catMouth }, x, 1, 6, 6), Color3.fromRGB(150, 50, 70), 1.6, LOWER_ARC)
		end
		mouth = part({ Name = "Mouth", BackgroundColor3 = Color3.fromRGB(116, 30, 56), Visible = false, ZIndex = 5 }, 32, 51, 10, 8, UDim.new(1, 0))
		teeth = box({ Name = "Teeth", AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 1), Size = UDim2.new(0.7, 0, 0, 2.5), BackgroundColor3 = WHITE, ZIndex = 6, Parent = mouth }, 1)
		tongue = box({ Name = "Tongue", AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, 0), Size = UDim2.fromScale(0.65, 0.45), BackgroundColor3 = Color3.fromRGB(255, 120, 140), ZIndex = 6, Parent = mouth }, UDim.new(1, 0))
	end

	------------------------------------------------------------------
	-- Table, set de table, assiette, bol, bubble tea, micro
	------------------------------------------------------------------
	-- Coins du bas arrondis comme la vidéo (ClipsDescendants découpe en
	-- rectangle : sans ça, coins carrés qui dépassent du cadre arrondi)
	local cup: Frame
	do
		local tableTop, tableBottom = Color3.fromRGB(238, 196, 150), Color3.fromRGB(176, 118, 80)
		local tableFrame = box({
			Name = "Table",
			Position = UDim2.fromOffset(0, TABLE_Y),
			Size = UDim2.new(1, 0, 1, -TABLE_Y),
			BackgroundColor3 = WHITE,
			ZIndex = 1,
			Parent = tableLayer,
		}, VIDEO_RADIUS)
		UI.Gradient(tableFrame, ColorSequence.new(tableTop, tableBottom), 90)
		-- ... et coins du haut bien carrés (bande du même dégradé par-dessus)
		local tableCap = box({ Size = UDim2.new(1, 0, 0, VIDEO_RADIUS), BackgroundColor3 = WHITE, ZIndex = 1, Parent = tableFrame })
		UI.Gradient(tableCap, ColorSequence.new(tableTop, tableTop:Lerp(tableBottom, VIDEO_RADIUS / (VIDEO_H - TABLE_Y))), 90)
		-- Arête arrière éclairée + ombre portée de la streameuse
		box({ Size = UDim2.new(1, 0, 0, 2), BackgroundColor3 = Color3.fromRGB(255, 226, 190), ZIndex = 2, Parent = tableFrame })
		local shadow = box({ AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 2), Size = UDim2.fromOffset(120, 10), BackgroundColor3 = Color3.fromRGB(110, 60, 60), BackgroundTransparency = 0.7, ZIndex = 2, Parent = tableFrame }, UDim.new(1, 0))
		UI.Gradient(shadow, ColorSequence.new(WHITE), 90).Transparency = NumberSequence.new(0.2, 1)
		-- Veines du bois
		for i, y in ipairs({ 14, 27, 40, 52 }) do
			box({ Position = UDim2.new(0.08 * i - 0.05, 0, 0, y), Size = UDim2.new(0.45, 0, 0, 1), BackgroundColor3 = Color3.fromRGB(150, 96, 60), BackgroundTransparency = 0.6, ZIndex = 2, Parent = tableFrame })
		end
		-- Set de table rose sous l'assiette
		local mat = box(atC({ Name = "Placemat", BackgroundColor3 = WHITE, ZIndex = 3, Parent = tableFrame }, 0, PLATE_Y - TABLE_Y + 2, 120, 26), 8)
		grad(mat, Color3.fromRGB(255, 200, 220), Color3.fromRGB(250, 160, 196))
		UI.Stroke(mat, WHITE, 1, 0.5)

		-- Bubble tea (derrière, à droite) : cadre déplaçable (elle le boit)
		local cupHome = UDim2.new(0.5, CUP_X, 0, CUP_BASE)
		cup = box({ Name = "BubbleTea", AnchorPoint = Vector2.new(0.5, 1), Position = cupHome, Size = UDim2.fromOffset(18, 30), BackgroundTransparency = 1, ZIndex = 1, Parent = propsLayer })
		box({ AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.fromOffset(6, 6), Size = UDim2.fromOffset(3.5, 16), Rotation = -12, BackgroundColor3 = Color3.fromRGB(255, 110, 150), ZIndex = 1, Parent = cup }, 1)
		local cupBody = box({ Position = UDim2.fromOffset(0, 3), Size = UDim2.fromOffset(18, 27), BackgroundColor3 = WHITE, ZIndex = 2, Parent = cup }, 4)
		UI.Gradient(cupBody, ColorSequence.new({
			ColorSequenceKeypoint.new(0, Color3.fromRGB(250, 246, 255)),
			ColorSequenceKeypoint.new(0.22, Color3.fromRGB(250, 246, 255)),
			ColorSequenceKeypoint.new(0.24, Color3.fromRGB(236, 200, 170)),
			ColorSequenceKeypoint.new(1, Color3.fromRGB(200, 150, 120)),
		}), 90)
		UI.Stroke(cupBody, WHITE, 1, 0.3)
		box({ Position = UDim2.fromOffset(-1, 0), Size = UDim2.fromOffset(20, 5), BackgroundColor3 = Color3.fromRGB(255, 255, 255), BackgroundTransparency = 0.1, ZIndex = 3, Parent = cup }, 2)
		for i = 0, 5 do
			round(at({ BackgroundColor3 = Color3.fromRGB(60, 36, 30), ZIndex = 3, Parent = cupBody }, 4 + (i % 3) * 5, 22 - math.floor(i / 3) * 4, 4, 4))
		end
		box(at({ BackgroundColor3 = WHITE, BackgroundTransparency = 0.5, ZIndex = 3, Parent = cupBody }, 3.5, 13, 2, 14), 1)

		-- Bol de nouilles fumant (derrière, à gauche)
		local bowl = box(atC({ Name = "Bowl", AnchorPoint = Vector2.new(0.5, 1), BackgroundTransparency = 1, ZIndex = 1, Parent = propsLayer }, BOWL_X, BOWL_BASE, 38, 22))
		local bowlBody = box({ Position = UDim2.fromOffset(2, 6), Size = UDim2.fromOffset(34, 16), BackgroundColor3 = WHITE, ZIndex = 1, Parent = bowl }, UDim.new(0.5, 0))
		grad(bowlBody, Color3.fromRGB(255, 120, 120), Color3.fromRGB(190, 60, 80))
		box({ Position = UDim2.fromOffset(4, 12), Size = UDim2.fromOffset(30, 2), BackgroundColor3 = WHITE, BackgroundTransparency = 0.2, ZIndex = 2, Parent = bowl }, 1)
		local rim = box({ Position = UDim2.fromOffset(0, 3), Size = UDim2.fromOffset(38, 8), BackgroundColor3 = Color3.fromRGB(255, 236, 236), ZIndex = 2, Parent = bowl }, UDim.new(1, 0))
		local broth = box(at({ BackgroundColor3 = WHITE, ZIndex = 2, Parent = rim }, 19, 4, 32, 5), UDim.new(1, 0))
		grad(broth, Color3.fromRGB(255, 210, 110), Color3.fromRGB(230, 150, 60))
		for i = 0, 2 do
			box(at({ BackgroundColor3 = Color3.fromRGB(255, 236, 170), Rotation = (i - 1) * 12, ZIndex = 3, Parent = rim }, 12 + i * 7, 3.5, 7, 1.6), 1)
		end
		round(at({ BackgroundColor3 = WHITE, ZIndex = 3, Parent = rim }, 27, 3.5, 6, 4))
		round(at({ BackgroundColor3 = Color3.fromRGB(255, 190, 60), ZIndex = 4, Parent = rim }, 27, 3.5, 3, 2.5))
		-- Baguettes dans le bol
		for i, rotation in ipairs({ 58, 66 }) do
			box({ AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.fromOffset(28 + i * 2, 7), Size = UDim2.fromOffset(1.8, 22), Rotation = rotation, BackgroundColor3 = Color3.fromRGB(150, 96, 60), ZIndex = 0, Parent = bowl }, 1)
		end

		-- Assiette
		local plate = box(atC({ Name = "Plate", BackgroundColor3 = WHITE, ZIndex = 2, Parent = propsLayer }, 0, PLATE_Y, 90, 20), UDim.new(1, 0))
		grad(plate, Color3.fromRGB(255, 255, 255), Color3.fromRGB(214, 214, 230))
		UI.Stroke(plate, Color3.fromRGB(190, 184, 210), 1.2)
		box(at({ BackgroundColor3 = Color3.fromRGB(236, 234, 246), ZIndex = 2, Parent = plate }, 45, 10.5, 68, 12), UDim.new(1, 0))
	end

	-- Micro ASMR "moumoute" sur pied + voyant ON
	local micLed: Frame, proMic: Frame
	do
		local micHolder = box({ Name = "FluffyMic", AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0, MIC_LEFT, 0, TABLE_Y + 32), Size = UDim2.fromOffset(40, 52), BackgroundTransparency = 1, ZIndex = 3, Parent = propsLayer })
		box({ AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, 0), Size = UDim2.fromOffset(26, 5), BackgroundColor3 = Color3.fromRGB(60, 58, 72), ZIndex = 1, Parent = micHolder }, 2)
		box({ AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -3), Size = UDim2.fromOffset(4, 22), BackgroundColor3 = Color3.fromRGB(70, 68, 84), ZIndex = 1, Parent = micHolder })
		local mic = round(at({ Name = "Mic", BackgroundColor3 = WHITE, ZIndex = 3, Parent = micHolder }, 20, 18, 25, 30))
		grad(mic, Color3.fromRGB(236, 232, 244), Color3.fromRGB(170, 166, 186), 60)
		for i = 0, 7 do
			local angle = i / 8 * math.pi * 2
			round(at({ BackgroundColor3 = Color3.fromRGB(190, 184, 206), ZIndex = 2, Parent = micHolder }, 20 + math.cos(angle) * 11, 18 + math.sin(angle) * 14, 11, 11))
		end
		micLed = round(at({ BackgroundColor3 = Color3.fromRGB(255, 50, 70), ZIndex = 4, Parent = micHolder }, 20, 38, 5, 5))

		-- Micro pro sur bras articulé (studio 3) : descend du coin en haut à gauche
		proMic = layer("ProMic", 1, propsLayer)
		local boom1 = box({ BackgroundColor3 = Color3.fromRGB(44, 42, 56), ZIndex = 1, Parent = proMic }, 2)
		local boom2 = box({ BackgroundColor3 = Color3.fromRGB(44, 42, 56), ZIndex = 1, Parent = proMic }, 2)
		-- (positionnés par setLimb, depuis le centre de la vidéo)
		local proMicBody = box(atC({ Name = "Capsule", BackgroundColor3 = WHITE, Rotation = -28, ZIndex = 3, Parent = proMic }, PRO_X, PRO_Y, 13, 30), 6)
		UI.Gradient(proMicBody, ColorSequence.new({
			ColorSequenceKeypoint.new(0, Color3.fromRGB(150, 146, 166)),
			ColorSequenceKeypoint.new(0.5, Color3.fromRGB(96, 92, 112)),
			ColorSequenceKeypoint.new(0.52, Color3.fromRGB(40, 38, 52)),
			ColorSequenceKeypoint.new(1, Color3.fromRGB(58, 56, 72)),
		}), 90)
		-- Grille du micro + bague dorée
		for i = 0, 3 do
			box(at({ BackgroundColor3 = WHITE, BackgroundTransparency = 0.7, ZIndex = 4, Parent = proMicBody }, 6.5, 3 + i * 3, 10, 1), 1)
		end
		box(at({ BackgroundColor3 = Color3.fromRGB(255, 206, 110), ZIndex = 4, Parent = proMicBody }, 6.5, 15.5, 13, 2), 1)
		-- Suspension antichoc (deux anneaux)
		for i = 0, 1 do
			local ring = round(atC({ BackgroundTransparency = 1, Rotation = -28, ZIndex = 2 + i * 3, Parent = proMic }, PRO_X + 2 - i * 4, PRO_Y + 4 + i * 6, 22, 7))
			UI.Stroke(ring, Color3.fromRGB(34, 32, 44), 1.5)
		end
		-- Bras articulé (depuis le haut de l'image) + articulation
		setLimb(boom1, -96, -12, PRO_X - 20, PRO_Y - 44, 3.5)
		setLimb(boom2, PRO_X - 20, PRO_Y - 44, PRO_X + 5, PRO_Y + 11, 3.5)
		round(atC({ BackgroundColor3 = Color3.fromRGB(90, 88, 108), ZIndex = 2, Parent = proMic }, PRO_X - 20, PRO_Y - 44, 6, 6))
	end

	-- Ondes sonores (réserve de 2 anneaux)
	local waves: { { Frame: Frame, Stroke: UIStroke } } = {}
	for i = 1, 2 do
		local ring = round(atC({ Name = "Wave" .. i, BackgroundTransparency = 1, ZIndex = 6, Parent = propsLayer }, 0, 0, 24, 24))
		waves[i] = { Frame = ring, Stroke = UI.Stroke(ring, WHITE, 2, 1) }
	end
	local waveIndex = 0
	local function micPosition(): UDim2
		if proMic.Visible then
			return UDim2.new(0.5, PRO_X, 0, PRO_Y)
		end
		return UDim2.new(0, MIC_LEFT, 0, TABLE_Y - 2)
	end
	local function soundWave(origin: UDim2?)
		if not effectsOn() then
			return
		end
		waveIndex = waveIndex % #waves + 1
		local wave = waves[waveIndex]
		wave.Frame.Position = origin or micPosition()
		wave.Frame.Size = UDim2.fromOffset(22, 22)
		UI.Tween(wave.Frame, 0.55, { Size = UDim2.fromOffset(70, 70) }, Enum.EasingStyle.Quad)
		wave.Stroke.Transparency = 0.1
		UI.Tween(wave.Stroke, 0.55, { Transparency = 1 }, Enum.EasingStyle.Quad)
	end

	------------------------------------------------------------------
	-- Le beurre croustillant (Feature "Butter")
	------------------------------------------------------------------
	local butterHome = UDim2.new(BUTTER_X, 0, 0, BUTTER_Y)
	local butterButton = UI.Create("TextButton", {
		Name = "Butter",
		Text = "",
		AutoButtonColor = false,
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 1),
		Position = butterHome,
		Size = UDim2.fromOffset(BUTTON_W, BUTTON_H),
		Visible = hasButter(),
		ZIndex = 4,
		Parent = propsLayer,
	})
	local butterScale = UI.Create("UIScale", { Parent = butterButton })
	-- Coupelle en porcelaine bleue
	local dish = box({
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, 0),
		Size = UDim2.fromOffset(BUTTON_W - 4, 13),
		BackgroundColor3 = WHITE,
		ZIndex = 1,
		Parent = butterButton,
	}, UDim.new(1, 0))
	grad(dish, WHITE, Color3.fromRGB(150, 190, 240))
	UI.Stroke(dish, Color3.fromRGB(90, 130, 200), 1.5)
	box(at({ BackgroundColor3 = Color3.fromRGB(110, 150, 220), BackgroundTransparency = 0.4, ZIndex = 1, Parent = dish }, (BUTTON_W - 4) / 2, 9, BUTTON_W - 16, 2), 1)
	-- Bloc (les traces de dents sont dedans, coupées par ClipsDescendants)
	local block = box({
		Name = "Block",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -6),
		Size = UDim2.fromOffset(BUTTER_W, BUTTER_H),
		BackgroundColor3 = WHITE,
		ClipsDescendants = true,
		ZIndex = 2,
		Parent = butterButton,
	}, 5)
	UI.Gradient(block, ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 244, 160)),
		ColorSequenceKeypoint.new(0.3, Color3.fromRGB(255, 226, 96)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(236, 184, 50)),
	}), 90)
	UI.Stroke(block, Color3.fromRGB(196, 140, 30), 1.5)
	-- Face du dessus (plus claire) + reflet brillant
	box({ Size = UDim2.new(1, 0, 0, 7), BackgroundColor3 = Color3.fromRGB(255, 250, 200), BackgroundTransparency = 0.2, ZIndex = 3, Parent = block })
	local shine = box({ Position = UDim2.fromOffset(5, 10), Size = UDim2.fromOffset(15, 4), BackgroundColor3 = WHITE, BackgroundTransparency = 0.25, ZIndex = 4, Parent = block }, 2)
	local sparkle = text({
		Text = "✨",
		TextSize = 13,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 17, 0, 24),
		Size = UDim2.fromOffset(14, 14),
		TextTransparency = 1,
		ZIndex = 6,
		Parent = butterButton,
	})
	-- Indice "CROQUE !" tant qu'on ne l'a pas croqué (flotte au-dessus du bloc)
	local butterHint = text({
		Text = Locale.T("BITE!"),
		Font = Theme.Fonts.Title,
		TextSize = 11,
		TextColor3 = Color3.fromRGB(90, 50, 0),
		BackgroundColor3 = Color3.fromRGB(255, 226, 96),
		BackgroundTransparency = 0,
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 0, HINT_Y),
		Size = UDim2.fromOffset(BUTTON_W, 15),
		ZIndex = 6,
		Parent = butterButton,
	})
	UI.Corner(butterHint, UDim.new(1, 0))
	UI.Stroke(butterHint, Color3.fromRGB(196, 140, 30), 1)

	local bites: { Frame } = {}
	local regenerating = false

	-- Une trace de dents : demi-disque "intérieur" sur le bord du dessus
	local function addBite()
		local size = random:NextInteger(13, 18)
		local slot = #bites
		-- Les bouchées avancent de droite à gauche (puis au hasard)
		local x = slot < 5 and (1 - slot * 0.2 - 0.05) or random:NextNumber(0.1, 0.9)
		local bite = box({
			Name = "Bite",
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.new(x, 0, 0, random:NextInteger(-1, 2)),
			Size = UDim2.fromOffset(size, size),
			BackgroundColor3 = Color3.fromRGB(255, 246, 206),
			ZIndex = 5,
			Parent = block,
		}, UDim.new(1, 0))
		UI.Stroke(bite, Color3.fromRGB(214, 160, 48), 1)
		table.insert(bites, bite)
	end

	------------------------------------------------------------------
	-- Bras articulés (épaule -> coude -> main), dessinés au-dessus de la table
	------------------------------------------------------------------
	type Arm = {
		Side: number,
		Upper: Frame,
		Fore: Frame,
		Hand: Frame,
		X: number, -- position actuelle de la main (depuis le centre de la vidéo)
		Y: number,
		TX: number, -- cible
		TY: number,
		RestX: number,
		RestY: number,
		DirX: number, -- direction de l'avant-bras (normalisée)
		DirY: number,
		Tip: number, -- longueur de l'outil tenu (baguettes) au-delà de la main
	}
	local function makeArm(side: number, restX: number, restY: number, chopsticks: boolean): Arm
		local upper = box({ Name = "UpperArm", AnchorPoint = Vector2.new(0.5, 0.5), BackgroundColor3 = WHITE, ZIndex = 1, Parent = armsLayer }, UDim.new(1, 0))
		UI.Gradient(upper, ColorSequence.new(HOODIE:Lerp(WHITE, 0.1), HOODIE:Lerp(HOODIE_DARK, 0.35)), side > 0 and 180 or 0)
		UI.Stroke(upper, HOODIE_DARK, 1, 0.35)
		local fore = box({ Name = "Forearm", AnchorPoint = Vector2.new(0.5, 0.5), BackgroundColor3 = WHITE, ZIndex = 2, Parent = armsLayer }, UDim.new(1, 0))
		UI.Gradient(fore, SLEEVE, 90)
		UI.Stroke(fore, HOODIE_DARK, 1, 0.35)
		-- Main : paume + pouce + plis des doigts (l'axe +Y local suit l'avant-bras)
		local hand = box({ Name = "Hand", AnchorPoint = Vector2.new(0.5, 0.5), Size = UDim2.fromOffset(13, 13), BackgroundTransparency = 1, ZIndex = 3, Parent = armsLayer })
		if chopsticks then
			for i, rotation in ipairs({ -10, -2 }) do
				local stick = box({ Name = "Chopstick", AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.fromOffset(6.5 + (i - 1.5) * 3, 5), Size = UDim2.fromOffset(1.8, 26), Rotation = rotation, BackgroundColor3 = WHITE, ZIndex = 1, Parent = hand }, 1)
				grad(stick, Color3.fromRGB(190, 130, 80), Color3.fromRGB(120, 70, 40))
			end
		end
		local palm = box(at({ Name = "Palm", BackgroundColor3 = WHITE, ZIndex = 2, Parent = hand }, 6.5, 6.5, 13, 13), UDim.new(0.45, 0))
		grad(palm, SKIN, SKIN_SHADE)
		local thumb = box(at({ Name = "Thumb", BackgroundColor3 = SKIN, Rotation = side * -30, ZIndex = 3, Parent = hand }, 6.5 - side * 6, 5, 4.5, 8), UDim.new(1, 0))
		thumb.BackgroundColor3 = SKIN
		for i = 0, 2 do
			box(at({ BackgroundColor3 = SKIN_SHADE:Lerp(Color3.fromRGB(190, 120, 110), 0.4), BackgroundTransparency = 0.3, ZIndex = 3, Parent = palm }, 4 + i * 2.6, 10, 1, 4), 1)
		end
		return {
			Side = side,
			Upper = upper,
			Fore = fore,
			Hand = hand,
			X = restX,
			Y = restY,
			TX = restX,
			TY = restY,
			RestX = restX,
			RestY = restY,
			DirX = 0,
			DirY = 1,
			Tip = chopsticks and 27 or 4,
		}
	end
	local leftArm = makeArm(-1, -40, TABLE_Y + 14, false)
	local rightArm = makeArm(1, 34, TABLE_Y + 8, true)

	-- Cinématique inverse à 2 os : le coude plie vers l'extérieur
	local function solveArm(arm: Arm, bodyBob: number)
		local sx, sy = arm.Side * SHOULDER_X, SHOULDER_Y + bodyBob
		local dx, dy = arm.X - sx, arm.Y - sy
		local distance = math.sqrt(dx * dx + dy * dy)
		local ux, uy = 0, 1
		if distance > 0.001 then
			ux, uy = dx / distance, dy / distance
		end
		local a, b = UPPER_LEN, FORE_LEN
		local d = math.clamp(distance, math.abs(a - b) + 0.5, a + b - 0.5)
		local cosA = math.clamp((a * a + d * d - b * b) / (2 * a * d), -1, 1)
		local sinA = math.sqrt(1 - cosA * cosA)
		local nx, ny = arm.Side * uy, -arm.Side * ux
		local ex, ey = sx + a * (ux * cosA + nx * sinA), sy + a * (uy * cosA + ny * sinA)
		local hx, hy = sx + ux * d, sy + uy * d
		setLimb(arm.Upper, sx, sy, ex, ey, 13)
		setLimb(arm.Fore, ex, ey, hx, hy, 11.5)
		local fx, fy = hx - ex, hy - ey
		local fl = math.max(0.001, math.sqrt(fx * fx + fy * fy))
		arm.DirX, arm.DirY = fx / fl, fy / fl
		arm.Hand.Position = UDim2.new(0.5, hx, 0, hy)
		arm.Hand.Rotation = math.deg(math.atan2(-fx, fy))
	end

	-- Cible de la main pour que le BOUT de l'outil (baguettes) arrive en (x, y)
	local function aimTip(arm: Arm, x: number, y: number)
		arm.TX, arm.TY = x - arm.DirX * arm.Tip, y - arm.DirY * arm.Tip
	end

	local function tipPosition(arm: Arm): (number, number)
		return arm.X + arm.DirX * arm.Tip, arm.Y + arm.DirY * arm.Tip
	end

	------------------------------------------------------------------
	-- Aliments, particules, onomatopées, cœurs, vapeur
	------------------------------------------------------------------
	local foods: { TextLabel } = {}
	local foodScales: { UIScale } = {}
	local function foodHome(index: number): UDim2
		return UDim2.new(0.5, FOOD_OFFSETS[index], 0, FOOD_Y)
	end
	for i = 1, #FOOD_OFFSETS do
		local food = text({
			Name = "Food",
			Text = pick(FOODS, random),
			TextSize = 21,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = foodHome(i),
			Size = UDim2.fromOffset(26, 26),
			Rotation = random:NextNumber(-12, 12),
			ZIndex = 2 + i % 2,
			Parent = fxLayer,
		})
		foods[i] = food
		foodScales[i] = UI.Create("UIScale", { Parent = food })
	end

	-- Miettes / éclats de beurre : réserve fixe, animée par la boucle de rendu
	type Particle = { Frame: Frame, Active: boolean, Age: number, Life: number, X: number, Y: number, VX: number, VY: number, Spin: number, Scale: number }
	local particles: { Particle } = {}
	for i = 1, PARTICLES do
		local f = box({ Name = "Crumb" .. i, AnchorPoint = Vector2.new(0.5, 0.5), Size = UDim2.fromOffset(4, 4), BackgroundColor3 = WHITE, Visible = false, ZIndex = 6, Parent = fxLayer }, 1)
		particles[i] = { Frame = f, Active = false, Age = 0, Life = 0.6, X = 0, Y = 0, VX = 0, VY = 0, Spin = 0, Scale = 0.5 }
	end
	-- (x en Scale de la vidéo + décalage : la vidéo change de largeur)
	local function burstParticles(scaleX: number, x: number, y: number, count: number, colors: { Color3 }, spread: number)
		if not effectsOn() then
			return
		end
		local spawned = 0
		for _, p in ipairs(particles) do
			if spawned >= count then
				break
			end
			if not p.Active then
				spawned += 1
				p.Active = true
				p.Age = 0
				p.Life = random:NextNumber(0.45, 0.7)
				p.Scale = scaleX
				p.X, p.Y = x, y
				p.VX = random:NextNumber(-spread, spread)
				p.VY = random:NextNumber(-90, -30)
				p.Spin = random:NextNumber(-400, 400)
				local size = random:NextInteger(3, 6)
				p.Frame.Size = UDim2.fromOffset(size, size)
				p.Frame.BackgroundColor3 = colors[random:NextInteger(1, #colors)]
				p.Frame.BackgroundTransparency = 0
				p.Frame.Visible = true
			end
		end
	end

	local popLabels: { TextLabel } = {}
	local popIndex = 0
	for i = 1, 3 do
		local label = text({
			Name = "Pop" .. i,
			Text = "",
			Font = Enum.Font.LuckiestGuy,
			TextSize = 22,
			TextTransparency = 1,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Size = UDim2.fromOffset(150, 30),
			ZIndex = 10,
			Parent = fxLayer,
		})
		local stroke = UI.Stroke(label, Color3.fromRGB(40, 20, 30), 2.5, 1)
		stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
		UI.Create("UIScale", { Parent = label })
		popLabels[i] = label
	end

	local function popWord(word: string, position: UDim2, color: Color3?)
		popIndex = popIndex % #popLabels + 1
		local label = popLabels[popIndex]
		local stroke = label:FindFirstChildOfClass("UIStroke")
		local scale = label:FindFirstChildOfClass("UIScale")
		label.Text = word
		label.TextColor3 = color or pick(POP_COLORS, random)
		label.Position = position
		label.Rotation = random:NextNumber(-14, 14)
		label.TextTransparency = 0
		if stroke then
			stroke.Transparency = 0
			UI.Tween(stroke, 0.6, { Transparency = 1 }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		end
		if scale then
			scale.Scale = 0.3
			UI.Tween(scale, 0.22, { Scale = 1.15 }, Enum.EasingStyle.Back)
		end
		UI.Tween(label, 0.8, {
			Position = position + UDim2.fromOffset(random:NextInteger(-10, 10), -30),
			TextTransparency = 1,
		}, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
	end

	local hearts: { { Label: TextLabel, Start: number, Life: number, X: number, Sway: number } } = {}
	for i = 1, MAX_HEARTS do
		local label = text({
			Name = "Heart" .. i,
			Text = "❤️",
			TextSize = 16,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Size = UDim2.fromOffset(20, 20),
			Visible = false,
			ZIndex = 9,
			Parent = fxLayer,
		})
		hearts[i] = { Label = label, Start = -math.huge, Life = 1.6, X = 0, Sway = 0 }
	end
	local function spawnHeart(emoji: string?)
		for _, heart in ipairs(hearts) do
			if not heart.Label.Visible then
				heart.Label.Text = emoji or pick(HEARTS, random)
				heart.Start = os.clock()
				heart.Life = random:NextNumber(1.3, 2)
				heart.X = random:NextNumber(-12, 4)
				heart.Sway = random:NextNumber(0, math.pi * 2)
				heart.Label.Visible = true
				return
			end
		end
	end

	-- Vapeur du bol (3 bouffées recyclées)
	local steam: { Frame } = {}
	for i = 1, 3 do
		steam[i] = round({ Name = "Steam", AnchorPoint = Vector2.new(0.5, 0.5), Size = UDim2.fromOffset(6, 6), BackgroundColor3 = WHITE, BackgroundTransparency = 1, ZIndex = 1, Parent = fxLayer })
	end

	------------------------------------------------------------------
	-- Habillage du live : vignettage, cadre caméra, pastilles, objectif
	------------------------------------------------------------------
	local edgeGradient: UIGradient, liveDot: Frame, viewersLabel: TextLabel, likesLabel: TextLabel, likesScale: UIScale, goalFill: Frame, goalGradient: UIGradient, goalCount: TextLabel
	do
		local topShade = box({ Size = UDim2.new(1, 0, 0, 34), BackgroundColor3 = Color3.fromRGB(10, 6, 20), ZIndex = 1, Parent = overlayLayer })
		UI.Gradient(topShade, ColorSequence.new(WHITE), 90).Transparency = NumberSequence.new(0.45, 1)
		local bottomShade = box({ AnchorPoint = Vector2.new(0, 1), Position = UDim2.fromScale(0, 1), Size = UDim2.new(1, 0, 0, 34), BackgroundColor3 = Color3.fromRGB(10, 6, 20), ZIndex = 1, Parent = overlayLayer }, VIDEO_RADIUS)
		UI.Gradient(bottomShade, ColorSequence.new(WHITE), 90).Transparency = NumberSequence.new(1, 0.4)

		-- Cadre caméra : liseré néon + coins de visée
		local frameEdge = box({ Name = "CamFrame", Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, ZIndex = 2, Parent = overlayLayer }, VIDEO_RADIUS)
		local edgeStroke = UI.Stroke(frameEdge, WHITE, 2, 0.15)
		edgeGradient = UI.Gradient(edgeStroke, ColorSequence.new({
			ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 110, 190)),
			ColorSequenceKeypoint.new(0.5, Color3.fromRGB(160, 110, 255)),
			ColorSequenceKeypoint.new(1, Color3.fromRGB(90, 210, 255)),
		}), 0)
		for _, corner in ipairs({ { 0, 0 }, { 1, 0 }, { 0, 1 }, { 1, 1 } }) do
			local cx, cy = corner[1], corner[2]
			local inset = 30
			local bracket = box({
				AnchorPoint = Vector2.new(cx, cy),
				Position = UDim2.new(cx, cx == 0 and 7 or -7, cy, cy == 0 and inset or -(inset - 4)),
				Size = UDim2.fromOffset(12, 12),
				BackgroundTransparency = 1,
				ZIndex = 3,
				Parent = overlayLayer,
			})
			box({ AnchorPoint = Vector2.new(cx, cy), Position = UDim2.fromScale(cx, cy), Size = UDim2.fromOffset(12, 2), BackgroundColor3 = WHITE, BackgroundTransparency = 0.25, ZIndex = 3, Parent = bracket })
			box({ AnchorPoint = Vector2.new(cx, cy), Position = UDim2.fromScale(cx, cy), Size = UDim2.fromOffset(2, 12), BackgroundColor3 = WHITE, BackgroundTransparency = 0.25, ZIndex = 3, Parent = bracket })
		end

		-- Pastilles en haut à gauche : ● LIVE + spectateurs
		local pills = box({ Name = "Pills", Position = UDim2.fromOffset(7, 7), Size = UDim2.new(1, -14, 0, 16), BackgroundTransparency = 1, ZIndex = 5, Parent = overlayLayer })
		local liveBadge = box({ Name = "Live", Size = UDim2.fromOffset(42, 16), BackgroundColor3 = WHITE, ZIndex = 5, Parent = pills }, 4)
		grad(liveBadge, Color3.fromRGB(255, 70, 90), Color3.fromRGB(215, 20, 50))
		liveDot = round(at({ BackgroundColor3 = WHITE, ZIndex = 6, Parent = liveBadge }, 8, 8, 6, 6))
		text({ Text = "LIVE", Font = Theme.Fonts.Title, TextSize = 11, Position = UDim2.fromOffset(13, 0), Size = UDim2.new(1, -14, 1, 0), ZIndex = 6, Parent = liveBadge })
		local viewersPill = box({ Name = "Viewers", Position = UDim2.fromOffset(46, 0), Size = UDim2.fromOffset(58, 16), BackgroundColor3 = Color3.fromRGB(12, 8, 20), BackgroundTransparency = 0.35, ZIndex = 5, Parent = pills }, 4)
		-- Petit bonhomme (icône "spectateurs")
		local viewerIcon = box(at({ BackgroundTransparency = 1, ZIndex = 6, Parent = viewersPill }, 9, 8, 10, 10))
		round(at({ BackgroundColor3 = Color3.fromRGB(255, 110, 120), ZIndex = 6, Parent = viewerIcon }, 5, 2.5, 4.5, 4.5))
		box(at({ BackgroundColor3 = Color3.fromRGB(255, 110, 120), ZIndex = 6, Parent = viewerIcon }, 5, 8, 8, 4), 2)
		viewersLabel = text({
			Name = "Count",
			Text = "0",
			Font = Theme.Fonts.Number,
			TextSize = 11,
			TextXAlignment = Enum.TextXAlignment.Left,
			Position = UDim2.fromOffset(17, 0),
			Size = UDim2.new(1, -19, 1, 0),
			ZIndex = 6,
			Parent = viewersPill,
		})
		-- Pastille "likes" en haut à droite
		local likesPill = box({ Name = "Likes", AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, 0, 0, 0), Size = UDim2.fromOffset(56, 16), BackgroundColor3 = Color3.fromRGB(12, 8, 20), BackgroundTransparency = 0.35, ZIndex = 5, Parent = pills }, 4)
		likesLabel = text({
			Name = "Count",
			Text = "❤ 0",
			Font = Theme.Fonts.Number,
			TextSize = 11,
			TextColor3 = Color3.fromRGB(255, 170, 200),
			Size = UDim2.fromScale(1, 1),
			ZIndex = 6,
			Parent = likesPill,
		})
		likesScale = UI.Create("UIScale", { Parent = likesPill })

		-- Objectif d'abonnés (barre qui se remplit)
		local goalBar = box({
			Name = "Goal",
			AnchorPoint = Vector2.new(0.5, 0),
			Position = UDim2.new(0.5, 0, 0, GOAL_Y),
			Size = UDim2.new(1, -16, 0, GOAL_H),
			BackgroundColor3 = Color3.fromRGB(14, 10, 26),
			BackgroundTransparency = 0.25,
			ClipsDescendants = true,
			ZIndex = 5,
			Parent = overlayLayer,
		}, UDim.new(1, 0))
		UI.Stroke(goalBar, Color3.fromRGB(200, 150, 255), 1, 0.45)
		goalFill = box({ Name = "Fill", Size = UDim2.fromScale(0.5, 1), BackgroundColor3 = WHITE, BackgroundTransparency = 0.1, ZIndex = 5, Parent = goalBar }, UDim.new(1, 0))
		goalGradient = UI.Gradient(goalFill, ColorSequence.new({
			ColorSequenceKeypoint.new(0, Color3.fromRGB(150, 80, 255)),
			ColorSequenceKeypoint.new(0.5, Color3.fromRGB(255, 90, 180)),
			ColorSequenceKeypoint.new(1, Color3.fromRGB(150, 80, 255)),
		}), 0)
		local goalLabel = text({
			Name = "Label",
			Text = Locale.T("💜 Follower goal"),
			Font = Theme.Fonts.Title,
			TextSize = 10,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextTruncate = Enum.TextTruncate.AtEnd,
			Position = UDim2.fromOffset(7, 0),
			Size = UDim2.new(0.55, -7, 1, 0),
			ZIndex = 6,
			Parent = goalBar,
		})
		goalCount = text({
			Name = "Count",
			Text = "",
			Font = Theme.Fonts.Number,
			TextSize = 10,
			TextXAlignment = Enum.TextXAlignment.Right,
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.new(1, -7, 0, 0),
			Size = UDim2.new(0.45, -4, 1, 0),
			ZIndex = 6,
			Parent = goalBar,
		})
		for _, label in ipairs({ goalLabel, goalCount }) do
			local stroke = UI.Stroke(label, Color3.fromRGB(20, 10, 30), 1.2, 0.35)
			stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
		end
	end

	-- Dons : alertes empilées en haut de la vidéo (sous les pastilles)
	local donationStack = box({
		Name = "Donations",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 27),
		Size = UDim2.new(1, -16, 0, 110),
		BackgroundTransparency = 1,
		ZIndex = 1,
		Parent = alertLayer,
	})
	UI.Create("UISizeConstraint", { MaxSize = Vector2.new(240, 110), Parent = donationStack })
	UI.Create("UIListLayout", {
		SortOrder = Enum.SortOrder.LayoutOrder,
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		Padding = UDim.new(0, 4),
		Parent = donationStack,
	})

	-- Likes (compteur qui grimpe)
	local likes = random:NextInteger(120, 400) * (1 + followers())
	local function addLikes(amount: number, bump: boolean)
		likes += amount
		if bump then
			likesScale.Scale = 1.2
			UI.Tween(likesScale, 0.3, { Scale = 1 }, Enum.EasingStyle.Back)
		end
	end

	------------------------------------------------------------------
	-- Expressions + gestes (pilotés par la boucle de rendu)
	------------------------------------------------------------------
	-- (une seule table : la fonction Start approche la limite de variables locales)
	local S = {
		chewUntil = 0,
		biteUntil = 0,
		wowUntil = 0,
		thanksUntil = 0,
		sipUntil = 0,
		talkUntil = 0,
		nextBlink = os.clock() + random:NextNumber(1.5, 4),
		blinkUntil = 0,
		lookX = 0, -- regard (lissé)
		lookY = 0,
		lookTargetX = 0,
		lookTargetY = 0,
		nextLook = 0,
		gesture = nil :: string?, -- "Heart" | "Wave"
		gestureUntil = 0,
		clock = 0,
		shown = true,
		visibilityTimer = 0,
		nextHeart = 0.5,
		viewersTimer = 0,
		likesTimer = 0,
		followTimer = 0,
		secondTimer = 0,
		sparkleTimer = 2,
		chatTimer = 0.8,
		fanTimer = 4,
		nextRaid = random:NextNumber(45, 90),
		uptime = random:NextInteger(40 * 60, 3 * 3600),
		shownExpression = "",
		compact = false, -- téléphone : chat en plus gros, sans épinglé ni saisie
		avatarSize = 14,
	}

	local function wow(duration: number?)
		S.wowUntil = os.clock() + (duration or 0.6)
	end

	-- Les gestes attendent que les mains soient libres (voir la boucle du repas)
	local mealBusy = false
	local function startGesture(name: string, duration: number)
		if mealBusy then
			return
		end
		S.gesture = name
		S.gestureUntil = os.clock() + duration
	end

	local function thanks()
		S.thanksUntil = os.clock() + 1.6
		startGesture("Heart", 1.5)
	end

	------------------------------------------------------------------
	-- Petit planificateur (remplace task.delay : tout passe par la boucle)
	------------------------------------------------------------------
	local pending: { { At: number, Run: () -> () } } = {}
	local function later(delay: number, run: () -> ())
		table.insert(pending, { At = os.clock() + delay, Run = run })
	end

	------------------------------------------------------------------
	-- Chat (Feature "LiveChat") : titre, épinglé, lignes recyclées, saisie
	------------------------------------------------------------------
	local chat = box({
		Name = "Chat",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -VIDEO_X, 0, VIDEO_Y),
		Size = UDim2.fromOffset(CHAT_W, VIDEO_H),
		BackgroundColor3 = CHAT_BG,
		ClipsDescendants = true,
		Visible = hasChat(),
		ZIndex = 2,
		Parent = card,
	}, 12)
	grad(chat, Color3.fromRGB(34, 28, 52), CHAT_BG)
	UI.Stroke(chat, Color3.fromRGB(78, 64, 116), 1)
	local chatTitle = text({
		Name = "Title",
		Text = "💬 <b>" .. Locale.T("Stream chat") .. "</b>",
		RichText = true,
		TextSize = 12,
		TextColor3 = Color3.fromRGB(226, 218, 250),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextTruncate = Enum.TextTruncate.AtEnd,
		Position = UDim2.fromOffset(8, 2),
		Size = UDim2.new(1, -26, 0, TITLE_H - 2),
		ZIndex = 3,
		Parent = chat,
	})
	-- Point vert "en ligne"
	local pinnedLabel: TextLabel
	local chatExtras: { [string]: GuiObject } = {} -- (épinglé, saisie : cachés en mode compact)
	do
		local onlineDot = round(at({ BackgroundColor3 = Color3.fromRGB(90, 230, 130), ZIndex = 3, Parent = chat }, CHAT_W - 11, TITLE_H / 2 + 1, 6, 6))
		UI.Stroke(onlineDot, Color3.fromRGB(90, 230, 130), 2, 0.7)
		box({ Position = UDim2.fromOffset(6, TITLE_H + 1), Size = UDim2.new(1, -12, 0, 1), BackgroundColor3 = Color3.fromRGB(80, 70, 116), ZIndex = 3, Parent = chat })

		-- Message épinglé (avec la mini photo de la streameuse)
		local pinned = box({
			Name = "Pinned",
			Position = UDim2.fromOffset(5, PINNED_Y),
			Size = UDim2.new(1, -10, 0, PINNED_H),
			BackgroundColor3 = WHITE,
			ZIndex = 3,
			Parent = chat,
		}, 7)
		grad(pinned, Color3.fromRGB(86, 60, 140), Color3.fromRGB(58, 42, 98), 0)
		UI.Stroke(pinned, Color3.fromRGB(170, 120, 255), 1, 0.35)
		pinnedLabel = text({
			Text = "",
			RichText = true,
			TextSize = 10,
			TextWrapped = true,
			TextColor3 = Color3.fromRGB(240, 232, 255),
			TextXAlignment = Enum.TextXAlignment.Left,
			Position = UDim2.fromOffset(5, 1),
			Size = UDim2.new(1, -8, 1, -2),
			ZIndex = 4,
			Parent = pinned,
		})
		chatExtras.Pinned = pinned
	end

	local chatList = box({
		Name = "Messages",
		Position = UDim2.fromOffset(0, LIST_Y),
		Size = UDim2.new(1, 0, 0, LIST_H),
		BackgroundTransparency = 1,
		ClipsDescendants = true,
		ZIndex = 3,
		Parent = chat,
	})
	-- Le "rouleau" est accroché en bas et grandit vers le haut (les plus
	-- vieux messages sortent par le haut, comme sur un vrai chat)
	local scroller = box({
		Name = "Scroller",
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.fromScale(0, 1),
		Size = UDim2.fromScale(1, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
		ZIndex = 3,
		Parent = chatList,
	})
	UI.Create("UIListLayout", {
		SortOrder = Enum.SortOrder.LayoutOrder,
		Padding = UDim.new(0, 3),
		Parent = scroller,
	})
	UI.Create("UIPadding", {
		PaddingLeft = UDim.new(0, 5),
		PaddingRight = UDim.new(0, 5),
		PaddingBottom = UDim.new(0, 3),
		Parent = scroller,
	})
	-- Fondu en haut de la liste
	local caret: Frame
	do
		local fade = box({ Name = "Fade", Size = UDim2.new(1, 0, 0, 26), BackgroundColor3 = Color3.fromRGB(30, 25, 46), ZIndex = 8, Parent = chatList })
		UI.Gradient(fade, ColorSequence.new(WHITE), 90).Transparency = NumberSequence.new(0, 1)

		-- Champ de saisie (décor) + bouton emote
		local input = box({
			Name = "Input",
			AnchorPoint = Vector2.new(0, 1),
			Position = UDim2.new(0, 5, 1, -5),
			Size = UDim2.new(1, -10, 0, INPUT_H),
			BackgroundColor3 = Color3.fromRGB(44, 38, 64),
			ZIndex = 3,
			Parent = chat,
		}, 6)
		UI.Stroke(input, Color3.fromRGB(96, 82, 140), 1, 0.3)
		chatExtras.Input = input
		text({
			Text = Locale.T("Send a message"),
			TextSize = 10,
			TextColor3 = Color3.fromRGB(150, 140, 180),
			TextXAlignment = Enum.TextXAlignment.Left,
			TextTruncate = Enum.TextTruncate.AtEnd,
			Position = UDim2.fromOffset(7, 0),
			Size = UDim2.new(1, -28, 1, 0),
			ZIndex = 4,
			Parent = input,
		})
		text({ Text = "🙂", TextSize = 11, AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -3, 0.5, 0), Size = UDim2.fromOffset(16, 16), ZIndex = 4, Parent = input })
		caret = box({ Position = UDim2.fromOffset(5, 5), Size = UDim2.fromOffset(1, INPUT_H - 10), BackgroundColor3 = Color3.fromRGB(200, 190, 240), ZIndex = 4, Parent = input })
	end

	-- Lignes recyclées : avatar à initiale + texte (badge, pseudo coloré, message)
	type ChatLine = { Frame: Frame, Avatar: Frame, Initial: TextLabel, Label: TextLabel, Padding: UIPadding }
	local chatLines: { ChatLine } = {}
	local chatOrder = 0
	local nextLine = 0
	for i = 1, CHAT_POOL do
		local frame = box({
			Name = "Line" .. i,
			Size = UDim2.fromScale(1, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			BackgroundColor3 = Color3.new(0, 0, 0),
			BackgroundTransparency = 1,
			Visible = false,
			ZIndex = 4,
			Parent = scroller,
		}, 5)
		local padding = UI.Create("UIPadding", { Parent = frame })
		local avatar = round({ Name = "Avatar", Position = UDim2.fromOffset(0, 1), Size = UDim2.fromOffset(14, 14), BackgroundColor3 = WHITE, ZIndex = 4, Parent = frame })
		local initial = text({ Text = "", Font = Theme.Fonts.Title, TextSize = 9, TextColor3 = Color3.fromRGB(30, 20, 40), Size = UDim2.fromScale(1, 1), ZIndex = 5, Parent = avatar })
		local label = text({
			Name = "Msg",
			Text = "",
			RichText = true,
			TextSize = 11,
			TextWrapped = true,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextYAlignment = Enum.TextYAlignment.Top,
			AutomaticSize = Enum.AutomaticSize.Y,
			Position = UDim2.fromOffset(18, 0),
			Size = UDim2.new(1, -18, 0, 0),
			TextColor3 = Color3.fromRGB(236, 230, 250),
			ZIndex = 5,
			Parent = frame,
		})
		chatLines[i] = { Frame = frame, Avatar = avatar, Initial = initial, Label = label, Padding = padding }
	end

	local function nameHash(name: string): number
		local sum = 0
		for i = 1, #name do
			sum += string.byte(name, i) * i
		end
		return sum
	end

	local function nameColor(name: string): string
		return NAME_COLORS[nameHash(name) % #NAME_COLORS + 1]
	end

	-- Rôle stable par pseudo : 🛡️ modo, 👑 VIP, 💎 abonné (ou rien)
	local function roleBadge(name: string): string
		if MODS[name] then
			return "🛡️"
		end
		local roll = nameHash(name) % 10
		if roll <= 1 then
			return "👑"
		elseif roll <= 5 then
			return "💎"
		end
		return ""
	end

	type ChatOptions = { Badge: string?, Highlight: Color3?, Emote: boolean?, System: boolean? }

	-- Recycle la plus vieille ligne et l'amène tout en bas
	local function writeLine(richText: string, name: string?, highlight: Color3?)
		nextLine = nextLine % CHAT_POOL + 1
		local line = chatLines[nextLine]
		chatOrder += 1
		line.Frame.LayoutOrder = chatOrder
		line.Frame.Visible = true
		line.Label.Text = richText
		if name then
			line.Avatar.Visible = true
			line.Avatar.BackgroundColor3 = hexColor(nameColor(name))
			line.Initial.Text = string.upper(string.sub(name, 1, 1))
			line.Label.Position = UDim2.fromOffset(S.avatarSize + 4, 0)
			line.Label.Size = UDim2.new(1, -(S.avatarSize + 4), 0, 0)
		else
			line.Avatar.Visible = false
			line.Label.Position = UDim2.fromOffset(0, 0)
			line.Label.Size = UDim2.fromScale(1, 0)
		end
		local pad = highlight and 3 or 0
		line.Frame.BackgroundColor3 = highlight or Color3.new(0, 0, 0)
		line.Frame.BackgroundTransparency = highlight and 0.5 or 1
		line.Padding.PaddingLeft = UDim.new(0, pad)
		line.Padding.PaddingRight = UDim.new(0, pad)
		line.Padding.PaddingTop = UDim.new(0, highlight and 2 or 0)
		line.Padding.PaddingBottom = UDim.new(0, highlight and 2 or 0)
		line.Label.TextTransparency = 1
		UI.Tween(line.Label, 0.22, { TextTransparency = 0 })
	end

	local function pushChat(name: string, message: string, options: ChatOptions?)
		if not chat.Visible then
			return
		end
		local badge = (options and options.Badge) or roleBadge(name)
		local prefix = badge ~= "" and (badge .. " ") or ""
		local body = escape(message)
		if options and options.Emote then
			body = '<font size="' .. (S.compact and 19 or 16) .. '">' .. body .. "</font>"
		end
		writeLine(prefix .. '<font color="' .. nameColor(name) .. '"><b>' .. escape(name) .. "</b></font>: " .. body, name, options and options.Highlight)
	end

	-- Message système (raid, abonnement, don...) : sans pseudo, surligné
	local function systemMessage(richText: string, color: Color3)
		if not chat.Visible then
			return
		end
		writeLine("<i>" .. richText .. "</i>", nil, color)
	end

	local HOST_OPTIONS: ChatOptions = { Badge = "🎙️", Highlight = Color3.fromRGB(145, 70, 255) }
	local function hostSays(message: string)
		pushChat(HOST, message, HOST_OPTIONS)
		S.talkUntil = os.clock() + 1.4
	end

	local function randomName(): string
		return pick(NAMES, random)
	end

	-- Réaction du chat limitée (pas plus d'une par `interval` pour une même clé)
	local lastReaction: { [string]: number } = {}
	local function react(key: string, interval: number, list: { string }, extra: number?)
		local now = os.clock()
		if now - (lastReaction[key] or 0) < interval then
			return
		end
		lastReaction[key] = now
		pushChat(randomName(), pick(list, random))
		-- Quelques messages de plus, un peu après (le chat s'emballe)
		for i = 1, extra or 0 do
			later(0.25 * i + random:NextNumber(0, 0.2), function()
				pushChat(randomName(), pick(list, random))
			end)
		end
	end

	-- Texte du message épinglé (dépend de l'abonnement et du beurre)
	local function refreshPinned(followed: boolean)
		if not followed then
			pinnedLabel.Text = Locale.T("📌 <b>Follow</b> to unlock donations 💸")
		elseif hasButter() then
			pinnedLabel.Text = Locale.T("📌 Thanks followers 💜 Bite the <b>butter</b>!")
		else
			pinnedLabel.Text = Locale.T("📌 Thanks followers 💜 Be nice!")
		end
	end

	-- Affiche / cache le chat quand la Feature change
	local chatShown = chat.Visible
	local function applyChatVisibility()
		local shown = hasChat()
		if shown == chatShown then
			return
		end
		chatShown = shown
		UI.Tween(video, 0.35, { Size = videoSize(shown) }, Enum.EasingStyle.Back)
		if shown then
			chat.Visible = true
			chat.Position = UDim2.new(1, CHAT_W, 0, VIDEO_Y)
			UI.Tween(chat, 0.35, { Position = UDim2.new(1, -VIDEO_X, 0, VIDEO_Y) }, Enum.EasingStyle.Back)
			hostSays(Locale.T("chat is open!! 🎉"))
		else
			chat.Visible = false
		end
	end

	-- Affiche / cache le beurre
	local butterShown = butterButton.Visible
	local function applyButterVisibility()
		local shown = hasButter()
		if shown == butterShown then
			return
		end
		butterShown = shown
		butterButton.Visible = shown
		if shown then
			butterScale.Scale = 0.2
			UI.Tween(butterScale, 0.5, { Scale = 1 }, Enum.EasingStyle.Back)
			hostSays(Locale.T("i brought BUTTER 🧈"))
		end
		refreshPinned(isFollowedOnServer())
	end

	------------------------------------------------------------------
	-- Studio (améliorations "StreamStudio" et "Followers")
	------------------------------------------------------------------
	local shownStudio, shownFollowers = -1, -1
	local ledRainbow = false
	local qualityTag = ""
	local function refreshStudio()
		local level, fans = studio(), followers()
		if level == shownStudio and fans == shownFollowers then
			return
		end
		shownStudio, shownFollowers = level, fans
		ringGroup.Visible = level >= 1
		softGlow.BackgroundTransparency = level >= 1 and 0.9 or 0.84
		ledRainbow = level >= 2
		ledGradient.Color = ledRainbow and LED_RAINBOW or LED_WARM
		proMic.Visible = level >= 3
		bokehGroup.Visible = level >= 5
		qualityTag = level >= 7 and " · 4K" or (level >= 3 and " · HD" or "")
		trophy.Visible = fans >= 5
		if fans >= 15 then
			trophyGradient.Color = ColorSequence.new(Color3.fromRGB(200, 250, 255), Color3.fromRGB(90, 180, 255))
		elseif fans >= 10 then
			trophyGradient.Color = ColorSequence.new(Color3.fromRGB(255, 236, 140), Color3.fromRGB(220, 160, 40))
		else
			trophyGradient.Color = ColorSequence.new(Color3.fromRGB(240, 240, 250), Color3.fromRGB(150, 150, 170))
		end
	end
	refreshStudio()

	ctx.Connect(ctx.State.FeaturesChanged, function()
		applyChatVisibility()
		applyButterVisibility()
	end)

	------------------------------------------------------------------
	-- Spectateurs : grimpent avec le niveau "Abonnés" (et le studio)
	------------------------------------------------------------------
	local followPendingUntil = 0
	local function isFollowed(): boolean
		return isFollowedOnServer() or os.clock() < followPendingUntil
	end

	local function targetViewers(): number
		local base = 40 * (1.9 ^ followers()) * (1 + studio() * 0.06)
		if hasChat() then
			base *= 1.5
		end
		if isFollowed() then
			base *= 1.15
		end
		return base
	end
	local viewers = targetViewers() * random:NextNumber(0.9, 1.1)
	local shownViewers = viewers
	local shownLikes = likes

	local function formatCount(value: number): string
		if value < 1e4 then
			return Format.WithSpaces(value)
		end
		return Format.Format(value, 1)
	end

	-- Objectif d'abonnés : un palier "rond" un peu au-dessus du compte
	local followerCount = math.floor(600 * (1.55 ^ followers()) + random:NextInteger(0, 300))
	local function nextGoal(count: number): number
		local target = count * 1.08 + 10
		local step = 10 ^ math.max(1, math.floor(math.log10(target)) - 1)
		return math.ceil(target / step) * step
	end
	local goal = nextGoal(followerCount)
	local goalStart = followerCount
	local shownGoalRatio = -1
	local function refreshGoal()
		local ratio = math.clamp((followerCount - goalStart) / math.max(1, goal - goalStart), 0, 1)
		ratio = 0.08 + ratio * 0.92
		if math.abs(ratio - shownGoalRatio) > 0.001 then
			shownGoalRatio = ratio
			goalFill.Size = UDim2.fromScale(ratio, 1)
		end
		goalCount.Text = formatCount(followerCount) .. " / " .. formatCount(goal)
	end
	refreshGoal()

	local function addFollowers(amount: number)
		followerCount += amount
		if followerCount >= goal then
			-- Objectif atteint : on fête ça, puis on vise le palier suivant
			popWord(Locale.T("GOAL!"), UDim2.new(0.5, 0, 0, GOAL_Y - 16), Color3.fromRGB(255, 214, 40))
			systemMessage(Locale.T("🎯 Follower goal reached: <b>%s</b>!", formatCount(goal)), Color3.fromRGB(200, 80, 160))
			for _ = 1, 3 do
				spawnHeart("🎉")
			end
			thanks()
			later(0.6, function()
				hostSays(Locale.T("we hit the goal!! thank you 😭💜"))
			end)
			goalStart = goal
			goal = nextGoal(followerCount)
			goalGradient.Offset = Vector2.new(0, 0)
		end
		refreshGoal()
	end

	------------------------------------------------------------------
	-- Bouton "Suivre" : récompense unique, puis "✔ Abonné" et les dons
	------------------------------------------------------------------
	local shownFollowed: boolean? = nil
	local function refreshFollow(announce: boolean)
		local followed = isFollowed()
		if followed == shownFollowed then
			return
		end
		local wasShown = shownFollowed
		shownFollowed = followed
		refreshPinned(followed)
		followShine.Visible = not followed
		if followed then
			followButton.Text = Locale.T("✔ Following")
			followButton.BackgroundColor3 = FOLLOWED_COLOR
			followGradient.Color = ColorSequence.new(WHITE, Color3.fromRGB(220, 220, 230))
			followStroke.Color = Color3.fromRGB(120, 110, 150)
			if announce and wasShown == false then
				systemMessage(Locale.T("💜 You're now following <b>%s</b>!", HOST), Color3.fromRGB(120, 60, 200))
				hostSays(Locale.T("thanks for the follow!! donations are open 💸"))
			end
		else
			followButton.Text = Locale.T("💜 Follow")
			followButton.BackgroundColor3 = FOLLOW_COLOR
			followGradient.Color = ColorSequence.new(WHITE, Color3.fromRGB(205, 190, 230))
			followStroke.Color = Color3.fromRGB(210, 180, 255)
		end
	end
	refreshFollow(false)
	ctx.Connect(ctx.State.Changed, function()
		refreshFollow(true)
		refreshStudio()
	end)

	ctx.Connect(followButton.Activated, function()
		if isFollowed() then
			-- Déjà abonné : petit cœur pour le plaisir
			spawnHeart("💜")
			addLikes(1, true)
			return
		end
		followPendingUntil = os.clock() + 6 -- en attendant la confirmation du serveur
		ctx.Interact("Follow")
		ctx.Sound.Play("Pop", 1.3)
		for _ = 1, 4 do
			spawnHeart("💜")
		end
		viewers += 1
		addLikes(10, true)
		addFollowers(1)
		wow(0.8)
		startGesture("Wave", 1.4)
		refreshFollow(true)
		later(0.6, function()
			react("follow", 0.5, TXT.followReactions, 2)
		end)
	end)

	ctx.OnBonus("Follow", function(payload)
		local amount = tonumber(payload.Amount)
		-- (au centre du bouton Suivre)
		local followX = CARD_W - (PAD + 2) - FOLLOW_W / 2
		if amount then
			ctx.FloatText(card, UDim2.fromOffset(followX, HEADER_MID + 14), "+" .. Format.Format(amount), Theme.Colors.Gold, 24)
		end
		ctx.Effects.Burst(card, UDim2.fromOffset(followX, HEADER_MID), Color3.fromRGB(190, 120, 255), 12)
		ctx.Sound.Play("Bonus", 1.1)
	end)

	------------------------------------------------------------------
	-- Dons (Spawner "Donation") : alerte cliquable -> ClaimSpawn
	------------------------------------------------------------------
	type Donation = {
		Card: TextButton,
		Title: TextLabel,
		Sub: TextLabel,
		Icon: TextLabel,
		Name: string,
		Claimed: boolean,
		Done: boolean,
		ExpiresAt: number,
	}
	local donations: { [string]: Donation } = {}
	local donationOrder = 0

	local function removeDonation(id: string, delay: number)
		local donation = donations[id]
		if not donation or donation.Done then
			return
		end
		donation.Done = true
		later(delay, function()
			local cardFrame = donation.Card
			if cardFrame.Parent then
				-- Se replie en douceur
				cardFrame.ClipsDescendants = true
				UI.Tween(cardFrame, 0.3, { BackgroundTransparency = 1, Size = UDim2.fromScale(1, 0) }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
				UI.Tween(donation.Title, 0.2, { TextTransparency = 1 })
				UI.Tween(donation.Sub, 0.2, { TextTransparency = 1 })
				UI.Tween(donation.Icon, 0.2, { TextTransparency = 1 })
			end
			later(0.35, function()
				if cardFrame.Parent then
					cardFrame:Destroy()
				end
				if donations[id] == donation then
					donations[id] = nil
				end
			end)
		end)
	end

	local function createDonation(info: any)
		local id = info.Id
		if type(id) ~= "string" or donations[id] then
			return
		end
		local variant = math.floor(tonumber(info.Variant) or random:NextInteger(1, 1000))
		local name = NAMES[(variant - 1) % #NAMES + 1]
		local line = TXT.donationLines[(variant - 1) % #TXT.donationLines + 1]
		local lifetime = tonumber(info.Lifetime) or 10
		local HEIGHT = 46

		donationOrder += 1
		local button = UI.Create("TextButton", {
			Name = "Donation",
			Text = "",
			AutoButtonColor = false,
			BackgroundColor3 = WHITE,
			BorderSizePixel = 0,
			Size = UDim2.new(1, 0, 0, HEIGHT),
			LayoutOrder = donationOrder,
			ZIndex = 1,
			Parent = donationStack,
		})
		UI.Corner(button, 10)
		UI.Gradient(button, ColorSequence.new({
			ColorSequenceKeypoint.new(0, Color3.fromRGB(70, 36, 120)),
			ColorSequenceKeypoint.new(1, Color3.fromRGB(34, 20, 64)),
		}), 0)
		local stroke = UI.Stroke(button, WHITE, 2)
		UI.Gradient(stroke, ColorSequence.new({
			ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 226, 110)),
			ColorSequenceKeypoint.new(0.5, Color3.fromRGB(255, 150, 60)),
			ColorSequenceKeypoint.new(1, Color3.fromRGB(255, 226, 110)),
		}), 0)
		-- Pastille dorée de l'icône
		local iconBox = box(at({ BackgroundColor3 = WHITE, ZIndex = 2, Parent = button }, 22, HEIGHT / 2, 34, 34), 9)
		grad(iconBox, Color3.fromRGB(255, 232, 120), Color3.fromRGB(255, 160, 50))
		local icon = text({
			Text = "💸",
			TextSize = 20,
			Size = UDim2.fromScale(1, 1),
			ZIndex = 3,
			Parent = iconBox,
		})
		local textX = 44
		local title = text({
			Text = "<b>" .. escape(name) .. "</b> " .. line,
			RichText = true,
			TextSize = 12,
			TextColor3 = Color3.fromRGB(255, 236, 160),
			TextXAlignment = Enum.TextXAlignment.Left,
			TextTruncate = Enum.TextTruncate.AtEnd,
			Position = UDim2.fromOffset(textX, 6),
			Size = UDim2.new(1, -(textX + 6), 0, 16),
			ZIndex = 2,
			Parent = button,
		})
		local sub = text({
			Text = Locale.T("Click to claim ✨"),
			Font = Theme.Fonts.Title,
			TextSize = 11,
			TextColor3 = Color3.fromRGB(150, 230, 255),
			TextXAlignment = Enum.TextXAlignment.Left,
			TextTruncate = Enum.TextTruncate.AtEnd,
			Position = UDim2.fromOffset(textX, 23),
			Size = UDim2.new(1, -(textX + 6), 0, 14),
			ZIndex = 2,
			Parent = button,
		})
		local timer = box({
			AnchorPoint = Vector2.new(0, 1),
			Position = UDim2.new(0, textX, 1, -5),
			Size = UDim2.new(1, -(textX + 10), 0, 2),
			BackgroundColor3 = Color3.fromRGB(255, 214, 90),
			ZIndex = 2,
			Parent = button,
		}, 1)
		TweenService:Create(timer, TweenInfo.new(lifetime, Enum.EasingStyle.Linear), { Size = UDim2.new(0, 0, 0, 2) }):Play()

		-- Pulsation pour attirer l'œil
		-- (nommé "PopScale" : UIUtil.Pop le réutilise au clic, un seul UIScale)
		local pulse = UI.Create("UIScale", { Name = "PopScale", Scale = 0.3, Parent = button })
		UI.Tween(pulse, 0.35, { Scale = 1 }, Enum.EasingStyle.Back)

		local donation: Donation = {
			Card = button,
			Title = title,
			Sub = sub,
			Icon = icon,
			Name = name,
			Claimed = false,
			Done = false,
			ExpiresAt = os.clock() + lifetime,
		}
		donations[id] = donation
		later(0.36, function()
			if button.Parent and not donation.Claimed and not donation.Done then
				TweenService:Create(pulse, TweenInfo.new(0.45, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), { Scale = 1.04 }):Play()
			end
		end)

		ctx.Sound.Play("Notif", 1.2)
		spawnHeart("💸")
		wow(0.7)
		systemMessage(Locale.T("💸 <b>%s</b> tipped the stream!", escape(name)), Color3.fromRGB(190, 120, 20))

		ctx.Connect(button.Activated, function()
			if donation.Claimed or donation.Done then
				return
			end
			donation.Claimed = true
			ctx.ClaimSpawn(id)
			ctx.Sound.Play("Cash", 1)
			sub.Text = "⏳ ..."
			icon.Text = "🤑"
			UI.Pop(button, 1.15, 0.3)
			-- Sans réponse du serveur (don expiré), l'alerte s'efface quand même
			removeDonation(id, 2.5)
		end)
	end

	ctx.OnSpawn("Donation", createDonation)

	ctx.OnBonus("Donation", function(payload)
		local amount = tonumber(payload.Amount)
		local donation = type(payload.SpawnId) == "string" and donations[payload.SpawnId] or nil
		local amountText = amount and ("+" .. Format.Format(amount)) or ""
		if donation and donation.Card.Parent then
			donation.Title.Text = Locale.T("✔ Thanks <b>%s</b>!", escape(donation.Name))
			donation.Sub.Text = amountText ~= "" and (amountText .. " Dopamine 💜") or Locale.T("Thanks 💜")
			if amount then
				ctx.FloatText(donation.Card, UDim2.fromScale(0.5, 0.5), amountText, Theme.Colors.Gold, 22)
			end
			ctx.Effects.Burst(donation.Card, UDim2.fromScale(0.5, 0.5), Theme.Colors.Gold, 8)
		elseif amount then
			ctx.FloatText(video, UDim2.new(0.5, 0, 0, 56), amountText, Theme.Colors.Gold, 24)
		end
		for _ = 1, 3 do
			spawnHeart("💸")
		end
		addLikes(random:NextInteger(20, 60), true)
		thanks()
		soundWave(nil)
		popWord(Locale.T("THANKS!!"), UDim2.new(0.5, 0, 0, HEAD_Y - 34), Color3.fromRGB(255, 214, 40))
		later(0.4, function()
			react("donation", 0.8, TXT.donationReactions, 2)
		end)
	end)

	------------------------------------------------------------------
	-- Clic sur le beurre : CROUNCH (limité à MaxPerSecond)
	------------------------------------------------------------------
	local butterConfig = ctx.Config.Interactions and ctx.Config.Interactions.Butter
	local butterMaxPerSecond = (butterConfig and tonumber(butterConfig.MaxPerSecond)) or 8
	local butterFraction = (butterConfig and tonumber(butterConfig.ClickFraction)) or 0.75
	local butterInterval = 1 / math.max(1, butterMaxPerSecond)
	local lastButter = -math.huge
	local butterCrunches = 0

	-- Le beurre revient tout neuf
	local function regenerateButter()
		regenerating = true
		UI.Tween(butterScale, 0.18, { Scale = 0 }, Enum.EasingStyle.Back, Enum.EasingDirection.In)
		later(1.1, function()
			for _, bite in ipairs(bites) do
				bite:Destroy()
			end
			table.clear(bites)
			block.Size = UDim2.fromOffset(BUTTER_W, BUTTER_H)
			butterScale.Scale = 0.2
			UI.Tween(butterScale, 0.45, { Scale = 1 }, Enum.EasingStyle.Back)
			regenerating = false
		end)
	end

	ctx.Connect(butterButton.Activated, function()
		if not hasButter() or regenerating then
			return
		end
		local now = os.clock()
		if now - lastButter < butterInterval then
			-- Trop rapide : petite secousse seulement (pas de rotation : le
			-- bloc découpe ses traces de dents avec ClipsDescendants)
			butterButton.Position = butterHome + UDim2.fromOffset(random:NextInteger(-3, 3), 0)
			UI.Tween(butterButton, 0.12, { Position = butterHome })
			return
		end
		lastButter = now
		butterCrunches += 1

		ctx.Interact("Butter")
		ctx.Sound.Play("Crunch", random:NextNumber(0.9, 1.15))

		-- Écrasement + trace de dents
		butterScale.Scale = 0.82
		UI.Tween(butterScale, 0.25, { Scale = 1 }, Enum.EasingStyle.Back)
		addBite()
		local eaten = #bites / BUTTER_BITES
		block.Size = UDim2.fromOffset(BUTTER_W * (1 - eaten * 0.25), BUTTER_H * (1 - eaten * 0.45))
		if butterHint.Visible then
			butterHint.Visible = false
		end

		local topY = BUTTER_Y - 6 - BUTTER_H * 0.6 -- haut du bloc
		burstParticles(BUTTER_X, 0, topY, 5, BUTTER_COLORS, 60)
		soundWave(UDim2.new(BUTTER_X, 0, 0, topY))
		popWord(pick(TXT.butterWords, random), UDim2.new(BUTTER_X, -12, 0, BUTTER_Y - BUTTON_H - 4), Color3.fromRGB(255, 226, 96))

		-- "+X" prédit (le serveur donne gain par clic x ClickFraction)
		local data = ctx.State.Data
		local value = (data and tonumber(data.ClickValue) or 0) * butterFraction
		if value > 0 then
			ctx.FloatText(video, UDim2.new(BUTTER_X, 0, 0, BUTTER_Y - BUTTON_H + 12), "+" .. Format.Format(value), Theme.Colors.Gold, 20)
		end

		wow(0.4)
		addLikes(random:NextInteger(1, 4), butterCrunches % 3 == 0)
		react("butter", 1.2, TXT.butterReactions)

		if #bites >= BUTTER_BITES then
			regenerateButter()
			later(0.3, function()
				hostSays(Locale.T("out of butter... time for a refill! 🧈"))
			end)
		end
	end)

	------------------------------------------------------------------
	-- Repas : machine à états (un aliment à la fois, parfois une gorgée)
	------------------------------------------------------------------
	type Meal = { Phase: string, T: number, Index: number?, Arm: Arm? }
	local meal: Meal = { Phase = "Wait", T = 1.2, Index = nil, Arm = nil }
	local bitesSinceSip = 0
	local cupX, cupY = CUP_X, CUP_BASE -- position du bas du gobelet

	local function refillPlate()
		for i, food in ipairs(foods) do
			food.Text = pick(FOODS, random)
			food.Rotation = random:NextNumber(-12, 12)
			foodScales[i].Scale = 1
			food.Position = foodHome(i) - UDim2.fromOffset(0, 80)
			food.Visible = true
			later((i - 1) * 0.08, function()
				UI.Tween(food, 0.45, { Position = foodHome(i) }, Enum.EasingStyle.Bounce)
			end)
		end
	end

	local function mealWait(): number
		return random:NextNumber(1.1, 1.9) / (1 + math.min(followers(), 15) * 0.02)
	end

	local function updateMeal(dt: number, now: number)
		meal.T -= dt
		local phase = meal.Phase
		if phase == "Wait" then
			mealBusy = false
			if meal.T > 0 or now < S.gestureUntil then
				return
			end
			if bitesSinceSip >= 3 and random:NextNumber() < 0.5 then
				-- Une gorgée de bubble tea
				bitesSinceSip = 0
				mealBusy = true
				meal.Phase, meal.T, meal.Arm = "SipReach", 0.35, leftArm
				leftArm.TX, leftArm.TY = CUP_X + 3, CUP_BASE - 12
				return
			end
			local index = nil
			for i, food in ipairs(foods) do
				if food.Visible then
					index = i
					break
				end
			end
			if not index then
				-- Assiette vide : on ressert !
				wow(0.8)
				popWord(Locale.T("REFILL!"), UDim2.new(0.5, 0, 0, HEAD_Y - 30), nil)
				refillPlate()
				pushChat(randomName(), Locale.T("SHE'S GOING FOR SECONDS 😭🔥"))
				meal.T = 1.3
				return
			end
			mealBusy = true
			S.gesture = nil
			local arm = FOOD_OFFSETS[index] < 0 and leftArm or rightArm
			meal.Phase, meal.T, meal.Index, meal.Arm = "Reach", 0.32, index, arm
			aimTip(arm, FOOD_OFFSETS[index], FOOD_Y)
			S.lookTargetX, S.lookTargetY = FOOD_OFFSETS[index] > 0 and 1 or -1, 2
		elseif phase == "Reach" then
			local arm = meal.Arm :: Arm
			aimTip(arm, FOOD_OFFSETS[meal.Index :: number], FOOD_Y)
			if meal.T <= 0 then
				meal.Phase, meal.T = "Lift", 0.36
				S.biteUntil = now + 0.5
			end
		elseif phase == "Lift" then
			local arm = meal.Arm :: Arm
			aimTip(arm, arm.Side * 3, MOUTH_Y + 2)
			local food = foods[meal.Index :: number]
			local tx, ty = tipPosition(arm)
			food.Position = UDim2.new(0.5, tx, 0, ty)
			food.Rotation *= 0.9
			foodScales[meal.Index :: number].Scale = math.max(0.65, foodScales[meal.Index :: number].Scale - dt * 1.2)
			S.lookTargetX, S.lookTargetY = 0, 1
			if meal.T <= 0 then
				-- CROC !
				food.Visible = false
				S.biteUntil = 0
				S.chewUntil = now + 1.1
				bitesSinceSip += 1
				popWord(pick(TXT.crunchWords, random), UDim2.new(0.5, random:NextNumber() < 0.5 and -52 or 52, 0, MOUTH_Y - 10), nil)
				burstParticles(0.5, 0, MOUTH_Y + 6, 4, CRUMB_COLORS, 45)
				soundWave(nil)
				ctx.Sound.Play("Pop", random:NextNumber(0.55, 0.75))
				addLikes(random:NextInteger(2, 8), true)
				if random:NextNumber() < 0.45 then
					react("eat", 0.5, TXT.eatReactions)
				end
				meal.Phase, meal.T = "Back", 0.35
				arm.TX, arm.TY = arm.RestX, arm.RestY
			end
		elseif phase == "Back" then
			local arm = meal.Arm :: Arm
			arm.TX, arm.TY = arm.RestX, arm.RestY
			if meal.T <= 0 then
				meal.Phase, meal.T, meal.Arm, meal.Index = "Wait", mealWait(), nil, nil
			end
		elseif phase == "SipReach" then
			if meal.T <= 0 then
				meal.Phase, meal.T = "SipLift", 0.42
			end
		elseif phase == "SipLift" or phase == "SipHold" then
			-- Le gobelet suit la main jusqu'à la bouche (paille sur les lèvres)
			leftArm.TX, leftArm.TY = -8, MOUTH_Y + 30
			cupX = cupX + (leftArm.X + 5 - cupX) * math.min(1, dt * 14)
			cupY = cupY + (leftArm.Y + 14 - cupY) * math.min(1, dt * 14)
			cup.Rotation = approach(cup.Rotation, 14, 10, dt)
			if phase == "SipLift" and meal.T <= 0 then
				meal.Phase, meal.T = "SipHold", 0.9
				S.sipUntil = now + 1
			elseif phase == "SipHold" and meal.T <= 0 then
				meal.Phase, meal.T = "SipBack", 0.4
			end
		elseif phase == "SipBack" then
			leftArm.TX, leftArm.TY = CUP_X + 3, CUP_BASE - 12
			cupX = approach(cupX, CUP_X, 12, dt)
			cupY = approach(cupY, CUP_BASE, 12, dt)
			cup.Rotation = approach(cup.Rotation, 0, 12, dt)
			if meal.T <= 0 then
				cupX, cupY, cup.Rotation = CUP_X, CUP_BASE, 0
				meal.Phase, meal.T = "Back", 0.3
				meal.Arm = leftArm
			end
		end
		if phase == "SipLift" or phase == "SipHold" or phase == "SipBack" then
			cup.Position = UDim2.new(0.5, cupX, 0, cupY)
		end
	end

	------------------------------------------------------------------
	-- Gros gains du joueur : le chat s'enflamme
	------------------------------------------------------------------
	local BIG_SOURCES = { Golden = true, Lightning = true, DVD = true, Email = true }
	ctx.Connect(ctx.State.NotifyReceived, function(payload)
		if type(payload) ~= "table" or not chat.Visible then
			return
		end
		local kind = payload.Type
		if kind == "Jackpot" then
			react("big", 1, TXT.jackpotReactions, 3)
			wow(0.8)
		elseif kind == "Rush" then
			react("big", 1, TXT.rushReactions, 2)
		elseif kind == "Achievement" then
			react("achievement", 2, TXT.achievementReactions, 0)
		elseif kind == "Unlock" then
			react("unlock", 2, TXT.unlockReactions, 0)
		elseif kind == "Bonus" and BIG_SOURCES[payload.Source] then
			react("big", 1.5, TXT.bigGainReactions, 1)
		end
	end)

	------------------------------------------------------------------
	-- Raid : une autre chaîne débarque avec ses spectateurs
	------------------------------------------------------------------
	local raiding = false
	local function startRaid()
		if raiding or not chat.Visible then
			return
		end
		raiding = true
		local raider = randomName()
		local count = math.floor(random:NextInteger(40, 160) * (1 + followers() * 0.5))
		viewers += count
		addLikes(count, true)
		addFollowers(math.max(1, math.floor(count / 12)))
		chatTitle.Text = "🚨 <b><font color=\"#FF9F45\">" .. Locale.T("RAID!") .. "</font></b>"
		systemMessage(Locale.T("🚨 RAID from <b>%s</b> with %s viewers!", escape(raider), tostring(count)), Color3.fromRGB(230, 110, 20))
		popWord(Locale.T("RAID!"), UDim2.new(0.5, 0, 0, 44), Color3.fromRGB(255, 159, 69))
		wow(1)
		startGesture("Wave", 1.6)
		for _ = 1, 3 do
			spawnHeart("🎉")
		end
		local delay = 0
		for _ = 1, random:NextInteger(6, 9) do
			delay += random:NextNumber(0.12, 0.3)
			later(delay, function()
				if random:NextNumber() < 0.3 then
					pushChat(randomName(), pick(EMOTE_MESSAGES, random), { Emote = true })
				else
					pushChat(randomName(), pick(TXT.raidMessages, random))
				end
			end)
		end
		later(delay + 0.6, function()
			hostSays(Locale.T("thanks for the raid %s!! 💜", raider))
		end)
		later(delay + 3.1, function()
			chatTitle.Text = "💬 <b>" .. Locale.T("Stream chat") .. "</b>"
			raiding = false
		end)
	end

	local function chatTick()
		if not chat.Visible then
			return
		end
		local roll = random:NextNumber()
		if roll < 0.05 then
			hostSays(pick(TXT.hostMessages, random))
		elseif roll < 0.09 then
			local mod = pick({ "Tonton_Jean", "Lulu_ASMR", "Moustache_Pro", "Madeleine_Proust" }, random)
			pushChat(mod, pick(TXT.modMessages, random))
		elseif roll < 0.15 and hasButter() then
			pushChat(randomName(), pick(TXT.butterNags, random))
		elseif roll < 0.17 and not isFollowed() then
			pushChat(randomName(), pick(TXT.followNags, random))
		elseif roll < 0.35 then
			pushChat(randomName(), pick(EMOTE_MESSAGES, random), { Emote = true })
		else
			pushChat(randomName(), pick(TXT.messages, random))
		end
	end

	-- Mode compact (petit écran : le slot est réduit) : texte du chat plus
	-- gros, message épinglé et champ de saisie cachés
	local function applyCompact()
		local scale = 1
		if type(ctx.GetSlotScale) == "function" then
			local ok, value = pcall(ctx.GetSlotScale)
			scale = ok and tonumber(value) or 1
		end
		local compact = scale < 0.62
		if compact == S.compact then
			return
		end
		S.compact = compact
		S.avatarSize = compact and 17 or 14
		for _, line in ipairs(chatLines) do
			line.Label.TextSize = compact and 14 or 11
			line.Avatar.Size = UDim2.fromOffset(S.avatarSize, S.avatarSize)
			line.Initial.TextSize = compact and 11 or 9
			if line.Avatar.Visible then
				line.Label.Position = UDim2.fromOffset(S.avatarSize + 4, 0)
				line.Label.Size = UDim2.new(1, -(S.avatarSize + 4), 0, 0)
			end
		end
		for _, extra in pairs(chatExtras) do
			extra.Visible = not compact
		end
		chatTitle.TextSize = compact and 15 or 12
		local top = compact and TITLE_H + 3 or LIST_Y
		chatList.Position = UDim2.fromOffset(0, top)
		chatList.Size = UDim2.new(1, 0, 0, compact and (VIDEO_H - top - 4) or LIST_H)
	end
	applyCompact()

	-- Quelques messages dès le départ (le chat n'est jamais vide)
	for _ = 1, 6 do
		chatTick()
	end

	------------------------------------------------------------------
	-- Visibilité : la boucle se met en pause quand le live est caché
	------------------------------------------------------------------
	local function computeShown(): boolean
		if type(ctx.IsVisible) == "function" then
			local ok, visible = pcall(ctx.IsVisible)
			if ok then
				return visible ~= false
			end
		end
		local node: Instance? = ctx.Container
		while node and node:IsA("GuiObject") do
			if not (node :: GuiObject).Visible then
				return false
			end
			node = node.Parent
		end
		if node and node:IsA("LayerCollector") and not (node :: LayerCollector).Enabled then
			return false
		end
		return true
	end

	------------------------------------------------------------------
	-- LA boucle de rendu
	------------------------------------------------------------------

	-- Une expression = yeux + sourcils + bouche + joues
	local function applyExpression(expression: string, now: number)
		local blinking = now < S.blinkUntil
		local eyeMode = "Open"
		if expression == "Chew" or expression == "Thanks" then
			eyeMode = "Happy"
		elseif expression == "Sip" or (blinking and (expression == "Idle" or expression == "Talk")) then
			eyeMode = "Closed"
		end
		local big = expression == "Wow"
		for _, eye in ipairs(eyes) do
			eye.Open.Visible = eyeMode == "Open"
			eye.Happy.Visible = eyeMode == "Happy"
			eye.Relaxed.Visible = eyeMode == "Closed"
			if eyeMode == "Open" then
				eye.Sclera.Size = big and UDim2.fromOffset(12.5, 14) or UDim2.fromOffset(11, 12)
				eye.Iris.Size = big and UDim2.fromOffset(7.5, 8.5) or UDim2.fromOffset(8.5, 9.5)
				local w, h = eye.Sclera.Size.X.Offset, eye.Sclera.Size.Y.Offset
				eye.Iris.Position = UDim2.fromOffset(w / 2 + S.lookX, h / 2 + 0.5 + S.lookY)
				eye.Lash.Position = UDim2.fromOffset(7, big and 1.2 or 2.5)
			end
			-- Sourcils
			local browY, browRot = 27, eye.Side * 6
			if big then
				browY, browRot = 23, eye.Side * -10
			elseif expression == "Bite" then
				browY, browRot = 25, eye.Side * -4
			elseif expression == "Thanks" or expression == "Chew" then
				browY, browRot = 26, eye.Side * -6
			elseif expression == "Sip" then
				browY, browRot = 27, eye.Side * 2
			end
			eye.Brow.Position = UDim2.fromOffset(eye.X, browY)
			eye.Brow.Rotation = browRot
		end
		-- Bouche
		local open, w, h = false, 10, 8
		if expression == "Bite" then
			open, w, h = true, 14, 12
		elseif big then
			open, w, h = true, 8, 10
		elseif expression == "Chew" then
			open, w, h = true, 9, 2.5 + math.abs(math.sin(S.clock * 15)) * 4
		elseif expression == "Talk" then
			open, w, h = true, 8, 2 + math.abs(math.sin(S.clock * 13)) * 5
		elseif expression == "Sip" then
			open, w, h = true, 4, 4
		end
		mouth.Visible = open
		if open then
			mouth.Size = UDim2.fromOffset(w, h)
			teeth.Visible = h >= 7
			tongue.Visible = h >= 6
		end
		smile.Visible = not open and expression ~= "Thanks"
		catMouth.Visible = expression == "Thanks"
		-- Joues
		if expression ~= S.shownExpression then
			S.shownExpression = expression
			local blush = (expression == "Thanks" or expression == "Wow") and 0.15 or (expression == "Chew" and 0.3 or 0.5)
			for _, b in ipairs(blushes) do
				b.BackgroundTransparency = blush
				b.Size = UDim2.fromOffset(expression == "Chew" and 12 or 10, expression == "Chew" and 6 or 5)
			end
		end
	end

	ctx.OnRender(function(rawDt: number)
		local dt = math.min(rawDt, 0.1)
		S.visibilityTimer -= dt
		if S.visibilityTimer <= 0 then
			S.visibilityTimer = 0.5
			S.shown = computeShown()
		end
		if not S.shown then
			return
		end
		S.clock += dt
		local now = os.clock()

		-- Tâches planifiées (messages en rafale, fin de raid, dons...)
		if #pending > 0 then
			local index = 1
			while index <= #pending do
				local job = pending[index]
				if now >= job.At then
					table.remove(pending, index)
					local ok, err = pcall(job.Run)
					if not ok then
						warn("[LiveStream] " .. tostring(err))
					end
				else
					index += 1
				end
			end
		end

		-- Repas (machine à états) + gestes
		updateMeal(dt, now)
		if now >= S.gestureUntil then
			S.gesture = nil
		end

		-- Expression du moment (la plus importante gagne)
		local expression = "Idle"
		if now < S.thanksUntil then
			expression = "Thanks"
		elseif now < S.wowUntil then
			expression = "Wow"
		elseif now < S.biteUntil then
			expression = "Bite"
		elseif now < S.sipUntil then
			expression = "Sip"
		elseif now < S.chewUntil then
			expression = "Chew"
		elseif now < S.talkUntil then
			expression = "Talk"
		end

		-- Regard : caméra, chat, nourriture...
		if now >= S.nextBlink then
			S.blinkUntil = now + 0.12
			S.nextBlink = now + random:NextNumber(2, 5)
		end
		if not mealBusy and now >= S.nextLook then
			S.nextLook = now + random:NextNumber(1.2, 3)
			local roll = random:NextNumber()
			if roll < 0.55 then
				S.lookTargetX, S.lookTargetY = 0, 0 -- la caméra
			elseif roll < 0.8 then
				S.lookTargetX, S.lookTargetY = 1.6, -0.4 -- le chat
			else
				S.lookTargetX, S.lookTargetY = random:NextNumber(-1.5, 1.5), 1.6 -- l'assiette
			end
		end
		S.lookX = approach(S.lookX, S.lookTargetX, 10, dt)
		S.lookY = approach(S.lookY, S.lookTargetY, 10, dt)
		applyExpression(expression, now)

		-- Balancement doux (plus rapide quand elle mâche)
		local chewing = expression == "Chew"
		local bob = chewing and math.abs(math.sin(S.clock * 9)) * 1.6 or math.sin(S.clock * 2) * 1.2
		streamer.Position = UDim2.new(0.5, 0, 0, STREAMER_Y + bob)
		local tilt = chewing and math.sin(S.clock * 7) * 3.5 or math.sin(S.clock * 1.3) * 2.5
		if expression == "Thanks" then
			tilt = 8
		elseif expression == "Talk" then
			tilt = math.sin(S.clock * 4) * 3
		end
		head.Rotation = approach(head.Rotation, tilt, 12, dt)

		-- Mains : repas, geste ou repos (avec un léger mouvement)
		if not mealBusy then
			if S.gesture == "Heart" then
				leftArm.TX, leftArm.TY = -8, MOUTH_Y + 24
				rightArm.TX, rightArm.TY = 8, MOUTH_Y + 24
			elseif S.gesture == "Wave" then
				leftArm.TX, leftArm.TY = -50 + math.sin(S.clock * 14) * 5, HEAD_Y + 8
				rightArm.TX, rightArm.TY = rightArm.RestX, rightArm.RestY
			else
				leftArm.TX, leftArm.TY = leftArm.RestX + math.sin(S.clock * 1.1) * 1.5, leftArm.RestY
				rightArm.TX, rightArm.TY = rightArm.RestX, rightArm.RestY + math.sin(S.clock * 1.3) * 1.2
			end
		elseif meal.Arm == rightArm then
			leftArm.TX, leftArm.TY = leftArm.RestX, leftArm.RestY
		elseif meal.Arm == leftArm then
			rightArm.TX, rightArm.TY = rightArm.RestX, rightArm.RestY
		end
		for _, arm in ipairs({ leftArm, rightArm }) do
			arm.X = approach(arm.X, arm.TX, 14, dt)
			arm.Y = approach(arm.Y, arm.TY, 14, dt)
			solveArm(arm, bob)
		end
		if S.gesture == "Heart" and effectsOn() and math.floor(S.clock * 3) ~= math.floor((S.clock - dt) * 3) then
			spawnHeart("💖")
		end

		-- Casque qui brille au rythme, pastilles, ruban LED, néon, lumières
		local glow = 0.5 + 0.5 * math.sin(S.clock * 3)
		for _, stroke in ipairs(cupStrokes) do
			stroke.Transparency = 0.05 + glow * 0.5
		end
		for _, ear in ipairs(earGlows) do
			ear.BackgroundTransparency = glow * 0.55
		end
		liveDot.BackgroundTransparency = math.sin(S.clock * 5) > 0 and 0 or 0.6
		avatarLive.BackgroundTransparency = math.sin(S.clock * 5) > 0 and 0 or 0.15
		micLed.BackgroundTransparency = math.sin(S.clock * 2.5) > -0.3 and 0 or 0.5
		if ledRainbow then
			ledGradient.Offset = Vector2.new((S.clock * 0.15) % 1 - 0.5, 0)
		end
		ringGradient.Rotation = (S.clock * 60) % 360
		strokeGradient.Rotation = (S.clock * 30) % 360
		edgeGradient.Offset = Vector2.new(math.sin(S.clock * 0.6) * 0.3, 0)
		goalGradient.Offset = Vector2.new((S.clock * 0.25) % 1 - 0.5, 0)
		if ringGroup.Visible then
			ringStroke.Transparency = 0.05 + glow * 0.12
			ringHaloStroke.Transparency = 0.7 + glow * 0.15
		end
		neonSign.TextTransparency = (math.sin(S.clock * 23) > 0.94) and 0.6 or 0
		shine.BackgroundTransparency = 0.2 + glow * 0.3
		if bokehGroup.Visible then
			for _, dot in ipairs(bokeh) do
				dot.Frame.BackgroundTransparency = dot.Base + 0.12 * math.sin(S.clock * 1.3 + dot.Phase)
			end
		end
		caret.Visible = math.floor(S.clock * 1.6) % 2 == 0
		if followShine.Visible then
			followShineGradient.Offset = Vector2.new(((S.clock * 0.5) % 2) - 1, 0)
		end

		-- Vapeur du bol
		for i, puff in ipairs(steam) do
			if effectsOn() then
				local p = ((S.clock / 2.4) + (i - 1) / 3) % 1
				puff.Position = UDim2.new(0.5, BOWL_X + math.sin(p * 6 + i) * 4, 0, BOWL_BASE - 20 - p * 30)
				puff.Size = UDim2.fromOffset(5 + p * 9, 5 + p * 9)
				puff.BackgroundTransparency = 0.5 + p * 0.5
			elseif puff.BackgroundTransparency < 1 then
				puff.BackgroundTransparency = 1
			end
		end

		-- Miettes / éclats (balistique simple)
		for _, p in ipairs(particles) do
			if p.Active then
				p.Age += dt
				if p.Age >= p.Life then
					p.Active = false
					p.Frame.Visible = false
				else
					p.VY += 420 * dt
					p.X += p.VX * dt
					p.Y += p.VY * dt
					p.Frame.Position = UDim2.new(p.Scale, p.X, 0, p.Y)
					p.Frame.Rotation += p.Spin * dt
					p.Frame.BackgroundTransparency = math.max(0, (p.Age / p.Life - 0.6) / 0.4)
				end
			end
		end

		-- Scintillement du beurre
		if butterButton.Visible then
			S.sparkleTimer -= dt
			if S.sparkleTimer <= 0 then
				S.sparkleTimer = random:NextNumber(1.5, 3.5)
				sparkle.TextTransparency = 0
				sparkle.Position = UDim2.new(0.5, random:NextInteger(-15, 17), 0, random:NextInteger(BUTTON_H - 6 - BUTTER_H + 3, BUTTON_H - 12))
				UI.Tween(sparkle, 0.6, { TextTransparency = 1 })
			end
			if butterHint.Visible then
				butterHint.Position = UDim2.new(0.5, 0, 0, HINT_Y - math.abs(math.sin(S.clock * 4)) * 3)
			end
		end

		-- Cœurs qui montent à droite
		for _, heart in ipairs(hearts) do
			local label = heart.Label
			if label.Visible then
				local t = (now - heart.Start) / heart.Life
				if t >= 1 then
					label.Visible = false
				else
					label.Position = UDim2.new(1, -18 + heart.X + math.sin(heart.Sway + t * 6) * 6, 0, TABLE_Y - 30 - t * 100)
					label.TextTransparency = t * t
					label.Rotation = math.sin(heart.Sway + t * 4) * 15
				end
			end
		end
		S.nextHeart -= dt
		if S.nextHeart <= 0 then
			S.nextHeart = random:NextNumber(0.6, 1.8) / (1 + followers() * 0.12)
			if effectsOn() or random:NextNumber() < 0.3 then
				spawnHeart()
			end
		end

		-- Spectateurs : marche aléatoire autour de la cible
		S.viewersTimer -= dt
		if S.viewersTimer <= 0 then
			S.viewersTimer = 0.6
			local target = targetViewers()
			viewers += (target - viewers) * 0.25 + target * random:NextNumber(-0.03, 0.03)
			viewers = math.max(1, viewers)
		end
		shownViewers += (viewers - shownViewers) * math.min(1, dt * 4)
		local rising = viewers > shownViewers + 0.5
		viewersLabel.Text = formatCount(math.floor(shownViewers + 0.5))
		viewersLabel.TextColor3 = rising and Color3.fromRGB(140, 255, 170) or WHITE

		-- Likes : montent tout seuls avec les spectateurs
		S.likesTimer -= dt
		if S.likesTimer <= 0 then
			S.likesTimer = 0.5
			addLikes(math.max(0, math.floor(viewers * random:NextNumber(0, 0.004) + random:NextNumber(0, 1.2))), false)
		end
		shownLikes += (likes - shownLikes) * math.min(1, dt * 5)
		likesLabel.Text = "❤ " .. formatCount(math.floor(shownLikes + 0.5))

		-- Nouveaux abonnés de temps en temps (barre d'objectif)
		S.fanTimer -= dt
		if S.fanTimer <= 0 then
			S.fanTimer = random:NextNumber(2.5, 6) / (1 + followers() * 0.08)
			addFollowers(random:NextInteger(1, 2))
		end

		-- Chaque seconde : durée du live dans le titre
		S.secondTimer -= dt
		if S.secondTimer <= 0 then
			S.secondTimer = 1
			S.uptime += 1
			if S.uptime % 5 == 0 then
				applyCompact()
			end
			subtitleLabel.Text = string.format("🍤 %s%s · <font color=\"#FF8FA8\">%d:%02d:%02d</font>", streamTitle, qualityTag, S.uptime // 3600, (S.uptime // 60) % 60, S.uptime % 60)
		end

		-- Abonnement : suit l'état serveur (et annule une attente expirée)
		S.followTimer -= dt
		if S.followTimer <= 0 then
			S.followTimer = 0.5
			refreshFollow(true)
		end

		-- Dons non cliqués : disparaissent à la fin de leur durée
		for id, donation in pairs(donations) do
			if not donation.Done and now >= donation.ExpiresAt then
				if not donation.Claimed then
					donation.Sub.Text = Locale.T("Too late 😢")
				end
				removeDonation(id, 0.4)
			end
		end

		-- Chat : de plus en plus rapide avec les abonnés, raids de temps en temps
		S.chatTimer -= dt
		if S.chatTimer <= 0 then
			local interval = math.clamp(1.4 / (1 + followers() * 0.15), 0.25, 1.4)
			S.chatTimer = random:NextNumber(0.6, 1.3) * interval
			chatTick()
		end
		if chat.Visible then
			S.nextRaid -= dt
			if S.nextRaid <= 0 then
				S.nextRaid = random:NextNumber(70, 140)
				startRaid()
			end
		end
	end)
end

function LiveStream.Stop(_ctx)
	-- Tout est dans ctx.Container (détruit par le StimulusManager)
end

return LiveStream
