--[[
	ChatReplies (ModuleScript)
	Emplacement : ReplicatedStorage > Client > Stimuli > Live > ChatReplies

	Ce que répondent la streameuse et les faux spectateurs quand le JOUEUR
	écrit dans le chat du live (Stimuli > LiveStream). Module "pur" (aucun
	service Roblox) : testable hors de Roblox.

	Entrée : le texte DÉJÀ FILTRÉ par le serveur (RemoteFunction
	"FilterText") et ses sujets (Shared > ChatTopics, ex. { "Greeting",
	"Question" }). Sortie : un "plan" que LiveStream joue dans le temps :
		{
			Topic = "Greeting",            -- sujet principal (ou "None", "Filtered"...)
			Mood = { Expression, Gesture, Float, Hearts },  -- réaction de la streameuse
			Host = { Delay = 1.7, Text = "coucou \1 !!" },  -- sa réponse (bulle + chat)
			Viewers = { { Delay = 1.2, Text = "...", Mod = false }, ... }, -- 1 à 4 (+ modo)
		}
	Le pseudo du joueur est remplacé par le caractère NAME ("\1") : LiveStream
	le met en valeur dans le chat (mention dorée) et le remet en clair dans la
	bulle. Toutes les phrases sont gentilles (même quand le joueur est
	méchant : réponses mignonnes / taquines, jamais d'insulte) et ne demandent
	jamais d'information personnelle.
	Chaque liste existe en anglais ET en français ({ en = {...}, fr = {...} }),
	"{n}" = pseudo du joueur.
]]

local ChatReplies = {}

-- Marque du pseudo dans les textes du plan (jamais tapée par un joueur :
-- le serveur retire les caractères de contrôle)
ChatReplies.NAME = "\1"

export type Mood = { Expression: string, Gesture: string?, Float: string?, Hearts: number? }
export type Line = { Delay: number, Text: string, Mod: boolean? }
export type Plan = { Topic: string, Mood: Mood, Host: Line, Viewers: { Line } }

-- Réaction de la streameuse (expression du visage, geste des bras, emoji qui
-- s'envole au-dessus de sa tête, nombre de cœurs)
ChatReplies.Moods = {
	Greeting = { Expression = "Happy", Gesture = "Wave", Float = "👋", Hearts = 1 },
	Bye = { Expression = "Happy", Gesture = "Wave", Float = "👋", Hearts = 1 },
	Love = { Expression = "Love", Gesture = "Heart", Float = "💖", Hearts = 4 },
	Compliment = { Expression = "Shy", Gesture = "Cheeks", Float = "🥰", Hearts = 3 },
	Mean = { Expression = "Pout", Float = "🥺" },
	Question = { Expression = "Think", Gesture = "Think", Float = "❓" },
	Food = { Expression = "Yum", Gesture = "Cheeks", Float = "🤤", Hearts = 1 },
	Butter = { Expression = "Wow", Gesture = "Cheer", Float = "🧈", Hearts = 1 },
	ASMR = { Expression = "Shh", Gesture = "Shh", Float = "🤫" },
	Dopamine = { Expression = "Wow", Gesture = "Cheer", Float = "🤯", Hearts = 1 },
	Follow = { Expression = "Shy", Gesture = "Heart", Float = "💜", Hearts = 3 },
	Laugh = { Expression = "Laugh", Float = "😂", Hearts = 1 },
	Music = { Expression = "Vibe", Gesture = "Cheer", Float = "🎵" },
	Sleep = { Expression = "Sleepy", Float = "💤" },
	Sad = { Expression = "Sad", Gesture = "Heart", Float = "💜", Hearts = 2 },
	Happy = { Expression = "Laugh", Gesture = "Cheer", Float = "🎉", Hearts = 2 },
	Game = { Expression = "Wow", Gesture = "Cheer", Float = "🎮" },
	Help = { Expression = "Think", Gesture = "Point", Float = "💡" },
	Age = { Expression = "Wink", Gesture = "Shh", Float = "🤫" },
	Name = { Expression = "Shy", Gesture = "Wave", Float = "✨", Hearts = 1 },
	Pet = { Expression = "Love", Gesture = "Cheeks", Float = "🐾", Hearts = 2 },
	Weather = { Expression = "Think", Gesture = "Point", Float = "☀️" },
	School = { Expression = "Talk", Gesture = "Point", Float = "📚" },
	None = { Expression = "Happy", Gesture = "Wave", Float = "💜", Hearts = 1 },
	-- Cas particuliers (voir Build)
	Filtered = { Expression = "Pout", Float = "🙈" },
	Test = { Expression = "Wow", Gesture = "Point", Float = "✅" },
	HowAreYou = { Expression = "Happy", Gesture = "Wave", Float = "😊", Hearts = 1 },
	Emoji = { Expression = "Laugh", Float = "✨", Hearts = 2 },
}

----------------------------------------------------------------------
-- Réponses de la streameuse (lues dans la bulle + écrites dans le chat)
----------------------------------------------------------------------
ChatReplies.Host = {
	Greeting = {
		en = {
			"hiii {n}!! welcome to the stream 💜", "omg hi {n}! grab a snack and stay a while 🍪",
			"heyyy {n} 👋 you're just in time for the crunch", "welcome {n}!! the butter says hi too 🧈",
			"hi {n}! so happy you're here 🥰", "hello hello {n}! make yourself comfy 💜",
			"{n}!! hiii, did you eat yet? 🍜", "yo {n}! perfect timing, i just refilled the plate 😋",
			"hey {n} 👋 chat, say hi to {n}!", "welcome in {n}! the vibes are immaculate today ✨",
		},
		fr = {
			"coucou {n} !! bienvenue dans le live 💜", "oh salut {n} ! prends un goûter et installe-toi 🍪",
			"heyyy {n} 👋 t'arrives pile pour le crunch", "bienvenue {n} !! le beurre te dit bonjour aussi 🧈",
			"salut {n} ! trop contente que tu sois là 🥰", "coucou coucou {n} ! fais comme chez toi 💜",
			"{n} !! coucou, t'as mangé ? 🍜", "wesh {n} ! pile au bon moment, je viens de resservir 😋",
			"hey {n} 👋 le chat, dites bonjour à {n} !", "bienvenue {n} ! l'ambiance est parfaite aujourd'hui ✨",
		},
	},
	Bye = {
		en = {
			"bye {n}!! thanks for watching 💜", "noooo {n} don't go 🥺 ...ok see you soon!",
			"see you soon {n}! i'll save you a snack 🍪", "bye bye {n} 👋 sweet dreams!",
			"thanks for hanging out {n}! come back soon 💜", "take care {n}!! drink some water 💧",
			"bye {n}! the butter will miss you 🧈", "see ya {n} ✨ you were the best chatter today",
		},
		fr = {
			"bye {n} !! merci d'avoir regardé 💜", "nooon {n} pars pas 🥺 ...bon, à bientôt !",
			"à bientôt {n} ! je te garde un goûter 🍪", "bye bye {n} 👋 fais de beaux rêves !",
			"merci pour ta visite {n} ! reviens vite 💜", "prends soin de toi {n} !! bois de l'eau 💧",
			"salut {n} ! le beurre va te regretter 🧈", "à plus {n} ✨ t'étais la star du chat aujourd'hui",
		},
	},
	Love = {
		en = {
			"awww {n} i love you too 💜💜", "stop it {n} you're making me blush 🥰",
			"sending you the biggest heart {n} 💖", "{n} is officially my favorite chatter 💖",
			"you're too sweet {n} 🥺💜", "love you more {n}!! 💕",
			"chat, {n} is spreading love, i repeat, {n} is spreading love 💜", "aww thank you {n}! this is a wholesome stream 💖",
		},
		fr = {
			"ooooh {n} moi aussi je t'aime 💜💜", "arrête {n} tu vas me faire rougir 🥰",
			"je t'envoie un énorme cœur {n} 💖", "{n} est officiellement mon viewer préféré 💖",
			"t'es trop chou {n} 🥺💜", "moi encore plus {n} !! 💕",
			"le chat, {n} répand de l'amour, je répète, {n} répand de l'amour 💜", "ooh merci {n} ! ce live est trop mignon 💖",
		},
	},
	Compliment = {
		en = {
			"thank youuu {n} 🥰 you're the best!", "omg {n} stop, you're too kind 😭💜",
			"you just made my day {n} ✨", "i'm framing that message {n} 🖼️💜",
			"thanks {n}!! i practiced my crunch all week 😤", "no YOU'RE amazing {n} 💖",
			"{n} with the kind words today 🥺", "chat, be more like {n} 💜",
		},
		fr = {
			"merciii {n} 🥰 t'es au top !", "oh {n} arrête, c'est trop gentil 😭💜",
			"tu viens d'illuminer ma journée {n} ✨", "je vais encadrer ce message {n} 🖼️💜",
			"merci {n} !! j'ai entraîné mon crunch toute la semaine 😤", "non c'est TOI qui es incroyable {n} 💖",
			"{n} et ses mots gentils aujourd'hui 🥺", "le chat, soyez tous comme {n} 💜",
		},
	},
	Mean = {
		en = {
			"aww {n}, that's a bit spicy 🌶️ but i still like you 💜", "ouch 🥺 ...i'll heal with butter 🧈",
			"hmm, sounds like someone needs a snack {n} 🍪", "no bad vibes here {n}, only crunchy vibes ✨",
			"i'll take that as a compliment 😌", "sending you a hug anyway {n} 🤗",
			"everyone has off days {n}, want a cookie? 🍪", "noted {n} 📝 ...*crunches louder*",
		},
		fr = {
			"oh {n}, c'est un peu piquant 🌶️ mais je t'aime bien quand même 💜", "aïe 🥺 ...je vais guérir avec du beurre 🧈",
			"hmm, on dirait que quelqu'un a besoin d'un goûter {n} 🍪", "pas de mauvaises ondes ici {n}, que des ondes croustillantes ✨",
			"je prends ça pour un compliment 😌", "je t'envoie un câlin quand même {n} 🤗",
			"tout le monde a des jours sans {n}, tu veux un cookie ? 🍪", "c'est noté {n} 📝 ...*croque encore plus fort*",
		},
	},
	Question = {
		en = {
			"good question {n}! the answer is... butter 🧈", "hmm 🤔 let me think about it while i crunch",
			"ooh {n}, i'd say yes! ...probably 😅", "that's top secret {n} 🤫",
			"great question! ask me again after this bite 😋", "{n}, honestly? no idea 😂",
			"hmm... maybe? chat, what do you think? 🤔", "the answer is always more snacks {n} 🍪",
			"i'll answer that in the next stream 👀", "you ask the real questions {n} 🧐",
		},
		fr = {
			"bonne question {n} ! la réponse est... le beurre 🧈", "hmm 🤔 laisse-moi réfléchir pendant que je croque",
			"ooh {n}, je dirais oui ! ...enfin je crois 😅", "c'est top secret {n} 🤫",
			"super question ! redemande-moi après cette bouchée 😋", "{n}, honnêtement ? aucune idée 😂",
			"hmm... peut-être ? le chat, vous en pensez quoi ? 🤔", "la réponse, c'est toujours plus de goûters {n} 🍪",
			"je répondrai à ça au prochain live 👀", "tu poses les vraies questions {n} 🧐",
		},
	},
	Food = {
		en = {
			"ooh you're hungry too {n}? let's eat together 🍜", "mmm {n}, now i want that too 🤤",
			"{n} you have great taste 😋", "next stream: i'll try your favorite food {n}!",
			"food is life {n} 🍕", "omg yes {n}, that sounds delicious 🤤",
			"noted for the menu {n} 📝🍔", "{n}, grab a snack and crunch with me! 🍪",
			"today's menu: noodles, dumplings and a bit of butter 🍜🧈", "whatever the chat tells me to eat 😋",
		},
		fr = {
			"ooh toi aussi t'as faim {n} ? on mange ensemble 🍜", "mmm {n}, maintenant j'en veux aussi 🤤",
			"{n} t'as trop bon goût 😋", "au prochain live je goûte ton plat préféré {n} !",
			"la bouffe c'est la vie {n} 🍕", "oh oui {n}, ça a l'air trop bon 🤤",
			"noté pour le menu {n} 📝🍔", "{n}, prends un goûter et croque avec moi ! 🍪",
			"au menu : nouilles, raviolis et un peu de beurre 🍜🧈", "ce que le chat me dit de manger 😋",
		},
	},
	Butter = {
		en = {
			"BUTTER! {n} gets it 🧈", "*CRONCH* this one's for you {n} 🧈",
			"salted or unsalted, {n}? 🧈🤔", "{n}, click the butter and hear the magic ✨",
			"the butter has fans now 😭🧈", "i will never stop crunching butter {n} 😤",
			"butter is my love language {n} 🧈💜", "shh... listen... *crunch* 🧈",
		},
		fr = {
			"LE BEURRE ! {n} a compris 🧈", "*CROUNCH* celle-là c'est pour toi {n} 🧈",
			"demi-sel ou doux, {n} ? 🧈🤔", "{n}, clique sur le beurre et écoute la magie ✨",
			"le beurre a des fans maintenant 😭🧈", "je n'arrêterai jamais de croquer du beurre {n} 😤",
			"le beurre c'est mon langage de l'amour {n} 🧈💜", "chut... écoute... *crunch* 🧈",
		},
	},
	ASMR = {
		en = {
			"shhh... *whispers* hi {n} 🤫", "let me get closer to the mic for you {n} 🎙️",
			"*tap tap tap* ...did you get tingles {n}? ✨", "ASMR mode activated for {n} 🎧",
			"*soft crunch* ...relaxing, right? 😌", "put your headphones on {n} 🎧",
			"*whispers* the butter is listening 🧈", "close your eyes {n}... and crunch 😌",
		},
		fr = {
			"chuuut... *chuchote* coucou {n} 🤫", "je m'approche du micro pour toi {n} 🎙️",
			"*tap tap tap* ...t'as eu des frissons {n} ? ✨", "mode ASMR activé pour {n} 🎧",
			"*crunch tout doux* ...relaxant, non ? 😌", "mets ton casque {n} 🎧",
			"*chuchote* le beurre nous écoute 🧈", "ferme les yeux {n}... et croque 😌",
		},
	},
	Dopamine = {
		en = {
			"keep clicking {n}!! the counter loves you 📈", "{n}, the dopamine is flowing 🤯",
			"numbers go up, happiness goes up 📈✨", "big clicker energy {n} 👆",
			"don't forget to visit the ocean {n} 🌊", "every click feeds the stream {n} 💜",
			"{n} is a clicking legend 👆🔥", "more upgrades = more me 😌",
		},
		fr = {
			"continue de cliquer {n} !! le compteur t'adore 📈", "{n}, la dopamine coule à flots 🤯",
			"les chiffres montent, le bonheur aussi 📈✨", "énergie de gros cliqueur {n} 👆",
			"n'oublie pas d'aller à l'océan {n} 🌊", "chaque clic nourrit le live {n} 💜",
			"{n} est une légende du clic 👆🔥", "plus d'améliorations = plus de moi 😌",
		},
	},
	Follow = {
		en = {
			"thanks for the support {n}!! 💜", "{n}, you're officially part of the family 💜",
			"hit that follow and the donations open up 💸", "welcome to the crunch crew {n} 🧈💜",
			"more followers = more snacks 🍪", "{n} you're a real one 💜",
			"notifications on {n}? 🔔 i see you", "the follower goal thanks you {n} 🎯",
		},
		fr = {
			"merci pour le soutien {n} !! 💜", "{n}, tu fais officiellement partie de la famille 💜",
			"abonne-toi et les dons s'ouvrent 💸", "bienvenue dans la team crunch {n} 🧈💜",
			"plus d'abonnés = plus de goûters 🍪", "{n} t'es au top 💜",
			"les notifs activées {n} ? 🔔 je te vois", "l'objectif d'abonnés te remercie {n} 🎯",
		},
	},
	Laugh = {
		en = {
			"HAHAHA {n} stop 😂", "i almost choked on my noodles {n} 😂🍜",
			"LMAO {n} you're too funny", "{n} i can't breathe 😭😂",
			"why is that so funny 😂😂", "{n} the comedian of the chat 🤣",
			"hehe, you got me {n} 😆", "ok that was hilarious {n} 😂",
		},
		fr = {
			"MDRRR {n} arrête 😂", "j'ai failli m'étouffer avec mes nouilles {n} 😂🍜",
			"PTDR {n} t'es trop drôle", "{n} j'arrive plus à respirer 😭😂",
			"pourquoi c'est si drôle 😂😂", "{n} l'humoriste du chat 🤣",
			"hihi, tu m'as eue {n} 😆", "ok c'était trop drôle {n} 😂",
		},
	},
	Music = {
		en = {
			"🎵 i'm vibing with you {n}", "what should we listen to next {n}? 🎶",
			"{n}, tell me your favorite song 🎵", "*head bob* this beat hits 🎧",
			"music + snacks = perfect stream 🎶🍪", "i'd sing but my mouth is full 😂🎵",
			"lofi beats to crunch to 🎧", "{n} the DJ of the stream 🎶",
		},
		fr = {
			"🎵 je vibe avec toi {n}", "on écoute quoi ensuite {n} ? 🎶",
			"{n}, dis-moi ta chanson préférée 🎵", "*hoche la tête* ce son est trop bien 🎧",
			"musique + goûter = live parfait 🎶🍪", "je chanterais bien mais j'ai la bouche pleine 😂🎵",
			"lofi beats pour croquer 🎧", "{n} le DJ du live 🎶",
		},
	},
	Sleep = {
		en = {
			"*yawns* same {n}, i'm sleepy too 😴", "go to sleep {n}!! the butter will wait 🧈💤",
			"sweet dreams {n} 🌙", "one more snack and then bed 😴🍪",
			"{n}, it's nap time for real 💤", "i'll whisper you to sleep {n} 🤫💤",
			"sleep is important {n}! goodnight 🌙", "yawn... who else is sleepy? 😪",
		},
		fr = {
			"*bâille* pareil {n}, j'ai sommeil aussi 😴", "va dormir {n} !! le beurre t'attendra 🧈💤",
			"fais de beaux rêves {n} 🌙", "encore un goûter et au lit 😴🍪",
			"{n}, c'est l'heure de la sieste pour de vrai 💤", "je vais te chuchoter une berceuse {n} 🤫💤",
			"le sommeil c'est important {n} ! bonne nuit 🌙", "*bâille*... qui d'autre a sommeil ? 😪",
		},
	},
	Sad = {
		en = {
			"aww {n} 🥺 sending you the biggest hug 🤗", "{n}, you're not alone, the whole chat is here 💜",
			"want some butter to feel better {n}? 🧈", "it's okay to have sad days {n}, we love you 💜",
			"virtual cookie for {n} 🍪💜", "chat, let's send {n} some love 💜💜",
			"{n}, i hope your day gets better ✨", "stay as long as you want {n}, it's cozy here 💜",
		},
		fr = {
			"ooh {n} 🥺 je t'envoie un énorme câlin 🤗", "{n}, tout le chat est là pour toi 💜",
			"tu veux du beurre pour aller mieux {n} ? 🧈", "c'est normal d'avoir des jours tristes {n}, on t'aime 💜",
			"cookie virtuel pour {n} 🍪💜", "le chat, on envoie de l'amour à {n} 💜💜",
			"{n}, j'espère que ta journée va s'arranger ✨", "reste autant que tu veux {n}, on est bien ici 💜",
		},
	},
	Happy = {
		en = {
			"yaaay {n}! happy vibes only 🎉", "your good mood is contagious {n} 😄",
			"let's gooo {n}!! 🎉", "this makes me so happy {n} 🥰",
			"{n}'s energy is unmatched ✨", "happy stream, happy chat, happy butter 🧈😄",
			"woohoo! let's celebrate with a crunch {n} 🎉", "love that for you {n} 💖",
		},
		fr = {
			"youpiii {n} ! que des bonnes ondes 🎉", "ta bonne humeur est contagieuse {n} 😄",
			"let's gooo {n} !! 🎉", "ça me rend trop heureuse {n} 🥰",
			"l'énergie de {n} est incroyable ✨", "live heureux, chat heureux, beurre heureux 🧈😄",
			"youhou ! on fête ça avec un crunch {n} 🎉", "trop bien pour toi {n} 💖",
		},
	},
	Game = {
		en = {
			"gamer {n} in the chat 🎮", "have you tried the arcade {n}? 🕹️",
			"i'm better at eating than gaming 😂🎮", "GG {n}! 🏆",
			"{n}, one more game then snack break? 🎮🍪", "what's your favorite game {n}? 👀",
			"this game is dangerously addictive 😳", "i'd play with you but my hands are full of noodles 🍜",
		},
		fr = {
			"gamer {n} dans le chat 🎮", "t'as testé l'arcade {n} ? 🕹️",
			"je suis meilleure pour manger que pour jouer 😂🎮", "GG {n} ! 🏆",
			"{n}, une dernière partie et pause goûter ? 🎮🍪", "c'est quoi ton jeu préféré {n} ? 👀",
			"ce jeu est dangereusement addictif 😳", "je jouerais bien avec toi mais j'ai les mains pleines de nouilles 🍜",
		},
	},
	Help = {
		en = {
			"tip: click the butter for bonus dopamine 🧈", "{n}, follow the stream to unlock donations 💸",
			"pro tip {n}: upgrades stack, buy them all 📈", "stuck? the ocean gives permanent bonuses 🌊",
			"my tip: golden stars give HUGE bonuses 🌟", "the arcade has fun games {n}! 🕹️",
			"take breaks, drink water, click responsibly 💧", "ask the chat {n}, they know everything 😂",
		},
		fr = {
			"astuce : clique sur le beurre pour un bonus de dopamine 🧈", "{n}, abonne-toi au live pour débloquer les dons 💸",
			"conseil de pro {n} : les améliorations s'additionnent, prends-les toutes 📈", "tu bloques ? l'océan donne des bonus permanents 🌊",
			"mon astuce : les étoiles dorées donnent d'ÉNORMES bonus 🌟", "l'arcade a des jeux trop cool {n} ! 🕹️",
			"fais des pauses, bois de l'eau, clique avec modération 💧", "demande au chat {n}, ils savent tout 😂",
		},
	},
	Age = {
		en = {
			"that's a secret {n} 🤫", "old enough to crunch butter on stream 😂🧈",
			"age is just a number, snacks are forever 🍪", "i'm as old as this noodle bowl 🍜 ...wait",
			"let's keep that a mystery {n} ✨", "in stream years? like 1000 😂",
			"a streamer never tells {n} 😌", "{n}, i'm forever young 😎",
		},
		fr = {
			"c'est un secret {n} 🤫", "assez grande pour croquer du beurre en live 😂🧈",
			"l'âge c'est qu'un chiffre, les goûters c'est pour toujours 🍪", "j'ai l'âge de ce bol de nouilles 🍜 ...attends",
			"gardons ça mystérieux {n} ✨", "en années de live ? genre 1000 😂",
			"une streameuse ne dit jamais son âge {n} 😌", "{n}, je suis éternellement jeune 😎",
		},
	},
	Name = {
		en = {
			"i'm MangeTout! nice to meet you {n} 💜", "MangeTout! it means \"eats everything\" in French 😋",
			"everyone calls me the butter queen 👑🧈", "you can call me Mange ✨",
			"MangeTout, professional snack tester 😎", "it's MangeTout! and you're {n}, i'll remember 💜",
			"the streamer is me, MangeTout, hi 👋", "MangeTout! {n} is a cute name too 🥰",
		},
		fr = {
			"moi c'est MangeTout ! enchantée {n} 💜", "MangeTout ! parce que je mange tout 😋",
			"tout le monde m'appelle la reine du beurre 👑🧈", "tu peux m'appeler Mange ✨",
			"MangeTout, goûteuse professionnelle de goûters 😎", "c'est MangeTout ! et toi c'est {n}, je retiens 💜",
			"la streameuse c'est moi, MangeTout, coucou 👋", "MangeTout ! {n} c'est trop joli comme pseudo aussi 🥰",
		},
	},
	Pet = {
		en = {
			"awww i love animals {n} 🐱", "my cat is sleeping behind the camera 🐈💤",
			"{n}, give your pet a pat from me 🐾", "animals make everything better 🐶💜",
			"is your pet watching the stream too {n}? 👀", "cats > butter? hmm, tough one 🐱🧈",
			"so cute!! 🥺🐾", "pet tax paid in snacks 🍪🐾",
		},
		fr = {
			"ooh j'adore les animaux {n} 🐱", "mon chat dort derrière la caméra 🐈💤",
			"{n}, fais une caresse à ton animal de ma part 🐾", "les animaux rendent tout meilleur 🐶💜",
			"ton animal regarde le live aussi {n} ? 👀", "les chats > le beurre ? hmm, dur 🐱🧈",
			"trop mignon !! 🥺🐾", "la taxe animal se paie en goûters 🍪🐾",
		},
	},
	Weather = {
		en = {
			"it's always sunny in the stream ☀️", "perfect weather for noodles 🍜🌧️",
			"{n}, stay cozy whatever the weather 💜", "rain outside, crunch inside 🌧️🧈",
			"i heard a storm upgrade exists... ⛈️", "weather report: 100% chance of snacks 🍪",
			"bring an umbrella {n} ☂️", "sun or snow, we stream 😤",
		},
		fr = {
			"il fait toujours beau dans le live ☀️", "temps parfait pour des nouilles 🍜🌧️",
			"{n}, reste bien au chaud quel que soit le temps 💜", "la pluie dehors, le crunch dedans 🌧️🧈",
			"il paraît qu'il existe une amélioration orage... ⛈️", "météo du jour : 100 % de chances de goûters 🍪",
			"prends un parapluie {n} ☂️", "soleil ou neige, on stream 😤",
		},
	},
	School = {
		en = {
			"homework first, stream after {n} 📚😤", "good luck with school {n}! you got this 💪",
			"study break with snacks? i approve 🍪📚", "{n}, i believe in you for the exam ✨",
			"school is hard, butter is soft 🧈", "don't forget to study {n}! 📖",
			"i was always eating in class 🤫", "smart AND a great chatter, {n}? 🧠💜",
		},
		fr = {
			"les devoirs d'abord, le live après {n} 📚😤", "bon courage pour l'école {n} ! tu vas gérer 💪",
			"pause révision avec un goûter ? j'approuve 🍪📚", "{n}, je crois en toi pour le contrôle ✨",
			"l'école c'est dur, le beurre c'est doux 🧈", "oublie pas de réviser {n} ! 📖",
			"moi je mangeais toujours en cours 🤫", "une tête ET la star du chat, {n} ? 🧠💜",
		},
	},
	None = {
		en = {
			"hi {n}!! thanks for chatting 💜", "i see you {n} 👀💜", "{n}, you're so real for that",
			"ooh interesting {n}! 🤔", "thanks for the message {n} ✨", "chat is so alive today, thanks {n}!",
			"{n} said it 👏", "noted {n} 📝💜", "haha {n} you're fun 😄", "love reading your messages {n} 💖",
		},
		fr = {
			"coucou {n} !! merci pour ton message 💜", "je te vois {n} 👀💜", "{n}, trop vrai",
			"ooh intéressant {n} ! 🤔", "merci pour le message {n} ✨", "le chat est trop vivant aujourd'hui, merci {n} !",
			"{n} l'a dit 👏", "c'est noté {n} 📝💜", "hihi {n} t'es drôle 😄", "j'adore lire tes messages {n} 💖",
		},
	},
}

----------------------------------------------------------------------
-- Réponses des faux spectateurs
----------------------------------------------------------------------
ChatReplies.Viewers = {
	Greeting = {
		en = {
			"hi {n}!! 👋", "welcome {n} 💜", "heyyy", "hello!! 👋👋", "yo {n}", "hi hi hi", "welcome to the fam 💜",
			"hiii 🥰", "hey {n}, you're gonna love the crunch", "sup {n}", "welcome!! grab a snack 🍿", "HI {n} 🎉", "👋👋👋",
			"hello from the chat!",
		},
		fr = {
			"coucou {n} !! 👋", "bienvenue {n} 💜", "salut !!", "yo {n}", "coucou coucou", "bienvenue dans la team 💜",
			"slt {n} 🥰", "hey {n}, tu vas adorer le crunch", "wesh {n}", "bienvenue !! prends un goûter 🍿", "SALUT {n} 🎉",
			"👋👋👋", "bonjour {n} !", "re {n} 😄",
		},
	},
	Bye = {
		en = {
			"bye {n}!! 👋", "cya {n}", "noooo come back 😭", "see ya tomorrow!", "bye bye 💜", "take care {n}", "gn {n} 🌙",
			"later {n}!", "sweet dreams 😴", "don't forget to come back 👀", "byeee 👋👋",
		},
		fr = {
			"bye {n} !! 👋", "à plus {n}", "nooon reviens 😭", "à demain !", "bye bye 💜", "prends soin de toi {n}",
			"bonne nuit {n} 🌙", "à la prochaine !", "tchao {n} !", "fais de beaux rêves 😴", "reviens vite 👀", "byeee 👋👋",
		},
	},
	Love = {
		en = {
			"awww 🥺", "so wholesome 💖", "💜💜💜", "we love {n}", "cute 🥰", "LOVE IN THE CHAT 💕", "same {n}!!",
			"wholesome chat 😭💜", "{n} spreading love 💖", "❤️❤️", "we all love her", "this chat is so sweet",
		},
		fr = {
			"ooooh 🥺", "trop mignon 💖", "💜💜💜", "on aime {n}", "trop chou 🥰", "DE L'AMOUR DANS LE CHAT 💕", "pareil {n} !!",
			"chat trop mignon 😭💜", "{n} répand l'amour 💖", "❤️❤️", "on l'aime tous", "ce chat est trop gentil",
		},
	},
	Compliment = {
		en = {
			"facts 💯", "true!!", "she's the GOAT", "W chatter", "agreed {n}", "real 👏", "best streamer ever",
			"10/10 stream", "{n} gets it", "👏👏👏", "so true", "+1",
		},
		fr = {
			"trop vrai 💯", "grave !!", "c'est la GOAT", "W chatteur", "d'accord avec {n}", "réel 👏", "meilleure streameuse",
			"live 10/10", "{n} a tout compris", "👏👏👏", "tellement vrai", "+1",
		},
	},
	Mean = {
		en = {
			"be nice 🥺", "no hate, only butter 🧈", "she's doing her best!!", "chat stays wholesome 💜",
			"take a snack break {n} 🍪", "we're all friends here", "kindness only pls", "not the vibe 😅",
			"hugs for everyone 🤗", "calm down and crunch 😌",
		},
		fr = {
			"on reste gentils 🥺", "pas de haine, que du beurre 🧈", "elle fait de son mieux !!", "le chat reste gentil 💜",
			"prends un goûter {n} 🍪", "on est tous potes ici", "que de la gentillesse svp", "c'est pas la vibe 😅",
			"câlin pour tout le monde 🤗", "respire et croque 😌",
		},
	},
	Question = {
		en = {
			"good question 🤔", "i wanna know too 👀", "+1 to {n}'s question", "she'll say butter 😂", "answer {n}!!",
			"hmm 🤔", "chat, anyone knows?", "probably yes", "no idea lol", "the real question", "big brain question 🧠",
			"asking the important stuff",
		},
		fr = {
			"bonne question 🤔", "moi aussi je veux savoir 👀", "+1 pour la question de {n}", "elle va dire le beurre 😂",
			"réponds à {n} !!", "hmm 🤔", "le chat, quelqu'un sait ?", "sûrement oui", "aucune idée mdr", "la vraie question",
			"question de génie 🧠", "enfin une question importante",
		},
	},
	Food = {
		en = {
			"i'm so hungry now 😭", "yummy 🤤", "same {n}!!", "now i want pizza 🍕", "stop i'm on a diet 😭", "food talk 😋",
			"{n} has taste", "i'm eating chips rn", "we need a food tier list", "🍔🍟🍕", "snack break!", "mukbang next? 👀",
		},
		fr = {
			"j'ai trop faim maintenant 😭", "miam 🤤", "pareil {n} !!", "maintenant je veux une pizza 🍕",
			"stop je suis au régime 😭", "on parle bouffe 😋", "{n} a du goût", "je mange des chips là",
			"il nous faut un classement des plats", "🍔🍟🍕", "pause goûter !", "mukbang raclette ? 👀",
		},
	},
	Butter = {
		en = {
			"BUTTER 🧈🧈", "*cronch*", "the butter sound 🤤", "team salted 🧂", "team unsalted", "{n} likes butter too 😂",
			"BUTTER GANG 🧈", "crunch it!!", "why does butter crunch 😭", "the butter lore", "click the butter!!", "🧈🔊",
		},
		fr = {
			"BEURRE 🧈🧈", "*crounch*", "le bruit du beurre 🤤", "team demi-sel 🧂", "team beurre doux",
			"{n} aime le beurre aussi 😂", "BEURRE GANG 🧈", "croque-le !!", "pourquoi le beurre croustille 😭",
			"le lore du beurre", "clique sur le beurre !!", "🧈🔊",
		},
	},
	ASMR = {
		en = {
			"tingles ✨", "so relaxing 😌", "headphones ON 🎧", "the mic quality 😳", "i'm melting", "shhh 🤫",
			"best ASMR ever", "i got chills", "this is my sleep routine", "more tapping pls", "whisper again!!", "🎧🎧🎧",
		},
		fr = {
			"des frissons ✨", "trop relaxant 😌", "casque MIS 🎧", "la qualité du micro 😳", "je fonds", "chuuut 🤫",
			"meilleur ASMR", "j'ai des frissons", "c'est ma routine du soir", "encore du tapping svp", "chuchote encore !!",
			"🎧🎧🎧",
		},
	},
	Dopamine = {
		en = {
			"CLICK CLICK CLICK 👆", "numbers go brrr 📈", "dopamine overload 🤯", "how many clicks are you at {n}?",
			"the counter is insane", "{n} is rich 🤑", "the grind never stops", "upgrade everything!!", "i'm addicted 😭",
			"one more click...", "📈📈📈", "ocean when? 🌊",
		},
		fr = {
			"CLIQUE CLIQUE CLIQUE 👆", "les chiffres s'envolent 📈", "overdose de dopamine 🤯",
			"t'en es à combien de clics {n} ?", "le compteur est fou", "{n} est riche 🤑", "on grind sans arrêt",
			"améliore tout !!", "je suis accro 😭", "encore un clic...", "📈📈📈", "l'océan c'est quand ? 🌊",
		},
	},
	Follow = {
		en = {
			"followed!! 💜", "notifs on 🔔", "W follow", "the family grows 💜", "we're almost at the goal 🎯",
			"follow train 🚂", "welcome to the team {n}", "day one fan here", "she deserves more followers", "💜💜💜",
		},
		fr = {
			"abonné !! 💜", "notifs activées 🔔", "W follow", "la famille grandit 💜", "on est presque à l'objectif 🎯",
			"train des abonnés 🚂", "bienvenue dans la team {n}", "fan depuis le premier jour",
			"elle mérite plus d'abonnés", "💜💜💜",
		},
	},
	Laugh = {
		en = {
			"LMAO 😂", "💀💀💀", "i'm crying 😭", "{n} is hilarious", "LOL", "hahaha", "😂😂😂", "chat is wild today",
			"she's laughing 😭", "comedy gold", "i spit out my drink", "🤣🤣",
		},
		fr = {
			"MDR 😂", "💀💀💀", "je pleure 😭", "{n} est trop drôle", "PTDR", "hahaha", "😂😂😂",
			"le chat est chaud aujourd'hui", "elle rigole 😭", "de l'or en barre", "j'ai recraché ma boisson", "🤣🤣",
		},
	},
	Music = {
		en = {
			"🎵🎵🎵", "vibing 🎧", "what's the song?", "banger alert 🔥", "{n} has good taste in music", "turn it up!!",
			"dance party 💃", "lofi gang", "🎶 la la la", "add it to the playlist", "i'm dancing in my chair",
			"music makes it 10x better",
		},
		fr = {
			"🎵🎵🎵", "ça vibe 🎧", "c'est quoi le son ?", "alerte banger 🔥", "{n} a bon goût en musique", "monte le son !!",
			"soirée danse 💃", "team lofi", "🎶 la la la", "ajoute-la à la playlist", "je danse sur ma chaise",
			"la musique rend tout 10x mieux",
		},
	},
	Sleep = {
		en = {
			"😴😴😴", "go to bed {n}!!", "sleepy chat", "💤💤", "same, i should sleep", "just one more minute...",
			"gn {n} 🌙", "i'm falling asleep lol", "ASMR = sleep", "*yawns*", "nap time 😴", "who's watching in bed?",
		},
		fr = {
			"😴😴😴", "va au lit {n} !!", "le chat a sommeil", "💤💤", "pareil, je devrais dormir",
			"juste encore une minute...", "bonne nuit {n} 🌙", "je m'endors mdr", "ASMR = dodo", "*bâille*",
			"c'est l'heure de la sieste 😴", "qui regarde depuis son lit ?",
		},
	},
	Sad = {
		en = {
			"hugs {n} 🤗", "💜💜💜", "you got this {n}!", "sending love 💖", "we're here for you", "it'll get better ✨",
			"virtual hug 🤗🤗", "chat loves you {n}", "stay strong 💪", "have a cookie 🍪",
		},
		fr = {
			"câlin {n} 🤗", "💜💜💜", "tu vas y arriver {n} !", "je t'envoie de l'amour 💖", "on est là pour toi",
			"ça va aller ✨", "câlin virtuel 🤗🤗", "le chat t'aime {n}", "courage 💪", "prends un cookie 🍪",
		},
	},
	Happy = {
		en = {
			"yay!! 🎉", "LET'S GOOO", "happy vibes ✨", "😄😄😄", "love this energy", "W {n}", "🎉🎉🎉",
			"so happy for you {n}", "good vibes only", "party in the chat 🥳",
		},
		fr = {
			"youpi !! 🎉", "LET'S GOOO", "bonnes ondes ✨", "😄😄😄", "j'adore cette énergie", "W {n}", "🎉🎉🎉",
			"trop content pour toi {n}", "que des bonnes vibes", "fête dans le chat 🥳",
		},
	},
	Game = {
		en = {
			"gamer moment 🎮", "GG", "the arcade is so fun 🕹️", "1v1 me {n}", "i'm hardstuck lol", "gaming + snacks = life",
			"what level are you {n}?", "🎮🎮🎮", "{n} is a pro", "just one more game...",
		},
		fr = {
			"moment gamer 🎮", "GG", "l'arcade est trop bien 🕹️", "1v1 {n}", "je suis bloqué mdr", "jeux + goûter = la vie",
			"t'es quel niveau {n} ?", "🎮🎮🎮", "{n} est un pro", "juste une dernière partie...",
		},
	},
	Help = {
		en = {
			"click the golden stars 🌟", "go to the ocean when you can 🌊", "buy the cheap upgrades first",
			"the butter gives a bonus!! 🧈", "follow for donations 💸", "i can help {n}!", "tip: DVD corner = jackpot",
			"try the arcade 🕹️", "open the mystery chest 📦", "patience + clicks 👆",
		},
		fr = {
			"clique les étoiles dorées 🌟", "va à l'océan dès que tu peux 🌊", "achète d'abord les améliorations pas chères",
			"le beurre donne des bonus !! 🧈", "abonne-toi pour les dons 💸", "je peux t'aider {n} !",
			"astuce : coin du DVD = jackpot", "teste l'arcade 🕹️", "ouvre le coffre mystère 📦", "patience + clics 👆",
		},
	},
	Age = {
		en = {
			"secret 🤫", "we'll never know 👀", "age is just a number", "she's timeless", "mystery streamer ✨",
			"lol nice try {n}", "no personal info in chat pls 🛡️", "forever young 😎",
		},
		fr = {
			"secret 🤫", "on saura jamais 👀", "l'âge c'est qu'un chiffre", "elle est intemporelle", "streameuse mystère ✨",
			"mdr bien essayé {n}", "pas d'infos perso dans le chat 🛡️", "éternellement jeune 😎",
		},
	},
	Name = {
		en = {
			"nice name {n}", "MangeTout the legend", "butter queen 👑", "{n} cool username",
			"she eats everything, it's in the name", "iconic name", "hi {n} 👋", "name checks out 😂",
		},
		fr = {
			"joli pseudo {n}", "MangeTout la légende", "la reine du beurre 👑", "{n} pseudo stylé",
			"elle mange tout, c'est dans le nom", "pseudo iconique", "salut {n} 👋", "le pseudo est mérité 😂",
		},
	},
	Pet = {
		en = {
			"PETS 🥺", "my cat is watching too 🐈", "team dogs 🐶", "team cats 🐱", "awww 🐾", "pet tax!!",
			"animals are the best", "{n} i love your pet already", "🐱🐶🐰", "my dog is snoring rn",
		},
		fr = {
			"DES ANIMAUX 🥺", "mon chat regarde aussi 🐈", "team chiens 🐶", "team chats 🐱", "ooooh 🐾", "la taxe animal !!",
			"les animaux c'est la vie", "{n} j'adore déjà ton animal", "🐱🐶🐰", "mon chien ronfle là",
		},
	},
	Weather = {
		en = {
			"it's raining here too 🌧️", "sunny here ☀️", "so cold today ❄️", "perfect stream weather", "cozy vibes",
			"{n} stay warm", "weather talk 😂", "⛈️⛈️", "i love rainy days", "summer when?",
		},
		fr = {
			"il pleut ici aussi 🌧️", "grand soleil ici ☀️", "il fait trop froid aujourd'hui ❄️", "temps parfait pour un live",
			"ambiance cosy", "{n} reste au chaud", "on parle météo 😂", "⛈️⛈️", "j'adore les jours de pluie",
			"l'été c'est quand ?",
		},
	},
	School = {
		en = {
			"i should be doing homework 😭", "good luck {n}!!", "study with me?", "exams are scary", "{n} you got this 💪",
			"school tomorrow 😩", "📚📚", "my teacher probably watches this stream", "study break!!", "math is hard",
		},
		fr = {
			"je devrais faire mes devoirs 😭", "bon courage {n} !!", "on révise ensemble ?", "les contrôles ça fait peur",
			"{n} tu vas gérer 💪", "cours demain 😩", "📚📚", "ma prof regarde ce live sûrement", "pause révisions !!",
			"les maths c'est dur",
		},
	},
	None = {
		en = {
			"true", "real", "W chat", "{n} 💜", "same", "lol", "fr fr", "agreed", "👀", "facts", "chat is alive today",
			"hi {n}!", "+1", "💜",
		},
		fr = {
			"trop vrai", "réel", "W chat", "{n} 💜", "pareil", "mdr", "grave", "d'accord", "👀", "c'est vrai",
			"le chat est vivant aujourd'hui", "coucou {n} !", "+1", "j'avoue",
		},
	},
	-- Message fait uniquement d'emojis
	Emoji = {
		en = { "😂😂", "💜💜", "🔥🔥🔥", "👀", "🥺", "✨✨", "😍", "🙌🙌", "same energy", "the emojis 😭" },
		fr = { "😂😂", "💜💜", "🔥🔥🔥", "👀", "🥺", "✨✨", "😍", "🙌🙌", "même énergie", "les emojis 😭" },
	},
}

----------------------------------------------------------------------
-- Cas particuliers (texte déjà filtré, analysé côté client)
----------------------------------------------------------------------
ChatReplies.Extra = {
	-- Le filtre de Roblox a masqué une partie du message (#####)
	FilteredHost = {
		en = { "oops, the filter ate that one 🤭", "hmm, i couldn't read that 😅", "the filter said no 🙈" },
		fr = { "oups, le filtre a mangé ton message 🤭", "hmm, j'ai pas pu lire 😅", "le filtre a dit non 🙈" },
	},
	Filtered = {
		en = { "🤐", "the filter strikes again 😂", "censored lol", "####?? 👀" },
		fr = { "🤐", "le filtre a encore frappé 😂", "censuré mdr", "####?? 👀" },
	},
	-- Un modo (gentil) quand le message est méchant ou filtré
	Mod = {
		en = { "keep it friendly please 💜", "be kind in chat pls 🛡️", "friendly reminder: be nice 💜", "only good vibes here 🛡️" },
		fr = { "on reste gentils svp 💜", "soyez gentils dans le chat 🛡️", "petit rappel : on est bienveillants 💜", "que des bonnes ondes ici 🛡️" },
	},
	-- "test", "essai", "123"...
	TestHost = {
		en = { "test received loud and clear {n}! 🎙️✅", "i can see you {n}! the chat works ✅", "mic check... yep, {n} is here ✅" },
		fr = { "test reçu 5 sur 5 {n} ! 🎙️✅", "je te vois {n} ! le chat marche ✅", "test micro... oui, {n} est là ✅" },
	},
	Test = {
		en = { "test successful ✅", "we can see you {n} 👀", "1 2 1 2 🎤", "it works!!" },
		fr = { "test réussi ✅", "on te voit {n} 👀", "1 2 1 2 🎤", "ça marche !!" },
	},
	-- "how are you", "ça va"...
	HowAreYouHost = {
		en = { "i'm great {n}, thanks for asking!! and you? 💜", "super good now that you're here {n} 🥰", "full of noodles and happy 😋 you {n}?" },
		fr = { "ça va super {n}, merci ! et toi ? 💜", "trop bien maintenant que t'es là {n} 🥰", "pleine de nouilles et heureuse 😋 et toi {n} ?" },
	},
	HowAreYou = {
		en = { "i'm good thanks!", "doing great 😄", "vibing 😎", "good and you {n}?", "chilling with snacks 🍿", "all good here 💜" },
		fr = { "ça va et toi {n} ?", "tranquille 😎", "trop bien 😄", "on est bien là 💜", "ça va, je mange des chips 🍿", "au top !" },
	},
	-- TOUT EN MAJUSCULES
	Caps = {
		en = { "WHY ARE WE YELLING 😂", "caps lock energy 🔊", "{n} is LOUD today 😂", "INDOOR VOICE PLS 🤫" },
		fr = { "POURQUOI ON CRIE 😂", "énergie MAJUSCULES 🔊", "{n} parle FORT aujourd'hui 😂", "VOIX D'INTÉRIEUR SVP 🤫" },
	},
	EmojiHost = {
		en = { "{n} speaks fluent emoji 😂💜", "same energy {n} ✨", "i felt that emoji {n} 🥺" },
		fr = { "{n} parle couramment l'emoji 😂💜", "même énergie {n} ✨", "j'ai ressenti cet emoji {n} 🥺" },
	},
	Long = {
		en = { "that's a whole essay {n} 📜😂", "{n} wrote a novel 📚", "reading all of it 👀" },
		fr = { "c'est une rédaction ça {n} 📜😂", "{n} a écrit un roman 📚", "je lis tout 👀" },
	},
	Repeat = {
		en = { "déjà vu 👀", "you said that already {n} 😂", "echo echo echo 🔁" },
		fr = { "impression de déjà-vu 👀", "tu l'as déjà dit {n} 😂", "écho écho écho 🔁" },
	},
	-- Premier message du joueur
	First = {
		en = { "welcome to your first chat {n}!! 🎉", "a new chatter appeared ✨", "first message W 🎉" },
		fr = { "bienvenue pour ton premier message {n} !! 🎉", "un nouveau dans le chat ✨", "premier message W 🎉" },
	},
}

-- Question + sujet précis : sujets dont les réponses "répondent", du plus
-- concret au plus vague (les autres sujets ne servent pas de réponse)
local ANSWER_PRIORITY = {
	Name = 1, Age = 2, Pet = 3, Food = 4, Butter = 5, Music = 6, Game = 7, Weather = 8, School = 9, Help = 10,
	ASMR = 11, Dopamine = 12, Follow = 13, Sleep = 14, Happy = 15,
}

-- Messages "test" (mots du message normalisé, séparés par une espace)
local TEST_MESSAGES = {
	["test"] = true, ["tests"] = true, ["testing"] = true, ["test test"] = true, ["test 1 2 3"] = true, ["test 123"] = true,
	["essai"] = true, ["123"] = true, ["1 2 3"] = true, ["mic check"] = true, ["hello world"] = true, ["is this working"] = true,
	["ca marche"] = true, ["est-ce que ca marche"] = true, ["est ce que ca marche"] = true, ["allo"] = true,
}
-- "comment ça va" : expressions cherchées dans " mots séparés "
local HOW_ARE_YOU = {
	" how are you ", " how are u ", " how r u ", " hru ", " how s it going ", " hows it going ", " how is it going ",
	" how you doing ", " how are you doing ", " wbu ", " hbu ", " ca va ", " cv ", " tu vas bien ", " vous allez bien ",
	" comment vas tu ", " comment tu vas ", " comment allez vous ", " la forme ", " bien ou quoi ", " ca dit quoi ",
}

----------------------------------------------------------------------
-- Construction du plan
----------------------------------------------------------------------

-- Tronque un texte à maxChars caractères (UTF-8), avec "…"
function ChatReplies.Quote(text: string, maxChars: number): string
	local length = utf8.len(text)
	if length == nil then
		return string.sub(text, 1, maxChars)
	end
	if length <= maxChars then
		return text
	end
	local cut = utf8.offset(text, maxChars) or (#text + 1)
	return string.sub(text, 1, cut - 1) .. "…"
end

type Options = {
	Topics: { string }?,
	Lang: string?,
	Text: string?,
	Normalized: string?, -- texte en minuscules sans accents (ChatTopics.Normalize), sinon string.lower
	First: boolean?,
	Repeat: boolean?,
	Random: any, -- Random (NextNumber / NextInteger)
}

function ChatReplies.Build(options: Options): Plan
	local random = options.Random
	local lang = options.Lang == "fr" and "fr" or "en"
	local text = options.Text or ""
	local topics = options.Topics or {}
	local normalized = options.Normalized or string.lower(text)
	local used: { [string]: boolean } = {}

	-- Une phrase au hasard (jamais deux fois la même dans une réponse)
	local function pickLine(variants: any): string
		local list = variants and (variants[lang] or variants.en)
		if type(list) ~= "table" or #list == 0 then
			return ""
		end
		local line = list[random:NextInteger(1, #list)]
		for _ = 1, 4 do
			if not used[line] then
				break
			end
			line = list[random:NextInteger(1, #list)]
		end
		used[line] = true
		return (string.gsub(line, "{n}", ChatReplies.NAME))
	end

	-- Particularités du message
	local words = {}
	for word in string.gmatch(normalized, "[%w%-]+") do
		table.insert(words, word)
	end
	local joined = table.concat(words, " ")
	local spaced = " " .. joined .. " "
	local filtered = string.find(text, "##", 1, true) ~= nil
	local letters = string.gsub(text, "[^%a]", "")
	local caps = #letters >= 5 and not string.find(letters, "%l")
	local emojiOnly = #words == 0 and string.find(text, "%S") ~= nil
	local long = (utf8.len(text) or #text) > 90
	local isTest = TEST_MESSAGES[joined] == true
	local howAreYou = false
	for _, phrase in ipairs(HOW_ARE_YOU) do
		if string.find(spaced, phrase, 1, true) then
			howAreYou = true
			break
		end
	end

	local primary: string = topics[1] or "None"
	if ChatReplies.Host[primary] == nil then
		primary = "None"
	end
	-- Une question sur un sujet précis ("tu manges quoi ?") : elle répond avec ce sujet
	local answer = primary
	if primary == "Question" then
		local best = math.huge
		for index = 2, #topics do
			local rank = ANSWER_PRIORITY[topics[index]]
			if rank and rank < best and ChatReplies.Host[topics[index]] then
				best, answer = rank, topics[index]
			end
		end
	end
	local topic: string = answer
	local hostVariants: any = ChatReplies.Host[answer]
	local upset = primary == "Mean" or primary == "Sad"
	local noTopic = primary == "None"
	if filtered then
		topic, hostVariants = "Filtered", ChatReplies.Extra.FilteredHost
	elseif isTest then
		topic, hostVariants = "Test", ChatReplies.Extra.TestHost
	elseif howAreYou and not upset then
		topic, hostVariants = "HowAreYou", ChatReplies.Extra.HowAreYouHost
	elseif emojiOnly and noTopic then
		topic, hostVariants = "Emoji", ChatReplies.Extra.EmojiHost
	end

	local plan: Plan = {
		Topic = topic,
		Mood = ChatReplies.Moods[topic] or ChatReplies.Moods.None,
		Host = { Delay = random:NextNumber(1.5, 2.2), Text = pickLine(hostVariants) },
		Viewers = {},
	}

	-- Spectateurs : 1 à 4 lignes (+ un modo si besoin)
	local lines: { Line } = {}
	local function add(variants: any, mod: boolean?)
		local line = pickLine(variants)
		if line ~= "" then
			table.insert(lines, { Delay = 0, Text = line, Mod = mod })
		end
	end
	local viewerCount = 0
	local function addViewer(variants: any)
		if viewerCount < 4 then
			viewerCount += 1
			add(variants)
		end
	end
	if filtered then
		add(ChatReplies.Extra.Mod, true)
		addViewer(ChatReplies.Extra.Filtered)
		if random:NextNumber() < 0.5 then
			addViewer(ChatReplies.Extra.Filtered)
		end
	else
		if primary == "Mean" then
			add(ChatReplies.Extra.Mod, true)
		end
		if options.First then
			addViewer(ChatReplies.Extra.First)
		end
		if isTest then
			addViewer(ChatReplies.Extra.Test)
		end
		if caps then
			addViewer(ChatReplies.Extra.Caps)
		end
		if long then
			addViewer(ChatReplies.Extra.Long)
		end
		if options.Repeat then
			addViewer(ChatReplies.Extra.Repeat)
		end
		local wanted = random:NextInteger(1, 3) + (#topics >= 2 and 1 or 0)
		local topical = 0
		while viewerCount < 4 and (topical < wanted or topical == 0) do
			local variants: any
			if topic == "HowAreYou" then
				variants = random:NextNumber() < 0.6 and ChatReplies.Extra.HowAreYou or ChatReplies.Viewers.Greeting
			else
				-- surtout le sujet de la réponse, parfois un autre sujet du message
				local pickTopic = answer
				if #topics >= 2 and random:NextNumber() < 0.4 then
					pickTopic = topics[random:NextInteger(1, #topics)]
				end
				if emojiOnly and pickTopic == "None" then
					pickTopic = "Emoji"
				end
				variants = ChatReplies.Viewers[pickTopic] or ChatReplies.Viewers.None
			end
			addViewer(variants)
			topical += 1
		end
	end

	-- Mentions "@pseudo" (un peu plus d'une fois sur trois) et délais étalés entre 1 et 6 s
	local slots = #lines
	for index, line in ipairs(lines) do
		if not string.find(line.Text, ChatReplies.NAME, 1, true) and random:NextNumber() < (line.Mod and 0.5 or 0.35) then
			line.Text = "@" .. ChatReplies.NAME .. " " .. line.Text
		end
		local slot = 5 / math.max(1, slots)
		line.Delay = (line.Mod and 0.4 or 0.9) + (index - 1) * slot + random:NextNumber(0, slot * 0.7)
		line.Delay = math.min(line.Delay, 6)
	end
	table.sort(lines, function(a, b)
		return a.Delay < b.Delay
	end)
	plan.Viewers = lines
	return plan
end

return ChatReplies
