--[[
	ChatTopics (ModuleScript)
	Emplacement : ReplicatedStorage > Shared > ChatTopics

	Devine de quoi parle un message tapé par le joueur (chat du live, mails)
	pour que les faux spectateurs / correspondants répondent "en fonction de
	ce qu'il a dit". Utilisé par le SERVEUR (Services > ChatService) : le
	résultat (une liste de sujets) est renvoyé au client avec le texte filtré.

	ChatTopics.Detect(text) -> { "Greeting", "Question", ... } (ordre =
	importance, sans doublon, 4 au plus). Mots-clés anglais ET français
	(argot de chat compris : "slt", "cc", "mdr", "ptdr", "wsh", "lol", "gg"...),
	sans accents, en minuscules, et emojis.
	Forme des mots-clés :
	  - "mot"        : mot entier ("hi" ne trouve pas "hit") ; les lettres
	                   répétées sont tolérées ("hellooo", "coucouuu", "mdrrr",
	                   "byee" trouvent "hello", "coucou", "mdr", "bye") ;
	  - "debut*"     : début de mot ("haha*" trouve "hahahaha", "ador*" trouve
	                   "adorable") ;
	  - "deux mots"  : expression, mots entiers dans l'ordre ("bonne nuit",
	                   "how old", "je t aime" : l'apostrophe sépare les mots) ;
	  - symbole / emoji : cherché tel quel ("?", "<3", "😂").
	ChatTopics.Negations annule un sujet quand une expression est trouvée
	("pas nul" n'est pas méchant).
	v9 : beaucoup plus de mots (argot FR/EN, emojis), lettres répétées,
	débuts de mots, expressions entières, négations ; "chat" retiré des
	animaux (c'est aussi le chat du live !) ; "test" retiré de l'école.
]]

local ChatTopics = {}

-- Sujet -> mots-clés (voir l'en-tête pour leur forme)
ChatTopics.Keywords = {
	Greeting = {
		"hi", "hii", "hello", "helo", "hey", "heya", "yo", "sup", "wassup", "wsp", "hiya", "howdy", "greetings", "hallo",
		"hola", "bonjour", "bjr", "salut", "slt", "coucou", "cc", "kikou", "bonsoir", "bsr", "wesh", "wsh", "gm",
		"good morning", "good evening", "good afternoon", "👋", "🙋",
	},
	Bye = {
		"bye", "goodbye", "bye bye", "byebye", "cya", "see ya", "see you", "later", "laters", "ttyl", "gtg", "g2g", "gn",
		"goodnight", "good night", "night", "aurevoir", "au revoir", "revoir", "ciao", "tchao", "adieu", "bonne nuit",
		"a plus", "a+", "a toute", "a demain", "a bientot", "bonne soiree", "bonne journee", "je dois y aller", "je vais y aller",
		"je file", "brb",
	},
	Love = {
		"love", "loves", "loved", "lovely", "luv", "ily", "ilysm", "cute", "cutie", "adorable", "kawaii", "aime", "aimes",
		"aimer", "ador*", "mignon", "mignonne", "chou", "choupi", "mims", "coeur", "coeurs", "bisou", "bisous", "jtm",
		"je t aime", "<3", "❤", "💕", "💖", "💗", "💘", "💜", "💙", "💚", "💛", "🧡", "🤍", "😍", "🥰", "😘", "😻",
	},
	Compliment = {
		"best", "great", "awesome", "amazing", "cool", "nice", "good", "beautiful", "pretty", "perfect", "fantastic",
		"gorgeous", "talented", "goat", "queen", "legend", "legendary", "fire", "dope", "slay", "pog",
		"poggers", "w", "gg", "ggs", "bravo", "wow", "thanks", "thank", "thx", "ty", "tysm", "merci", "mrc", "genial",
		"super", "trop bien", "incroyable", "magnifique", "belle", "beau", "top", "parfait", "parfaite", "stylé", "style",
		"ouf", "dingue", "masterclass", "meilleur", "meilleure", "la meilleure", "trop forte", "trop fort", "reine", "bg",
		"canon", "not bad", "pas mal", "🔥", "👏", "💯", "🙌", "⭐", "🌟", "👑",
	},
	Mean = {
		"bad", "ugly", "boring", "hate", "hater", "haters", "stupid", "dumb", "worst", "cringe", "trash", "sucks", "suck",
		"lame", "idiot", "loser", "noob", "gross", "disgusting", "annoying", "shut up", "stfu", "fake", "mid", "ew", "yuck",
		"nul", "nulle", "moche", "deteste", "bete", "ennuyeux", "ennuyeuse", "naze", "pourri", "pourrie", "claque", "eclate",
		"degueu", "degueulasse", "beurk", "berk", "bouffon", "boloss", "relou", "chiant", "chiante", "cheh", "tais toi",
		"ferme la", "t es nul", "t es nulle", "🤮", "💩", "👎", "🙄", "😒", "😡", "🤬",
	},
	Question = {
		"?", "how", "why", "what", "whats", "wat", "wut", "when", "where", "who", "which", "whose", "wyd", "hbu", "wbu",
		"do you", "can you", "are you", "r u", "comment", "pourquoi", "pk", "pq", "quoi", "koi", "quand", "c est qui", "quel",
		"quelle", "quels", "quelles", "lequel", "laquelle", "combien", "est-ce", "est ce que", "tu peux", "tu sais",
		"c est quoi", "❓", "❔", "🤔",
	},
	Food = {
		"food", "eat", "eating", "ate", "hungry", "snack", "snacks", "pizza", "burger", "burgers", "fries", "cake", "cookie",
		"cookies", "croissant", "ramen", "sushi", "pasta", "noodles", "nugget", "nuggets", "chips", "chocolate", "candy",
		"ice cream", "cheese", "tacos", "taco", "kebab", "sandwich", "donut", "donuts", "hotdog", "breakfast", "lunch",
		"dinner", "yum", "yummy", "tasty", "delicious", "mukbang", "boba", "bubble tea", "soup", "salad", "fruit", "apple",
		"banana", "strawberry", "cook", "cooking", "recipe", "restaurant", "mcdo", "mcdonalds", "kfc", "manger", "mange",
		"manges", "mangez", "bouffe", "bouffer", "faim", "gateau", "gateaux", "frites", "miam", "delicieux", "pates",
		"nouilles", "chocolat", "bonbon", "bonbons", "glace", "fromage", "raclette", "fondue", "gouter", "repas", "petit dej",
		"dejeuner", "diner", "soupe", "salade", "pomme", "banane", "fraise", "recette", "cuisine", "appetit", "bon appetit",
		"🍕", "🍔", "🍟", "🌭", "🌮", "🍣", "🍜", "🍝", "🍩", "🍪", "🎂", "🍰", "🧁", "🍫", "🍬", "🍭", "🍿", "🥐", "🧀",
		"🍗", "🍓", "🍎", "🍌", "🥪", "🤤", "😋",
	},
	Butter = {
		"butter", "buttery", "beurre", "crunch", "crunchy", "cronch", "croque", "croquer", "crounch", "croustillant", "croc",
		"demi-sel", "salted", "unsalted", "🧈",
	},
	ASMR = {
		"asmr", "tingles", "tingle", "whisper", "whispering", "chuchote", "chuchoter", "chuchotement", "frissons", "frisson",
		"relax", "relaxing", "relaxant", "calm", "calme", "apaisant", "detente", "satisfying", "satisfaisant", "sound",
		"sounds", "bruit", "bruits", "micro", "mic", "tapping", "headphones", "casque", "ecouteurs", "audio", "🎧", "🎙",
		"🔊",
	},
	Dopamine = {
		"dopamine", "dopa", "click", "clicks", "clicking", "clicker", "clic", "clics", "cliquer", "clique", "cliques",
		"rich", "riche", "money", "argent", "cash", "thune", "fric", "rebirth", "ocean", "upgrade", "upgrades",
		"amelioration", "ameliorations", "million", "millions", "billion", "milliard", "points", "score", "💰", "🤑",
		"📈",
	},
	Follow = {
		"follow", "follows", "followed", "following", "follower", "followers", "sub", "subs", "subbed", "subscribe",
		"subscribed", "abonne", "abonnee", "abonnes", "abonner", "abonnement", "abo", "suivre", "notif", "notifs",
		"cloche", "bell", "🔔",
	},
	Laugh = {
		"lol", "lol*", "lmao", "lmfao", "rofl", "haha*", "hehe*", "hihi*", "jaja*", "xd", "mdr", "mdr*", "ptdr", "ptdr*",
		"funny", "hilarious", "joke", "drole", "rire", "rigole", "rigoler", "marrant", "blague", "mort de rire", "dead", "ded",
		"kek", "😂", "🤣", "💀", "😹", "😆", "😅",
	},
	Music = {
		"music", "song", "songs", "musique", "chanson", "chansons", "lofi", "beat", "beats", "playlist", "vinyl", "vinyle",
		"sing", "singing", "chante", "chanter", "chanteuse", "dance", "dancing", "danse", "danser", "rap", "kpop", "k-pop",
		"piano", "guitar", "guitare", "concert", "album", "spotify", "dj", "melody", "melodie", "banger", "🎵", "🎶",
		"🎤", "💃", "🕺",
	},
	Sleep = {
		"sleep", "sleeping", "sleepy", "tired", "nap", "bedtime", "insomnia", "yawn", "dormir", "dors", "dort", "dodo",
		"fatigue", "fatiguee", "creve", "crevee", "sommeil", "sieste", "insomnie", "baille", "zz*", "😴", "💤", "🥱",
	},
	Sad = {
		"sad", "cry", "crying", "cried", "depressed", "lonely", "upset", "unhappy", "heartbroken", "sadge", "triste",
		"pleure", "pleurer", "seul", "seule", "deprime", "deprimee", "snif", "ouin", "chagrin", "bad day", "not ok",
		"mauvaise journee", "pas bien", "ca va pas", "ca va mal", "tu me manques", "😢", "🥺", "💔", "😞", "😔", "😿",
	},
	Happy = {
		"happy", "glad", "yay", "joy", "excited", "hype", "hyped", "yes", "yeah", "lets go", "let s go", "letsgo", "lesgo",
		"content", "contente", "heureux", "heureuse", "youpi", "trop content", "trop contente", "ouais", "birthday",
		"anniversaire", "anniv", "joyeux", "fete", "vacances", "holidays", "😊", "😄", "😁", "🥳", "🎉", "🎊", "😃",
	},
	Game = {
		"game", "games", "gaming", "gamer", "roblox", "play", "playing", "played", "jeu", "jeux", "jouer", "joue", "joues",
		"arcade", "level", "levels", "niveau", "minecraft", "fortnite", "obby", "brookhaven", "bloxburg", "adopt me", "pvp",
		"win", "won", "gagne", "perdu", "console", "ps5", "xbox", "switch", "🎮", "🕹",
	},
	Help = {
		"help", "helpp", "aide", "aider", "aidez", "tuto", "tutorial", "conseil", "conseils", "astuce", "astuces", "tips",
		"tip", "how to", "comment faire", "stuck", "bloque", "bloquee", "explain", "explique", "guide", "sos",
	},
	Age = {
		"age", "how old", "years old", "quel age", "ton age", "your age", "ans",
	},
	Name = {
		"name", "names", "nom", "prenom", "appelle", "appelles", "pseudo", "username", "called", "streamer", "streameuse",
		"mangetout", "who are you", "qui es tu", "t es qui",
	},
	Pet = {
		"cat", "cats", "kitty", "kitten", "dog", "dogs", "puppy", "doggo", "pet", "pets", "animal", "animals", "animaux",
		"chien", "chiens", "chaton", "chatons", "chiot", "chiots", "minou", "toutou", "hamster", "lapin", "bunny", "bird",
		"oiseau", "fish", "poisson", "horse", "cheval", "meow", "miaou", "woof", "wouf", "mon chat", "ton chat", "my cat",
		"your cat", "🐱", "🐶", "🐈", "🐕", "🐰", "🐹", "🐾", "🐦", "🐟",
	},
	Weather = {
		"weather", "rain", "raining", "rainy", "sun", "sunny", "snow", "snowing", "storm", "thunder", "cloud", "cloudy",
		"wind", "cold", "hot", "summer", "winter", "meteo", "pluie", "pleut", "soleil", "neige", "orage", "tonnerre", "nuage",
		"vent", "froid", "chaud", "hiver", "quel temps", "il fait beau", "beau temps", "mauvais temps", "☀", "🌧", "❄",
		"⛈", "🌈", "☔",
	},
	School = {
		"school", "homework", "exam", "exams", "teacher", "class", "classes", "study", "studying", "math", "maths", "grade",
		"grades", "university", "ecole", "college", "lycee", "devoir", "devoirs", "controle", "examen", "examens", "prof",
		"profs", "reviser", "revise", "revision", "revisions", "cours", "classe", "maitresse", "bac", "brevet", "fac",
		"cantine", "📚", "✏",
	},
}

-- Expressions qui ANNULENT un sujet ("pas nul" n'est pas méchant)
ChatTopics.Negations = {
	Mean = { "not bad", "pas mal", "pas nul", "pas nulle", "pas moche", "not ugly", "not boring", "pas ennuyeux" },
	Sad = { "not sad", "pas triste" },
}

-- Ordre d'importance (le premier sujet trouvé guide la réponse principale)
ChatTopics.Order = {
	"Mean", "Sad", "Greeting", "Bye", "Question", "Butter", "ASMR", "Food", "Follow", "Love", "Compliment",
	"Laugh", "Music", "Sleep", "Happy", "Dopamine", "Game", "Help", "Age", "Name", "Pet", "Weather", "School",
}

-- Minuscule + accents courants retirés
local ACCENTS = {
	["à"] = "a", ["â"] = "a", ["ä"] = "a", ["á"] = "a", ["ç"] = "c", ["é"] = "e", ["è"] = "e", ["ê"] = "e", ["ë"] = "e",
	["î"] = "i", ["ï"] = "i", ["í"] = "i", ["ô"] = "o", ["ö"] = "o", ["ó"] = "o", ["ù"] = "u", ["û"] = "u", ["ü"] = "u",
	["ú"] = "u", ["ÿ"] = "y", ["ñ"] = "n", ["œ"] = "oe", ["æ"] = "ae", ["À"] = "a", ["Â"] = "a", ["Ä"] = "a", ["É"] = "e",
	["È"] = "e", ["Ê"] = "e", ["Ë"] = "e", ["Ç"] = "c", ["Î"] = "i", ["Ï"] = "i", ["Ô"] = "o", ["Ö"] = "o", ["Ù"] = "u",
	["Û"] = "u", ["Ü"] = "u", ["Œ"] = "oe", ["’"] = "'",
}

function ChatTopics.Normalize(text: string): string
	local lowered = string.lower(text)
	for accent, plain in pairs(ACCENTS) do
		lowered = string.gsub(lowered, accent, plain)
	end
	return lowered
end

-- Remplace chaque suite d'au moins `minRun` lettres identiques par une seule
local function collapse(word: string, minRun: number): string
	local out = {}
	local i, n = 1, #word
	while i <= n do
		local c = string.sub(word, i, i)
		local j = i
		while j < n and string.sub(word, j + 1, j + 1) == c do
			j += 1
		end
		local run = j - i + 1
		table.insert(out, run >= minRun and c or string.rep(c, run))
		i = j + 1
	end
	return table.concat(out)
end

-- Mots-clés classés une fois pour toutes (mot / début / expression / symbole)
type Compiled = { Words: { [string]: boolean }, Prefixes: { string }, Phrases: { string }, Symbols: { string } }
local compiledCache: { [string]: Compiled } = {}
local function compile(topic: string): Compiled
	local cached = compiledCache[topic]
	if cached then
		return cached
	end
	local entry: Compiled = { Words = {}, Prefixes = {}, Phrases = {}, Symbols = {} }
	for _, keyword in ipairs(ChatTopics.Keywords[topic] or {}) do
		keyword = ChatTopics.Normalize(keyword)
		if string.match(keyword, "^[%w%-]+%*$") then
			table.insert(entry.Prefixes, string.sub(keyword, 1, -2))
		elseif string.match(keyword, "^[%w%-]+$") then
			entry.Words[keyword] = true
		elseif string.match(keyword, "^[%w%-' ]+$") then
			-- expression : mots séparés par une seule espace, apostrophes = espaces
			local words = {}
			for word in string.gmatch(keyword, "[%w%-]+") do
				table.insert(words, word)
			end
			table.insert(entry.Phrases, " " .. table.concat(words, " ") .. " ")
		else
			table.insert(entry.Symbols, keyword)
		end
	end
	compiledCache[topic] = entry
	return entry
end

-- Liste des sujets du message (au plus 4)
function ChatTopics.Detect(text: string): { string }
	if type(text) ~= "string" or text == "" then
		return {}
	end
	local normalized = ChatTopics.Normalize(string.sub(text, 1, 400))
	-- Mots (les apostrophes et la ponctuation coupent les mots) + formes sans lettres répétées
	local list: { string } = {}
	local words: { [string]: boolean } = {}
	for word in string.gmatch(normalized, "[%w%-]+") do
		table.insert(list, word)
		words[word] = true
		words[collapse(word, 3)] = true -- "hellooo" -> "hello"
		words[collapse(word, 2)] = true -- "byee" -> "bye"
	end
	local spaced = " " .. table.concat(list, " ") .. " "

	local function hasPhrase(phrase: string): boolean
		return string.find(spaced, phrase, 1, true) ~= nil
	end

	local found: { string } = {}
	for _, topic in ipairs(ChatTopics.Order) do
		local entry = compile(topic)
		local hit = false
		for _, symbol in ipairs(entry.Symbols) do
			if string.find(normalized, symbol, 1, true) then
				hit = true
				break
			end
		end
		if not hit then
			for word in pairs(words) do
				if entry.Words[word] then
					hit = true
					break
				end
				for _, prefix in ipairs(entry.Prefixes) do
					if string.sub(word, 1, #prefix) == prefix then
						hit = true
						break
					end
				end
				if hit then
					break
				end
			end
		end
		if not hit then
			for _, phrase in ipairs(entry.Phrases) do
				if hasPhrase(phrase) then
					hit = true
					break
				end
			end
		end
		if hit and ChatTopics.Negations[topic] then
			for _, phrase in ipairs(ChatTopics.Negations[topic]) do
				if hasPhrase(" " .. phrase .. " ") then
					hit = false
					break
				end
			end
		end
		if hit then
			table.insert(found, topic)
			if #found >= 4 then
				break
			end
		end
	end
	return found
end

return ChatTopics
