--[[
	ChatTopics (ModuleScript)
	Emplacement : ReplicatedStorage > Shared > ChatTopics

	Devine de quoi parle un message tapé par le joueur (chat du live, mails)
	pour que les faux spectateurs / correspondants répondent "en fonction de
	ce qu'il a dit". Utilisé par le SERVEUR sur le texte brut (avant le
	filtre Roblox, qui peut remplacer des mots par des #), le résultat
	(une liste de sujets) est renvoyé au client avec le texte filtré.

	ChatTopics.Detect(text) -> { "Greeting", "Question", ... } (ordre =
	importance, sans doublon). Mots-clés anglais ET français, sans accents,
	en minuscules.
]]

local ChatTopics = {}

-- Sujet -> mots / débuts de mots (comparés aux mots du message)
ChatTopics.Keywords = {
	Greeting = { "hi", "hello", "hey", "yo", "sup", "hiya", "bonjour", "salut", "coucou", "bonsoir", "wesh", "slt", "cc", "hola" },
	Bye = { "bye", "goodbye", "cya", "later", "gn", "goodnight", "night", "aurevoir", "revoir", "ciao", "bisous", "adieu", "bonne nuit" },
	Love = { "love", "luv", "ily", "cute", "adorable", "kawaii", "aime", "adore", "mignon", "mignonne", "coeur", "<3", "bisou" },
	Compliment = { "best", "great", "awesome", "amazing", "cool", "nice", "good", "beautiful", "pretty", "genial", "super", "trop bien", "incroyable", "magnifique", "belle", "beau", "top", "parfait", "gg", "bravo", "wow" },
	Mean = { "bad", "ugly", "boring", "hate", "stupid", "dumb", "worst", "cringe", "nul", "nulle", "moche", "deteste", "bete", "ennuyeux", "naze", "pourri" },
	Question = { "?", "how", "why", "what", "when", "where", "who", "which", "comment", "pourquoi", "quoi", "quand", "qui", "quel", "quelle", "combien", "est-ce" },
	Food = { "food", "eat", "eating", "hungry", "snack", "pizza", "burger", "fries", "cake", "cookie", "manger", "mange", "faim", "gateau", "frites", "miam", "yummy", "delicious", "delicieux", "croissant", "ramen", "sushi" },
	Butter = { "butter", "beurre", "crunch", "croque", "crounch", "croustillant" },
	ASMR = { "asmr", "tingles", "whisper", "chuchote", "chuchotement", "frissons", "relax", "relaxing", "detente", "sons", "sound", "sounds", "micro", "mic" },
	Dopamine = { "dopamine", "click", "clicks", "clic", "clics", "cliquer", "clique", "rich", "riche", "money", "argent", "rebirth", "ocean", "upgrade", "amelioration" },
	Follow = { "follow", "sub", "subscribe", "abonne", "abonnement", "suivre", "follower", "followers", "notif" },
	Laugh = { "lol", "lmao", "haha", "hahaha", "mdr", "ptdr", "xd", "funny", "drole", "rire", "😂", "🤣" },
	Music = { "music", "song", "musique", "chanson", "lofi", "beat", "beats", "playlist", "vinyl", "vinyle" },
	Sleep = { "sleep", "tired", "sleepy", "dormir", "dodo", "fatigue", "fatiguee", "sommeil", "nap", "sieste" },
	Sad = { "sad", "cry", "crying", "depressed", "lonely", "triste", "pleure", "seul", "seule", "deprime" },
	Happy = { "happy", "glad", "yay", "joy", "content", "contente", "heureux", "heureuse", "youpi", "trop content" },
	Game = { "game", "roblox", "play", "playing", "jeu", "jouer", "joue", "gaming", "gamer", "arcade", "level", "niveau" },
	Help = { "help", "aide", "aidez", "tuto", "tutorial", "conseil", "astuce", "tips", "tip" },
	Age = { "age", "old", "ans", "years" },
	Name = { "name", "nom", "appelle", "pseudo", "streamer", "streameuse" },
	Pet = { "cat", "dog", "chat", "chien", "pet", "animal", "chaton", "chiot", "hamster", "lapin" },
	Weather = { "weather", "rain", "sun", "snow", "meteo", "pluie", "soleil", "neige", "orage", "storm" },
	School = { "school", "homework", "exam", "ecole", "college", "lycee", "devoirs", "controle", "examen", "prof", "reviser" },
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
	["ú"] = "u", ["ÿ"] = "y", ["ñ"] = "n", ["œ"] = "oe", ["À"] = "a", ["É"] = "e", ["È"] = "e", ["Ç"] = "c", ["Ê"] = "e",
}

function ChatTopics.Normalize(text: string): string
	local lowered = string.lower(text)
	for accent, plain in pairs(ACCENTS) do
		lowered = string.gsub(lowered, accent, plain)
	end
	return lowered
end

-- Liste des sujets du message (au plus 4)
function ChatTopics.Detect(text: string): { string }
	if type(text) ~= "string" or text == "" then
		return {}
	end
	local normalized = " " .. ChatTopics.Normalize(string.sub(text, 1, 300)) .. " "
	-- Mots séparés (les apostrophes et la ponctuation coupent les mots)
	local words: { [string]: boolean } = {}
	for word in string.gmatch(normalized, "[%w%-]+") do
		words[word] = true
	end
	local found: { string } = {}
	for _, topic in ipairs(ChatTopics.Order) do
		local keywords = ChatTopics.Keywords[topic]
		local hit = false
		for _, keyword in ipairs(keywords) do
			if string.find(keyword, "[^%w%-]") then
				-- Expression avec espace ou symbole (ex. "bonne nuit", "?", "<3", emoji)
				if string.find(normalized, keyword, 1, true) then
					hit = true
				end
			elseif words[keyword] then
				hit = true
			end
			if hit then
				break
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
