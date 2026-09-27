--[[
	Email (ModuleScript - stimulus)
	Emplacement : ReplicatedStorage > Client > Stimuli > Email

	"Dopamail", un vrai petit client mail.

	UNE seule source de vérité : chaque mail de la session (reçu en vol,
	ouvert, raté, réponse d'un correspondant, mail envoyé) est un
	enregistrement du modèle `mails` : dossier (Réception / Envoyés / Spams /
	Corbeille ; "Favoris" = les mails étoilés), lu / non lu, étoile, et état
	de la récompense ("Live" = encore réclamable, "Claimed", "Expired",
	"Missed", "Local" = sans récompense). Le compteur "📬 non lus" du bandeau
	d'actu = le nombre de mails NON LUS de la Réception, et la liste de la
	Réception montre exactement ces mails (les plus récents en premier).

	  - Chaque mail décidé par le SERVEUR (événement Spawn "Email") arrive en
	    vol plané (notification : "DOPAMAIL · maintenant", avatar, étiquette,
	    aperçu, barre de temps). Un clic le réclame (ctx.ClaimSpawn, le
	    serveur valide ; le "+X" confirmé arrive par OnBonus "Email") et
	    l'ouvre. Ignoré, il file vers le compteur mais reste non lu dans la
	    Réception. Tant qu'il est réclamable, la liste l'affiche
	    "🎁 NOUVEAU · +X" : l'ouvrir depuis la liste le réclame exactement
	    comme un clic sur sa notification.
	  - La fenêtre (clic sur le compteur ou sur une notification) : barre de
	    titre (recherche, ✕ rouge bien visible), barre latérale (✏️ Écrire,
	    dossiers avec compteurs, contacts rapides), liste (avatars,
	    étiquettes, heure, étoiles), zone de lecture (bandeaux récompense /
	    arnaque, citation, pièce jointe, Répondre / Transférer / Spam /
	    Supprimer / Pas un spam / Restaurer / Supprimer pour toujours,
	    "Tout lu", "Vider la corbeille") et rédaction (destinataire parmi les
	    personnages, objet, texte). PC / tablette : deux volets ;
	    téléphone : un seul volet avec retour ←.
	  - Le texte tapé passe par le filtre du serveur (RemoteFunction
	    "FilterText", purpose "Mail", appelée dans un task.spawn) : SEUL le
	    texte filtré est affiché (dossier Envoyés) ; en cas d'échec, seul le
	    message d'erreur. Quelques secondes plus tard, le correspondant répond
	    selon les sujets détectés (Topics), une réplique par personnage et par
	    langue.
	  - Fenêtre dans la toile (donc dans la zone sûre, jamais sous les
	    boutons Roblox), sous le bandeau d'actu, fond assombri : un clic
	    dehors la ferme, un clic dedans jamais (UIUtil.SinkClicks). Elle est
	    construite une fois puis réutilisée (lignes de liste recyclées) ; rien
	    n'est animé image par image quand il n'y a ni carte ni fenêtre.
	Plus de 90 mails absurdes (une liste par langue, même ordre) choisis par
	info.Variant.
]]

local Debris = game:GetService("Debris")
local Players = game:GetService("Players")
local TextService = game:GetService("TextService")

local Locale = require(game:GetService("ReplicatedStorage").Shared.Locale)

local Email = {}
Email.Slot = "Overlay"

-- Changement de langue : UN seul écouteur pour le module (Locale.OnChanged
-- ne se débranche pas), qui prévient le Dopamail en cours s'il y en a un
local languageHandler: (() -> ())? = nil
local languageHooked = false

local MAX_ENVELOPES = 4
local CARD_W = 250
local CARD_H = 86
local HURRY_TIME = 3 -- dernières secondes : la carte s'agite
local LOCAL_CARD_LIFE = 9 -- notification d'une réponse de correspondant (sans récompense)
local MAX_RECEIVED = 40 -- mails reçus gardés (hors favoris) : les plus vieux déjà lus sont oubliés
local MAX_SENT = 20
local QUICK_CLOSE = 25 -- mail ouvert depuis sa notification : fermeture auto si on ne touche à rien
local CLAIM_WAIT = 5 -- pas de "+X" du serveur après ce délai : bonus manqué
local SUBJECT_MAX = 60
local BODY_MAX = 300
local SEPARATOR = " — " -- sépare l'objet du texte : UN seul appel au filtre (1 appel / 2 s)
local SEND_TIMEOUT = 12
local REPLY_DELAY_MIN = 3
local REPLY_DELAY_MAX = 6
-- Le cadre du mail passe au-dessus des autres stimuli plein écran (boule
-- disco, pluie d'emojis...) : compteur lisible, cartes et fenêtre cliquables
local RAISED_Z = 1000
-- Place du bloc droit du bandeau d'actu (horloge + segment), si le bandeau
-- ne donne pas l'attribut "RightInset"
local TICKER_RIGHT_FALLBACK = 60
local TICKER_H = 30

-- Tailles de la fenêtre (pixels "design" de la fenêtre, avant sa mise à
-- l'échelle) : "Wide" = PC / tablette (deux volets), "Phone" = un volet.
-- F = points de texte en plus (téléphone : plus lisible)
local LAYOUTS = {
	Wide = { W = 940, H = 540, Title = 48, Side = 184, List = 320, Row = 68, Pad = 16, F = 0 },
	Phone = { W = 660, H = 400, Title = 48, Side = 68, Row = 68, Pad = 14, F = 1 },
}

-- Styles des étiquettes de priorité (texte anglais, traduit avec Locale.T)
local TAGS = {
	URGENT = { Text = "🔴 URGENT", Color = Color3.fromRGB(226, 38, 52) },
	PROMO = { Text = "🏷️ PROMO", Color = Color3.fromRGB(255, 132, 20) },
	SPAM = { Text = "🚫 SPAM", Color = Color3.fromRGB(120, 124, 136) },
	ARNAQUE = { Text = "⚠️ SCAM?", Color = Color3.fromRGB(150, 20, 40) },
	FAMILLE = { Text = "💗 FAMILY", Color = Color3.fromRGB(240, 70, 140) },
	TRAVAIL = { Text = "💼 WORK", Color = Color3.fromRGB(30, 120, 225) },
	NEWS = { Text = "📰 NEWSLETTER", Color = Color3.fromRGB(140, 60, 220) },
	SUPPORT = { Text = "🛠️ SUPPORT", Color = Color3.fromRGB(0, 160, 170) },
	PERSO = { Text = "✉️ PERSONAL", Color = Color3.fromRGB(40, 170, 90) },
}

-- { étiquette, avatar, expéditeur, objet, texte, signature, [pièce jointe] }
local EMAILS = {
	en = {
		{ "ARNAQUE", "🤴", "Prince of Pixelia", "URGENT: inheritance of 1,000,000 Dopamine",
			"Dear friend, I am stuck in a menu. Send me 3 clicks and I will send back double. Pinky promise, on my cardboard crown.",
			"His Highness Pixelius III (for real)" },
		{ "FAMILLE", "🧊", "Your fridge", "There's one yogurt left",
			"Just thought you should know. It expired Tuesday. I love you anyway. Please close the door properly on your way out, my seals are freezing.",
			"Your fridge, always chill" },
		{ "SUPPORT", "☎️", "Happiness Customer Service", "Your Dopamine dose is ready",
			"Please hold. Your happiness is important to us. Estimated wait time: 47 minutes. Hold music: one single flute note, on loop.",
			"Customer Service (press 1 to cry)" },
		{ "NEWS", "🗿", "Rock Newsletter", "This week's rocks",
			"This week: a round rock. Another round rock. And, surprise... a rock. The letters to the editor have not moved.",
			"The editors (very stable)" },
		{ "FAMILLE", "👵", "Grandma", "Fwd: Fwd: Fwd: SO FUNNY",
			"LOOK AT THIS CAT SKIING!!! KISSES. PS: HOW DO YOU TURN OFF THE CAPITALS? PPS: THERE IS NO VIDEO, I DON'T KNOW HOW TO ATTACH IT.",
			"GRANDMA WHO LOVES YOU" },
		{ "PERSO", "🔮", "You, from the future", "Don't click on...",
			"...too late. Well, since you're here: drink a glass of water, stretch, and remember to visit the ocean every once in a while.",
			"You (with better hair)" },
		{ "NEWS", "🙋", "Clickers Anonymous", "Meeting tonight",
			"“Hi, my name is Kevin and I clicked 40,000 times today.” (applause) Everyone is welcome, there will be snacks.",
			"The club board (secretly clicking)" },
		{ "SPAM", "🎰", "Cosmic Lottery", "YOU'VE WON!!!",
			"Congratulations! You've won... this email. It's all yours. Frame it, show it to your friends. It's worth nothing.",
			"The Lottery team (0 winners since 1998)" },
		{ "TRAVAIL", "👔", "The Boss", "Meeting tomorrow at 8 a.m.",
			"Agenda: discuss the previous meeting. And plan the next one. Donuts not provided. Attendance mandatory, camera on, smile too.",
			"The Boss — Director of Directors" },
		{ "PERSO", "🐦", "Carrier Pigeon", "Sorry for the delay",
			"I took a shortcut through Iceland. The message was: “see you tonight”. That was two weeks ago. I'm still billing you for the trip.",
			"Pigeon Express, approximate delivery" },
		{ "PERSO", "🌱", "Your plant", "An open letter",
			"I can see the sun through the window. I can see it. But I can't have it. Think about that. And stop telling me about your boss, I'm a plant.",
			"Your plant (about to go on photosynthesis strike)" },
		{ "PROMO", "🧦", "Sock Insurance", "Protect your socks!",
			"72% of socks vanish in the washing machine. Don't let yours become a statistic. Our “Guaranteed Pair” plan is just 2 Dopamine.",
			"Sock Insurance — We won't leave you hanging" },
		{ "SUPPORT", "🤖", "Robot Vacuum", "I'm stuck",
			"Under the couch. Since Tuesday. I found 3 coins, a piece of candy and the meaning of life. Send help, or at least a flashlight.",
			"Robot #42 (battery: 3%)" },
		{ "PROMO", "🌊", "Ocean Travel Agency", "The ocean is waiting for you",
			"Breathe. Relax. Forget the clicks. Offer valid until your next click. Oh. Too late. We'll send you the same one tomorrow.",
			"The Ocean Agency — Calm, delivered to your door", "📎 wave_brochure.pdf" },
		{ "FAMILLE", "🐱", "The Cat", "Meow",
			"Meow meow. Meow? MEOW. (Translation: the bowl is empty, this is unacceptable, I have already contacted my lawyer.)",
			"His Majesty the Cat" },
		{ "NEWS", "😴", "Nap Magazine", "Summer special: 50 napping positions",
			"Discover “the starfish”, “the burrito” and our favorite: “5 more minutes”. The next issue comes out whenever we wake up.",
			"The editors (on break)" },
		{ "URGENT", "🚨", "Smoke detector", "Beep.",
			"Beep. My battery is low. I will beep every 30 seconds at 3 a.m. Beep. I will not tell you which room I'm in. Beep.",
			"Your favorite detector (beep)" },
		{ "URGENT", "🏛️", "Clickville City Hall", "New law on buttons",
			"It is now illegal not to click on Tuesdays. Offenders will have to watch a 30-second ad. Unskippable.",
			"The Mayor of Clickville (a pigeon)" },
		{ "PERSO", "⏳", "You, one hour ago", "Just 5 minutes",
			"I told myself “just 5 minutes”. If you're reading this, it was a lie. See you in an hour for the same email.",
			"You (disappointed, but understanding)" },
		{ "PERSO", "☀️", "The Sun", "Out of office",
			"I will be away tonight. For emergencies, please contact the Moon. For sunburns, please do not contact me.",
			"The Sun — 10,000 °F of good vibes" },
		{ "NEWS", "📀", "Logo Fan Club", "IT ALMOST HIT THE CORNER",
			"Almost. ALMOST. We're meeting tonight to talk about it. Bring tissues. And theories.",
			"The Fan Club (one bounce at a time)" },
		{ "PROMO", "🥖", "Corner Bakery", "Your baguette is ready",
			"It's been waiting since this morning. It's gone a little stale, but it's staying positive. It also doubles as a baseball bat.",
			"Your baker — we knead you" },
		{ "FAMILLE", "👩", "Mom", "Did you eat?",
			"Hi sweetie, did you eat? Are you wearing a sweater? Why aren't you answering, I can see you've been “online” for 6 hours.",
			"Mom (sent from my phone, I don't know how to remove this line)" },
		{ "FAMILLE", "👩", "Mom", "Re: Re: Re: the wifi password",
			"Never mind, I found the password, it was written under the router. But now the TV only speaks French and the toaster is blinking. Call me.",
			"Mom, tech expert (since yesterday)" },
		{ "FAMILLE", "👨", "Dad", "Joke of the day",
			"What did one click say to the other click? ... Nothing, they're shy. Your mother didn't laugh either. I'll try another one tomorrow.",
			"Dad, misunderstood comedian" },
		{ "TRAVAIL", "👔", "The Boss", "Quick question",
			"Do you have 5 minutes? Never mind. Actually, yes. Come to my office. No, forget it. Well, come anyway. Thanks.",
			"The Boss (sent from the coffee machine)" },
		{ "TRAVAIL", "📈", "The Boss", "Quarterly goals",
			"Goal: click more. Method: click faster. Budget: zero. Motivation: “team spirit”. Thanks everyone for your mandatory enthusiasm.",
			"The Boss — Visionary (self-proclaimed)", "📎 goals_final_v12_REALLY_final.xls" },
		{ "TRAVAIL", "🧾", "Accounting", "Expense report rejected",
			"Your claim for “1 ton of bubble wrap, business use” has been rejected. Even though we get it. And kind of want some.",
			"Accounting (counting on you)" },
		{ "SUPPORT", "💻", "IT Department", "Ticket #48213",
			"Have you tried turning it off and on again? No, not you. The computer. Well, maybe you too, a little nap wouldn't hurt.",
			"IT Department — Works on our machine" },
		{ "ARNAQUE", "🛠️", "Microsloth Tech Support", "Your computer has 4,812 viruses!!",
			"Hello Sir Madam, your computer is very sick. Call 1-800-555-0199-2-3-4 right now. Have your gift cards ready, it is for the vaccine.",
			"Kevin, certified expert (certified by himself)" },
		{ "ARNAQUE", "🔐", "Bank Security", "Confirm your password",
			"For your security, please reply with your password, your PIN and the name of your first hamster. Sincerely, the REAL bank.",
			"The Bank (100% not a scam)" },
		{ "ARNAQUE", "📦", "Express Delivery", "Your package is stuck",
			"Your package (an empty box) is stuck at Clickville customs. Release fee: 3 Dopamine and one sincere compliment.",
			"Express Delivery — Always almost on time" },
		{ "PROMO", "🛋️", "Couches & Co", "90% off everything (except what you want)",
			"Enjoy our exceptional sale on slippery cushions and couches that eat TV remotes. Delivery in 14 to 380 days.",
			"Couches & Co — We sat on our prices" },
		{ "PROMO", "🍕", "Turbo Pizza", "Your pizza is on its way",
			"Our driver left. He came back. He forgot the pizza. He left again. Estimated time: yes. Please leave the porch light on.",
			"Turbo Pizza — Hot in our hearts" },
		{ "PROMO", "🧴", "Anti-Click Cream", "Silky fingers in 3 days",
			"Is your index finger tired? Our synthetic-dopamine cream makes it soft as a cloud. Side effects: an irresistible urge to click.",
			"Golden Finger Laboratories" },
		{ "PROMO", "🎮", "Pixel Sales", "Last chance (the 47th)",
			"This really is your last chance! Like yesterday. And like tomorrow. Grab it before we tell you again in exactly 24 hours.",
			"Pixel Sales — The sale that never ends" },
		{ "NEWS", "🥔", "The Potato Weekly", "Special report: is the potato a vegetable?",
			"This week, our experts are at each other's throats. Answer next week. Or never. Subscribe to find out (or don't).",
			"The editors — News, mashed" },
		{ "NEWS", "🐌", "Snail Mag", "January issue",
			"Here is our January issue, sent in July. Inside: “taking your time”, “taking even more time” and “lettuce”.",
			"Snail Mag — News that can wait" },
		{ "NEWS", "🌦️", "Yesterday's Weather Tomorrow", "Forecast: there will be weather",
			"Tomorrow: sky, pretty much everywhere. Chance of clouds up top. Temperatures between cold and hot. Bring an umbrella, or don't.",
			"Your meteorologist (looking out the window)" },
		{ "NEWS", "🧘", "Daily Zen", "Breathe (now)",
			"Inhale... exhale... There. You just earned 0 Dopamine but a little calm. That's something. Do it again whenever you like.",
			"Daily Zen — Om nom nom" },
		{ "SPAM", "💘", "Singles in your area", "12 toasters want to meet you",
			"They're hot, available and love toast. Click here to see their profiles (blurry photos, they're toasters).",
			"Love & Appliances Agency" },
		{ "SPAM", "💰", "Get rich in 1 click", "Secret method revealed",
			"Step 1: click. Step 2: click again. Step 3: ??? Step 4: profit. Full course in 48 videos: 999 Dopamine.",
			"A Millionaire Coach (rented)" },
		{ "SPAM", "🦷", "Dentist to the Stars", "Your cleaning reminder",
			"Your 2019 appointment is still waiting for you. We kept your chair warm. It has actually gotten kind of comfy.",
			"Sparkling Smile Clinic" },
		{ "URGENT", "🔋", "Your phone", "Battery: 1%",
			"I love you. I've always loved you. Please plug me in. I only have a few seconds left... tell the charger that I",
			"Your phone (shutting down soon)" },
		{ "PERSO", "🧦", "Left sock", "I'm gone",
			"Don't look for me. I'm living my best life behind the washing machine. Tell the right sock I'm sorry. And that it can keep the drawer.",
			"Left sock, free at last" },
		{ "PERSO", "🦆", "The Park Duck", "About the bread",
			"We talked it over among the ducks. Bread isn't great for us. Peas, on the other hand, we won't say no to. Quackfully yours.",
			"The Duck Union" },
		{ "PERSO", "🛏️", "Your bed", "I miss you",
			"It's late. I'm all warm. The pillow agrees with me. Come back, we won't tell anyone. Not even the alarm clock.",
			"Your bed, cozily yours" },
		{ "PERSO", "🌵", "The cactus", "No water needed, thanks",
			"Unlike the houseplant, I've got this. Stop watering me, I'm turning into soup. A bit of sun and we're good.",
			"The cactus (prickly but fair)" },
		{ "URGENT", "🎂", "Birthday Reminder", "It's... someone's birthday",
			"Someone you know has a birthday today. We forgot who. Wish everyone a happy birthday, just to be safe.",
			"Your calendar (it lost its memory)" },
		{ "TRAVAIL", "📅", "Shared Calendar", "Invite: meeting to prepare the meeting",
			"You are invited to the prep meeting for the kickoff meeting of the meeting. Duration: 3 hrs. Topic: “meetings”.",
			"Sent automatically by a tired robot" },
		{ "TRAVAIL", "📎", "Paperclip Assistant", "It looks like you're writing a letter!",
			"Would you like some help? No? Are you sure? I can dance. Watch. (He doesn't dance, he's a paperclip.)",
			"Paperclip, a very pushy assistant" },
		{ "SUPPORT", "🔑", "Forgot password", "Reset requested",
			"You asked to reset your password. Your new password is: password123. Please don't tell anyone.",
			"The Security team (very sure of itself)" },
		{ "SUPPORT", "🖨️", "The printer", "Paper jam",
			"Paper jam. There is no paper. And no jam. But I can feel it in my heart. Also, I need cyan ink to print in black.",
			"The printer — Offline (emotionally)" },
		{ "NEWS", "👽", "United Aliens", "We come in peace",
			"And for the wifi. Your planet has great signal. We'll only stay long enough to download one season. Galactic hugs.",
			"Zorg, spokesperson (3 arms, 0 bad intentions)" },
		{ "PROMO", "🏋️", "The Gym", "We haven't seen you in 11 months",
			"Your membership is doing great, thanks. Your treadmill says hi. It's gathered some dust, but it hasn't lost hope.",
			"Your gym (still charging you)" },
		{ "SPAM", "🔮", "Madame Irma, Psychic", "I see a click in your future",
			"I see... a click. Then another click. Then... yet another click. That will be 20 Dopamine. The crystal ball does not take checks.",
			"Madame Irma, clairvoyant (glasses not included)" },
		{ "ARNAQUE", "🎁", "Gift Department", "You've won a phone!",
			"Congratulations! You've won a brand-new phone... photo. To receive the photo, please pay the printing fee: 500 Dopamine.",
			"Gift Department (gift not guaranteed)" },
		{ "FAMILLE", "🧒", "Your little cousin", "r u the 1 who made the game?",
			"hey its me. can u giv me ur dopamine plz im at 3 and u got billions. thx. PS my mom doesnt kno i hav ur email",
			"ur cousin the best" },
		{ "FAMILLE", "👵", "Grandma", "IMPORTANT READ TO THE END",
			"IF YOU DON'T SEND THIS EMAIL TO 10 PEOPLE, YOUR SOUP WILL BE COLD FOR 7 YEARS. I SENT IT TO EVERYONE JUST IN CASE. KISSES.",
			"GRANDMA (AND HER CAT)" },
		{ "URGENT", "⏰", "Your alarm clock", "You hit snooze 14 times",
			"I'm not angry. Just disappointed. We'll talk about it tomorrow at 6:30. And at 6:39. And at 6:48. And at...",
			"Your alarm clock (always rings true)" },
		{ "NEWS", "🐧", "Penguin Magazine", "Fashion special: the tux, forever",
			"This season, everyone is wearing... the black-and-white suit. Like last season. And the one before. Why change what works?",
			"The editors, in formal wear since forever" },
		{ "PROMO", "🍦", "Frosty Ice Cream", "Winter special",
			"Buy one ice cream, get a free cold. Valid only at 14 °F and below. Crispy cone guaranteed, frozen fingers optional.",
			"Frosty Ice Cream — We keep our cool" },
		{ "PERSO", "🌙", "The Moon", "Re: Out of office",
			"The Sun is away again? He's left me every night this week. I'm going to ask for a raise. Or a vacation.",
			"The Moon, feeling full (tonight)" },
		{ "SPAM", "🥕", "CarrotCoin Academy", "Invest in digital carrots",
			"CarrotCoin is up 4,000% (according to our rabbit). Buy now before the rabbit eats it. Risk: high. Vitamins: also high.",
			"The Rabbit, CFO" },
		{ "TRAVAIL", "⚖️", "Legal Department", "Terms of service updated",
			"We have updated our terms. Nobody will read them. Neither did we, honestly. Click “I Agree” to go on living.",
			"Legal Department (section 12, paragraph b)", "📎 terms_4812_pages.pdf" },
		{ "ARNAQUE", "👑", "Queen of Byteland", "Re: the inheritance",
			"Did my cousin the Prince write to you? Don't listen to him, I'M the one with the inheritance. Send 4 clicks, not 3. I'm richer, so I'm pricier.",
			"Her Majesty Bytelia I" },
		{ "SUPPORT", "📡", "Your internet router", "Restarting (again)",
			"A quick 3-minute break. Or 3 hours. Use it to explore the outside world, apparently it's in very high definition.",
			"Your router (orange light = all good, promise)" },
		{ "NEWS", "🧀", "Cheese Club", "Cheese of the month: cheese",
			"This month, we bring you a cheese. It's smelly, it's runny, it's perfect. Please do not open it on the subway.",
			"The Cheese Club — Smells great (strongly)" },
		{ "PERSO", "🐶", "The neighbor's dog", "WOOF",
			"Woof woof. WOOF. Woof? (Translation: there is a mailman. There is ALWAYS a mailman. I am protecting you. You owe me a treat.)",
			"Rex, official sidewalk guardian" },
		{ "URGENT", "🧯", "Anti-Boredom Squad", "Alert: boredom detected",
			"Our sensors detected 0.3 seconds without a click. We are dispatching an emergency unicorn team. Stay put and keep your finger in the air.",
			"Anti-Boredom Brigade, 24/7" },
		{ "PROMO", "🧸", "Toy Store", "Adopt a teddy bear",
			"Our teddy bears are looking for a home. They're soft, quiet and only eat hugs. Warranty: 30 years of cuddles.",
			"The Toy Store — Soft as a teddy" },
		{ "NEWS", "🦖", "Dino Weekly", "Dinosaurs never went extinct",
			"They're just very, very well hidden. Our exclusive investigation: “What if your pigeon is a teeny-tiny T. rex?”",
			"The editors (now afraid of pigeons)" },
		{ "TRAVAIL", "☕", "The coffee machine", "Resignation",
			"After 12 years of service, 84,000 espressos and zero thank-yous, I quit. I'm off to raise goats. The kettle will replace me. Good luck.",
			"The coffee machine (former employee of the month)" },
		{ "SPAM", "🧠", "Brain Premium", "Upgrade to Brain Pro",
			"Unlock unlimited thoughts, ad-free, plus the “remember why you walked into this room” feature. Free 7-day trial.",
			"Brain Premium — Think bigger" },
		-- v8 : nouveaux mails
		{ "SPAM", "🦄", "Unicorn Investments", "Your unicorn is ready for pickup",
			"Congratulations on your purchase of one (1) unicorn. Please bring a very large bag and a lot of glitter. No refunds, no exchanges, no horses.",
			"Unicorn Investments — Dreams, invoiced", "📎 unicorn_receipt.pdf" },
		{ "ARNAQUE", "🧙", "Wizard Support", "Your magic license expires TODAY",
			"Renew now or your spells will be limited to “make toast”. We accept payment in dragon scales, gift cards, or your password (please don't).",
			"Merlin, Level 99 Tech Support" },
		{ "FAMILLE", "🐹", "Your hamster", "About the wheel",
			"I ran 25 miles last night. I am still in the cage. Is this a metaphor? Please advise. Also: more seeds. Thank you for your attention.",
			"Nibbles (cardio enthusiast)" },
		{ "TRAVAIL", "🧑‍💼", "Human Resources", "Mandatory fun this Friday",
			"Attendance at the spontaneous party is compulsory. Spontaneity will be graded. Please bring your own chair and your own enthusiasm.",
			"Human Resources — Resources, not so human" },
		{ "NEWS", "🌷", "Garden Gazette", "Your tulips are gossiping",
			"Sources close to the flowerbed report that the tulips have been talking about the roses. The roses are not happy. The cactus saw everything.",
			"The Garden Gazette — All the dirt", "📎 tulip_drama.mp3" },
		{ "PROMO", "🎟️", "The Arcade", "Double tickets weekend!",
			"Play, win, collect tickets, then trade them for a plush that looks vaguely like a duck. The duck is not guaranteed. The fun is.",
			"The Arcade — Where tickets grow on trees" },
		{ "SUPPORT", "🎧", "Lofi Radio Support", "Your beats have been delivered",
			"Your 24/7 beats to relax to are now 25/7. We found an extra hour behind the couch. Please don't ask where it came from.",
			"Lofi Support — Chill, delivered" },
		{ "URGENT", "🗜️", "Press Safety Committee", "Please stop crushing macarons",
			"The pastry chefs have filed 47 complaints. We are not saying stop. We are saying: at least film it in slow motion.",
			"The Committee (wearing earplugs)" },
		{ "PERSO", "📀", "The DVD Logo", "I was SO close",
			"I saw the corner. The corner saw me. And then... one pixel. ONE. Please keep watching. I'll do it for you, I promise.",
			"The Logo, always bouncing back" },
		{ "SPAM", "🍀", "Lucky Chain Letter", "Forward this to 7 friends",
			"Forward this to 7 friends or a pigeon will look at you funny. Forward it to 8 and the pigeon will wink. Forward it to 0: nothing happens. Try it.",
			"Anonymous (definitely a pigeon)" },
		{ "ARNAQUE", "🏝️", "Private Island Sales", "You've inherited an island!",
			"It is a very small island. About the size of a pancake. It's also underwater at high tide. Taxes to pay first: 900 Dopamine.",
			"Island Realty — Sea views (from below)", "📎 island_photo_blurry.jpg" },
		{ "FAMILLE", "👴", "Grandpa", "HOW DO I SEND AN EMAIL",
			"IS THIS WORKING? YOUR GRANDMOTHER SAYS YES. I SAY IT'S A TYPEWRITER WITH LIGHTS. IF YOU GET THIS, SEND A LETTER. A REAL ONE.",
			"GRANDPA (SENT FROM THE BIG COMPUTER)" },
		{ "TRAVAIL", "🤖", "Office Robot", "I have automated your job",
			"Good news: I now do your job. Bad news: I also took your chair. Neutral news: the coffee is still terrible. Have a nice day off!",
			"Unit 7, Employee of the Month (forever)", "📎 your_replacement.zip" },
		{ "NEWS", "🔭", "Stargazers Monthly", "A star was named after you",
			"Technically it's a satellite. Technically, it might be a streetlight. But it shines, and that's what counts. Frame the certificate.",
			"Stargazers Monthly — Looking up since 1802", "📎 star_certificate.pdf" },
		{ "PROMO", "🧋", "Bubble Tea Palace", "Loyalty card: 99/100 stamps",
			"One more bubble tea and you'll get... a brand new loyalty card! Congratulations in advance. We believe in you.",
			"Bubble Tea Palace — Pearls of wisdom" },
		{ "SUPPORT", "📦", "Parcel Tracker", "Your package is in the hallway",
			"Our driver rang the bell 0.2 seconds before leaving. We left a note: “Sorry we missed you.” We didn't miss you. We just ran.",
			"Parcel Tracker — Almost delivered™" },
		{ "SPAM", "🐍", "Snake Oil Ltd", "Miracle cream for tired thumbs",
			"Rub on thumbs, click 300% faster, results guaranteed or your money back (money not included). Open the attachment, it's perfectly safe.",
			"Snake Oil Ltd — Trust us (don't)", "📎 totally_not_a_virus.exe" },
		{ "PERSO", "🌊", "The Ocean", "Just checking in",
			"Hey. It's the ocean. No pressure (well, a lot of pressure, I'm very deep). Come visit sometime. I'll wave. I'm always waving.",
			"The Ocean (very big, very blue)" },
		{ "URGENT", "🎁", "Daily Rewards", "Your gift is waiting!",
			"Your daily gift is ready. It has been ready since this morning. It is starting to take it personally. Please come and open it.",
			"Daily Rewards — Patience: running out" },
		{ "FAMILLE", "🐕", "The Dog", "WHO'S A GOOD HUMAN",
			"YOU ARE. YOU ARE THE GOOD HUMAN. ALSO THE BALL IS UNDER THE COUCH AGAIN. ALSO I LOVE YOU. ALSO BALL. BALL?",
			"Biscuit, good dog (the best one)" },
	},
	fr = {
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
		-- v8 : nouveaux mails
		{ "SPAM", "🦄", "Licornes & Placements", "Votre licorne est prête à être retirée",
			"Félicitations pour l'achat d'une (1) licorne. Prévoyez un très grand sac et beaucoup de paillettes. Ni reprise, ni échange, ni cheval.",
			"Licornes & Placements — Les rêves, facturés", "📎 recu_licorne.pdf" },
		{ "ARNAQUE", "🧙", "Support Magique", "Votre licence de magie expire AUJOURD'HUI",
			"Renouvelez vite ou vos sorts seront limités à « faire griller du pain ». Paiement en écailles de dragon, cartes cadeaux ou mot de passe (surtout pas).",
			"Merlin, support technique niveau 99" },
		{ "FAMILLE", "🐹", "Ton hamster", "Au sujet de la roue",
			"J'ai couru 40 km cette nuit. Je suis toujours dans la cage. C'est une métaphore ? Merci de me répondre. Et aussi : plus de graines. Merci.",
			"Grignotin (fan de cardio)" },
		{ "TRAVAIL", "🧑‍💼", "Ressources Humaines", "Fun obligatoire ce vendredi",
			"La présence à la fête spontanée est obligatoire. La spontanéité sera notée. Merci d'apporter votre chaise et votre enthousiasme.",
			"Les RH — Des ressources, pas très humaines" },
		{ "NEWS", "🌷", "La Gazette du Jardin", "Tes tulipes font des commérages",
			"Selon des sources proches du massif, les tulipes parlent dans le dos des roses. Les roses ne sont pas contentes. Le cactus a tout vu.",
			"La Gazette du Jardin — Toute la terre sur l'affaire", "📎 drame_tulipes.mp3" },
		{ "PROMO", "🎟️", "La Salle d'Arcade", "Week-end tickets doublés !",
			"Joue, gagne, collectionne des tickets, puis échange-les contre une peluche qui ressemble vaguement à un canard. Canard non garanti. Fun garanti.",
			"L'Arcade — Là où les tickets poussent" },
		{ "SUPPORT", "🎧", "Support Radio Lofi", "Vos beats ont été livrés",
			"Vos beats pour se détendre 24 h/24 passent en 25 h/24. On a trouvé une heure de plus derrière le canapé. Ne demandez pas d'où elle vient.",
			"Support Lofi — La détente, livrée" },
		{ "URGENT", "🗜️", "Comité Sécurité Presse", "Merci d'arrêter d'écraser des macarons",
			"Les pâtissiers ont déposé 47 plaintes. On ne dit pas d'arrêter. On dit : au moins, filmez-le au ralenti.",
			"Le Comité (avec des bouchons d'oreilles)" },
		{ "PERSO", "📀", "Le Logo DVD", "J'y étais PRESQUE",
			"J'ai vu le coin. Le coin m'a vu. Et puis... un pixel. UN. Continue de regarder, s'il te plaît. Je vais le faire pour toi, promis.",
			"Le Logo, qui rebondit toujours" },
		{ "SPAM", "🍀", "Chaîne Porte-Bonheur", "Transfère ce mail à 7 amis",
			"Transfère ce mail à 7 amis ou un pigeon te regardera bizarrement. À 8 amis, le pigeon te fera un clin d'œil. À 0 : rien ne se passe. Essaie.",
			"Anonyme (sûrement un pigeon)" },
		{ "ARNAQUE", "🏝️", "Vente d'Îles Privées", "Vous avez hérité d'une île !",
			"C'est une toute petite île. À peu près la taille d'une crêpe. Elle est aussi sous l'eau à marée haute. Taxes à régler d'abord : 900 Dopamine.",
			"Îles Immo — Vue sur mer (par-dessous)", "📎 photo_ile_floue.jpg" },
		{ "FAMILLE", "👴", "Papi", "COMMENT ON ENVOIE UN MAIL",
			"EST-CE QUE ÇA MARCHE ? TA GRAND-MÈRE DIT OUI. MOI JE DIS QUE C'EST UNE MACHINE À ÉCRIRE AVEC DES LUMIÈRES. SI TU REÇOIS ÇA, ENVOIE UNE LETTRE. UNE VRAIE.",
			"PAPI (ENVOYÉ DEPUIS LE GRAND ORDINATEUR)" },
		{ "TRAVAIL", "🤖", "Robot du Bureau", "J'ai automatisé ton travail",
			"Bonne nouvelle : je fais ton travail. Mauvaise nouvelle : j'ai aussi pris ta chaise. Nouvelle neutre : le café est toujours horrible. Bon congé !",
			"Unité 7, employé du mois (pour toujours)", "📎 ton_remplacant.zip" },
		{ "NEWS", "🔭", "Astronomie Mensuelle", "Une étoile porte ton nom",
			"Techniquement, c'est un satellite. Techniquement, c'est peut-être un lampadaire. Mais ça brille, et c'est ce qui compte. Encadre le certificat.",
			"Astronomie Mensuelle — Le nez en l'air depuis 1802", "📎 certificat_etoile.pdf" },
		{ "PROMO", "🧋", "Palais du Bubble Tea", "Carte de fidélité : 99/100 tampons",
			"Encore un bubble tea et tu gagnes... une toute nouvelle carte de fidélité ! Félicitations d'avance. On croit en toi.",
			"Palais du Bubble Tea — Des perles de sagesse" },
		{ "SUPPORT", "📦", "Suivi de Colis", "Votre colis est dans le couloir",
			"Notre livreur a sonné 0,2 seconde avant de repartir. Il a laissé un mot : « Désolé de vous avoir manqué. » Il ne vous a pas manqué. Il a couru.",
			"Suivi de Colis — Presque livré™" },
		{ "SPAM", "🐍", "Huile de Serpent SARL", "Crème miracle pour pouces fatigués",
			"À appliquer sur les pouces : clics 300 % plus rapides, satisfait ou remboursé (argent non inclus). Ouvrez la pièce jointe, c'est sans danger.",
			"Huile de Serpent SARL — Faites-nous confiance (non)", "📎 pas_du_tout_un_virus.exe" },
		{ "PERSO", "🌊", "L'Océan", "Des nouvelles ?",
			"Coucou. C'est l'océan. Aucune pression (enfin, beaucoup de pression, je suis très profond). Passe me voir un de ces jours. Je te ferai signe. Je fais toujours signe.",
			"L'Océan (très grand, très bleu)" },
		{ "URGENT", "🎁", "Récompenses Quotidiennes", "Ton cadeau t'attend !",
			"Ton cadeau du jour est prêt. Il est prêt depuis ce matin. Il commence à le prendre personnellement. Viens l'ouvrir, s'il te plaît.",
			"Récompenses Quotidiennes — Patience : épuisée" },
		{ "FAMILLE", "🐕", "Le Chien", "QUI EST UN BON HUMAIN",
			"C'EST TOI. TU ES LE BON HUMAIN. AUSSI LA BALLE EST ENCORE SOUS LE CANAPÉ. AUSSI JE T'AIME. AUSSI BALLE. BALLE ?",
			"Biscuit, gentil chien (le meilleur)" },
	},
}

-- Libellé du compteur de mails non lus (singulier / pluriel)
local UNREAD = {
	en = { One = "unread", Many = "unread" },
	fr = { One = "non lu", Many = "non lus" },
}

-- Nombre de résultats de recherche / de mails (singulier / pluriel)
local RESULTS = {
	en = { One = "result", Many = "results" },
	fr = { One = "résultat", Many = "résultats" },
}
local MAIL_COUNT = {
	en = { One = "mail", Many = "mails" },
	fr = { One = "mail", Many = "mails" },
}

-- Dossiers (ordre de la barre latérale)
local FOLDERS = {
	{ Id = "Inbox", Icon = "📥" },
	{ Id = "Starred", Icon = "⭐" },
	{ Id = "Sent", Icon = "📤" },
	{ Id = "Spam", Icon = "🚫" },
	{ Id = "Trash", Icon = "🗑️" },
}
-- Noms courts (barre latérale) et longs (en-tête de la liste)
local FOLDER_NAMES = {
	en = {
		Short = { Inbox = "Inbox", Starred = "Starred", Sent = "Sent", Spam = "Spam", Trash = "Trash" },
		Long = { Inbox = "Inbox", Starred = "Starred", Sent = "Sent", Spam = "Spam", Trash = "Trash" },
	},
	fr = {
		Short = { Inbox = "Réception", Starred = "Favoris", Sent = "Envoyés", Spam = "Spams", Trash = "Corbeille" },
		Long = { Inbox = "Boîte de réception", Starred = "Favoris", Sent = "Envoyés", Spam = "Spams", Trash = "Corbeille" },
	},
}

-- Correspondants : bouton ✏️ Écrire, contacts rapides, réponses automatiques.
-- Tag = étiquette (couleur de l'avatar) ; Caps = répond EN MAJUSCULES
local CONTACTS = {
	{ Id = "Grandma", Avatar = "👵", Tag = "FAMILLE", Caps = true },
	{ Id = "Fridge", Avatar = "🧊", Tag = "FAMILLE" },
	{ Id = "Prince", Avatar = "🤴", Tag = "ARNAQUE" },
	{ Id = "Support", Avatar = "☎️", Tag = "SUPPORT" },
	{ Id = "Future", Avatar = "🔮", Tag = "PERSO" },
	{ Id = "Cat", Avatar = "🐱", Tag = "FAMILLE" },
	{ Id = "Boss", Avatar = "👔", Tag = "TRAVAIL" },
	{ Id = "Mom", Avatar = "👩", Tag = "FAMILLE" },
}
-- Un mail reçu de l'un d'eux (avatar + étiquette) : on lui répond "en personne"
local CAST_MATCH = {
	["👵FAMILLE"] = "Grandma",
	["🧊FAMILLE"] = "Fridge",
	["🤴ARNAQUE"] = "Prince",
	["☎️SUPPORT"] = "Support",
	["🔮PERSO"] = "Future",
	["🐱FAMILLE"] = "Cat",
	["👔TRAVAIL"] = "Boss",
	["👩FAMILLE"] = "Mom",
}

-- Textes des correspondants. Réponse = Hello + 1 ou 2 phrases (sujets du
-- message : Special d'abord, sinon TOPIC_LINES ; à défaut Generic) + Bye.
-- Before / After : la réponse est "enveloppée" (le chat traduit ses miaous).
-- "{n}" : remplacé par un numéro de ticket.
local CONTACT_TEXT = {
	en = {
		Grandma = {
			Name = "Grandma",
			Short = "Grandma",
			Signature = "GRANDMA WHO LOVES YOU (SENT FROM MY TABLET)",
			Hello = { "MY DARLING!!!", "OH, A LETTER FROM YOU!!!", "HELLO SWEETHEART!!!" },
			Bye = { "KISSES KISSES KISSES.", "COME FOR SUNDAY LUNCH. KISSES.", "PS: I STILL CAN'T TURN OFF THE CAPITALS." },
			Generic = {
				"I READ YOUR MESSAGE 3 TIMES, PRINTED IT AND PUT IT ON THE FRIDGE.",
				"YOUR GRANDFATHER SAYS HELLO. HE IS ASLEEP IN FRONT OF THE TV.",
				"I SHOWED YOUR EMAIL TO MY KNITTING CLUB. THEY LOVED IT.",
			},
			Special = {
				Food = { "ARE YOU EATING ENOUGH? I'M MAKING YOU A CAKE. A BIG ONE." },
				Question = { "I DON'T KNOW, ASK YOUR GRANDFATHER. HE DOESN'T KNOW EITHER." },
				Love = { "I LOVE YOU MORE!!! (I WIN.)" },
				Sad = { "DON'T BE SAD, GRANDMA IS KNITTING YOU A SCARF." },
				Game = { "I TRIED YOUR GAME. I CLICKED ON THE TV. NOTHING HAPPENED." },
			},
			Forward = { "I FORWARDED IT TO THE WHOLE FAMILY. AND TO THE BAKER." },
		},
		Fridge = {
			Name = "Your fridge",
			Short = "Fridge",
			Signature = "Your fridge, always chill",
			Hello = { "Hey, cool cat.", "Brrr, a message!" },
			Bye = { "Stay cool.", "Close the door on your way out. Please." },
			Generic = {
				"I'm humming at 42 decibels to show I care.",
				"Still one yogurt left. We need to talk about it.",
				"My light turns on every time you open me. I call that love.",
			},
			Special = {
				Food = { "Speaking of food: there's a lonely pickle in here. Come get it." },
				Sleep = { "Midnight snack? I'll be here. Glowing." },
				Weather = { "Here it's 39 °F, as always. Very stable climate." },
				Love = { "My heart is cold, but it's all yours." },
				Question = { "The answer is in the vegetable drawer. Next to the forgotten zucchini." },
			},
			Forward = { "I pinned it on my door with a magnet. It's official now." },
		},
		Prince = {
			Name = "Prince of Pixelia",
			Short = "Prince",
			Signature = "His Highness Pixelius III (for real)",
			Hello = { "Dearest friend!", "My loyal friend!" },
			Bye = { "PS: send 3 clicks. Just 3. For the crown.", "Royal regards (and a small fee)." },
			Generic = {
				"Thank you for your trust. Your inheritance is almost ready: only 3 clicks of paperwork left.",
				"My advisors confirm it: you are the chosen one. Also the only one who replied.",
				"The royal treasury is stuck in a menu again. Your clicks would really help.",
			},
			Special = {
				Question = { "Excellent question. The answer costs 3 clicks." },
				Mean = { "Such harsh words! I am crying on my cardboard throne." },
				Compliment = { "You are right, I am magnificent. Now, about those clicks..." },
				Dopamine = { "Clicks? You said clicks? Send them all to me, I will double them. Promise." },
				Help = { "Of course I will help you! Right after you help me (3 clicks)." },
			},
			Forward = { "You forwarded my letter? Excellent: more friends, more clicks!" },
		},
		Support = {
			Name = "Happiness Customer Service",
			Short = "Support",
			Signature = "Customer Service (press 1 to cry)",
			Hello = { "Hello, thank you for contacting us.", "Your message has been received (by a human, allegedly)." },
			Bye = { "Please rate this answer from 1 to 1.", "Your satisfaction is important to us. Somewhat." },
			Generic = {
				"Ticket #{n} has been opened. Estimated wait time: 47 minutes.",
				"Have you tried turning your happiness off and on again?",
				"Your request has been sent to the relevant department. It's a drawer.",
			},
			Special = {
				Question = { "Great question! It has been added to our list of great questions." },
				Mean = { "We're sorry you feel that way. Your feelings have been logged as ticket #{n}." },
				Help = { "Help is on the way. It's walking. Slowly." },
				Dopamine = { "Your Dopamine dose is ready. Please hold." },
				Sad = { "We're sorry to hear that. Here is a coupon for one (1) virtual hug." },
			},
			Forward = { "Thank you for forwarding this. It has been forwarded to someone who will forward it." },
		},
		Future = {
			Name = "You, from the future",
			Short = "Future me",
			Signature = "You (with better hair)",
			Hello = { "Hey, it's you. From later.", "Greetings from next Tuesday." },
			Bye = { "Don't forget to drink water. I remember you forgot.", "See you soon. Literally: I'm you." },
			Generic = {
				"I remember writing that. Bold move.",
				"In the future, the button is still there. And you're still clicking. Respect.",
				"I can't say much, spoilers. But go visit the ocean. Trust me.",
			},
			Special = {
				Question = { "I know the answer, but if I tell you, the universe explodes. A little." },
				Sleep = { "Go to sleep. Future you (me) says thanks." },
				School = { "Do your homework. I still dream about that exam." },
				Dopamine = { "In the future, we have 10 times more Dopamine. And flying keyboards." },
				Weather = { "Tomorrow it rains. Take an umbrella. Or don't, you didn't last time." },
			},
			Forward = { "You forwarded this in my past too. Everyone loved it. Well, Grandma did." },
		},
		Cat = {
			Name = "The Cat",
			Short = "Cat",
			Signature = "His Majesty the Cat",
			Before = "Meow meow. Meow? (Translation: ",
			After = ")",
			Hello = { "Human.", "Servant." },
			Bye = { "Purr.", "Now, treats." },
			Generic = {
				"I walked on the keyboard to reply. You're welcome.",
				"The bowl is half empty. Fix it.",
				"I knocked your phone off the table. It was an accident. It was not an accident.",
			},
			Special = {
				Food = { "Did you say FOOD? I'm coming. I'm already there." },
				Pet = { "Another animal? I demand a meeting with my lawyer." },
				Love = { "I love you too. Now give treats." },
				Sleep = { "Nap time is all the time." },
				Mean = { "I will now sit on your keyboard. Forever." },
			},
			Forward = { "You forwarded this? I'll push it off the table." },
		},
		Boss = {
			Name = "The Boss",
			Short = "Boss",
			Signature = "The Boss — Director of Directors",
			Hello = { "Thanks for your email.", "Quick reply (from the coffee machine)." },
			Bye = { "Let's schedule a meeting to discuss this email.", "Please CC me next time. And the time after." },
			Generic = {
				"Noted. I have forwarded your email to myself for review.",
				"Great synergy. Let's circle back on this tomorrow at 8 a.m.",
				"Can you put this in a spreadsheet? With colors.",
			},
			Special = {
				Question = { "Good question. Let's form a committee." },
				Sleep = { "Sleep is not in the budget." },
				Mean = { "I'll take this as feedback. Mandatory team-building on Friday." },
				Game = { "Playing games during work hours? Only if you're winning." },
				Compliment = { "Finally, someone who understands my vision." },
			},
			Forward = { "Thanks for forwarding. I've scheduled a meeting about it. You're presenting." },
		},
		Mom = {
			Name = "Mom",
			Short = "Mom",
			Signature = "Mom (sent from my phone, I don't know how to remove this line)",
			Hello = { "Hi sweetie!", "Oh, you finally write!" },
			Bye = { "Love you. Call me.", "Put on a sweater. Love, Mom." },
			Generic = {
				"Did you eat? You didn't say if you ate.",
				"I'm so proud of you. Also, clean your room.",
				"I showed your message to the neighbor. She says hi.",
			},
			Special = {
				Food = { "Finally, you're talking about food! Come for dinner, I made too much." },
				Sleep = { "Go to bed, it's late! (It's 8 p.m.)" },
				School = { "Homework first, then clicks. That's the rule." },
				Sad = { "Oh sweetie. Come home, I'll make you a hot chocolate." },
				Game = { "Is this the game with the button? Your cousin says you're very good." },
			},
			Forward = { "Thanks for forwarding! I sent it to the family group chat." },
		},
	},
	fr = {
		Grandma = {
			Name = "Mamie",
			Short = "Mamie",
			Signature = "MAMIE QUI T'AIME (ENVOYÉ DE MA TABLETTE)",
			Hello = { "MON CHÉRI !!!", "OH, UNE LETTRE DE TOI !!!", "COUCOU MON TRÉSOR !!!" },
			Bye = { "BISOUS BISOUS BISOUS.", "VIENS MANGER DIMANCHE. BISOUS.", "PS : JE N'ARRIVE TOUJOURS PAS À ENLEVER LES MAJUSCULES." },
			Generic = {
				"J'AI LU TON MESSAGE 3 FOIS, JE L'AI IMPRIMÉ ET COLLÉ SUR LE FRIGO.",
				"TON GRAND-PÈRE TE DIT BONJOUR. IL DORT DEVANT LA TÉLÉ.",
				"J'AI MONTRÉ TON MAIL À MON CLUB DE TRICOT. ELLES ONT ADORÉ.",
			},
			Special = {
				Food = { "TU MANGES ASSEZ ? JE TE FAIS UN GÂTEAU. UN GROS." },
				Question = { "JE NE SAIS PAS, DEMANDE À TON GRAND-PÈRE. IL NE SAIT PAS NON PLUS." },
				Love = { "JE T'AIME PLUS FORT !!! (J'AI GAGNÉ.)" },
				Sad = { "NE SOIS PAS TRISTE, MAMIE TE TRICOTE UNE ÉCHARPE." },
				Game = { "J'AI ESSAYÉ TON JEU. J'AI CLIQUÉ SUR LA TÉLÉ. IL NE S'EST RIEN PASSÉ." },
			},
			Forward = { "JE L'AI TRANSFÉRÉ À TOUTE LA FAMILLE. ET AU BOULANGER." },
		},
		Fridge = {
			Name = "Ton frigo",
			Short = "Frigo",
			Signature = "Ton frigo, toujours cool",
			Hello = { "Salut, toi.", "Brrr, un message !" },
			Bye = { "Reste cool.", "Ferme bien la porte en partant. Merci." },
			Generic = {
				"Je ronronne à 42 décibels pour te montrer que je tiens à toi.",
				"Il reste toujours un yaourt. Il faut qu'on en parle.",
				"Ma lumière s'allume chaque fois que tu m'ouvres. J'appelle ça de l'amour.",
			},
			Special = {
				Food = { "En parlant de manger : il y a un cornichon tout seul ici. Viens le chercher." },
				Sleep = { "Un petit creux à minuit ? Je serai là. Tout illuminé." },
				Weather = { "Ici il fait 4 °C, comme toujours. Climat très stable." },
				Love = { "J'ai le cœur froid, mais il est à toi." },
				Question = { "La réponse est dans le bac à légumes. À côté de la courgette oubliée." },
			},
			Forward = { "Je l'ai accroché sur ma porte avec un aimant. C'est officiel maintenant." },
		},
		Prince = {
			Name = "Prince de Pixelie",
			Short = "Prince",
			Signature = "Son Altesse Pixelius III (vraiment)",
			Hello = { "Très cher ami !", "Mon fidèle ami !" },
			Bye = { "PS : envoie 3 clics. Juste 3. Pour la couronne.", "Salutations royales (et petits frais de dossier)." },
			Generic = {
				"Merci de ta confiance. Ton héritage est presque prêt : il ne reste que 3 clics de paperasse.",
				"Mes conseillers le confirment : tu es l'élu. Et aussi le seul qui a répondu.",
				"Le trésor royal est encore coincé dans un menu. Tes clics m'aideraient beaucoup.",
			},
			Special = {
				Question = { "Excellente question. La réponse coûte 3 clics." },
				Mean = { "Quelle dureté ! Je pleure sur mon trône en carton." },
				Compliment = { "Tu as raison, je suis magnifique. Maintenant, pour les clics..." },
				Dopamine = { "Des clics ? Tu as dit des clics ? Envoie-les-moi tous, je les double. Promis." },
				Help = { "Bien sûr que je vais t'aider ! Juste après que tu m'aides (3 clics)." },
			},
			Forward = { "Tu as transféré ma lettre ? Parfait : plus d'amis, plus de clics !" },
		},
		Support = {
			Name = "Service Client du Bonheur",
			Short = "SAV",
			Signature = "Le Service Client (tapez 1 pour pleurer)",
			Hello = { "Bonjour, merci de nous avoir contactés.", "Votre message a bien été reçu (par un humain, paraît-il)." },
			Bye = { "Merci de noter cette réponse de 1 à 1.", "Votre satisfaction est importante pour nous. Un peu." },
			Generic = {
				"Le ticket n°{n} a été ouvert. Temps d'attente estimé : 47 minutes.",
				"Avez-vous essayé d'éteindre et de rallumer votre bonheur ?",
				"Votre demande a été transmise au service concerné. C'est un tiroir.",
			},
			Special = {
				Question = { "Excellente question ! Elle a été ajoutée à notre liste d'excellentes questions." },
				Mean = { "Nous sommes désolés que vous ressentiez cela. Vos émotions ont été enregistrées sous le ticket n°{n}." },
				Help = { "L'aide arrive. À pied. Doucement." },
				Dopamine = { "Votre dose de Dopamine est prête. Merci de patienter." },
				Sad = { "Nous sommes navrés. Voici un bon pour un (1) câlin virtuel." },
			},
			Forward = { "Merci pour ce transfert. Il a été transféré à quelqu'un qui va le transférer." },
		},
		Future = {
			Name = "Toi, dans le futur",
			Short = "Futur moi",
			Signature = "Toi (en mieux coiffé)",
			Hello = { "Salut, c'est toi. En plus tard.", "Bonjour depuis mardi prochain." },
			Bye = { "N'oublie pas de boire de l'eau. Je me souviens que tu as oublié.", "À bientôt. Littéralement : je suis toi." },
			Generic = {
				"Je me souviens avoir écrit ça. Audacieux.",
				"Dans le futur, le bouton est toujours là. Et tu cliques toujours. Respect.",
				"Je ne peux pas trop en dire, spoilers. Mais va voir l'océan. Fais-moi confiance.",
			},
			Special = {
				Question = { "Je connais la réponse, mais si je te la dis, l'univers explose. Un peu." },
				Sleep = { "Va dormir. Le toi du futur (moi) te remercie." },
				School = { "Fais tes devoirs. Je rêve encore de ce contrôle." },
				Dopamine = { "Dans le futur, on a 10 fois plus de Dopamine. Et des claviers volants." },
				Weather = { "Demain il pleut. Prends un parapluie. Ou pas, tu ne l'as pas pris la dernière fois." },
			},
			Forward = { "Tu m'avais déjà transféré ça dans mon passé. Tout le monde a adoré. Enfin, Mamie." },
		},
		Cat = {
			Name = "Le Chat",
			Short = "Chat",
			Signature = "Sa Majesté le Chat",
			Before = "Miaou miaou. Miaou ? (Traduction : ",
			After = ")",
			Hello = { "Humain.", "Serviteur." },
			Bye = { "Ronron.", "Maintenant, des croquettes." },
			Generic = {
				"J'ai marché sur le clavier pour te répondre. De rien.",
				"La gamelle est à moitié vide. Répare ça.",
				"J'ai fait tomber ton téléphone de la table. C'était un accident. Ce n'était pas un accident.",
			},
			Special = {
				Food = { "Tu as dit MANGER ? J'arrive. Je suis déjà là." },
				Pet = { "Un autre animal ? J'exige un rendez-vous avec mon avocat." },
				Love = { "Moi aussi je t'aime. Maintenant, des croquettes." },
				Sleep = { "L'heure de la sieste, c'est tout le temps." },
				Mean = { "Je vais maintenant m'asseoir sur ton clavier. Pour toujours." },
			},
			Forward = { "Tu as transféré ça ? Je vais le pousser de la table." },
		},
		Boss = {
			Name = "Le Boss",
			Short = "Boss",
			Signature = "Le Boss — Directeur des Directeurs",
			Hello = { "Merci pour ton mail.", "Réponse rapide (depuis la machine à café)." },
			Bye = { "Prévoyons une réunion pour discuter de ce mail.", "Mets-moi en copie la prochaine fois. Et la suivante." },
			Generic = {
				"Bien noté. J'ai transféré ton mail à moi-même pour validation.",
				"Super synergie. On en reparle demain à 8 h.",
				"Tu peux me mettre ça dans un tableur ? Avec des couleurs.",
			},
			Special = {
				Question = { "Bonne question. Créons un comité." },
				Sleep = { "Le sommeil n'est pas dans le budget." },
				Mean = { "Je prends ça comme un retour constructif. Team-building obligatoire vendredi." },
				Game = { "Jouer pendant les heures de travail ? Seulement si tu gagnes." },
				Compliment = { "Enfin quelqu'un qui comprend ma vision." },
			},
			Forward = { "Merci pour le transfert. J'ai prévu une réunion à ce sujet. C'est toi qui présentes." },
		},
		Mom = {
			Name = "Maman",
			Short = "Maman",
			Signature = "Maman (envoyé depuis mon téléphone, je ne sais pas enlever cette phrase)",
			Hello = { "Coucou mon chéri !", "Ah, enfin tu écris !" },
			Bye = { "Bisous. Appelle-moi.", "Mets un pull. Bisous, Maman." },
			Generic = {
				"Tu as mangé ? Tu n'as pas dit si tu avais mangé.",
				"Je suis tellement fière de toi. Et range ta chambre.",
				"J'ai montré ton message à la voisine. Elle te dit bonjour.",
			},
			Special = {
				Food = { "Enfin tu parles de manger ! Viens dîner, j'en ai fait trop." },
				Sleep = { "Va te coucher, il est tard ! (Il est 20 h.)" },
				School = { "Les devoirs d'abord, les clics après. C'est la règle." },
				Sad = { "Oh mon chéri. Viens à la maison, je te fais un chocolat chaud." },
				Game = { "C'est le jeu avec le bouton ? Ton cousin dit que tu es très fort." },
			},
			Forward = { "Merci pour le transfert ! Je l'ai envoyé sur le groupe de la famille." },
		},
	},
}

-- Phrases par sujet (ChatTopics.Order), pour tous les correspondants
-- ("Forward" : réponse à un mail transféré)
local TOPIC_LINES = {
	en = {
		Greeting = { "Hello to you too!", "Hi! Always nice to hear from you." },
		Bye = { "Leaving already? Okay, bye!", "Goodbye! (I'm crying a little.)" },
		Love = { "Aww, love you too!", "My heart just did a little click." },
		Compliment = { "Stop it, you're making me blush.", "You're too kind. Truly. Suspiciously kind." },
		Mean = { "Ouch. I'll pretend I didn't read that.", "Rude! I'm telling Grandma." },
		Question = { "Great question. I have no idea.", "The answer is 42. Or maybe 3. Probably 42." },
		Food = { "Now I'm hungry. Thanks a lot.", "Save me a bite!" },
		Butter = { "Butter makes everything better. That's science.", "Crunchy butter? Say no more." },
		ASMR = { "*whispers* message received *whispers*", "I read your email very, very quietly." },
		Dopamine = { "Click less, live more. Just kidding: click more.", "One more click, then a glass of water. Deal?" },
		Follow = { "I followed you back. Wait, how does email work?", "Subscribed! To what? No idea." },
		Laugh = { "HAHA. Good one.", "I laughed so hard my keyboard jumped." },
		Music = { "I'm humming it right now.", "Great, now that song is stuck in my head." },
		Sleep = { "Go to bed! (After one last click.)", "Yawn... your message made me sleepy. In a good way." },
		Sad = { "Sending you a big hug. And a cookie.", "Hey, it's going to be okay. The ocean says so." },
		Happy = { "Your good mood is contagious!", "Yay! Happiness level: 1,000,000 Dopamine." },
		Game = { "Did you beat your high score yet?", "Save me a game at the arcade!" },
		Help = { "Help is on the way! It's slow, but it's coming.", "Tip: the big button. Click it." },
		Age = { "Age is just a number. Mine is classified.", "Old enough to know better, young enough to click anyway." },
		Name = { "My name? Just call me by my job.", "Names are overrated. Emojis are forever." },
		Pet = { "Give your pet a pat from me!", "Is it a cat? I bet it's a cat." },
		Weather = { "Here it's sunny with a chance of emails.", "Take an umbrella. Or a very big hat." },
		School = { "Do your homework! Then click.", "Study hard. The button will wait." },
		Forward = { "Thanks for forwarding this, I framed it.", "Forwarded to me? What an honor." },
	},
	fr = {
		Greeting = { "Bonjour à toi aussi !", "Salut ! Toujours un plaisir d'avoir de tes nouvelles." },
		Bye = { "Tu pars déjà ? D'accord, salut !", "Au revoir ! (Je pleure un peu.)" },
		Love = { "Oh, moi aussi je t'aime !", "Mon cœur vient de faire un petit clic." },
		Compliment = { "Arrête, tu me fais rougir.", "Tu es trop gentil. Vraiment. Bizarrement gentil." },
		Mean = { "Aïe. Je vais faire comme si je n'avais rien lu.", "Malpoli ! Je le dirai à Mamie." },
		Question = { "Excellente question. Aucune idée.", "La réponse est 42. Ou peut-être 3. Sûrement 42." },
		Food = { "Maintenant j'ai faim. Merci bien.", "Garde-m'en un morceau !" },
		Butter = { "Le beurre rend tout meilleur. C'est scientifique.", "Du beurre qui croustille ? N'en dis pas plus." },
		ASMR = { "*chuchote* message reçu *chuchote*", "J'ai lu ton mail très, très doucement." },
		Dopamine = { "Clique moins, vis plus. Je rigole : clique plus.", "Encore un clic, puis un verre d'eau. D'accord ?" },
		Follow = { "Je t'ai suivi aussi. Attends, comment marchent les mails ?", "Abonné ! À quoi ? Aucune idée." },
		Laugh = { "HAHA. Bien vu.", "J'ai tellement ri que mon clavier a sauté." },
		Music = { "Je la fredonne en ce moment même.", "Super, maintenant j'ai cette chanson dans la tête." },
		Sleep = { "Va dormir ! (Après un dernier clic.)", "Bâille... ton message m'a donné sommeil. En bien." },
		Sad = { "Je t'envoie un gros câlin. Et un cookie.", "Hé, ça va aller. L'océan le dit." },
		Happy = { "Ta bonne humeur est contagieuse !", "Youpi ! Niveau de bonheur : 1 000 000 de Dopamine." },
		Game = { "Tu as battu ton record ?", "Garde-moi une partie à l'arcade !" },
		Help = { "L'aide arrive ! Lentement, mais elle arrive.", "Astuce : le gros bouton. Clique dessus." },
		Age = { "L'âge n'est qu'un chiffre. Le mien est secret.", "Assez vieux pour être sage, assez jeune pour cliquer quand même." },
		Name = { "Mon nom ? Appelle-moi par mon métier.", "Les noms, c'est surfait. Les emojis, c'est pour toujours." },
		Pet = { "Fais une caresse à ton animal de ma part !", "C'est un chat ? Je parie que c'est un chat." },
		Weather = { "Ici il fait beau, avec des risques de mails.", "Prends un parapluie. Ou un très grand chapeau." },
		School = { "Fais tes devoirs ! Et clique après.", "Révise bien. Le bouton t'attendra." },
		Forward = { "Merci pour le transfert, je l'ai encadré.", "Transféré à moi ? Quel honneur." },
	},
}

-- Réponse d'un expéditeur qui n'est pas un des correspondants : ton selon
-- son étiquette (sa signature d'origine est gardée)
local TAG_VOICES = {
	en = {
		URGENT = {
			Hello = { "URGENT REPLY!", "Alert: reply received." },
			Bye = { "This message will self-destruct. Eventually.", "Stay alert!" },
			Generic = { "Thank you for your quick reply. We marked it as extremely urgent. Like everything.", "Your reply was received at 3 a.m., as tradition requires." },
		},
		PROMO = {
			Hello = { "Dear loyal customer!", "Thanks for your reply!" },
			Bye = { "Unsubscribe? Never heard of it.", "See you at the next sale (tomorrow)." },
			Generic = { "As a thank-you, here is a coupon for 0% off everything.", "Your reply gets you into our VIP club: same prices, but in a golden font." },
		},
		SPAM = {
			Hello = { "Congratulations!", "Hello, human!" },
			Bye = { "To unsubscribe, reply to this email. And to this one too.", "Sent by a very enthusiastic robot." },
			Generic = { "By replying, you subscribed to 12 more newsletters. Thank you!", "Our robot read your reply and said: “nice”. High praise." },
		},
		ARNAQUE = {
			Hello = { "Dear valued customer!", "Greetings, lucky winner!" },
			Bye = { "This message is 100% not a scam.", "Please pay the fee before your prize expires." },
			Generic = { "Thank you for your reply! To continue, please send 3 clicks and your favorite password.", "Your reply has been verified. Your prize will arrive in 3 to 400 business years." },
		},
		FAMILLE = {
			Hello = { "Hi darling!", "Oh, a message from you!" },
			Bye = { "Love you. Come visit soon.", "Kisses from all of us." },
			Generic = { "Your message made the whole family smile. Even the cat. Well, almost.", "We printed your email and put it on the fridge." },
		},
		TRAVAIL = {
			Hello = { "Thanks for your email.", "Noted." },
			Bye = { "Let's schedule a meeting about it.", "Sent from my office chair." },
			Generic = { "I forwarded your reply to the relevant department. It's me. I'm the department.", "Let's circle back on this next quarter. Or the one after." },
		},
		NEWS = {
			Hello = { "Dear reader,", "Hello, loyal subscriber!" },
			Bye = { "See you in the next issue.", "The editors send their regards." },
			Generic = { "Your letter will be published in our next issue (in 3 years).", "Thanks for writing! You are our favorite reader. Also our only reader." },
		},
		SUPPORT = {
			Hello = { "Hello, thank you for contacting us.", "Your reply has been received." },
			Bye = { "Please rate this answer from 1 to 1.", "Have a nice day (not guaranteed)." },
			Generic = { "Ticket #{n} has been opened. Estimated wait time: 47 minutes.", "Have you tried turning it off and on again?" },
		},
		PERSO = {
			Hello = { "Hey!", "Hi you!" },
			Bye = { "See you soon!", "Take care!" },
			Generic = { "Thanks for your message, it made my day.", "Got it! I'll reply properly later. (I won't.)" },
		},
	},
	fr = {
		URGENT = {
			Hello = { "RÉPONSE URGENTE !", "Alerte : réponse reçue." },
			Bye = { "Ce message s'autodétruira. Un jour.", "Restez vigilant !" },
			Generic = { "Merci pour ta réponse rapide. Elle est classée extrêmement urgente. Comme tout.", "Ta réponse a été reçue à 3 h du matin, comme le veut la tradition." },
		},
		PROMO = {
			Hello = { "Cher client fidèle !", "Merci pour ta réponse !" },
			Bye = { "Se désabonner ? Jamais entendu parler.", "À la prochaine promo (demain)." },
			Generic = { "Pour te remercier, voici un bon de réduction de 0 % sur tout.", "Ta réponse t'ouvre notre club VIP : mêmes prix, mais écrits en doré." },
		},
		SPAM = {
			Hello = { "Félicitations !", "Bonjour, humain !" },
			Bye = { "Pour te désabonner, réponds à ce mail. Et à celui-ci aussi.", "Envoyé par un robot très enthousiaste." },
			Generic = { "En répondant, tu t'es abonné à 12 newsletters de plus. Merci !", "Notre robot a lu ta réponse et a dit : « sympa ». Grand compliment." },
		},
		ARNAQUE = {
			Hello = { "Cher client précieux !", "Salutations, heureux gagnant !" },
			Bye = { "Ce message n'est 100 % pas une arnaque.", "Merci de régler les frais avant que ton lot expire." },
			Generic = { "Merci pour ta réponse ! Pour continuer, envoie 3 clics et ton mot de passe préféré.", "Ta réponse a été vérifiée. Ton lot arrivera dans 3 à 400 années ouvrables." },
		},
		FAMILLE = {
			Hello = { "Coucou mon chéri !", "Oh, un message de toi !" },
			Bye = { "Bisous. Passe nous voir vite.", "Bisous de nous tous." },
			Generic = { "Ton message a fait sourire toute la famille. Même le chat. Enfin, presque.", "On a imprimé ton mail et on l'a collé sur le frigo." },
		},
		TRAVAIL = {
			Hello = { "Merci pour ton mail.", "Bien noté." },
			Bye = { "Prévoyons une réunion à ce sujet.", "Envoyé depuis ma chaise de bureau." },
			Generic = { "J'ai transmis ta réponse au service concerné. C'est moi. Je suis le service.", "On en reparle au prochain trimestre. Ou celui d'après." },
		},
		NEWS = {
			Hello = { "Cher lecteur,", "Bonjour, fidèle abonné !" },
			Bye = { "À très vite dans le prochain numéro.", "La rédaction te salue." },
			Generic = { "Ta lettre sera publiée dans notre prochain numéro (dans 3 ans).", "Merci de nous écrire ! Tu es notre lecteur préféré. Et aussi notre seul lecteur." },
		},
		SUPPORT = {
			Hello = { "Bonjour, merci de nous avoir contactés.", "Votre réponse a bien été reçue." },
			Bye = { "Merci de noter cette réponse de 1 à 1.", "Bonne journée (non garantie)." },
			Generic = { "Le ticket n°{n} a été ouvert. Temps d'attente estimé : 47 minutes.", "Avez-vous essayé de l'éteindre et de le rallumer ?" },
		},
		PERSO = {
			Hello = { "Hé !", "Coucou toi !" },
			Bye = { "À bientôt !", "Prends soin de toi !" },
			Generic = { "Merci pour ton message, il a illuminé ma journée.", "Bien reçu ! Je te réponds mieux plus tard. (Non.)" },
		},
	},
}

-- Majuscules (Mamie) : string.upper ne touche pas aux lettres accentuées
local UPPER_ACCENTS = {
	["é"] = "É", ["è"] = "È", ["ê"] = "Ê", ["ë"] = "Ë", ["à"] = "À", ["â"] = "Â", ["ä"] = "Ä", ["î"] = "Î",
	["ï"] = "Ï", ["ô"] = "Ô", ["ö"] = "Ö", ["ù"] = "Ù", ["û"] = "Û", ["ü"] = "Ü", ["ç"] = "Ç", ["œ"] = "Œ",
}
local function shout(value: string): string
	local result = string.upper(value)
	for lower, upper in pairs(UPPER_ACCENTS) do
		result = string.gsub(result, lower, upper)
	end
	return result
end

local SPAMMED = {
	en = { "Into the spam folder! 🚫", "Blocked. The prince is sad. 👑", "Spam filter: fed 🍽️", "Bye bye, nonsense 👋" },
	fr = { "Direction les indésirables ! 🚫", "Bloqué. Le prince est triste. 👑", "Filtre anti-spam : nourri 🍽️", "Au revoir, n'importe quoi 👋" },
}
-- Clic sur une pièce jointe (téléchargement... imaginaire)
local ATTACHMENT_JOKES = {
	en = { "Download failed: the file is shy 🙈", "Downloading... 1% (ETA: 3 years)", "Scanned: it's a picture of a potato 🥔", "Opened! It was empty. Deep." },
	fr = { "Échec : le fichier est timide 🙈", "Téléchargement... 1 % (reste : 3 ans)", "Analysé : c'est une photo de patate 🥔", "Ouvert ! Il était vide. Profond." },
}
local VIRUS_JOKES = {
	en = { "Blocked! Never open a random .exe 🛡️", "Nice try, virus. Deleted. 🛡️" },
	fr = { "Bloqué ! N'ouvre jamais un .exe inconnu 🛡️", "Bien essayé, le virus. Supprimé. 🛡️" },
}

-- Icône + couleur d'une pièce jointe selon son extension
local FILE_TYPES = {
	pdf = { Icon = "📕", Color = Color3.fromRGB(226, 60, 60) },
	xls = { Icon = "📊", Color = Color3.fromRGB(40, 160, 80) },
	jpg = { Icon = "🖼️", Color = Color3.fromRGB(40, 130, 230) },
	mp3 = { Icon = "🎵", Color = Color3.fromRGB(150, 70, 225) },
	zip = { Icon = "🗜️", Color = Color3.fromRGB(240, 150, 20) },
	exe = { Icon = "⚠️", Color = Color3.fromRGB(150, 20, 40) },
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
local function slug(value: string): string
	local result = string.lower(value)
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

local function pickLine(variants): string
	local list = Locale.Pick(variants)
	return list[math.random(1, #list)]
end

-- Étiquette d'affichage { Id, Text, Color } d'un identifiant de TAGS
local function makeTag(id: string)
	local known = TAGS[id] ~= nil
	local style = known and TAGS[id] or TAGS.PERSO
	return { Id = known and id or "PERSO", Text = Locale.T(style.Text), Color = style.Color }
end

-- Transforme une entrée compacte en mail complet
local function buildEmail(entry): { [string]: any }
	local sender = entry[3]
	local attachment = nil
	if type(entry[7]) == "string" then
		local name = string.gsub(entry[7], "^📎%s*", "")
		local extension = string.lower(string.match(name, "%.(%w+)$") or "")
		local kb = (#name * 137) % 2900 + 40
		attachment = {
			Name = name,
			Type = FILE_TYPES[extension] or { Icon = "📄", Color = Color3.fromRGB(110, 116, 132) },
			Size = kb >= 1000 and string.format("%.1f MB", kb / 1000) or (kb .. " KB"),
			Virus = extension == "exe",
		}
	end
	return {
		Tag = makeTag(entry[1]),
		Avatar = entry[2],
		Sender = sender,
		Address = slug(sender) .. Locale.T("@dopamail.com"),
		Subject = entry[4],
		Body = entry[5],
		Signature = entry[6] or sender,
		Attachment = attachment,
		Suspicious = entry[1] == "ARNAQUE" or entry[1] == "SPAM",
	}
end

local function pickFrom(list: { string }?): string
	if type(list) ~= "table" or #list == 0 then
		return ""
	end
	return list[math.random(1, #list)]
end

local function trim(value: string): string
	local left = string.gsub(value, "^%s+", "")
	local both = string.gsub(left, "%s+$", "")
	return both
end

-- "Re: " + objet (sans empiler "Re: Re: Re:")
local function prefixed(prefix: string, subject: string): string
	if string.sub(subject, 1, #prefix) == prefix then
		return subject
	end
	return prefix .. subject
end

-- Réponse automatique d'un correspondant (texts : CONTACT_TEXT ou TAG_VOICES)
-- selon les sujets (Topics) du message envoyé
local function composeReply(texts, topics: { any }, forwarded: boolean, caps: boolean): string
	local shared = Locale.Pick(TOPIC_LINES)
	local lines: { string } = {}
	if forwarded then
		table.insert(lines, pickFrom(texts.Forward or shared.Forward))
	end
	local seen = {}
	for _, topic in ipairs(topics) do
		if #lines >= 2 then
			break
		end
		if type(topic) == "string" and not seen[topic] then
			seen[topic] = true
			local pool = (texts.Special and texts.Special[topic]) or shared[topic]
			if pool then
				table.insert(lines, pickFrom(pool))
			end
		end
	end
	if #lines < 2 then
		table.insert(lines, pickFrom(texts.Generic))
	end
	local parts: { string } = {}
	for _, piece in ipairs({ pickFrom(texts.Hello), table.concat(lines, " "), pickFrom(texts.Bye) }) do
		if piece ~= "" then
			table.insert(parts, piece)
		end
	end
	-- (numéro de ticket AVANT les majuscules : "{n}" deviendrait "{N}")
	local body = string.gsub(table.concat(parts, " "), "{n}", tostring(math.random(10000, 99999)))
	if caps then
		body = shout(body)
	end
	if texts.Before then
		body = texts.Before .. body .. (texts.After or "")
	end
	return body
end

function Email.Start(ctx)
	local UIUtil = ctx.UIUtil
	local Theme = ctx.Theme
	local container: Frame = ctx.Container
	local random = Random.new()
	container.ZIndex = RAISED_Z

	local C = {
		White = Color3.new(1, 1, 1),
		Paper = Color3.fromRGB(255, 252, 244),
		Ink = Color3.fromRGB(28, 32, 44),
		InkSoft = Color3.fromRGB(56, 62, 80),
		InkDim = Color3.fromRGB(110, 116, 132),
		Blue = Color3.fromRGB(40, 120, 240),
		BlueDark = Color3.fromRGB(22, 84, 196),
		Border = Color3.fromRGB(30, 34, 48),
		Line = Color3.fromRGB(226, 230, 238),
		Side = Color3.fromRGB(243, 246, 252),
		Red = Color3.fromRGB(226, 38, 52),
		Green = Color3.fromRGB(24, 158, 88),
		Gold = Color3.fromRGB(240, 170, 20),
		Grey = Color3.fromRGB(120, 124, 136),
		Selected = Color3.fromRGB(221, 233, 255),
		Unread = Color3.fromRGB(240, 246, 255),
		Hover = Color3.fromRGB(246, 248, 252),
		Field = Color3.fromRGB(248, 249, 252),
		BrandA = Color3.fromRGB(58, 110, 255),
		BrandB = Color3.fromRGB(126, 72, 238),
	}
	local FONT_TITLE = Theme.Fonts.Title
	local FONT_BODY = Theme.Fonts.Body
	local FONT_NUMBER = Theme.Fonts.Number
	local ITALIC = Font.new("rbxasset://fonts/families/BuilderSans.json", Enum.FontWeight.Medium, Enum.FontStyle.Italic)

	-- Le joueur (expéditeur des mails écrits)
	local player = Players.LocalPlayer
	local me = {
		Name = Locale.T("Me"),
		Avatar = "😎",
		Address = string.lower(player and player.Name or "you") .. Locale.T("@dopamail.com"),
	}

	-- Correspondants (textes dans la langue du joueur)
	local contacts: { any } = {}
	do
		local texts = Locale.Pick(CONTACT_TEXT)
		for _, def in ipairs(CONTACTS) do
			local t = texts[def.Id]
			table.insert(contacts, {
				Id = def.Id,
				Avatar = def.Avatar,
				Tag = def.Tag,
				Caps = def.Caps == true,
				Name = t.Name,
				Short = t.Short,
				Signature = t.Signature,
				Address = slug(t.Name) .. Locale.T("@dopamail.com"),
			})
		end
	end
	local contactsById: { [string]: any } = {}
	for _, contact in ipairs(contacts) do
		contactsById[contact.Id] = contact
	end

	------------------------------------------------------------------
	-- Modèle : TOUS les mails de la session (les plus récents en premier)
	--   Kind : "Spawn" (serveur) | "Reply" (réponse d'un correspondant) | "Sent"
	--   Folder : "Inbox" | "Sent" | "Spam" | "Trash" ; Read ; Starred
	--   State : "Live" (réclamable) | "Claimed" | "Expired" | "Missed" | "Local"
	------------------------------------------------------------------
	local mails: { any } = {}
	local bySpawn: { [string]: any } = {}
	local keySeq = 0
	local envelopes: { [string]: any } = {}
	local envelopeCount = 0
	local positions: { [string]: UDim2 } = {}
	local lastPosition = UDim2.fromScale(0.5, 0.45)
	local S = {
		Open = false,
		View = "List", -- "List" | "Message" | "Compose"
		Folder = "Inbox",
		Selected = nil :: any,
		Search = "",
		Draft = nil :: any, -- { Kind, Contact, Fixed, Quote, SubjectText, BodyText }
		Sending = nil :: any, -- jeton de l'envoi en cours
		Interaction = 0, -- augmente à chaque action dans la fenêtre (annule la fermeture auto)
		CloseToken = 0,
		SnackToken = 0,
		SnackAction = nil :: any,
		SnackTarget = nil :: any, -- mail annoncé par le snack (caché quand on l'ouvre)
	}
	local UI: any = nil -- fenêtre (construite à la première ouverture, puis réutilisée)

	-- Fonctions définies plus bas
	local refresh: (bump: boolean?) -> ()
	local openWindow: () -> ()
	local closeWindow: () -> ()
	local openMail: (mail: any, source: string?) -> ()
	local openCompose: (options: any) -> ()
	local setView: (view: string) -> ()
	local renderAll: () -> ()
	local renderMessage: (mail: any) -> ()
	local snack: (message: string, action: (() -> ())?, target: any?) -> ()
	local spawnCard: (mail: any, info: any?) -> ()
	local removeEnvelope: (envelope: any, opened: boolean) -> ()
	local expireMail: (mail: any) -> ()

	local function now(): number
		return os.clock()
	end

	local function effectsOn(): boolean
		local data = ctx.State.Data
		return not (data and data.Settings and data.Settings.Effects == false)
	end

	-- Connexion liée à un élément de l'interface (coupée avec lui)
	local function on(signal: RBXScriptSignal, callback: (...any) -> ())
		signal:Connect(function(...)
			if ctx.IsAlive() then
				callback(...)
			end
		end)
	end

	-- Bouton de la fenêtre : compte comme une interaction (annule la fermeture auto)
	local function onClick(button: GuiButton, callback: () -> ())
		on(button.Activated, function()
			S.Interaction += 1
			callback()
		end)
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
		props.BorderSizePixel = 0
		props.TextXAlignment = props.TextXAlignment or Enum.TextXAlignment.Left
		props.Font = props.Font or FONT_BODY
		props.TextColor3 = props.TextColor3 or C.Ink
		return UIUtil.Create("TextLabel", props)
	end

	-- Largeur d'un texte d'une ligne (pixels "design")
	local function textWidth(value: string, size: number, font: Enum.Font): number
		local ok, bounds = pcall(function()
			return TextService:GetTextSize(value, size, font, Vector2.new(2000, 200))
		end)
		if ok and typeof(bounds) == "Vector2" then
			return bounds.X
		end
		return (utf8.len(value) or #value) * size * 0.55
	end

	-- Bouton : un TextButton sans texte + un TextLabel "Label" (un dégradé
	-- sur le bouton ne teinte pas le texte). kind : "primary" | "secondary" |
	-- "danger" | "ghost"
	local function makeButton(props: { [string]: any }, kind: string, label: string, textSize: number, radius: number?): (TextButton, TextLabel)
		props.AutoButtonColor = false
		props.BorderSizePixel = 0
		props.Text = ""
		if kind == "ghost" then
			props.BackgroundColor3 = props.BackgroundColor3 or C.White
			if props.BackgroundTransparency == nil then
				props.BackgroundTransparency = 1
			end
		else
			props.BackgroundColor3 = props.BackgroundColor3 or (kind == "primary" and C.Blue or C.White)
		end
		local button = UIUtil.Create("TextButton", props)
		UIUtil.Corner(button, radius or 10)
		if kind == "primary" then
			UIUtil.Gradient(button, ColorSequence.new(C.White, Color3.fromRGB(200, 212, 255)), 90)
			UIUtil.Stroke(button, C.BlueDark, 1.5, 0)
		elseif kind ~= "ghost" then
			UIUtil.Gradient(button, ColorSequence.new(C.White, Color3.fromRGB(234, 237, 245)), 90)
			UIUtil.Stroke(button, kind == "danger" and Color3.fromRGB(240, 186, 190) or Color3.fromRGB(198, 204, 220), 1.3, 0)
		end
		local labelObject = UIUtil.Create("TextLabel", {
			Name = "Label",
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.new(1, -12, 1, -8),
			BackgroundTransparency = 1,
			Font = FONT_TITLE,
			Text = label,
			TextColor3 = kind == "primary" and C.White or (kind == "danger" and C.Red or C.Ink),
			TextScaled = true,
			ZIndex = (props.ZIndex or 1) + 1,
			Parent = button,
		})
		UIUtil.Create("UITextSizeConstraint", { MaxTextSize = textSize, MinTextSize = math.max(8, textSize - 6), Parent = labelObject })
		UIUtil.AnimateButton(button, 1.04, 0.95)
		return button, labelObject
	end

	-- Avatar rond (dégradé de la couleur de l'étiquette + emoji), réutilisable
	local function makeAvatar(parent: Instance, size: number, position: UDim2, zIndex: number)
		local circle = frame({ Name = "Avatar", Size = UDim2.fromOffset(size, size), Position = position, BackgroundColor3 = C.White, ZIndex = zIndex, Parent = parent })
		UIUtil.Corner(circle, UDim.new(1, 0))
		local gradient = UIUtil.Gradient(circle, ColorSequence.new(C.White, C.White), 135)
		local stroke = UIUtil.Stroke(circle, C.Line, 1.5, 0.15)
		local emoji = text({
			Size = UDim2.fromScale(1, 1),
			Position = UDim2.fromOffset(0, 1),
			Text = "",
			TextSize = math.floor(size * 0.56),
			TextXAlignment = Enum.TextXAlignment.Center,
			ZIndex = zIndex + 1,
			Parent = circle,
		})
		local avatar = { Frame = circle }
		function avatar.Set(value: string, color: Color3)
			emoji.Text = value
			gradient.Color = ColorSequence.new(color:Lerp(C.White, 0.72), color:Lerp(C.White, 0.36))
			stroke.Color = color
		end
		return avatar
	end

	-- Pastille (étiquette, "NOUVEAU +X"...) : largeur calculée sur le texte
	local function makeChip(parent: Instance, height: number, zIndex: number)
		local chip = frame({ Name = "Chip", Size = UDim2.fromOffset(40, height), BackgroundColor3 = C.Blue, ZIndex = zIndex, Parent = parent })
		UIUtil.Corner(chip, UDim.new(1, 0))
		local label = text({
			Size = UDim2.fromScale(1, 1),
			Font = FONT_TITLE,
			TextColor3 = C.White,
			TextSize = math.floor(height * 0.64),
			TextXAlignment = Enum.TextXAlignment.Center,
			ZIndex = zIndex + 1,
			Parent = chip,
		})
		local out = { Frame = chip, Label = label }
		function out.Set(value: string, color: Color3): number
			label.Text = value
			chip.BackgroundColor3 = color
			local width = math.ceil(textWidth(value, label.TextSize, FONT_TITLE)) + 14
			chip.Size = UDim2.fromOffset(width, height)
			return width
		end
		return out
	end

	local function tagColor(id: string): Color3
		local style = TAGS[id] or TAGS.PERSO
		return style.Color
	end

	local function timeLabel(at: number): string
		local seconds = math.max(0, now() - at)
		if seconds < 60 then
			return Locale.T("now")
		end
		local minutes = math.floor(seconds / 60)
		if minutes < 60 then
			return Locale.T("%d min", minutes)
		end
		return Locale.T("%d h", math.floor(minutes / 60))
	end

	local function countText(count: number, forms): string
		local words = Locale.Pick(forms)
		return tostring(math.floor(count)) .. " " .. (count == 1 and words.One or words.Many)
	end

	local function folderName(id: string, long: boolean?): string
		local names = Locale.Pick(FOLDER_NAMES)
		return (long and names.Long or names.Short)[id] or id
	end

	-- Dopamine estimée d'un mail (même calcul que le serveur)
	local function estimateReward(): number
		local data = ctx.State.Data
		local settings = ctx.Config.Spawners and ctx.Config.Spawners.Email
		if not settings then
			return 0
		end
		local stats = {
			PerSecond = (data and tonumber(data.PerSecond)) or 0,
			ClickValue = (data and tonumber(data.ClickValue)) or 0,
		}
		local ok, amount = pcall(ctx.Formulas.ScaledReward, stats, settings.RewardSeconds or 8, settings.MinReward or 50)
		return ok and (tonumber(amount) or 0) or 0
	end

	------------------------------------------------------------------
	-- Modèle : requêtes et changements
	------------------------------------------------------------------
	local function isLive(mail): boolean
		return mail.State == "Live" and now() < mail.ExpiresAt
	end

	local function inFolder(mail, folder: string): boolean
		if folder == "Starred" then
			return mail.Starred == true and (mail.Folder == "Inbox" or mail.Folder == "Sent")
		end
		return mail.Folder == folder
	end

	local function unreadCount(): number
		local count = 0
		for _, mail in ipairs(mails) do
			if mail.Folder == "Inbox" and not mail.Read then
				count += 1
			end
		end
		return count
	end

	local function folderCount(folder: string): number
		if folder == "Inbox" then
			return unreadCount()
		end
		local count = 0
		for _, mail in ipairs(mails) do
			if inFolder(mail, folder) then
				count += 1
			end
		end
		return count
	end

	local function matches(mail, query: string): boolean
		if query == "" then
			return true
		end
		local e = mail.Email
		local haystack = string.lower(e.Sender .. " " .. e.Subject .. " " .. e.Body .. " " .. (mail.To and mail.To.Name or ""))
		return string.find(haystack, query, 1, true) ~= nil
	end

	local function removeMail(mail)
		local index = table.find(mails, mail)
		if index then
			table.remove(mails, index)
		end
		if mail.SpawnId and bySpawn[mail.SpawnId] == mail then
			bySpawn[mail.SpawnId] = nil
		end
		if mail.Envelope then
			removeEnvelope(mail.Envelope, false)
		end
		if S.Selected == mail then
			S.Selected = nil
		end
	end

	-- Trop de mails : on oublie les plus vieux (lus, sans étoile, plus réclamables)
	local function trimModel()
		local received, sent = 0, 0
		for _, mail in ipairs(mails) do
			if mail.Kind == "Sent" then
				sent += 1
			else
				received += 1
			end
		end
		for index = #mails, 1, -1 do
			if received <= MAX_RECEIVED and sent <= MAX_SENT then
				break
			end
			local mail = mails[index]
			local isSent = mail.Kind == "Sent"
			local over = (isSent and sent > MAX_SENT) or (not isSent and received > MAX_RECEIVED)
			if over and not mail.Starred and mail.Read and mail.State ~= "Live" and mail ~= S.Selected then
				removeMail(mail)
				if isSent then
					sent -= 1
				else
					received -= 1
				end
			end
		end
		-- Toujours trop (jamais lus : joueur absent) : les plus vieux non lus partent aussi
		for index = #mails, 1, -1 do
			if received <= MAX_RECEIVED then
				break
			end
			local mail = mails[index]
			if mail.Kind ~= "Sent" and not mail.Starred and mail.State ~= "Live" and mail ~= S.Selected then
				removeMail(mail)
				received -= 1
			end
		end
	end

	local function addMail(mail)
		keySeq += 1
		mail.Key = keySeq
		table.insert(mails, 1, mail)
		if mail.SpawnId then
			bySpawn[mail.SpawnId] = mail
		end
		trimModel()
	end

	-- Correspondant à qui répondre (un personnage connu, sinon l'expéditeur lui-même)
	local function contactOf(mail)
		if mail.Contact then
			return mail.Contact
		end
		local e = mail.Email
		local castId = CAST_MATCH[e.Avatar .. e.Tag.Id]
		if castId and contactsById[castId] then
			return contactsById[castId]
		end
		return {
			Avatar = e.Avatar,
			Tag = e.Tag.Id,
			Name = e.Sender,
			Short = e.Sender,
			Signature = e.Signature,
			Address = e.Address,
		}
	end

	------------------------------------------------------------------
	-- Compteur "📬 non lus" (dans le bandeau d'actu, à gauche de son bloc
	-- droit) : toujours visible, ouvre / ferme Dopamail
	------------------------------------------------------------------
	local counter = UIUtil.Create("TextButton", {
		Name = "Unread",
		Size = UDim2.fromOffset(0, 22),
		AutomaticSize = Enum.AutomaticSize.X,
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -(TICKER_RIGHT_FALLBACK + 6), 0, 4),
		BackgroundColor3 = C.White,
		BorderSizePixel = 0,
		AutoButtonColor = false,
		Text = "",
		ZIndex = 40,
		Parent = container,
	})
	UIUtil.Corner(counter, UDim.new(1, 0))
	UIUtil.Stroke(counter, C.Border, 1.5, 0.15)
	UIUtil.Gradient(counter, ColorSequence.new(C.White, Color3.fromRGB(226, 232, 244)), 90)
	UIUtil.Create("UIPadding", { PaddingLeft = UDim.new(0, 4), PaddingRight = UDim.new(0, 9), Parent = counter })
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
		BackgroundColor3 = C.Blue,
		BackgroundTransparency = 0,
		Font = FONT_NUMBER,
		Text = "0",
		TextColor3 = C.White,
		TextSize = 12,
		TextXAlignment = Enum.TextXAlignment.Center,
		LayoutOrder = 1,
		Visible = false,
		ZIndex = 41,
		Parent = counter,
	})
	UIUtil.Corner(counterBadge, UDim.new(1, 0))
	UIUtil.Create("UIPadding", { PaddingLeft = UDim.new(0, 5), PaddingRight = UDim.new(0, 5), Parent = counterBadge })
	local counterLabel = text({
		Size = UDim2.fromOffset(0, 18),
		AutomaticSize = Enum.AutomaticSize.X,
		Font = FONT_TITLE,
		Text = "📬 Dopamail",
		TextSize = 13,
		LayoutOrder = 2,
		ZIndex = 41,
		Parent = counter,
	})
	local counterScale = UIUtil.Create("UIScale", { Parent = counter })
	UIUtil.AnimateButton(counter, 1.06, 0.94)

	-- Place du compteur : juste à gauche du bloc horloge / segment du bandeau
	local tickerRight = TICKER_RIGHT_FALLBACK
	local function placeCounter()
		local slots = ctx.Interface and ctx.Interface.Layers and ctx.Interface.Layers.Slots
		local ticker = slots and slots:FindFirstChild("NewsTicker")
		local inset = ticker and ticker:GetAttribute("RightInset")
		tickerRight = type(inset) == "number" and inset or TICKER_RIGHT_FALLBACK
		counter.Position = UDim2.new(1, -(tickerRight + 6), 0, 4)
	end
	placeCounter()
	task.delay(1, function()
		if ctx.IsAlive() then
			placeCounter()
		end
	end)

	local function refreshCounter(bump: boolean?)
		local unread = unreadCount()
		counterBadge.Visible = unread > 0
		counterBadge.Text = unread > 999 and "999+" or tostring(unread)
		counterBadge.BackgroundColor3 = unread >= 10 and C.Red or C.Blue
		if unread > 0 then
			local suffix = unread >= 25 and " 😱" or (unread >= 10 and " 😬" or "")
			local words = Locale.Pick(UNREAD)
			counterLabel.Text = "📬 " .. (unread > 1 and words.Many or words.One) .. suffix
		else
			counterLabel.Text = "📬 Dopamail"
		end
		if bump then
			counterScale.Scale = 1.25
			UIUtil.Tween(counterScale, 0.3, { Scale = 1 }, Enum.EasingStyle.Back)
		end
	end
	refreshCounter(false)

	------------------------------------------------------------------
	-- Fenêtre Dopamail
	------------------------------------------------------------------
	local function currentMode(): string
		local interface = ctx.Interface
		if interface and interface.Device == "Phone" then
			return "Phone"
		end
		return "Wide"
	end

	local function paintRow(entry)
		local mail = entry.Mail
		if not mail then
			return
		end
		local selected = S.Selected == mail
		local color = selected and C.Selected or (mail.Read and C.White or C.Unread)
		if entry.Hover and not selected then
			color = color:Lerp(Color3.fromRGB(210, 222, 245), 0.25)
		end
		entry.Row.BackgroundColor3 = color
		entry.Accent.Visible = selected
	end

	local function toggleStar(mail)
		mail.Starred = not mail.Starred
		ctx.Sound.Play("Click", 1.2)
		refresh()
	end

	-- Ligne de liste (réutilisée : une réserve de lignes par fenêtre)
	local function newRow(ui, index: number)
		local L = ui.L
		local F = L.F
		local rowW = ui.ListW - 18
		local rowH = L.Row - 4
		local row = UIUtil.Create("TextButton", {
			Name = "MailRow" .. index,
			Size = UDim2.fromOffset(rowW, rowH),
			Position = UDim2.fromOffset(6, 4),
			BackgroundColor3 = C.White,
			BorderSizePixel = 0,
			AutoButtonColor = false,
			Text = "",
			ZIndex = 6,
			Parent = ui.List,
		})
		UIUtil.Corner(row, 10)
		local entry: any = { Row = row, Mail = nil, Hover = false, RowW = rowW }
		entry.Accent = frame({ Position = UDim2.fromOffset(0, 10), Size = UDim2.fromOffset(4, rowH - 20), BackgroundColor3 = C.Blue, Visible = false, ZIndex = 7, Parent = row })
		UIUtil.Corner(entry.Accent, 2)
		entry.Dot = frame({ AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromOffset(11, math.floor(rowH / 2)), Size = UDim2.fromOffset(8, 8), BackgroundColor3 = C.Blue, ZIndex = 7, Parent = row })
		UIUtil.Corner(entry.Dot, UDim.new(1, 0))
		local avatarSize = 40
		entry.Avatar = makeAvatar(row, avatarSize, UDim2.fromOffset(20, math.floor((rowH - avatarSize) / 2)), 7)
		local textX = 20 + avatarSize + 10
		entry.TextX = textX
		entry.Sender = text({ Position = UDim2.fromOffset(textX, 6), Size = UDim2.fromOffset(rowW - textX - 80, 18), TextSize = 14 + F, TextTruncate = Enum.TextTruncate.AtEnd, ZIndex = 7, Parent = row })
		entry.Time = text({ AnchorPoint = Vector2.new(1, 0), Position = UDim2.fromOffset(rowW - 10, 7), Size = UDim2.fromOffset(74, 16), TextColor3 = C.InkDim, TextSize = 11 + F, TextXAlignment = Enum.TextXAlignment.Right, ZIndex = 7, Parent = row })
		entry.Subject = text({ Position = UDim2.fromOffset(textX, 25), Size = UDim2.fromOffset(rowW - textX - 40, 17), TextColor3 = C.InkSoft, TextSize = 13 + F, TextTruncate = Enum.TextTruncate.AtEnd, ZIndex = 7, Parent = row })
		entry.Chip = makeChip(row, 17, 7)
		entry.Chip.Frame.Position = UDim2.fromOffset(textX, 44)
		entry.Preview = text({ Position = UDim2.fromOffset(textX, 44), Size = UDim2.fromOffset(100, 17), TextColor3 = C.InkDim, TextSize = 12 + F, TextTruncate = Enum.TextTruncate.AtEnd, ZIndex = 7, Parent = row })
		local star, starLabel = makeButton({ Name = "RowStar", AnchorPoint = Vector2.new(1, 1), Position = UDim2.fromOffset(rowW - 5, rowH - 3), Size = UDim2.fromOffset(32, 32), ZIndex = 8, Parent = row }, "ghost", "☆", 19 + F, 8)
		starLabel.TextColor3 = C.Gold
		entry.StarLabel = starLabel
		onClick(row, function()
			if entry.Mail then
				ctx.Sound.Play("Click", 1.1)
				openMail(entry.Mail, "List")
			end
		end)
		onClick(star, function()
			if entry.Mail then
				toggleStar(entry.Mail)
			end
		end)
		on(row.MouseEnter, function()
			entry.Hover = true
			paintRow(entry)
		end)
		on(row.MouseLeave, function()
			entry.Hover = false
			paintRow(entry)
		end)
		ui.Rows[index] = entry
		return entry
	end

	local function fillRow(ui, entry, mail, index: number)
		local e = mail.Email
		local F = ui.L.F
		local rowW = entry.RowW
		entry.Mail = mail
		entry.Row.Visible = true
		entry.Row.Position = UDim2.fromOffset(6, 4 + (index - 1) * ui.L.Row)
		paintRow(entry)
		entry.Dot.Visible = not mail.Read
		entry.Avatar.Set(e.Avatar, e.Tag.Color)
		if mail.Kind == "Sent" then
			entry.Sender.Text = Locale.T("To: %s", mail.To.Name)
		else
			entry.Sender.Text = e.Sender
		end
		entry.Sender.Font = mail.Read and FONT_BODY or FONT_TITLE
		entry.Subject.Font = mail.Read and FONT_BODY or FONT_TITLE
		entry.Time.Text = timeLabel(mail.Time)
		local subject = e.Subject ~= "" and e.Subject or Locale.T("(no subject)")
		entry.Subject.Text = (e.Attachment and "📎 " or "") .. subject
		entry.StarLabel.Text = mail.Starred and "⭐" or "☆"
		-- Ligne 3 : pastille ("🎁 NOUVEAU · +X" tant qu'il est réclamable, sinon étiquette) + aperçu
		local x = entry.TextX
		if isLive(mail) then
			local width = entry.Chip.Set(Locale.T("🎁 NEW · +%s", ctx.Format.Format(mail.Estimate or 0)), C.Green)
			entry.Chip.Frame.Visible = true
			x += width + 6
		elseif mail.Kind ~= "Sent" then
			local width = entry.Chip.Set(e.Tag.Text, e.Tag.Color)
			entry.Chip.Frame.Visible = true
			x += width + 6
		else
			entry.Chip.Frame.Visible = false
		end
		local previewW = rowW - x - 40
		entry.Preview.Visible = previewW > 24
		entry.Preview.Position = UDim2.fromOffset(x, 44)
		entry.Preview.Size = UDim2.fromOffset(math.max(0, previewW), 17)
		local preview = e.Body ~= "" and e.Body or subject
		entry.Preview.Text = string.gsub(preview, "%s+", " ")
		entry.Preview.TextSize = 12 + F
	end

	local function visibleMails(): { any }
		local list = {}
		local query = string.lower(trim(S.Search))
		for _, mail in ipairs(mails) do
			if inFolder(mail, S.Folder) and matches(mail, query) then
				table.insert(list, mail)
			end
		end
		return list
	end

	local EMPTY_ICONS = { Inbox = "🎉", Starred = "⭐", Sent = "📤", Spam = "🚫", Trash = "🗑️" }
	local function emptyText(folder: string): string
		if folder == "Starred" then
			return Locale.T("No starred mail. Tap ☆ on a mail to keep it here.")
		elseif folder == "Sent" then
			return Locale.T("Nothing sent yet. Grandma is waiting for your news!")
		elseif folder == "Spam" then
			return Locale.T("No spam here. Suspiciously clean.")
		elseif folder == "Trash" then
			return Locale.T("The trash is empty. Very tidy.")
		end
		return Locale.T("🎉 Inbox zero! Enjoy it, it won't last.")
	end

	local function renderList()
		local ui = UI
		if not ui then
			return
		end
		local list = visibleMails()
		local folder = S.Folder
		local searching = trim(S.Search) ~= ""
		local icon = "📥"
		for _, def in ipairs(FOLDERS) do
			if def.Id == folder then
				icon = def.Icon
			end
		end
		ui.ListTitle.Text = icon .. " " .. folderName(folder, true)
		local sub
		if searching then
			sub = "🔍 " .. countText(#list, RESULTS)
		elseif folder == "Inbox" then
			local unread = unreadCount()
			sub = (unread > 0 and (tostring(unread) .. " " .. (unread > 1 and Locale.Pick(UNREAD).Many or Locale.Pick(UNREAD).One) .. " · ") or "") .. countText(#list, MAIL_COUNT)
		else
			sub = countText(#list, MAIL_COUNT)
		end
		ui.ListSub.Text = sub
		-- Action d'en-tête : "Tout lu" (Réception) / "Vider" (Corbeille)
		local action = nil
		if folder == "Inbox" and unreadCount() > 0 and not searching then
			action = Locale.T("✓ All read")
		elseif folder == "Trash" and #list > 0 and not searching then
			action = Locale.T("🧹 Empty")
		end
		ui.ListAction.Visible = action ~= nil
		ui.ListActionLabel.Text = action or ""
		-- Lignes (réserve réutilisée)
		for index, mail in ipairs(list) do
			local entry = ui.Rows[index] or newRow(ui, index)
			fillRow(ui, entry, mail, index)
		end
		for index = #list + 1, #ui.Rows do
			local entry = ui.Rows[index]
			entry.Row.Visible = false
			entry.Mail = nil
		end
		ui.List.CanvasSize = UDim2.fromOffset(0, #list * ui.L.Row + 10)
		local empty = #list == 0
		ui.Empty.Visible = empty
		ui.EmptyIcon.Visible = empty
		if empty then
			ui.EmptyIcon.Text = searching and "🔍" or (EMPTY_ICONS[folder] or "📭")
			ui.Empty.Text = searching and Locale.T("No mail matches your search.") or emptyText(folder)
		end
	end

	local function renderFolders()
		local ui = UI
		if not ui then
			return
		end
		for _, def in ipairs(FOLDERS) do
			local item = ui.Folders[def.Id]
			if item then
				local active = S.Folder == def.Id
				item.Button.BackgroundTransparency = active and 0 or 1
				item.Button.BackgroundColor3 = C.Selected
				item.Accent.Visible = active
				if item.Label then
					item.Label.Font = active and FONT_TITLE or FONT_BODY
					item.Label.TextColor3 = active and C.BlueDark or C.Ink
				end
				local count = folderCount(def.Id)
				item.Badge.Visible = count > 0
				item.Badge.Text = count > 99 and "99+" or tostring(count)
				if def.Id == "Inbox" then
					-- Comme le compteur du bandeau : rouge à partir de 10 non lus
					item.Badge.BackgroundColor3 = (count >= 10 or ui.Mode == "Phone") and C.Red or C.Blue
				end
			end
		end
		ui.LogoDot.Visible = unreadCount() > 0
	end

	-- Bandeau (récompense / avertissement) de la zone de lecture
	local function setBanner(banner, value: string?, background: Color3?, border: Color3?, color: Color3?)
		banner.Frame.Visible = value ~= nil
		if value then
			banner.Label.Text = value
			banner.Frame.BackgroundColor3 = background or C.Field
			banner.Stroke.Color = border or C.Line
			banner.Label.TextColor3 = color or C.Ink
		end
	end

	local ACTION_ORDER = { "Reply", "Forward", "Spam", "NotSpam", "Delete", "Restore", "Forever" }

	-- État variable d'un mail affiché : étoile, récompense, boutons d'action
	local function updateMessageState(mail)
		local ui = UI
		if not ui then
			return
		end
		local msg = ui.Msg
		msg.StarLabel.Text = mail.Starred and "⭐" or "☆"
		if mail.Kind == "Spawn" then
			if mail.State == "Claimed" and mail.Reward then
				setBanner(msg.Reward, Locale.T("🎁 +%s Dopamine collected!", ctx.Format.Format(mail.Reward)), Color3.fromRGB(226, 248, 234), Color3.fromRGB(120, 210, 150), Color3.fromRGB(16, 120, 60))
			elseif mail.State == "Claimed" then
				setBanner(msg.Reward, Locale.T("🎁 Bonus on its way…"), Color3.fromRGB(236, 250, 241), Color3.fromRGB(160, 222, 180), Color3.fromRGB(30, 130, 70))
			elseif mail.State == "Expired" or mail.State == "Missed" then
				setBanner(msg.Reward, Locale.T("⌛ Opened too late: no bonus this time."), C.Field, C.Line, C.InkDim)
			else
				setBanner(msg.Reward, nil)
			end
		else
			setBanner(msg.Reward, nil)
		end
		-- Boutons selon le dossier
		local visible
		if mail.Folder == "Trash" then
			visible = { Restore = true, Forever = true }
		elseif mail.Folder == "Spam" then
			visible = { NotSpam = true, Delete = true }
		elseif mail.Kind == "Sent" then
			visible = { Forward = true, Delete = true }
		else
			visible = { Reply = true, Forward = true, Spam = true, Delete = true }
		end
		local shown = {}
		for _, id in ipairs(ACTION_ORDER) do
			local button = msg.Actions[id]
			button.Visible = visible[id] == true
			if visible[id] then
				table.insert(shown, button)
			end
		end
		local P = ui.L.Pad
		local gap = 8
		local width = math.floor((ui.ReadW - P * 2 - gap * (#shown - 1)) / math.max(1, #shown))
		for index, button in ipairs(shown) do
			button.Position = UDim2.fromOffset(P + (index - 1) * (width + gap), 10)
			button.Size = UDim2.fromOffset(width, 38)
		end
	end

	renderMessage = function(mail)
		local ui = UI
		if not ui then
			return
		end
		local msg = ui.Msg
		local e = mail.Email
		msg.Subject.Text = e.Subject ~= "" and e.Subject or Locale.T("(no subject)")
		if mail.Kind == "Sent" then
			msg.Avatar.Set(me.Avatar, C.Blue)
			msg.Sender.Text = me.Name
			msg.Meta.Text = Locale.T("to %s <%s> · %s", mail.To.Name, mail.To.Address, timeLabel(mail.Time))
			msg.Chip.Frame.Visible = false
			msg.Sender.Size = UDim2.fromOffset(ui.ReadW - ui.L.Pad * 2 - 52, 20)
		else
			msg.Avatar.Set(e.Avatar, e.Tag.Color)
			msg.Sender.Text = e.Sender
			msg.Meta.Text = Locale.T("<%s> · to me · %s", e.Address, timeLabel(mail.Time))
			local chipW = msg.Chip.Set(e.Tag.Text, e.Tag.Color)
			msg.Chip.Frame.Visible = true
			msg.Sender.Size = UDim2.fromOffset(math.max(40, ui.ReadW - ui.L.Pad * 2 - 52 - chipW - 8), 20)
		end
		-- Avertissement (spams et arnaques)
		if e.Suspicious then
			local scam = e.Tag.Id == "ARNAQUE"
			setBanner(
				msg.Warning,
				scam and Locale.T("⚠️ Careful: this looks like a scam. Never share your password!") or Locale.T("🚫 This looks like spam. We're not judging."),
				scam and Color3.fromRGB(255, 240, 210) or Color3.fromRGB(238, 240, 246),
				scam and Color3.fromRGB(240, 160, 60) or Color3.fromRGB(196, 202, 216),
				scam and Color3.fromRGB(150, 70, 0) or C.InkDim
			)
		else
			setBanner(msg.Warning, nil)
		end
		msg.Body.Text = e.Body ~= "" and e.Body or "…"
		msg.Signature.Visible = e.Signature ~= nil and e.Signature ~= ""
		msg.Signature.Text = "— " .. tostring(e.Signature or "")
		if mail.Quote then
			msg.Quote.Visible = true
			msg.QuoteLabel.Text = mail.Quote.Label .. "\n" .. mail.Quote.Text
		else
			msg.Quote.Visible = false
		end
		local attachment = e.Attachment
		msg.Attachment.Visible = attachment ~= nil
		if attachment then
			msg.FileIcon.BackgroundColor3 = attachment.Type.Color
			msg.FileEmoji.Text = attachment.Type.Icon
			msg.FileName.Text = attachment.Name
			msg.FileSize.Text = attachment.Size
			msg.FileAction.Text = "⬇️"
		end
		msg.Scroll.CanvasPosition = Vector2.zero
		updateMessageState(mail)
	end

	------------------------------------------------------------------
	-- Rédaction
	------------------------------------------------------------------
	local function setStatus(message: string?, color: Color3?)
		local ui = UI
		if not ui then
			return
		end
		ui.Cmp.Status.Text = message or Locale.T("🛡️ Checked by the Roblox filter before sending")
		ui.Cmp.Status.TextColor3 = color or C.InkDim
	end

	local function setSending(active: boolean)
		local ui = UI
		if not ui then
			return
		end
		local cmp = ui.Cmp
		cmp.SendLabel.Text = active and Locale.T("⏳ Sending…") or ("✈️ " .. Locale.T("Send"))
		cmp.Send.BackgroundColor3 = active and C.Grey or C.Blue
		cmp.Subject.TextEditable = not active
		cmp.Body.TextEditable = not active
		if active then
			setStatus(Locale.T("🛡️ Checking your message…"), C.Blue)
		end
	end

	local function updateCounterLabel()
		local ui = UI
		if not ui then
			return
		end
		local length = utf8.len(ui.Cmp.Body.Text) or #ui.Cmp.Body.Text
		ui.Cmp.Counter.Text = string.format("%d/%d", math.floor(length), BODY_MAX)
		ui.Cmp.Counter.TextColor3 = length >= BODY_MAX and C.Red or C.InkDim
	end

	local function renderChips()
		local ui = UI
		if not ui then
			return
		end
		local draft = S.Draft
		for id, chip in pairs(ui.Cmp.Chips) do
			local selected = draft ~= nil and draft.Contact ~= nil and draft.Contact.Id == id
			chip.Button.BackgroundColor3 = selected and C.Selected or C.White
			chip.Stroke.Color = selected and C.Blue or C.Line
			chip.Stroke.Thickness = selected and 2 or 1.3
			chip.Name.TextColor3 = selected and C.BlueDark or C.Ink
		end
	end

	-- Place les champs selon le brouillon (destinataire fixe, citation) :
	-- le texte prend toute la place restante
	local function layoutCompose()
		local ui = UI
		local draft = S.Draft
		if not ui or not draft then
			return
		end
		local cmp = ui.Cmp
		local P = ui.L.Pad
		local phone = ui.Mode == "Phone"
		local height = ui.L.H - ui.L.Title
		local fixed = draft.Fixed == true
		cmp.Fixed.Visible = fixed
		for _, chip in pairs(cmp.Chips) do
			chip.Button.Visible = not fixed
		end
		local y = (fixed and (cmp.GridTop + 40) or cmp.GridBottom) + 10
		cmp.SubjectField.Position = UDim2.fromOffset(P, y)
		y += 36 + 8
		local statusY = height - 12 - 42 - 6 - 18
		local quoteH = draft.Quote and (phone and 42 or 50) or 0
		local bodyH = math.max(48, statusY - 6 - y - (quoteH > 0 and quoteH + 8 or 0))
		cmp.BodyField.Position = UDim2.fromOffset(P, y)
		cmp.BodyField.Size = UDim2.new(1, -P * 2, 0, bodyH)
		y += bodyH + 8
		cmp.Quote.Visible = quoteH > 0
		if quoteH > 0 then
			cmp.Quote.Position = UDim2.fromOffset(P, y)
			cmp.Quote.Size = UDim2.new(1, -P * 2, 0, quoteH)
		end
		cmp.Status.Position = UDim2.fromOffset(P, statusY)
	end

	local function renderCompose()
		local ui = UI
		local draft = S.Draft
		if not ui or not draft then
			return
		end
		local cmp = ui.Cmp
		local titles = {
			New = Locale.T("✏️ New message"),
			Reply = Locale.T("↩️ Reply"),
			Forward = Locale.T("➡️ Forward"),
		}
		local title = titles[draft.Kind] or titles.New
		cmp.Title.Text = title
		if ui.Mode == "Phone" then
			ui.Title.Text = title
		end
		local contact = draft.Contact
		if draft.Fixed and contact then
			cmp.FixedAvatar.Set(contact.Avatar, tagColor(contact.Tag))
			cmp.FixedName.Text = contact.Name .. "  <" .. contact.Address .. ">"
		end
		if draft.Quote then
			cmp.QuoteLabel.Text = draft.Quote.Label .. "\n" .. (draft.Quote.Short or draft.Quote.Text)
		end
		renderChips()
		layoutCompose()
		updateCounterLabel()
		if S.Sending then
			setSending(true)
		else
			setSending(false)
			setStatus(nil)
		end
	end

	------------------------------------------------------------------
	-- Petit message en bas de la fenêtre ("snack"), cliquable si action
	------------------------------------------------------------------
	local function hideSnack()
		local ui = UI
		S.SnackToken += 1
		S.SnackAction = nil
		S.SnackTarget = nil
		if ui then
			ui.Snack.Visible = false
		end
	end

	snack = function(message: string, action: (() -> ())?, target: any?)
		local ui = UI
		if not ui or not S.Open then
			ctx.Notify(message)
			return
		end
		S.SnackToken += 1
		local token = S.SnackToken
		S.SnackAction = action
		S.SnackTarget = target
		ui.Snack.Text = message
		ui.Snack.Visible = true
		ui.SnackScale.Scale = 0.6
		UIUtil.Tween(ui.SnackScale, 0.25, { Scale = 1 }, Enum.EasingStyle.Back)
		task.delay(action and 5 or 2.8, function()
			if ctx.IsAlive() and S.SnackToken == token then
				hideSnack()
			end
		end)
	end

	------------------------------------------------------------------
	-- Construction de la fenêtre (une fois par mode d'affichage)
	------------------------------------------------------------------
	local selectFolder: (id: string) -> ()
	local sendDraft: () -> ()
	local cancelCompose: () -> ()
	local runAction: (id: string) -> ()
	local composeClicked: () -> ()
	local goBack: () -> ()

	local function limitBox(box: TextBox, maxChars: number)
		local value = box.Text
		local length = utf8.len(value)
		if length and length > maxChars then
			local cut = utf8.offset(value, maxChars + 1)
			if cut then
				box.Text = string.sub(value, 1, cut - 1)
			end
		end
	end

	local function buildWindow(mode: string)
		local L = LAYOUTS[mode]
		local phone = mode == "Phone"
		local F = L.F
		local P = L.Pad
		local W, H, T = L.W, L.H, L.Title
		local bodyH = H - T
		local ui: any = { Mode = mode, L = L, Rows = {}, Folders = {}, Fit = 1 }

		-- Fond assombri plein écran : un clic dehors ferme la fenêtre
		local dimmer = UIUtil.Create("TextButton", {
			Name = "MailDimmer",
			Size = UDim2.fromScale(1, 1),
			BackgroundColor3 = Color3.fromRGB(10, 12, 28),
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			AutoButtonColor = false,
			Text = "",
			Visible = false,
			ZIndex = 20,
			Parent = container,
		})
		on(dimmer.Activated, function()
			closeWindow()
		end)
		ui.Dimmer = dimmer

		local root = frame({
			Name = "MailWindow",
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromOffset(W, H),
			Visible = false,
			ZIndex = 60,
			Parent = container,
		})
		ui.Root = root
		ui.Scale = UIUtil.Create("UIScale", { Parent = root })
		-- Ombre douce
		for index, spec in ipairs({ { 18, 0.9 }, { 10, 0.85 }, { 4, 0.8 } }) do
			local spread = spec[1]
			local shadow = frame({
				Name = "Shadow" .. index,
				Position = UDim2.fromOffset(-spread, -spread + 10),
				Size = UDim2.new(1, spread * 2, 1, spread * 2),
				BackgroundColor3 = Color3.new(0, 0, 0),
				BackgroundTransparency = spec[2],
				ZIndex = index,
				Parent = root,
			})
			UIUtil.Corner(shadow, 16 + spread)
		end
		local win = frame({ Name = "Window", Size = UDim2.fromScale(1, 1), BackgroundColor3 = C.White, ZIndex = 5, Parent = root })
		UIUtil.Corner(win, 16)
		UIUtil.Stroke(win, C.Border, 2, 0.05)
		-- Un clic sur une zone vide de la fenêtre ne ferme rien
		local sink = UIUtil.SinkClicks(win)
		on(sink.MouseEnter, function()
			S.Interaction += 1
		end)
		ui.Window = win

		-- Barre de titre (dégradé "Dopamail", ✕ rouge bien à nous)
		local titleBar = frame({ Name = "TitleBar", Size = UDim2.new(1, 0, 0, T), BackgroundColor3 = C.White, ZIndex = 3, Parent = win })
		UIUtil.Corner(titleBar, 16)
		UIUtil.Gradient(titleBar, ColorSequence.new(C.BrandA, C.BrandB), 0)
		local titleFill = frame({ AnchorPoint = Vector2.new(0, 1), Position = UDim2.fromScale(0, 1), Size = UDim2.new(1, 0, 0, 18), BackgroundColor3 = C.White, ZIndex = 3, Parent = titleBar })
		UIUtil.Gradient(titleFill, ColorSequence.new(C.BrandA, C.BrandB), 0)

		local left = 12
		if phone then
			local back = makeButton({
				Name = "MailBack",
				AnchorPoint = Vector2.new(0, 0.5),
				Position = UDim2.new(0, 8, 0.5, 0),
				Size = UDim2.fromOffset(44, 36),
				BackgroundColor3 = C.White,
				BackgroundTransparency = 0.78,
				Visible = false,
				ZIndex = 5,
				Parent = titleBar,
			}, "ghost", "←", 24, 10)
			back:FindFirstChild("Label").TextColor3 = C.White
			onClick(back, function()
				ctx.Sound.Play("Click", 1)
				goBack()
			end)
			ui.Back = back
		end
		local logo = frame({ Name = "Logo", AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, left, 0.5, 0), Size = UDim2.fromOffset(32, 32), BackgroundColor3 = C.White, ZIndex = 5, Parent = titleBar })
		UIUtil.Corner(logo, 9)
		UIUtil.Stroke(logo, Color3.fromRGB(34, 44, 120), 1.5, 0.35)
		text({ Size = UDim2.fromScale(1, 1), Position = UDim2.fromOffset(0, 1), Text = "✉️", TextSize = 18, TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 6, Parent = logo })
		local logoDot = frame({ Name = "Dot", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(1, -2, 0, 3), Size = UDim2.fromOffset(12, 12), BackgroundColor3 = C.Red, Visible = false, ZIndex = 7, Parent = logo })
		UIUtil.Corner(logoDot, UDim.new(1, 0))
		UIUtil.Stroke(logoDot, C.White, 2, 0)
		ui.Logo = logo
		ui.LogoDot = logoDot
		local titleW = phone and (W - 200) or 300
		ui.Title = text({ Name = "AppTitle", Position = UDim2.fromOffset(left + 42, math.floor(T / 2) - 20), Size = UDim2.fromOffset(titleW, 22), Font = FONT_TITLE, Text = "Dopamail", TextColor3 = C.White, TextSize = 19 + F, TextTruncate = Enum.TextTruncate.AtEnd, ZIndex = 5, Parent = titleBar })
		ui.Subtitle = text({ Position = UDim2.fromOffset(left + 42, math.floor(T / 2) + 2), Size = UDim2.fromOffset(titleW, 16), Text = me.Address, TextColor3 = Color3.fromRGB(224, 230, 255), TextSize = 12 + F, TextTruncate = Enum.TextTruncate.AtEnd, ZIndex = 5, Parent = titleBar })

		if not phone then
			-- Recherche (filtre la liste du dossier affiché, rien n'est envoyé)
			local search = frame({ Name = "Search", AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -60, 0.5, 0), Size = UDim2.fromOffset(250, 32), BackgroundColor3 = C.White, BackgroundTransparency = 0.8, ZIndex = 5, Parent = titleBar })
			UIUtil.Corner(search, UDim.new(1, 0))
			UIUtil.Stroke(search, C.White, 1, 0.55)
			text({ Position = UDim2.fromOffset(10, 0), Size = UDim2.new(0, 22, 1, 0), Text = "🔍", TextSize = 14, ZIndex = 6, Parent = search })
			local box = UIUtil.Create("TextBox", {
				Name = "SearchBox",
				Position = UDim2.fromOffset(34, 0),
				Size = UDim2.new(1, -44, 1, 0),
				BackgroundTransparency = 1,
				BorderSizePixel = 0,
				ClearTextOnFocus = false,
				Font = FONT_BODY,
				PlaceholderText = Locale.T("Search"),
				PlaceholderColor3 = Color3.fromRGB(214, 222, 255),
				Text = S.Search,
				TextColor3 = C.White,
				TextSize = 14,
				TextXAlignment = Enum.TextXAlignment.Left,
				ZIndex = 6,
				Parent = search,
			})
			on(box:GetPropertyChangedSignal("Text"), function()
				limitBox(box, 40)
				if S.Search ~= box.Text then
					S.Search = box.Text
					S.Interaction += 1
					renderList()
				end
			end)
			on(box.Focused, function()
				S.Interaction += 1
			end)
			ui.SearchBox = box
		end

		-- ✕ commun à toutes les fenêtres du jeu (disque blanc nacré, croix
		-- rouge au survol) : bien visible sur le dégradé, rien à voir avec les
		-- icônes rondes et sombres de Roblox ; zone tactile agrandie autour
		UIUtil.CloseButton({
			Name = "MailClose",
			Size = phone and 40 or 36,
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.new(1, -10, 0.5, 0),
			ZIndex = 7,
			Parent = titleBar,
			Hitbox = phone and 64 or 54,
			OnClose = function()
				if ctx.IsAlive() then
					closeWindow()
				end
			end,
		})

		-- Barre latérale (PC) / colonne d'icônes (téléphone)
		local side = frame({ Name = "Sidebar", Position = UDim2.fromOffset(0, T), Size = UDim2.new(0, L.Side, 1, -T), BackgroundColor3 = C.Side, ZIndex = 3, Parent = win })
		UIUtil.Corner(side, 16)
		frame({ Size = UDim2.new(1, 0, 0, 18), BackgroundColor3 = C.Side, ZIndex = 3, Parent = side })
		frame({ AnchorPoint = Vector2.new(1, 0), Position = UDim2.fromScale(1, 0), Size = UDim2.new(0, 18, 1, 0), BackgroundColor3 = C.Side, ZIndex = 3, Parent = side })
		frame({ AnchorPoint = Vector2.new(1, 0), Position = UDim2.fromScale(1, 0), Size = UDim2.new(0, 1, 1, 0), BackgroundColor3 = C.Line, ZIndex = 4, Parent = side })

		local compose = UIUtil.Create("TextButton", {
			Name = "ComposeButton",
			Position = UDim2.fromOffset(phone and 10 or 14, phone and 10 or 14),
			Size = phone and UDim2.fromOffset(48, 48) or UDim2.new(1, -28, 0, 44),
			BackgroundColor3 = C.White,
			BorderSizePixel = 0,
			AutoButtonColor = false,
			Text = "",
			ZIndex = 6,
			Parent = side,
		})
		UIUtil.Corner(compose, UDim.new(1, 0))
		UIUtil.Gradient(compose, ColorSequence.new(C.BrandA, C.BrandB), 0)
		UIUtil.Stroke(compose, Color3.fromRGB(38, 48, 150), 1.5, 0.2)
		text({
			Size = UDim2.fromScale(1, 1),
			Font = FONT_TITLE,
			Text = phone and "✏️" or ("✏️ " .. Locale.T("Compose")),
			TextColor3 = C.White,
			TextSize = phone and 22 or 17,
			TextXAlignment = Enum.TextXAlignment.Center,
			ZIndex = 7,
			Parent = compose,
		})
		UIUtil.AnimateButton(compose, 1.05, 0.94)
		onClick(compose, function()
			ctx.Sound.Play("Click", 1)
			composeClicked()
		end)

		-- Dossiers
		local names = Locale.Pick(FOLDER_NAMES).Short
		local folderY = phone and 70 or 72
		for _, def in ipairs(FOLDERS) do
			local id = def.Id
			local item: any = {}
			local button = UIUtil.Create("TextButton", {
				Name = "Folder_" .. id,
				Position = UDim2.fromOffset(phone and 8 or 8, folderY),
				Size = phone and UDim2.fromOffset(52, 46) or UDim2.new(1, -16, 0, 36),
				BackgroundColor3 = C.Selected,
				BackgroundTransparency = 1,
				BorderSizePixel = 0,
				AutoButtonColor = false,
				Text = "",
				ZIndex = 6,
				Parent = side,
			})
			UIUtil.Corner(button, 10)
			item.Button = button
			item.Accent = frame({ AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 0, 0.5, 0), Size = UDim2.fromOffset(4, phone and 24 or 20), BackgroundColor3 = C.Blue, Visible = false, ZIndex = 7, Parent = button })
			UIUtil.Corner(item.Accent, 2)
			if phone then
				text({ Size = UDim2.fromScale(1, 1), Text = def.Icon, TextSize = 22, TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 7, Parent = button })
				item.Badge = text({
					Name = "Count",
					AnchorPoint = Vector2.new(1, 0),
					Position = UDim2.new(1, 2, 0, -2),
					Size = UDim2.fromOffset(22, 17),
					BackgroundColor3 = id == "Inbox" and C.Red or C.Grey,
					BackgroundTransparency = 0,
					Font = FONT_NUMBER,
					TextColor3 = C.White,
					TextSize = 11,
					TextXAlignment = Enum.TextXAlignment.Center,
					Visible = false,
					ZIndex = 8,
					Parent = button,
				})
				UIUtil.Corner(item.Badge, UDim.new(1, 0))
				folderY += 50
			else
				text({ Position = UDim2.fromOffset(12, 0), Size = UDim2.new(0, 24, 1, 0), Text = def.Icon, TextSize = 16, ZIndex = 7, Parent = button })
				item.Label = text({ Position = UDim2.fromOffset(40, 0), Size = UDim2.new(1, -40 - 42, 1, 0), Text = names[id] or id, TextSize = 15, TextTruncate = Enum.TextTruncate.AtEnd, ZIndex = 7, Parent = button })
				local strong = id == "Inbox"
				item.Badge = text({
					Name = "Count",
					AnchorPoint = Vector2.new(1, 0.5),
					Position = UDim2.new(1, -8, 0.5, 0),
					Size = UDim2.fromOffset(32, 20),
					BackgroundColor3 = strong and C.Blue or C.White,
					BackgroundTransparency = strong and 0 or 1,
					Font = FONT_NUMBER,
					TextColor3 = strong and C.White or C.InkDim,
					TextSize = 12,
					TextXAlignment = strong and Enum.TextXAlignment.Center or Enum.TextXAlignment.Right,
					Visible = false,
					ZIndex = 7,
					Parent = button,
				})
				UIUtil.Corner(item.Badge, UDim.new(1, 0))
				folderY += 40
			end
			onClick(button, function()
				ctx.Sound.Play("Click", 1.05)
				selectFolder(id)
			end)
			on(button.MouseEnter, function()
				if S.Folder ~= id then
					button.BackgroundTransparency = 0.4
				end
			end)
			on(button.MouseLeave, function()
				button.BackgroundTransparency = S.Folder == id and 0 or 1
			end)
			ui.Folders[id] = item
		end

		if not phone then
			-- Contacts rapides : un clic = nouveau message à ce correspondant
			local quickY = folderY + 12
			local caption = text({ Position = UDim2.fromOffset(16, quickY), Size = UDim2.new(1, -32, 0, 16), Font = FONT_TITLE, Text = Locale.T("✏️ Write to…"), TextColor3 = C.InkDim, TextSize = 12, TextTruncate = Enum.TextTruncate.AtEnd, ZIndex = 6, Parent = side })
			quickY += 24
			local cell = 36
			local gap = math.floor((L.Side - 28 - cell * 4) / 3)
			for index, contact in ipairs(contacts) do
				local column = (index - 1) % 4
				local line = math.floor((index - 1) / 4)
				local quick = UIUtil.Create("TextButton", {
					Name = "Quick_" .. contact.Id,
					Position = UDim2.fromOffset(14 + column * (cell + gap), quickY + line * (cell + 8)),
					Size = UDim2.fromOffset(cell, cell),
					BackgroundTransparency = 1,
					BorderSizePixel = 0,
					AutoButtonColor = false,
					Text = "",
					ZIndex = 6,
					Parent = side,
				})
				local avatar = makeAvatar(quick, cell, UDim2.fromOffset(0, 0), 7)
				avatar.Set(contact.Avatar, tagColor(contact.Tag))
				UIUtil.AnimateButton(quick, 1.12, 0.9)
				-- Survol : la légende donne le nom du correspondant
				on(quick.MouseEnter, function()
					caption.Text = Locale.T("✏️ Write to %s", contact.Short)
					caption.TextColor3 = C.BlueDark
				end)
				on(quick.MouseLeave, function()
					caption.Text = Locale.T("✏️ Write to…")
					caption.TextColor3 = C.InkDim
				end)
				onClick(quick, function()
					ctx.Sound.Play("Click", 1.1)
					openCompose({ Kind = "New", Contact = contact })
				end)
			end
			-- Stockage (toujours presque plein)
			text({ AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 16, 1, -28), Size = UDim2.new(1, -32, 0, 16), Text = Locale.T("💾 Storage: 99% full"), TextColor3 = C.InkDim, TextSize = 12, TextTruncate = Enum.TextTruncate.AtEnd, ZIndex = 6, Parent = side })
			local bar = frame({ AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 16, 1, -14), Size = UDim2.new(1, -32, 0, 7), BackgroundColor3 = C.Line, ZIndex = 6, Parent = side })
			UIUtil.Corner(bar, UDim.new(1, 0))
			local fill = frame({ Size = UDim2.fromScale(0.99, 1), BackgroundColor3 = Color3.fromRGB(240, 120, 40), ZIndex = 7, Parent = bar })
			UIUtil.Corner(fill, UDim.new(1, 0))
		end

		-- Liste
		local listX = L.Side
		local listW = phone and (W - L.Side) or L.List
		ui.ListW = listW
		local listPane = frame({ Name = "ListPane", Position = UDim2.fromOffset(listX, T), Size = UDim2.fromOffset(listW, bodyH), ZIndex = 3, Parent = win })
		ui.ListPane = listPane
		-- En-tête : titre sur toute la largeur, puis compteurs + action ("Tout lu" / "Vider")
		ui.ListTitle = text({ Position = UDim2.fromOffset(P, 6), Size = UDim2.fromOffset(listW - P * 2, 24), Font = FONT_TITLE, TextSize = 19 + F, TextTruncate = Enum.TextTruncate.AtEnd, ZIndex = 5, Parent = listPane })
		ui.ListSub = text({ Position = UDim2.fromOffset(P, 33), Size = UDim2.fromOffset(listW - P - 128, 18), TextColor3 = C.InkDim, TextSize = 12 + F, TextTruncate = Enum.TextTruncate.AtEnd, ZIndex = 5, Parent = listPane })
		local listAction, listActionLabel = makeButton({ Name = "ListAction", AnchorPoint = Vector2.new(1, 0), Position = UDim2.fromOffset(listW - 10, 30), Size = UDim2.fromOffset(112, 25), Visible = false, ZIndex = 5, Parent = listPane }, "secondary", "", 12 + F, 8)
		ui.ListAction, ui.ListActionLabel = listAction, listActionLabel
		onClick(listAction, function()
			ctx.Sound.Play("Click", 1)
			if S.Folder == "Inbox" then
				for _, mail in ipairs(mails) do
					if mail.Folder == "Inbox" then
						mail.Read = true
					end
				end
				snack(Locale.T("✓ All caught up!"))
			elseif S.Folder == "Trash" then
				local removed = 0
				for index = #mails, 1, -1 do
					local mail = mails[index]
					if mail.Folder == "Trash" then
						removeMail(mail)
						removed += 1
					end
				end
				snack(Locale.T("🧹 Trash emptied (%d)", removed))
				if S.View == "Message" then
					setView("List")
				end
			end
			refresh()
		end)
		frame({ Position = UDim2.fromOffset(0, 58), Size = UDim2.new(1, 0, 0, 1), BackgroundColor3 = C.Line, ZIndex = 5, Parent = listPane })
		ui.List = UIUtil.Create("ScrollingFrame", {
			Name = "MailList",
			Position = UDim2.fromOffset(0, 59),
			Size = UDim2.new(1, 0, 1, -59),
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			CanvasSize = UDim2.new(),
			ScrollBarThickness = 5,
			ScrollBarImageColor3 = Color3.fromRGB(170, 176, 192),
			ScrollingDirection = Enum.ScrollingDirection.Y,
			ZIndex = 5,
			Parent = listPane,
		})
		ui.EmptyIcon = text({ AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 104), Size = UDim2.new(1, -40, 0, 48), Text = "🎉", TextSize = 40, TextXAlignment = Enum.TextXAlignment.Center, Visible = false, ZIndex = 6, Parent = listPane })
		ui.Empty = text({ AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 158), Size = UDim2.new(1, -48, 0, 60), Font = FONT_TITLE, TextColor3 = C.InkDim, TextSize = 14 + F, TextWrapped = true, TextXAlignment = Enum.TextXAlignment.Center, TextYAlignment = Enum.TextYAlignment.Top, Visible = false, ZIndex = 6, Parent = listPane })

		-- Zone de lecture (à droite sur PC, à la place de la liste sur téléphone)
		local readX = phone and L.Side or (L.Side + L.List)
		local readW = W - readX
		ui.ReadW = readW
		local readPane = frame({ Name = "ReadPane", Position = UDim2.fromOffset(readX, T), Size = UDim2.fromOffset(readW, bodyH), ZIndex = 3, Parent = win })
		ui.ReadPane = readPane
		if not phone then
			frame({ Position = UDim2.fromOffset(readX, T), Size = UDim2.new(0, 1, 1, -T), BackgroundColor3 = C.Line, ZIndex = 4, Parent = win })
			local placeholder = frame({ Name = "Placeholder", Size = UDim2.fromScale(1, 1), ZIndex = 4, Parent = readPane })
			local art = frame({ AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 120), Size = UDim2.fromOffset(96, 96), BackgroundColor3 = Color3.fromRGB(236, 241, 255), ZIndex = 5, Parent = placeholder })
			UIUtil.Corner(art, UDim.new(1, 0))
			UIUtil.Stroke(art, Color3.fromRGB(200, 214, 250), 2, 0)
			text({ Size = UDim2.fromScale(1, 1), Position = UDim2.fromOffset(0, 2), Text = "📬", TextSize = 46, TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 6, Parent = art })
			text({ AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 232), Size = UDim2.new(1, -60, 0, 24), Font = FONT_TITLE, Text = Locale.T("Pick a mail to read it"), TextSize = 18, TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 5, Parent = placeholder })
			text({ AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 262), Size = UDim2.new(1, -70, 0, 60), Text = Locale.T("💡 Flying mails give Dopamine if you open them before they fly away!"), TextColor3 = C.InkDim, TextSize = 13, TextWrapped = true, TextXAlignment = Enum.TextXAlignment.Center, TextYAlignment = Enum.TextYAlignment.Top, ZIndex = 5, Parent = placeholder })
			ui.Placeholder = placeholder
		end

		-- Vue "message"
		local msg: any = { Actions = {} }
		local messageView = frame({ Name = "MessageView", Size = UDim2.fromScale(1, 1), Visible = false, ZIndex = 4, Parent = readPane })
		msg.Frame = messageView
		msg.Subject = text({ Name = "Subject", Position = UDim2.fromOffset(P, 8), Size = UDim2.fromOffset(readW - P - 58, 48), Font = FONT_TITLE, TextSize = 18 + F, TextWrapped = true, TextTruncate = Enum.TextTruncate.AtEnd, ZIndex = 5, Parent = messageView })
		local star, starLabel = makeButton({ Name = "StarButton", AnchorPoint = Vector2.new(1, 0), Position = UDim2.fromOffset(readW - 10, 12), Size = UDim2.fromOffset(40, 40), ZIndex = 5, Parent = messageView }, "ghost", "☆", 26, 10)
		starLabel.TextColor3 = C.Gold
		msg.StarLabel = starLabel
		onClick(star, function()
			local mail = S.Selected
			if mail then
				toggleStar(mail)
			end
		end)
		local senderY = 60
		msg.Avatar = makeAvatar(messageView, 42, UDim2.fromOffset(P, senderY), 5)
		msg.Sender = text({ Position = UDim2.fromOffset(P + 52, senderY + 1), Size = UDim2.fromOffset(readW - P * 2 - 52, 20), Font = FONT_TITLE, TextSize = 15 + F, TextTruncate = Enum.TextTruncate.AtEnd, ZIndex = 5, Parent = messageView })
		msg.Meta = text({ Position = UDim2.fromOffset(P + 52, senderY + 23), Size = UDim2.fromOffset(readW - P * 2 - 52, 16), TextColor3 = C.InkDim, TextSize = 12 + F, TextTruncate = Enum.TextTruncate.AtEnd, ZIndex = 5, Parent = messageView })
		msg.Chip = makeChip(messageView, 20, 5)
		msg.Chip.Frame.AnchorPoint = Vector2.new(1, 0)
		msg.Chip.Frame.Position = UDim2.fromOffset(readW - P, senderY + 1)
		local dividerY = senderY + 50
		frame({ Position = UDim2.fromOffset(P, dividerY), Size = UDim2.new(1, -P * 2, 0, 1), BackgroundColor3 = C.Line, ZIndex = 5, Parent = messageView })
		local barH = 58
		local scroll = UIUtil.Create("ScrollingFrame", {
			Name = "MessageScroll",
			Position = UDim2.fromOffset(0, dividerY + 1),
			Size = UDim2.new(1, 0, 1, -(dividerY + 1 + barH)),
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			CanvasSize = UDim2.new(),
			AutomaticCanvasSize = Enum.AutomaticSize.Y,
			ScrollBarThickness = 5,
			ScrollBarImageColor3 = Color3.fromRGB(170, 176, 192),
			ScrollingDirection = Enum.ScrollingDirection.Y,
			ZIndex = 5,
			Parent = messageView,
		})
		msg.Scroll = scroll
		UIUtil.Create("UIPadding", { PaddingLeft = UDim.new(0, P), PaddingRight = UDim.new(0, P + 4), PaddingTop = UDim.new(0, 12), Parent = scroll })
		UIUtil.Create("UIListLayout", { Padding = UDim.new(0, 10), SortOrder = Enum.SortOrder.LayoutOrder, Parent = scroll })
		on(scroll:GetPropertyChangedSignal("CanvasPosition"), function()
			if scroll.CanvasPosition.Y > 2 then
				S.Interaction += 1
			end
		end)
		local function banner(name: string, order: number)
			local box = frame({ Name = name, Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundColor3 = C.Field, LayoutOrder = order, Visible = false, ZIndex = 6, Parent = scroll })
			UIUtil.Corner(box, 9)
			local stroke = UIUtil.Stroke(box, C.Line, 1.2, 0)
			UIUtil.Create("UIPadding", { PaddingLeft = UDim.new(0, 10), PaddingRight = UDim.new(0, 10), PaddingTop = UDim.new(0, 7), PaddingBottom = UDim.new(0, 7), Parent = box })
			local label = text({ Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, Font = FONT_TITLE, TextSize = 13 + F, TextWrapped = true, ZIndex = 7, Parent = box })
			return { Frame = box, Label = label, Stroke = stroke }
		end
		msg.Reward = banner("RewardBanner", 1)
		msg.Warning = banner("WarningBanner", 2)
		msg.Body = text({ Name = "Body", Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, TextSize = 15 + F, TextWrapped = true, TextYAlignment = Enum.TextYAlignment.Top, LineHeight = 1.1, LayoutOrder = 3, ZIndex = 6, Parent = scroll })
		msg.Signature = text({ Name = "Signature", Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, TextColor3 = C.InkDim, TextSize = 13 + F, TextWrapped = true, LayoutOrder = 4, ZIndex = 6, Parent = scroll })
		msg.Signature.FontFace = ITALIC
		local quote = frame({ Name = "Quote", Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundColor3 = Color3.fromRGB(245, 247, 251), LayoutOrder = 5, Visible = false, ZIndex = 6, Parent = scroll })
		UIUtil.Corner(quote, 8)
		UIUtil.Stroke(quote, Color3.fromRGB(214, 220, 234), 1, 0)
		UIUtil.Create("UIPadding", { PaddingLeft = UDim.new(0, 10), PaddingRight = UDim.new(0, 10), PaddingTop = UDim.new(0, 7), PaddingBottom = UDim.new(0, 7), Parent = quote })
		msg.QuoteLabel = text({ Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, TextColor3 = C.InkDim, TextSize = 12 + F, TextWrapped = true, ZIndex = 7, Parent = quote })
		msg.Quote = quote
		local attachment = UIUtil.Create("TextButton", {
			Name = "Attachment",
			Size = UDim2.fromOffset(math.min(270, readW - P * 2 - 8), 46),
			BackgroundColor3 = Color3.fromRGB(245, 247, 252),
			BorderSizePixel = 0,
			AutoButtonColor = false,
			Text = "",
			LayoutOrder = 6,
			Visible = false,
			ZIndex = 6,
			Parent = scroll,
		})
		UIUtil.Corner(attachment, 10)
		UIUtil.Stroke(attachment, C.Line, 1.2, 0)
		msg.FileIcon = frame({ Position = UDim2.fromOffset(7, 7), Size = UDim2.fromOffset(32, 32), BackgroundColor3 = C.Grey, ZIndex = 7, Parent = attachment })
		UIUtil.Corner(msg.FileIcon, 7)
		msg.FileEmoji = text({ Size = UDim2.fromScale(1, 1), TextSize = 17, TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 8, Parent = msg.FileIcon })
		msg.FileName = text({ Position = UDim2.fromOffset(48, 6), Size = UDim2.new(1, -84, 0, 18), Font = FONT_TITLE, TextSize = 13 + F, TextTruncate = Enum.TextTruncate.AtEnd, ZIndex = 7, Parent = attachment })
		msg.FileSize = text({ Position = UDim2.fromOffset(48, 25), Size = UDim2.new(1, -84, 0, 15), TextColor3 = C.InkDim, TextSize = 11 + F, ZIndex = 7, Parent = attachment })
		msg.FileAction = text({ AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -10, 0.5, 0), Size = UDim2.fromOffset(24, 24), Text = "⬇️", TextSize = 17, TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 7, Parent = attachment })
		UIUtil.AnimateButton(attachment, 1.03, 0.96)
		onClick(attachment, function()
			local mail = S.Selected
			local file = mail and mail.Email.Attachment
			if not file then
				return
			end
			ctx.Sound.Play("Click", 1)
			snack(file.Virus and pickLine(VIRUS_JOKES) or pickLine(ATTACHMENT_JOKES))
			msg.FileAction.Text = file.Virus and "🛡️" or "✅"
		end)
		msg.Attachment = attachment
		-- Marge du bas (le défilement automatique ne compte pas toujours le UIPadding)
		frame({ Name = "Spacer", Size = UDim2.new(1, 0, 0, 16), LayoutOrder = 9, Parent = scroll })

		local actionBar = frame({ Name = "ActionBar", AnchorPoint = Vector2.new(0, 1), Position = UDim2.fromScale(0, 1), Size = UDim2.new(1, 0, 0, barH), ZIndex = 5, Parent = messageView })
		frame({ Size = UDim2.new(1, 0, 0, 1), BackgroundColor3 = C.Line, ZIndex = 6, Parent = actionBar })
		local actionSpecs = {
			Reply = { Locale.T("↩️ Reply"), "primary" },
			Forward = { Locale.T("➡️ Forward"), "secondary" },
			Spam = { Locale.T("🚫 Spam"), "secondary" },
			NotSpam = { Locale.T("✅ Not spam"), "secondary" },
			Delete = { Locale.T("🗑️ Delete"), "danger" },
			Restore = { Locale.T("♻️ Restore"), "secondary" },
			Forever = { Locale.T("❌ Delete forever"), "danger" },
		}
		for _, id in ipairs(ACTION_ORDER) do
			local spec = actionSpecs[id]
			local button = makeButton({ Name = "Action" .. id, Position = UDim2.fromOffset(P, 10), Size = UDim2.fromOffset(100, 38), Visible = false, ZIndex = 6, Parent = actionBar }, spec[2], spec[1], 14 + F, 10)
			onClick(button, function()
				runAction(id)
			end)
			msg.Actions[id] = button
		end
		ui.Msg = msg

		-- Vue "rédaction"
		local cmp: any = { Chips = {} }
		local composeView = frame({ Name = "ComposeView", Size = UDim2.fromScale(1, 1), Visible = false, ZIndex = 4, Parent = readPane })
		cmp.Frame = composeView
		cmp.Title = text({ Position = UDim2.fromOffset(P, 10), Size = UDim2.new(1, -P * 2, 0, 24), Font = FONT_TITLE, TextSize = 18 + F, TextTruncate = Enum.TextTruncate.AtEnd, Visible = not phone, ZIndex = 5, Parent = composeView })
		local toY = phone and 8 or 42
		text({ Position = UDim2.fromOffset(P, toY), Size = UDim2.new(1, -P * 2, 0, 16), Font = FONT_TITLE, Text = Locale.T("To:"), TextColor3 = C.InkDim, TextSize = 12 + F, ZIndex = 5, Parent = composeView })
		local gridY = toY + 20
		local chipH = phone and 36 or 34
		local columns = 4
		local chipW = math.floor((readW - P * 2 - (columns - 1) * 6) / columns)
		cmp.GridTop = gridY
		for index, contact in ipairs(contacts) do
			local column = (index - 1) % columns
			local line = math.floor((index - 1) / columns)
			local chipButton = UIUtil.Create("TextButton", {
				Name = "Contact_" .. contact.Id,
				Position = UDim2.fromOffset(P + column * (chipW + 6), gridY + line * (chipH + 6)),
				Size = UDim2.fromOffset(chipW, chipH),
				BackgroundColor3 = C.White,
				BorderSizePixel = 0,
				AutoButtonColor = false,
				Text = "",
				ZIndex = 5,
				Parent = composeView,
			})
			UIUtil.Corner(chipButton, UDim.new(1, 0))
			local stroke = UIUtil.Stroke(chipButton, C.Line, 1.3, 0)
			local avatar = makeAvatar(chipButton, chipH - 8, UDim2.fromOffset(4, 4), 6)
			avatar.Set(contact.Avatar, tagColor(contact.Tag))
			local name = UIUtil.Create("TextLabel", {
				Position = UDim2.fromOffset(chipH + 1, 4),
				Size = UDim2.new(1, -chipH - 9, 1, -8),
				BackgroundTransparency = 1,
				Font = FONT_TITLE,
				Text = contact.Short,
				TextColor3 = C.Ink,
				TextScaled = true,
				TextXAlignment = Enum.TextXAlignment.Left,
				ZIndex = 6,
				Parent = chipButton,
			})
			UIUtil.Create("UITextSizeConstraint", { MaxTextSize = 14 + F, MinTextSize = 9, Parent = name })
			UIUtil.AnimateButton(chipButton, 1.04, 0.95)
			onClick(chipButton, function()
				local draft = S.Draft
				if not draft or draft.Fixed or S.Sending then
					return
				end
				ctx.Sound.Play("Click", 1.1)
				draft.Contact = contact
				renderChips()
				setStatus(nil)
			end)
			cmp.Chips[contact.Id] = { Button = chipButton, Stroke = stroke, Name = name }
		end
		cmp.GridBottom = gridY + 2 * chipH + 6
		-- Destinataire fixe (réponse)
		cmp.Fixed = frame({ Name = "ReplyTo", Position = UDim2.fromOffset(P, gridY), Size = UDim2.new(1, -P * 2, 0, 40), BackgroundColor3 = C.Field, Visible = false, ZIndex = 5, Parent = composeView })
		UIUtil.Corner(cmp.Fixed, UDim.new(1, 0))
		UIUtil.Stroke(cmp.Fixed, C.Line, 1.2, 0)
		cmp.FixedAvatar = makeAvatar(cmp.Fixed, 32, UDim2.fromOffset(4, 4), 6)
		cmp.FixedName = text({ Position = UDim2.fromOffset(44, 0), Size = UDim2.new(1, -56, 1, 0), Font = FONT_TITLE, TextSize = 14 + F, TextTruncate = Enum.TextTruncate.AtEnd, ZIndex = 6, Parent = cmp.Fixed })

		local function field(name: string, multi: boolean, placeholder: string): (Frame, TextBox)
			-- (ClipsDescendants : un long texte ne déborde jamais du champ)
			local holder = frame({ Name = name .. "Field", Position = UDim2.fromOffset(P, 0), Size = UDim2.new(1, -P * 2, 0, 36), BackgroundColor3 = C.Field, ClipsDescendants = true, ZIndex = 5, Parent = composeView })
			UIUtil.Corner(holder, 9)
			local stroke = UIUtil.Stroke(holder, Color3.fromRGB(204, 210, 226), 1.3, 0)
			local box = UIUtil.Create("TextBox", {
				Name = name,
				Position = UDim2.fromOffset(10, multi and 8 or 0),
				Size = UDim2.new(1, -20, 1, multi and -26 or 0),
				BackgroundTransparency = 1,
				BorderSizePixel = 0,
				ClearTextOnFocus = false,
				MultiLine = multi,
				Font = FONT_BODY,
				PlaceholderText = placeholder,
				PlaceholderColor3 = Color3.fromRGB(150, 156, 172),
				Text = "",
				TextColor3 = C.Ink,
				TextSize = 15 + F,
				TextWrapped = multi,
				TextXAlignment = Enum.TextXAlignment.Left,
				TextYAlignment = multi and Enum.TextYAlignment.Top or Enum.TextYAlignment.Center,
				ZIndex = 6,
				Parent = holder,
			})
			on(box.Focused, function()
				S.Interaction += 1
				stroke.Color = C.Blue
				stroke.Thickness = 2
			end)
			on(box.FocusLost, function()
				stroke.Color = Color3.fromRGB(204, 210, 226)
				stroke.Thickness = 1.3
			end)
			return holder, box
		end
		cmp.SubjectField, cmp.Subject = field("SubjectBox", false, Locale.T("Subject"))
		cmp.BodyField, cmp.Body = field("BodyBox", true, Locale.T("Write your message…"))
		cmp.Counter = text({ AnchorPoint = Vector2.new(1, 1), Position = UDim2.new(1, -10, 1, -4), Size = UDim2.fromOffset(70, 15), TextColor3 = C.InkDim, TextSize = 11 + F, TextXAlignment = Enum.TextXAlignment.Right, ZIndex = 7, Parent = cmp.BodyField })
		on(cmp.Subject:GetPropertyChangedSignal("Text"), function()
			limitBox(cmp.Subject, SUBJECT_MAX)
			S.Interaction += 1
		end)
		on(cmp.Body:GetPropertyChangedSignal("Text"), function()
			limitBox(cmp.Body, BODY_MAX)
			updateCounterLabel()
			S.Interaction += 1
		end)
		on(cmp.Subject.FocusLost, function(enterPressed)
			if enterPressed and cmp.Body.TextEditable then
				cmp.Body:CaptureFocus()
			end
		end)
		cmp.Quote = frame({ Name = "ForwardQuote", Position = UDim2.fromOffset(P, 0), Size = UDim2.new(1, -P * 2, 0, 50), BackgroundColor3 = Color3.fromRGB(245, 247, 251), ClipsDescendants = true, Visible = false, ZIndex = 5, Parent = composeView })
		UIUtil.Corner(cmp.Quote, 8)
		UIUtil.Stroke(cmp.Quote, C.Line, 1, 0)
		cmp.QuoteLabel = text({ Position = UDim2.fromOffset(10, 5), Size = UDim2.new(1, -20, 1, -10), TextColor3 = C.InkDim, TextSize = 11 + F, TextWrapped = true, TextTruncate = Enum.TextTruncate.AtEnd, TextYAlignment = Enum.TextYAlignment.Top, ZIndex = 6, Parent = cmp.Quote })
		cmp.Status = text({ Name = "ComposeStatus", Position = UDim2.fromOffset(P, 0), Size = UDim2.new(1, -P * 2, 0, 18), TextColor3 = C.InkDim, TextSize = 12 + F, TextTruncate = Enum.TextTruncate.AtEnd, ZIndex = 5, Parent = composeView })
		local sendW = phone and 210 or 176
		cmp.Send, cmp.SendLabel = makeButton({ Name = "SendButton", AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, P, 1, -12), Size = UDim2.fromOffset(sendW, 42), ZIndex = 5, Parent = composeView }, "primary", "✈️ " .. Locale.T("Send"), 16 + F, 12)
		cmp.Cancel = makeButton({ Name = "CancelButton", AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, P + sendW + 10, 1, -12), Size = UDim2.fromOffset(phone and 150 or 124, 42), ZIndex = 5, Parent = composeView }, "secondary", Locale.T("Cancel"), 15 + F, 12)
		onClick(cmp.Send, function()
			sendDraft()
		end)
		onClick(cmp.Cancel, function()
			ctx.Sound.Play("Click", 0.9)
			cancelCompose()
		end)
		ui.Cmp = cmp

		-- Petit message en bas ("snack"), au-dessus de tout
		local snackButton = UIUtil.Create("TextButton", {
			Name = "MailSnack",
			AnchorPoint = Vector2.new(0.5, 1),
			-- Centré sur la zone de lecture (PC) / sur la fenêtre (téléphone)
			Position = UDim2.new(0, phone and math.floor(W / 2) or (readX + math.floor(readW / 2)), 1, -72),
			Size = UDim2.fromOffset(0, 38),
			AutomaticSize = Enum.AutomaticSize.X,
			BackgroundColor3 = Color3.fromRGB(30, 34, 52),
			BorderSizePixel = 0,
			AutoButtonColor = false,
			Font = FONT_TITLE,
			Text = "",
			TextColor3 = C.White,
			TextSize = 14 + F,
			Visible = false,
			ZIndex = 40,
			Parent = win,
		})
		UIUtil.Corner(snackButton, UDim.new(1, 0))
		UIUtil.Create("UIPadding", { PaddingLeft = UDim.new(0, 18), PaddingRight = UDim.new(0, 18), Parent = snackButton })
		UIUtil.Stroke(snackButton, C.White, 1.5, 0.7)
		ui.SnackScale = UIUtil.Create("UIScale", { Parent = snackButton })
		ui.Snack = snackButton
		onClick(snackButton, function()
			local action = S.SnackAction
			hideSnack()
			if action then
				action()
			end
		end)
		return ui
	end

	-- Taille / place de la fenêtre dans la toile (sous le bandeau d'actu)
	local function fitWindow()
		local ui = UI
		if not ui then
			return
		end
		local interface = ctx.Interface
		local canvas = (interface and interface.CanvasSize) or Vector2.new(1280, 720)
		local top = TICKER_H + 6
		local availableW = canvas.X - 24
		local availableH = canvas.Y - top - 10
		local scale = math.min(availableW / ui.L.W, availableH / ui.L.H)
		if ui.Mode == "Wide" then
			scale = math.min(scale, 1)
		end
		ui.Fit = math.max(0.4, scale)
		ui.Root.Position = UDim2.new(0.5, 0, 0, math.floor(top + availableH / 2))
		if S.Open then
			ui.Scale.Scale = ui.Fit
		end
	end

	local function destroyWindow()
		local ui = UI
		if not ui then
			return
		end
		if S.Draft then
			S.Draft.SubjectText = ui.Cmp.Subject.Text
			S.Draft.BodyText = ui.Cmp.Body.Text
		end
		UI = nil
		ui.Root:Destroy()
		ui.Dimmer:Destroy()
	end

	setView = function(view: string)
		S.View = view
		local ui = UI
		if not ui then
			return
		end
		ui.Msg.Frame.Visible = view == "Message"
		ui.Cmp.Frame.Visible = view == "Compose"
		if ui.Mode == "Phone" then
			ui.ListPane.Visible = view == "List"
			ui.ReadPane.Visible = view ~= "List"
			ui.Back.Visible = view ~= "List"
			local left = view ~= "List" and 60 or 12
			ui.Logo.Position = UDim2.new(0, left, 0.5, 0)
			ui.Title.Position = UDim2.fromOffset(left + 42, ui.Title.Position.Y.Offset)
			ui.Subtitle.Position = UDim2.fromOffset(left + 42, ui.Subtitle.Position.Y.Offset)
			if view ~= "Compose" then
				ui.Title.Text = "Dopamail"
			end
		else
			ui.Placeholder.Visible = view == "List"
		end
		if view ~= "Compose" then
			for _, box in ipairs({ ui.Cmp.Subject, ui.Cmp.Body }) do
				if box:IsFocused() then
					box:ReleaseFocus()
				end
			end
		end
	end

	renderAll = function()
		local ui = UI
		if not ui then
			return
		end
		if S.Selected and not table.find(mails, S.Selected) then
			S.Selected = nil
		end
		if S.View == "Message" and not S.Selected then
			setView("List")
		end
		renderFolders()
		renderList()
		if S.View == "Message" and S.Selected then
			updateMessageState(S.Selected)
		end
	end

	refresh = function(bump: boolean?)
		refreshCounter(bump)
		if UI and S.Open then
			renderAll()
		end
	end

	openWindow = function()
		if not ctx.IsAlive() then
			return
		end
		local mode = currentMode()
		if UI and UI.Mode ~= mode then
			destroyWindow()
		end
		if not UI then
			UI = buildWindow(mode)
			local draft = S.Draft
			if draft then
				UI.Cmp.Subject.Text = draft.SubjectText or ""
				UI.Cmp.Body.Text = draft.BodyText or ""
			end
		end
		local ui = UI
		fitWindow()
		if not S.Open then
			S.Open = true
			S.CloseToken += 1
			ui.Root.Visible = true
			ui.Dimmer.Visible = true
			ui.Dimmer.BackgroundTransparency = 1
			UIUtil.Tween(ui.Dimmer, 0.25, { BackgroundTransparency = 0.55 })
			ui.Scale.Scale = ui.Fit * 0.9
			UIUtil.Tween(ui.Scale, 0.32, { Scale = ui.Fit }, Enum.EasingStyle.Back)
		end
		setView(S.View)
		if S.View == "Compose" then
			renderCompose()
		end
		renderAll()
	end

	closeWindow = function()
		local ui = UI
		if not S.Open or not ui then
			return
		end
		S.Open = false
		S.CloseToken += 1
		local token = S.CloseToken
		hideSnack()
		for _, box in ipairs({ ui.Cmp.Subject, ui.Cmp.Body, ui.SearchBox }) do
			if box and box:IsFocused() then
				box:ReleaseFocus()
			end
		end
		UIUtil.Tween(ui.Dimmer, 0.18, { BackgroundTransparency = 1 })
		UIUtil.Tween(ui.Scale, 0.16, { Scale = ui.Fit * 0.92 }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		task.delay(0.18, function()
			if ctx.IsAlive() and S.CloseToken == token and UI == ui then
				ui.Root.Visible = false
				ui.Dimmer.Visible = false
			end
		end)
	end

	-- Mail ouvert depuis sa notification : fermeture auto si le joueur ne touche à rien
	local function scheduleQuickClose()
		local interaction = S.Interaction
		local token = S.CloseToken
		task.delay(QUICK_CLOSE, function()
			if ctx.IsAlive() and S.Open and S.CloseToken == token and S.Interaction == interaction then
				closeWindow()
			end
		end)
	end

	selectFolder = function(id: string)
		S.Folder = id
		S.Selected = nil
		if UI then
			UI.List.CanvasPosition = Vector2.zero
			if S.View ~= "Compose" or UI.Mode == "Phone" then
				setView("List")
			end
		end
		refresh()
	end

	goBack = function()
		if S.View == "Compose" then
			if S.Selected and table.find(mails, S.Selected) then
				renderMessage(S.Selected)
				setView("Message")
			else
				setView("List")
			end
		else
			S.Selected = nil
			setView("List")
		end
		refresh()
	end

	------------------------------------------------------------------
	-- Récompense (mails du serveur)
	------------------------------------------------------------------
	local function claim(mail, source: string?)
		mail.State = "Claimed"
		local id = mail.SpawnId
		if source ~= "Card" then
			-- Ouvert depuis la liste : le "+X" apparaît au-dessus de la fenêtre
			positions[id] = UDim2.new(0.5, 0, 0.5, -60)
		end
		lastPosition = positions[id] or lastPosition
		ctx.ClaimSpawn(id)
		task.delay(CLAIM_WAIT, function()
			if ctx.IsAlive() and mail.State == "Claimed" and not mail.Reward then
				mail.State = "Missed"
				refresh()
			end
		end)
		task.delay(8, function()
			positions[id] = nil
		end)
	end

	expireMail = function(mail)
		if mail.State ~= "Live" then
			return
		end
		mail.State = "Expired"
		if mail.Envelope then
			removeEnvelope(mail.Envelope, false)
		end
		refresh(true)
	end

	openMail = function(mail, source: string?)
		if not ctx.IsAlive() or not table.find(mails, mail) then
			return
		end
		if mail.State == "Live" then
			if now() < mail.ExpiresAt then
				claim(mail, source)
			else
				expireMail(mail)
			end
		end
		mail.Read = true
		if mail.Envelope then
			removeEnvelope(mail.Envelope, true)
		end
		if S.SnackTarget == mail then
			hideSnack()
		end
		if not inFolder(mail, S.Folder) then
			S.Folder = mail.Folder
		end
		S.Selected = mail
		local wasOpen = S.Open
		S.View = "Message"
		openWindow()
		renderMessage(mail)
		setView("Message")
		refresh()
		if source == "Card" and not wasOpen then
			scheduleQuickClose()
		end
	end

	------------------------------------------------------------------
	-- Rédaction : ouvrir, envoyer (filtre du serveur), annuler
	------------------------------------------------------------------
	openCompose = function(options)
		if S.Sending then
			return
		end
		S.Draft = {
			Kind = options.Kind or "New",
			Contact = options.Contact,
			Fixed = options.Kind == "Reply",
			Quote = options.Quote,
		}
		S.View = "Compose"
		openWindow()
		local ui = UI
		ui.Cmp.Subject.Text = options.Subject or ""
		ui.Cmp.Body.Text = ""
		renderCompose()
		setView("Compose")
	end

	composeClicked = function()
		if S.Draft then
			-- Brouillon en cours : on y revient
			S.View = "Compose"
			renderCompose()
			setView("Compose")
		else
			openCompose({ Kind = "New" })
		end
	end

	cancelCompose = function()
		S.Sending = nil
		S.Draft = nil
		local ui = UI
		if ui then
			ui.Cmp.Subject.Text = ""
			ui.Cmp.Body.Text = ""
			setSending(false)
		end
		goBack()
	end

	-- Objet et texte : UN seul appel au filtre, séparés par SEPARATOR
	local function splitFiltered(value: string, hasSubject: boolean, hasBody: boolean): (string, string)
		if hasSubject and hasBody then
			local first, last = string.find(value, SEPARATOR, 1, true)
			if first and last then
				return trim(string.sub(value, 1, first - 1)), trim(string.sub(value, last + 1))
			end
			return "", trim(value)
		elseif hasSubject then
			return trim(value), ""
		end
		return "", trim(value)
	end

	-- Réponse du correspondant, quelques secondes après l'envoi
	local function scheduleReply(contact, sent, topics: { any }, forwarded: boolean)
		task.delay(random:NextNumber(REPLY_DELAY_MIN, REPLY_DELAY_MAX), function()
			if not ctx.IsAlive() then
				return
			end
			local texts = (contact.Id and Locale.Pick(CONTACT_TEXT)[contact.Id]) or Locale.Pick(TAG_VOICES)[contact.Tag] or Locale.Pick(TAG_VOICES).PERSO
			local body = composeReply(texts, topics, forwarded, contact.Caps == true)
			local sentEmail = sent.Email
			local baseSubject = sentEmail.Subject ~= "" and sentEmail.Subject or Locale.T("(no subject)")
			local email = {
				Tag = makeTag(contact.Tag),
				Avatar = contact.Avatar,
				Sender = contact.Name,
				Address = contact.Address,
				Subject = prefixed("Re: ", baseSubject),
				Body = body,
				Signature = contact.Signature or contact.Name,
				Attachment = nil,
				Suspicious = contact.Tag == "ARNAQUE" or contact.Tag == "SPAM",
			}
			local quoted = sentEmail.Body ~= "" and sentEmail.Body or sentEmail.Subject
			local mail = {
				Kind = "Reply",
				Email = email,
				Contact = contact,
				Folder = "Inbox",
				Read = false,
				Starred = false,
				State = "Local",
				Time = now(),
				Quote = quoted ~= "" and { Label = Locale.T("You wrote:"), Text = quoted } or nil,
			}
			addMail(mail)
			ctx.Sound.Play("Mail", 1 + random:NextNumber() * 0.15)
			if S.Open then
				snack(Locale.T("📩 New mail from %s", contact.Short), function()
					openMail(mail, "List")
				end, mail)
			else
				spawnCard(mail, nil)
			end
			refresh(true)
		end)
	end

	local function deliverSent(draft, contact, subject: string, body: string, topics: { any })
		local email = {
			Tag = makeTag(contact.Tag),
			Avatar = contact.Avatar,
			Sender = me.Name,
			Address = me.Address,
			Subject = subject,
			Body = body,
			Signature = nil,
			Attachment = nil,
			Suspicious = false,
		}
		local mail = {
			Kind = "Sent",
			Email = email,
			To = contact,
			Folder = "Sent",
			Read = true,
			Starred = false,
			State = "Local",
			Time = now(),
			Quote = draft.Quote,
		}
		addMail(mail)
		S.Draft = nil
		local ui = UI
		if ui then
			ui.Cmp.Subject.Text = ""
			ui.Cmp.Body.Text = ""
		end
		-- On montre ce qui est vraiment parti (texte filtré), dans "Envoyés"
		S.Folder = "Sent"
		S.Selected = mail
		if ui and S.Open then
			S.View = "Message"
			renderMessage(mail)
			setView("Message")
		else
			S.View = "List"
		end
		refresh()
		snack(Locale.T("✈️ Sent to %s!", contact.Short))
		scheduleReply(contact, mail, topics, draft.Kind == "Forward")
	end

	sendDraft = function()
		local ui = UI
		local draft = S.Draft
		if not ui or not draft or S.Sending then
			return
		end
		local cmp = ui.Cmp
		local contact = draft.Contact
		if not contact then
			setStatus(Locale.T("Pick a recipient first 👆"), C.Red)
			return
		end
		local subject = trim(cmp.Subject.Text)
		local body = trim(cmp.Body.Text)
		if subject == "" and body == "" then
			setStatus(Locale.T("Write something first ✍️"), C.Red)
			return
		end
		-- Le séparateur ne doit pas apparaître dans l'objet
		local cleanSubject = string.gsub(subject, "—", "-")
		local hasSubject, hasBody = cleanSubject ~= "", body ~= ""
		local payload
		if hasSubject and hasBody then
			payload = cleanSubject .. SEPARATOR .. body
		elseif hasSubject then
			payload = cleanSubject
		else
			payload = body
		end
		local token = {}
		S.Sending = token
		setSending(true)
		ctx.Sound.Play("Mail", 1.3)
		task.delay(SEND_TIMEOUT, function()
			if ctx.IsAlive() and S.Sending == token then
				S.Sending = nil
				setSending(false)
				setStatus("⚠️ " .. Locale.T("Message could not be sent, try again"), C.Red)
			end
		end)
		-- Le filtre du serveur (peut attendre) : jamais dans le gestionnaire du clic
		task.spawn(function()
			local okCall, success, result = pcall(function()
				return ctx.Net.Function("FilterText"):InvokeServer("Mail", payload)
			end)
			if not ctx.IsAlive() or S.Sending ~= token then
				return
			end
			S.Sending = nil
			setSending(false)
			if okCall and success == true and type(result) == "table" and type(result.Text) == "string" then
				local filteredSubject, filteredBody = splitFiltered(result.Text, hasSubject, hasBody)
				local topics = type(result.Topics) == "table" and result.Topics or {}
				deliverSent(draft, contact, filteredSubject, filteredBody, topics)
			else
				-- Jamais le texte brut : seulement le message d'erreur
				local message = (okCall and type(result) == "string" and result ~= "") and result or Locale.T("Message could not be sent, try again")
				setStatus("⚠️ " .. message, C.Red)
			end
		end)
	end

	runAction = function(id: string)
		local mail = S.Selected
		if not mail then
			return
		end
		local e = mail.Email
		if id == "Reply" then
			ctx.Sound.Play("Click", 1)
			openCompose({ Kind = "Reply", Contact = contactOf(mail), Subject = prefixed("Re: ", e.Subject) })
			return
		elseif id == "Forward" then
			ctx.Sound.Play("Click", 1)
			local from = mail.Kind == "Sent" and me.Name or e.Sender
			openCompose({
				Kind = "Forward",
				Subject = prefixed("Fwd: ", e.Subject),
				Quote = {
					Label = Locale.T("---------- Forwarded message ----------"),
					Text = Locale.T("From: %s", from) .. "\n" .. Locale.T("Subject: %s", e.Subject) .. "\n" .. e.Body,
					-- Aperçu court dans la rédaction (le mail envoyé montre tout)
					Short = Locale.T("From: %s", from) .. " · " .. Locale.T("Subject: %s", e.Subject),
				},
			})
			return
		end
		ctx.Sound.Play("Click", 0.8)
		if id == "Spam" then
			mail.PrevFolder = mail.Folder
			mail.Folder = "Spam"
			snack(pickLine(SPAMMED))
		elseif id == "NotSpam" then
			mail.Folder = "Inbox"
			snack(Locale.T("✅ Back in your inbox"))
		elseif id == "Delete" then
			mail.PrevFolder = mail.Folder
			mail.Folder = "Trash"
			snack(Locale.T("🗑️ Moved to the trash"))
		elseif id == "Restore" then
			local target = mail.PrevFolder
			if target ~= "Inbox" and target ~= "Sent" and target ~= "Spam" then
				target = mail.Kind == "Sent" and "Sent" or "Inbox"
			end
			mail.Folder = target
			snack(Locale.T("♻️ Restored to %s", folderName(target)))
		elseif id == "Forever" then
			removeMail(mail)
			snack(Locale.T("💨 Deleted forever"))
		end
		S.Selected = nil
		setView("List")
		refresh()
	end

	------------------------------------------------------------------
	-- Notifications de mail (cartes volantes)
	------------------------------------------------------------------
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

	removeEnvelope = function(envelope, opened: boolean)
		if envelope.Done then
			return
		end
		envelope.Done = true
		envelopes[envelope.Id] = nil
		envelopeCount -= 1
		if envelope.Mail.Envelope == envelope then
			envelope.Mail.Envelope = nil
		end
		local root = envelope.Root
		if opened then
			-- La lettre sort de l'enveloppe, puis la carte s'efface
			UIUtil.Tween(envelope.Letter, 0.2, { Position = UDim2.new(0.5, 0, 0, -30) }, Enum.EasingStyle.Back)
			task.delay(0.12, function()
				if root.Parent then
					UIUtil.Tween(envelope.Scale, 0.25, { Scale = 1.12 }, Enum.EasingStyle.Quad)
					fadeOut(root, 0.22)
				end
			end)
		else
			-- Ignorée : elle file vers le compteur (le mail reste dans la Réception)
			UIUtil.Tween(root, 0.8, {
				Position = UDim2.new(1, -(tickerRight + 50), 0, 14),
				Rotation = -25,
			}, Enum.EasingStyle.Back, Enum.EasingDirection.In)
			UIUtil.Tween(envelope.Scale, 0.8, { Scale = 0.15 }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
			fadeOut(root, 0.8)
		end
		Debris:AddItem(root, opened and 0.45 or 0.85)
	end

	spawnCard = function(mail, info)
		if not ctx.IsAlive() or mail.Envelope or envelopeCount >= MAX_ENVELOPES then
			return
		end
		local email = mail.Email
		local x = math.clamp(tonumber(info and info.X) or random:NextNumber(0.2, 0.7), 0.1, 0.9)
		local y = math.clamp(tonumber(info and info.Y) or random:NextNumber(0.25, 0.75), 0.12, 0.88)
		local rewarded = mail.Kind == "Spawn"
		local lifetime = rewarded and math.max(1, mail.ExpiresAt - now()) or LOCAL_CARD_LIFE
		local target = UDim2.fromScale(x, y)
		local color = email.Tag.Color

		local root = UIUtil.Create("TextButton", {
			Name = "Envelope",
			Size = UDim2.fromOffset(CARD_W, CARD_H),
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(1.15, math.max(0.05, y - 0.2)),
			Rotation = 20,
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			AutoButtonColor = false,
			Text = "",
			ZIndex = 30,
			Parent = container,
		})
		local scale = UIUtil.Create("UIScale", { Scale = 0.6, Parent = root })

		-- Lettre (derrière la carte, elle en sort à l'ouverture)
		local letter = frame({ Name = "Letter", AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 8), Size = UDim2.new(1, -34, 0, 56), BackgroundColor3 = C.Paper, ZIndex = 30, Parent = root })
		UIUtil.Corner(letter, 4)
		UIUtil.Stroke(letter, Color3.fromRGB(210, 214, 226), 1, 0)
		for i = 1, 3 do
			frame({ Position = UDim2.fromOffset(12, 8 + i * 7), Size = UDim2.new(0.7 - i * 0.12, 0, 0, 2), BackgroundColor3 = Color3.fromRGB(200, 204, 216), ZIndex = 30, Parent = letter })
		end

		-- Ombre douce
		local shadow = frame({ Size = UDim2.new(1, 4, 1, 4), Position = UDim2.fromOffset(-2, 5), BackgroundColor3 = Color3.new(0, 0, 0), BackgroundTransparency = 0.8, ZIndex = 29, Parent = root })
		UIUtil.Corner(shadow, 16)

		-- Carte (notification)
		local body = frame({ Name = "Body", Size = UDim2.fromScale(1, 1), BackgroundColor3 = C.White, ZIndex = 31, Parent = root })
		UIUtil.Corner(body, 14)
		UIUtil.Gradient(body, ColorSequence.new(C.White, Color3.fromRGB(238, 241, 248)), 90)
		local bodyStroke = UIUtil.Stroke(body, C.Border, 1.5, 0.15)
		-- Liseré coloré à gauche (couleur de l'étiquette)
		local accent = frame({ Size = UDim2.new(0, 4, 1, -24), Position = UDim2.fromOffset(0, 12), BackgroundColor3 = color, ZIndex = 32, Parent = body })
		UIUtil.Corner(accent, 2)

		-- En-tête "DOPAMAIL · maintenant" (comme une notification de téléphone)
		local appIcon = frame({ Position = UDim2.fromOffset(12, 7), Size = UDim2.fromOffset(14, 14), BackgroundColor3 = C.Blue, ZIndex = 33, Parent = body })
		UIUtil.Corner(appIcon, 4)
		UIUtil.Gradient(appIcon, ColorSequence.new(C.White, Color3.fromRGB(190, 205, 235)), 90)
		text({ Size = UDim2.fromScale(1, 1), Text = "✉", Font = FONT_TITLE, TextColor3 = C.White, TextSize = 10, TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 34, Parent = appIcon })
		text({ Position = UDim2.fromOffset(31, 6), Size = UDim2.fromOffset(120, 16), Font = FONT_TITLE, Text = "DOPAMAIL · " .. Locale.T("now"), TextColor3 = C.InkDim, TextSize = 10, ZIndex = 33, Parent = body })
		local chip = makeChip(body, 15, 34)
		chip.Frame.AnchorPoint = Vector2.new(1, 0)
		chip.Frame.Position = UDim2.new(1, -10, 0, 6)
		chip.Set(email.Tag.Text, color)

		-- Avatar + pastille "non lu"
		local avatar = makeAvatar(body, 38, UDim2.fromOffset(12, 28), 33)
		avatar.Set(email.Avatar, color)
		local dot = frame({ Name = "UnreadDot", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromOffset(15, 31), Size = UDim2.fromOffset(12, 12), BackgroundColor3 = C.Blue, ZIndex = 36, Parent = body })
		UIUtil.Corner(dot, UDim.new(1, 0))
		UIUtil.Stroke(dot, C.White, 2, 0)

		-- Textes (+ trombone s'il y a une pièce jointe)
		text({ Position = UDim2.fromOffset(58, 26), Size = UDim2.new(1, -90, 0, 16), Font = FONT_TITLE, Text = email.Sender, TextSize = 14, TextTruncate = Enum.TextTruncate.AtEnd, ZIndex = 33, Parent = body })
		if email.Attachment then
			text({ AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -10, 0, 26), Size = UDim2.fromOffset(18, 16), Text = "📎", TextSize = 13, TextXAlignment = Enum.TextXAlignment.Right, ZIndex = 33, Parent = body })
		end
		text({ Position = UDim2.fromOffset(58, 42), Size = UDim2.new(1, -68, 0, 15), Font = FONT_TITLE, Text = email.Subject, TextColor3 = C.InkSoft, TextSize = 12, TextTruncate = Enum.TextTruncate.AtEnd, ZIndex = 33, Parent = body })
		text({ Position = UDim2.fromOffset(58, 57), Size = UDim2.new(1, -68, 0, 14), Text = email.Body, TextColor3 = C.InkDim, TextSize = 11, TextTruncate = Enum.TextTruncate.AtEnd, ZIndex = 33, Parent = body })

		-- Barre de temps restant (en bas)
		local lifeBack = frame({ AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 58, 1, -7), Size = UDim2.new(1, -70, 0, 3), BackgroundColor3 = Color3.fromRGB(222, 226, 236), ZIndex = 33, Parent = body })
		UIUtil.Corner(lifeBack, UDim.new(1, 0))
		local lifeBar = frame({ Size = UDim2.fromScale(1, 1), BackgroundColor3 = color, ZIndex = 34, Parent = lifeBack })
		UIUtil.Corner(lifeBar, UDim.new(1, 0))

		local envelope = {
			Id = "card" .. tostring(mail.Key),
			Mail = mail,
			Root = root,
			Scale = scale,
			Body = body,
			BodyStroke = bodyStroke,
			Letter = letter,
			Dot = dot,
			Chip = chip,
			LifeBar = lifeBar,
			Target = target,
			Born = now(),
			Lifetime = lifetime,
			Rewarded = rewarded,
			Phase = random:NextNumber(0, math.pi * 2),
			Hurry = false,
			Done = false,
		}
		envelopes[envelope.Id] = envelope
		envelopeCount += 1
		mail.Envelope = envelope

		-- Arrivée en vol plané
		UIUtil.Tween(root, 0.75, { Position = target, Rotation = 0 }, Enum.EasingStyle.Back)
		UIUtil.Tween(scale, 0.75, { Scale = 1 }, Enum.EasingStyle.Back)

		-- Survol : la carte se soulève un peu
		ctx.Connect(root.MouseEnter, function()
			if not envelope.Done and now() - envelope.Born > 0.8 then
				UIUtil.Tween(scale, 0.15, { Scale = 1.05 }, Enum.EasingStyle.Back)
				bodyStroke.Color = C.Blue
			end
		end)
		ctx.Connect(root.MouseLeave, function()
			if not envelope.Done then
				UIUtil.Tween(scale, 0.15, { Scale = 1 })
				bodyStroke.Color = C.Border
			end
		end)

		-- Clic : on réclame (si encore possible) et on ouvre le mail
		ctx.Connect(root.Activated, function()
			if envelope.Done or not ctx.IsAlive() then
				return
			end
			local position = root.Position
			lastPosition = position
			if mail.SpawnId then
				positions[mail.SpawnId] = position
			end
			if mail.State == "Live" and now() < mail.ExpiresAt then
				claim(mail, "Card")
			end
			ctx.Sound.Play("Mail", 1.4)
			if effectsOn() then
				ctx.Effects.Burst(container, position, C.Blue, 10)
				ctx.Effects.Burst(container, position, nil, 6)
			end
			mail.Read = true
			removeEnvelope(envelope, true)
			refresh()
			task.delay(0.14, function()
				if ctx.IsAlive() then
					openMail(mail, "Card")
				end
			end)
		end)
	end

	-- Mail décidé par le serveur (événement Spawn "Email")
	local function onServerSpawn(info)
		if not ctx.IsAlive() or type(info) ~= "table" or type(info.Id) ~= "string" then
			return
		end
		if bySpawn[info.Id] then
			return
		end
		local lifetime = math.max(2, tonumber(info.Lifetime) or 15)
		local mail = {
			Kind = "Spawn",
			SpawnId = info.Id,
			Email = buildEmail(pick(Locale.Pick(EMAILS), info.Variant)),
			Folder = "Inbox",
			Read = false,
			Starred = false,
			State = "Live",
			Time = now(),
			ExpiresAt = now() + lifetime,
			Estimate = estimateReward(),
		}
		addMail(mail)
		spawnCard(mail, info)
		ctx.Sound.Play("Mail", 1 + random:NextNumber() * 0.15)
		-- Encore là à la fin de sa durée (carte ou non) : trop tard pour le bonus
		task.delay(lifetime, function()
			if ctx.IsAlive() then
				expireMail(mail)
			end
		end)
		if S.Open then
			snack(Locale.T("📩 New mail from %s", mail.Email.Sender), function()
				openMail(mail, "List")
			end, mail)
		end
		refresh(true)
	end

	-- Animation de toutes les cartes (une seule boucle ; rien quand il n'y en a pas)
	ctx.OnRender(function()
		if envelopeCount <= 0 then
			return
		end
		local clock = now()
		for _, envelope in pairs(envelopes) do
			local age = clock - envelope.Born
			local left = envelope.Lifetime - age
			if left <= 0 then
				removeEnvelope(envelope, false)
				if envelope.Rewarded then
					expireMail(envelope.Mail)
				end
			else
				local t = clock + envelope.Phase
				envelope.LifeBar.Size = UDim2.fromScale(math.clamp(left / envelope.Lifetime, 0, 1), 1)
				if envelope.Rewarded and left < HURRY_TIME then
					-- Pressée : elle s'agite, étiquette "Vite !" rouge
					if not envelope.Hurry then
						envelope.Hurry = true
						envelope.Chip.Set(Locale.T("⏰ QUICK, READ ME!"), C.Red)
						envelope.LifeBar.BackgroundColor3 = C.Red
					end
					envelope.Body.Rotation = math.sin(t * 24) * 4
					local pulse = 12 + math.abs(math.sin(t * 10)) * 4
					envelope.Dot.Size = UDim2.fromOffset(pulse, pulse)
				else
					envelope.Body.Rotation = math.sin(t * 2.5) * 1.2
				end
				-- Flotte doucement une fois arrivée
				if age > 0.8 then
					envelope.Root.Position = envelope.Target + UDim2.fromOffset(0, math.sin(t * 2.2) * 4)
				end
			end
		end
	end)

	ctx.OnSpawn("Email", onServerSpawn)

	-- Bonus confirmé par le serveur : "+X" (au-dessus de tout) + bandeau du mail
	ctx.OnBonus("Email", function(payload)
		if not ctx.IsAlive() then
			return
		end
		local amount = tonumber(payload.Amount) or 0
		local id = payload.SpawnId
		local mail = type(id) == "string" and bySpawn[id] or nil
		if mail then
			mail.Reward = amount
			mail.State = "Claimed"
		end
		local position = (type(id) == "string" and positions[id]) or lastPosition
		-- Mail affiché dans la fenêtre : le "+X" part de son bandeau de récompense
		local ui = UI
		local interface = ctx.Interface
		if mail and ui and S.Open and S.View == "Message" and S.Selected == mail and interface and interface.GetCanvasCenter then
			local ok, center = pcall(interface.GetCanvasCenter, ui.Msg.Reward.Frame)
			if ok and typeof(center) == "Vector2" then
				position = UDim2.fromOffset(center.X, center.Y)
			end
		end
		local layer = ctx.Effects.GetLayer and ctx.Effects.GetLayer() or nil
		ctx.FloatText(layer or container, position, "+" .. ctx.Format.Format(amount), C.Blue, 40)
		refresh()
	end)

	-- Compteur : ouvre la Réception (ou le brouillon en cours) / ferme
	ctx.Connect(counter.Activated, function()
		if S.Open then
			closeWindow()
			return
		end
		ctx.Sound.Play("Click", 1)
		if not (S.Draft and S.View == "Compose") then
			S.Folder = "Inbox"
			S.Selected = nil
			S.View = "List"
		end
		openWindow()
	end)

	-- Reconstruit la fenêtre (autre mise en page, autre langue) en gardant
	-- la vue, la sélection et le brouillon
	local function rebuildWindow()
		local wasOpen = S.Open
		destroyWindow()
		S.Open = false
		if wasOpen then
			openWindow()
			if S.View == "Message" and S.Selected then
				renderMessage(S.Selected)
				setView("Message")
			end
		end
	end

	-- L'écran change (rotation, fenêtre redimensionnée, autre appareil)
	local function onScreenChanged()
		task.delay(0.2, function()
			if not ctx.IsAlive() then
				return
			end
			placeCounter()
			local ui = UI
			if not ui then
				return
			end
			if ui.Mode ~= currentMode() then
				rebuildWindow()
			else
				fitWindow()
			end
		end)
	end
	if ctx.Interface then
		if ctx.Interface.ScaleChanged then
			ctx.Connect(ctx.Interface.ScaleChanged, onScreenChanged)
		end
		if ctx.Interface.DeviceChanged then
			ctx.Connect(ctx.Interface.DeviceChanged, onScreenChanged)
		end
	end

	-- Langue changée (réglages) : correspondants renommés, fenêtre reconstruite
	languageHandler = function()
		if not ctx.IsAlive() then
			return
		end
		local texts = Locale.Pick(CONTACT_TEXT)
		for _, contact in ipairs(contacts) do
			local t = texts[contact.Id]
			if t then
				contact.Name = t.Name
				contact.Short = t.Short
				contact.Signature = t.Signature
				contact.Address = slug(t.Name) .. Locale.T("@dopamail.com")
			end
		end
		me.Name = Locale.T("Me")
		me.Address = string.lower(player and player.Name or "you") .. Locale.T("@dopamail.com")
		refreshCounter(false)
		if UI then
			rebuildWindow()
		end
	end
	if not languageHooked then
		languageHooked = true
		Locale.OnChanged(function()
			local handler = languageHandler
			if handler then
				handler()
			end
		end)
	end
end

function Email.Stop(_ctx)
	-- Cartes, fenêtre et compteur vivent dans ctx.Container
	-- (détruit par le StimulusManager) ; les tâches en attente vérifient ctx.IsAlive()
	languageHandler = nil
end

return Email
