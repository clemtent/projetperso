--[[
	Email (ModuleScript - stimulus)
	Emplacement : ReplicatedStorage > Client > Stimuli > Email

	"Dopamail", un vrai petit client mail :
	  - chaque mail (décidé par le SERVEUR via l'événement Spawn "Email")
	    arrive en vol plané sous forme de notification : en-tête "DOPAMAIL ·
	    maintenant", avatar rond de l'expéditeur (pastille bleue "non lu"),
	    nom, objet, aperçu du texte, trombone s'il y a une pièce jointe,
	    étiquette colorée (URGENT, PROMO, FAMILLE, TRAVAIL, ARNAQUE ?...) et
	    barre de temps restant ;
	  - un clic l'ouvre : la lettre sort, puis une vraie fenêtre de mail
	    s'ouvre (barre de titre, dossiers Boîte de réception / Favoris /
	    Envoyés / Spam / Corbeille avec compteurs, objet, étoile, expéditeur,
	    adresse, corps, signature, pièce jointe "téléchargeable", bandeau
	    d'avertissement pour les spams et arnaques, boutons Répondre /
	    Transférer / Spam / Supprimer) + ClaimSpawn (le serveur valide) ; le
	    "+X" confirmé (OnBonus "Email") s'affiche à côté ;
	  - si on l'ignore trop longtemps, la notification file vers le compteur
	    "📬 non lus" (en haut à droite, dans le bandeau d'actu) ; cliquer sur
	    le compteur ouvre la boîte de réception : la liste des mails ratés,
	    qu'on peut lire (sans récompense : ils ont expiré côté serveur).
	Plus de 90 mails absurdes (une liste par langue, même ordre) choisis par
	info.Variant.
]]

local Debris = game:GetService("Debris")

local Locale = require(game:GetService("ReplicatedStorage").Shared.Locale)

local Email = {}
Email.Slot = "Overlay"

local MAX_ENVELOPES = 4
local CARD_W = 250
local CARD_H = 86
local POPUP_W = 440
local POPUP_H = 292
local SIDEBAR_W = 110
local POPUP_AUTO_CLOSE = 16
local HURRY_TIME = 3 -- dernières secondes : la carte s'agite
local MISSED_KEEP = 12 -- mails ratés gardés dans la boîte de réception
-- Place du bloc droit du bandeau d'actu (horloge + segment), si le bandeau
-- ne donne pas l'attribut "RightInset"
local TICKER_RIGHT_FALLBACK = 60

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

-- Réponses quand on clique sur "Répondre" / "Transférer" / "Spam"
local REPLIES = {
	en = {
		"Sent... to nobody 📭",
		"Draft saved for 2087",
		"You replied “ok”. Classic.",
		"Reply: “lol” 👍",
		"Message went straight to spam 🗑️",
		"Replied with a single emoji 👌",
		"Reply sent: “haha yes”",
	},
	fr = {
		"Envoyé... à personne 📭",
		"Brouillon enregistré pour 2087",
		"Tu as répondu « ok ». Classique.",
		"Réponse : « mdr » 👍",
		"Message parti dans les spams 🗑️",
		"Répondu avec un seul emoji 👌",
		"Réponse envoyée : « haha oui »",
	},
}
local FORWARDS = {
	en = {
		"Forwarded to Grandma 👵",
		"Forwarded to the cat 🐱",
		"Forwarded to yourself 🔁",
		"Forwarded to everyone 😱",
		"Forwarded to the Boss (oops) 👔",
	},
	fr = {
		"Transféré à Mamie 👵",
		"Transféré au chat 🐱",
		"Transféré à toi-même 🔁",
		"Transféré à tout le monde 😱",
		"Transféré au Boss (oups) 👔",
	},
}
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

-- Transforme une entrée compacte en mail complet
local function buildEmail(entry): { [string]: any }
	local style = TAGS[entry[1]] or TAGS.PERSO
	local tag = { Id = entry[1], Text = Locale.T(style.Text), Color = style.Color }
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
		Tag = tag,
		Avatar = entry[2],
		Sender = sender,
		Address = slug(sender) .. Locale.T("@dopamail.com"),
		Subject = entry[4],
		Body = entry[5],
		Signature = entry[6] or sender,
		Attachment = attachment,
		Suspicious = entry[1] == "ARNAQUE" or entry[1] == "SPAM",
		Read = false,
		Starred = false,
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
	local line = Color3.fromRGB(226, 230, 238)
	local sidebarColor = Color3.fromRGB(243, 246, 252)
	local red = Color3.fromRGB(226, 38, 52)

	local envelopes: { [string]: any } = {}
	local envelopeCount = 0
	local missed = 0 -- mails ratés non lus
	local missedList: { any } = {} -- les plus récents en premier
	local spamCount = random:NextInteger(1200, 4800)
	local trashCount = random:NextInteger(40, 300)
	local sentCount = random:NextInteger(3, 30)
	local starredCount = 0
	local positions: { [string]: UDim2 } = {}
	local lastPosition = UDim2.fromScale(0.5, 0.45)
	local popup: any = nil -- fenêtre ouverte

	local function effectsOn(): boolean
		local data = ctx.State.Data
		return not (data and data.Settings and data.Settings.Effects == false)
	end

	-- Connexion liée à un bouton de fenêtre (coupée avec lui à sa destruction)
	local function on(signal: RBXScriptSignal, callback: (...any) -> ())
		signal:Connect(function(...)
			if ctx.IsAlive() then
				callback(...)
			end
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
		props.TextXAlignment = props.TextXAlignment or Enum.TextXAlignment.Left
		props.Font = props.Font or Theme.Fonts.Body
		props.TextColor3 = props.TextColor3 or ink
		return UIUtil.Create("TextLabel", props)
	end

	-- Avatar rond : dégradé de la couleur de l'étiquette + emoji
	local function avatar(parent: Instance, email, size: number, position: UDim2, zIndex: number): Frame
		local color = email.Tag.Color
		local circle = frame({ Size = UDim2.fromOffset(size, size), Position = position, BackgroundColor3 = white, ZIndex = zIndex, Parent = parent })
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
		local chip = frame({ Size = UDim2.fromOffset(0, height), AutomaticSize = Enum.AutomaticSize.X, BackgroundColor3 = tag.Color, ZIndex = zIndex, Parent = parent })
		UIUtil.Corner(chip, UDim.new(1, 0))
		UIUtil.Create("UIPadding", { PaddingLeft = UDim.new(0, 6), PaddingRight = UDim.new(0, 6), Parent = chip })
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

	-- Petit bouton de fenêtre
	local function makeButton(parent: Instance, label: string, filled: boolean, textColor: Color3, x: number, y: number, width: number, height: number, z: number): TextButton
		local button = UIUtil.Create("TextButton", {
			Size = UDim2.fromOffset(width, height),
			Position = UDim2.fromOffset(x, y),
			BackgroundColor3 = filled and blue or white,
			AutoButtonColor = false,
			Font = Theme.Fonts.Title,
			Text = label,
			TextColor3 = textColor,
			TextScaled = true,
			ZIndex = z,
			Parent = parent,
		})
		UIUtil.Create("UITextSizeConstraint", { MaxTextSize = 13, MinTextSize = 8, Parent = button })
		UIUtil.Create("UIPadding", { PaddingLeft = UDim.new(0, 4), PaddingRight = UDim.new(0, 4), PaddingTop = UDim.new(0, 5), PaddingBottom = UDim.new(0, 5), Parent = button })
		UIUtil.Corner(button, 8)
		UIUtil.Stroke(button, filled and Color3.fromRGB(20, 80, 180) or Color3.fromRGB(200, 206, 220), 1.2, 0)
		UIUtil.Gradient(button, ColorSequence.new(white, Color3.fromRGB(222, 226, 236)), 90)
		UIUtil.AnimateButton(button, 1.05, 0.93)
		return button
	end

	------------------------------------------------------------------
	-- Compteur "📬 non lus" (dans le bandeau d'actu, à gauche de son bloc
	-- droit) : cliquable, ouvre la boîte de réception
	------------------------------------------------------------------
	local counter = UIUtil.Create("TextButton", {
		Name = "Unread",
		Size = UDim2.fromOffset(0, 22),
		AutomaticSize = Enum.AutomaticSize.X,
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -(TICKER_RIGHT_FALLBACK + 6), 0, 4),
		BackgroundColor3 = white,
		AutoButtonColor = false,
		Text = "",
		Visible = false,
		ZIndex = 40,
		Parent = container,
	})
	UIUtil.Corner(counter, UDim.new(1, 0))
	UIUtil.Stroke(counter, border, 1.5, 0.15)
	UIUtil.Gradient(counter, ColorSequence.new(white, Color3.fromRGB(226, 232, 244)), 90)
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
	UIUtil.Create("UIPadding", { PaddingLeft = UDim.new(0, 5), PaddingRight = UDim.new(0, 5), Parent = counterBadge })
	local counterLabel = text({
		Size = UDim2.fromOffset(0, 18),
		AutomaticSize = Enum.AutomaticSize.X,
		Font = Theme.Fonts.Title,
		Text = "📬 " .. Locale.Pick(UNREAD).Many,
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
	task.delay(1, placeCounter)
	if ctx.Interface and ctx.Interface.ScaleChanged then
		ctx.Connect(ctx.Interface.ScaleChanged, function()
			task.delay(0.2, placeCounter)
		end)
	end

	local function unreadCount(): number
		return envelopeCount + missed
	end

	local function refreshCounter(bump: boolean?)
		local unread = unreadCount()
		counter.Visible = unread > 0
		local suffix = ""
		if unread >= 50 then
			suffix = " 😱"
		elseif unread >= 10 then
			suffix = " 😬"
		end
		counterBadge.Text = unread > 999 and "999+" or tostring(unread)
		counterBadge.BackgroundColor3 = unread >= 10 and red or blue
		counterLabel.Text = "📬 " .. (unread > 1 and Locale.Pick(UNREAD).Many or Locale.Pick(UNREAD).One) .. suffix
		if bump ~= false then
			counterScale.Scale = 1.25
			UIUtil.Tween(counterScale, 0.3, { Scale = 1 }, Enum.EasingStyle.Back)
		end
	end

	------------------------------------------------------------------
	-- Fenêtre du client mail
	------------------------------------------------------------------
	local PANE_W = POPUP_W - SIDEBAR_W
	local PANE_H = POPUP_H - 30

	local function closePopup(target, how: string?)
		local current = target or popup
		if not current or current.Closed then
			return
		end
		current.Closed = true
		if popup == current then
			popup = nil
		end
		local root = current.Root
		if how == "trash" or how == "spam" then
			-- La fenêtre file dans le dossier (Corbeille / Spam) de la barre latérale
			local row = current.Folders[how == "trash" and "Trash" or "Spam"]
			local rowY = row and (30 + row.Position.Y.Offset + 12) or POPUP_H
			local offset = UDim2.fromOffset(SIDEBAR_W / 2 - root.AnchorPoint.X * POPUP_W, rowY - root.AnchorPoint.Y * POPUP_H)
			UIUtil.Tween(root, 0.35, { Position = root.Position + offset, Rotation = how == "trash" and 20 or -12 }, Enum.EasingStyle.Back, Enum.EasingDirection.In)
			UIUtil.Tween(current.Scale, 0.35, { Scale = 0.06 }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		else
			UIUtil.Tween(current.Scale, 0.2, { Scale = 0.6 }, Enum.EasingStyle.Back, Enum.EasingDirection.In)
		end
		UIUtil.Tween(current.Group, 0.3, { GroupTransparency = 1 })
		UIUtil.Tween(current.Outline, 0.3, { Transparency = 1 })
		UIUtil.Tween(current.Shadow, 0.3, { BackgroundTransparency = 1 })
		Debris:AddItem(root, 0.4)
	end

	-- Ligne de dossier de la barre latérale
	local function folderRow(parent: Instance, y: number, icon: string, name: string, count: number?, active: boolean, accent: Color3?): Frame
		local row = frame({ Position = UDim2.fromOffset(6, y), Size = UDim2.new(1, -12, 0, 24), BackgroundColor3 = active and Color3.fromRGB(214, 228, 252) or sidebarColor, BackgroundTransparency = active and 0 or 1, ZIndex = 63, Parent = parent })
		UIUtil.Corner(row, 7)
		UIUtil.Label({
			Position = UDim2.fromOffset(5, 4),
			Size = UDim2.new(1, -36, 1, -8),
			Font = active and Theme.Fonts.Title or Theme.Fonts.Body,
			Text = icon .. " " .. name,
			TextColor3 = active and blue or ink,
			TextXAlignment = Enum.TextXAlignment.Left,
			MaxTextSize = 12,
			ZIndex = 64,
			Parent = row,
		})
		do
			local badge = text({
				Name = "Count",
				AnchorPoint = Vector2.new(1, 0.5),
				Position = UDim2.new(1, -4, 0.5, 0),
				Size = UDim2.fromOffset(0, 15),
				AutomaticSize = Enum.AutomaticSize.X,
				BackgroundColor3 = accent or blue,
				BackgroundTransparency = 0,
				Font = Theme.Fonts.Number,
				Text = (count or 0) > 999 and "999+" or tostring(count or 0),
				TextColor3 = white,
				TextSize = 10,
				TextXAlignment = Enum.TextXAlignment.Center,
				Visible = (count or 0) > 0,
				ZIndex = 65,
				Parent = row,
			})
			UIUtil.Corner(badge, UDim.new(1, 0))
			UIUtil.Create("UIPadding", { PaddingLeft = UDim.new(0, 5), PaddingRight = UDim.new(0, 5), Parent = badge })
		end
		return row
	end

	-- Construit la fenêtre (barre de titre, dossiers, zone de lecture vide)
	local function buildWindow(ax: number, ay: number, from: UDim2)
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
		local shadow = frame({ Size = UDim2.new(1, 10, 1, 10), Position = UDim2.fromOffset(-5, 5), BackgroundColor3 = Color3.new(0, 0, 0), BackgroundTransparency = 0.78, ZIndex = 60, Parent = root })
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

		-- Barre de titre
		local titleBar = frame({ Size = UDim2.new(1, 0, 0, 30), BackgroundColor3 = white, ZIndex = 62, Parent = group })
		UIUtil.Gradient(titleBar, ColorSequence.new(Color3.fromRGB(44, 60, 104), Color3.fromRGB(26, 36, 66)), 90)
		for index, color in ipairs({ Color3.fromRGB(255, 95, 86), Color3.fromRGB(255, 189, 46), Color3.fromRGB(39, 201, 63) }) do
			local light = frame({ Size = UDim2.fromOffset(10, 10), AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 10 + (index - 1) * 15, 0.5, 0), BackgroundColor3 = color, ZIndex = 63, Parent = titleBar })
			UIUtil.Corner(light, UDim.new(1, 0))
		end
		text({
			Size = UDim2.new(1, -150, 1, 0),
			Position = UDim2.fromOffset(62, 0),
			Font = Theme.Fonts.Title,
			Text = Locale.T("📥 Dopamail — Inbox"),
			TextColor3 = white,
			TextSize = 13,
			TextTruncate = Enum.TextTruncate.AtEnd,
			ZIndex = 63,
			Parent = titleBar,
		})
		-- Fausse barre de recherche
		local search = frame({ AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -36, 0.5, 0), Size = UDim2.fromOffset(92, 18), BackgroundColor3 = white, BackgroundTransparency = 0.85, ZIndex = 63, Parent = titleBar })
		UIUtil.Corner(search, UDim.new(1, 0))
		text({ Position = UDim2.fromOffset(8, 0), Size = UDim2.new(1, -10, 1, 0), Text = "🔍 " .. Locale.T("Search"), TextColor3 = Color3.fromRGB(200, 210, 235), TextSize = 10, ZIndex = 64, Parent = search })
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

		-- Barre latérale : bouton "Écrire" (décor), dossiers, stockage
		local sidebar = frame({ Position = UDim2.fromOffset(0, 30), Size = UDim2.new(0, SIDEBAR_W, 1, -30), BackgroundColor3 = sidebarColor, ZIndex = 62, Parent = group })
		frame({ AnchorPoint = Vector2.new(1, 0), Position = UDim2.fromScale(1, 0), Size = UDim2.new(0, 1, 1, 0), BackgroundColor3 = line, ZIndex = 63, Parent = sidebar })
		local compose = frame({ Position = UDim2.fromOffset(8, 8), Size = UDim2.new(1, -16, 0, 24), BackgroundColor3 = blue, ZIndex = 63, Parent = sidebar })
		UIUtil.Corner(compose, UDim.new(1, 0))
		UIUtil.Gradient(compose, ColorSequence.new(white, Color3.fromRGB(205, 215, 235)), 90)
		text({ Size = UDim2.fromScale(1, 1), Font = Theme.Fonts.Title, Text = "✏️ " .. Locale.T("Compose"), TextColor3 = white, TextSize = 12, TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 64, Parent = compose })
		local folders = {
			Inbox = folderRow(sidebar, 40, "📥", Locale.T("Inbox"), unreadCount(), true, red),
			Starred = folderRow(sidebar, 66, "⭐", Locale.T("Starred"), starredCount, false, Color3.fromRGB(240, 170, 20)),
			Sent = folderRow(sidebar, 92, "📤", Locale.T("Sent"), nil, false),
			Spam = folderRow(sidebar, 118, "🚫", Locale.T("Spam"), spamCount, false, Color3.fromRGB(120, 124, 136)),
			Trash = folderRow(sidebar, 144, "🗑️", Locale.T("Trash"), nil, false),
		}
		-- Stockage (toujours presque plein)
		text({ Position = UDim2.new(0, 10, 1, -40), Size = UDim2.new(1, -20, 0, 14), Text = Locale.T("💾 Storage: 99% full"), TextColor3 = inkDim, TextSize = 10, TextTruncate = Enum.TextTruncate.AtEnd, ZIndex = 63, Parent = sidebar })
		local bar = frame({ Position = UDim2.new(0, 10, 1, -22), Size = UDim2.new(1, -20, 0, 6), BackgroundColor3 = line, ZIndex = 63, Parent = sidebar })
		UIUtil.Corner(bar, UDim.new(1, 0))
		local fill = frame({ Size = UDim2.fromScale(0.99, 1), BackgroundColor3 = Color3.fromRGB(240, 120, 40), ZIndex = 64, Parent = bar })
		UIUtil.Corner(fill, UDim.new(1, 0))

		-- Zone de lecture (reconstruite à chaque vue)
		local pane = frame({ Name = "Pane", Position = UDim2.fromOffset(SIDEBAR_W, 30), Size = UDim2.new(1, -SIDEBAR_W, 1, -30), ZIndex = 62, Parent = group })

		-- Contour (hors du CanvasGroup)
		local outline = frame({ Size = UDim2.fromScale(1, 1), ZIndex = 70, Parent = root })
		UIUtil.Corner(outline, 14)
		local outlineStroke = UIUtil.Stroke(outline, border, 1.5, 1)

		local current = {
			Root = root,
			Scale = scale,
			Group = group,
			Shadow = shadow,
			Outline = outlineStroke,
			Pane = pane,
			Folders = folders,
			Closed = false,
			Token = 0,
			Mode = "",
		}
		on(closeButton.Activated, function()
			closePopup(current)
		end)

		-- Ouverture : la fenêtre s'agrandit depuis la notification
		UIUtil.Tween(root, 0.4, { Position = UDim2.fromScale(ax, ay) }, Enum.EasingStyle.Quint)
		UIUtil.Tween(scale, 0.4, { Scale = 1 }, Enum.EasingStyle.Back)
		UIUtil.Tween(group, 0.25, { GroupTransparency = 0 })
		UIUtil.Tween(outlineStroke, 0.25, { Transparency = 0.1 })
		return current
	end

	-- Met à jour un compteur de dossier (texte du badge)
	local function setFolderCount(current, name: string, count: number)
		local row = current and current.Folders[name]
		local badge = row and row:FindFirstChild("Count")
		if not badge or not badge:IsA("TextLabel") then
			return
		end
		badge.Text = count > 999 and "999+" or tostring(count)
		badge.Visible = count > 0
		local scale = badge:FindFirstChildOfClass("UIScale") or UIUtil.Create("UIScale", { Parent = badge })
		scale.Scale = 1.4
		UIUtil.Tween(scale, 0.3, { Scale = 1 }, Enum.EasingStyle.Back)
	end

	-- Petite animation d'entrée du contenu de la zone de lecture
	local function slideIn(content: Frame)
		content.Position = UDim2.fromOffset(0, 10)
		UIUtil.Tween(content, 0.3, { Position = UDim2.fromOffset(0, 0) }, Enum.EasingStyle.Quint)
	end

	local showInbox: (current: any) -> ()

	-- Vue "message" dans la zone de lecture
	local function showMessage(current, email, fromInbox: boolean)
		current.Token += 1
		current.Mode = "Message"
		current.Pane:ClearAllChildren()
		local content = frame({ Size = UDim2.fromScale(1, 1), ZIndex = 62, Parent = current.Pane })
		slideIn(content)
		local W = PANE_W

		-- Objet + étoile (favoris)
		if fromInbox then
			local back = UIUtil.Create("TextButton", { Position = UDim2.fromOffset(8, 8), Size = UDim2.fromOffset(22, 22), BackgroundColor3 = sidebarColor, AutoButtonColor = true, Font = Theme.Fonts.Title, Text = "←", TextColor3 = ink, TextSize = 14, ZIndex = 64, Parent = content })
			UIUtil.Corner(back, UDim.new(1, 0))
			on(back.Activated, function()
				ctx.Sound.Play("Click", 1)
				showInbox(current)
			end)
		end
		local subjectX = fromInbox and 36 or 12
		text({ Position = UDim2.fromOffset(subjectX, 8), Size = UDim2.fromOffset(W - subjectX - 40, 22), Font = Theme.Fonts.Title, Text = email.Subject, TextSize = 16, TextTruncate = Enum.TextTruncate.AtEnd, ZIndex = 63, Parent = content })
		local star = UIUtil.Create("TextButton", { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -10, 0, 7), Size = UDim2.fromOffset(24, 24), BackgroundTransparency = 1, Font = Theme.Fonts.Title, Text = email.Starred and "⭐" or "☆", TextColor3 = Color3.fromRGB(240, 170, 20), TextSize = 18, ZIndex = 64, Parent = content })
		local starScale = UIUtil.Create("UIScale", { Parent = star })
		on(star.Activated, function()
			email.Starred = not email.Starred
			star.Text = email.Starred and "⭐" or "☆"
			starredCount = math.max(0, starredCount + (email.Starred and 1 or -1))
			setFolderCount(current, "Starred", starredCount)
			starScale.Scale = 1.5
			UIUtil.Tween(starScale, 0.35, { Scale = 1 }, Enum.EasingStyle.Back)
			ctx.Sound.Play("Click", 1.2)
		end)

		-- Expéditeur
		avatar(content, email, 34, UDim2.fromOffset(12, 36), 63)
		text({ Position = UDim2.fromOffset(54, 36), Size = UDim2.fromOffset(W - 190, 16), Font = Theme.Fonts.Title, Text = email.Sender, TextSize = 13, TextTruncate = Enum.TextTruncate.AtEnd, ZIndex = 63, Parent = content })
		text({ Position = UDim2.fromOffset(54, 53), Size = UDim2.fromOffset(W - 66, 14), Text = Locale.T("<%s> · to me · just now", email.Address), TextColor3 = inkDim, TextSize = 11, TextTruncate = Enum.TextTruncate.AtEnd, ZIndex = 63, Parent = content })
		local chip = tagChip(content, email, 17, 64)
		chip.AnchorPoint = Vector2.new(1, 0)
		chip.Position = UDim2.new(1, -12, 0, 36)
		frame({ Position = UDim2.fromOffset(12, 76), Size = UDim2.new(1, -24, 0, 1), BackgroundColor3 = line, ZIndex = 63, Parent = content })

		-- Bandeau d'avertissement (spams et arnaques)
		local y = 82
		if email.Suspicious then
			local scam = email.Tag.Id == "ARNAQUE"
			local warning = frame({ Position = UDim2.fromOffset(12, y), Size = UDim2.new(1, -24, 0, 22), BackgroundColor3 = scam and Color3.fromRGB(255, 236, 200) or Color3.fromRGB(236, 238, 244), ZIndex = 63, Parent = content })
			UIUtil.Corner(warning, 6)
			UIUtil.Stroke(warning, scam and Color3.fromRGB(240, 150, 40) or Color3.fromRGB(190, 196, 210), 1, 0)
			UIUtil.Label({
				Position = UDim2.fromOffset(8, 2),
				Size = UDim2.new(1, -14, 1, -4),
				Font = Theme.Fonts.Title,
				Text = scam and Locale.T("⚠️ Careful: this looks like a scam. Never share your password!") or Locale.T("🚫 This looks like spam. We're not judging."),
				TextColor3 = scam and Color3.fromRGB(150, 70, 0) or inkDim,
				TextXAlignment = Enum.TextXAlignment.Left,
				MaxTextSize = 11,
				ZIndex = 64,
				Parent = warning,
			})
			y += 28
		end

		-- Corps + signature + pièce jointe
		local attachment = email.Attachment
		local bottom = PANE_H - 42 -- haut des boutons
		local attachmentY = bottom - 34
		local signatureY = (attachment and attachmentY or bottom) - 20
		UIUtil.Label({
			Position = UDim2.fromOffset(12, y),
			Size = UDim2.fromOffset(W - 24, signatureY - y - 2),
			Text = email.Body,
			TextColor3 = ink,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextYAlignment = Enum.TextYAlignment.Top,
			TextWrapped = true,
			MaxTextSize = 13,
			ZIndex = 63,
			Parent = content,
		})
		local signature = text({ Position = UDim2.fromOffset(12, signatureY), Size = UDim2.fromOffset(W - 24, 16), Text = "— " .. email.Signature, TextColor3 = inkDim, TextSize = 12, TextTruncate = Enum.TextTruncate.AtEnd, ZIndex = 63, Parent = content })
		signature.FontFace = Font.new("rbxasset://fonts/families/BuilderSans.json", Enum.FontWeight.Medium, Enum.FontStyle.Italic)
		if attachment then
			local card = UIUtil.Create("TextButton", { Position = UDim2.fromOffset(12, attachmentY), Size = UDim2.fromOffset(196, 30), BackgroundColor3 = Color3.fromRGB(245, 247, 252), AutoButtonColor = false, Text = "", ZIndex = 63, Parent = content })
			UIUtil.Corner(card, 8)
			UIUtil.Stroke(card, line, 1.2, 0)
			local icon = frame({ Position = UDim2.fromOffset(4, 4), Size = UDim2.fromOffset(22, 22), BackgroundColor3 = attachment.Type.Color, ZIndex = 64, Parent = card })
			UIUtil.Corner(icon, 5)
			UIUtil.Label({ Size = UDim2.fromScale(1, 1), Text = attachment.Type.Icon, MaxTextSize = 13, ZIndex = 65, Parent = icon })
			text({ Position = UDim2.fromOffset(32, 3), Size = UDim2.fromOffset(136, 14), Font = Theme.Fonts.Title, Text = attachment.Name, TextSize = 11, TextTruncate = Enum.TextTruncate.AtEnd, ZIndex = 64, Parent = card })
			text({ Position = UDim2.fromOffset(32, 16), Size = UDim2.fromOffset(120, 12), Text = attachment.Size, TextColor3 = inkDim, TextSize = 10, ZIndex = 64, Parent = card })
			local download = text({ AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -6, 0.5, 0), Size = UDim2.fromOffset(20, 20), Text = "⬇️", TextSize = 13, TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 64, Parent = card })
			UIUtil.AnimateButton(card, 1.04, 0.95)
			on(card.Activated, function()
				ctx.Sound.Play("Click", 1)
				local message = attachment.Virus and pickLine(VIRUS_JOKES) or pickLine(ATTACHMENT_JOKES)
				ctx.FloatText(container, current.Root.Position, message, attachment.Virus and red or blue, 24)
				download.Text = attachment.Virus and "🛡️" or "✅"
			end)
		end

		-- Boutons
		local gap = 6
		local buttonW = math.floor((W - 24 - gap * 3) / 4)
		local replyButton = makeButton(content, Locale.T("↩️ Reply"), true, white, 12, bottom, buttonW, 30, 66)
		local forwardButton = makeButton(content, Locale.T("➡️ Forward"), false, ink, 12 + (buttonW + gap), bottom, buttonW, 30, 66)
		local spamButton = makeButton(content, Locale.T("🚫 Spam"), false, Color3.fromRGB(110, 116, 132), 12 + (buttonW + gap) * 2, bottom, buttonW, 30, 66)
		local deleteButton = makeButton(content, Locale.T("🗑️ Delete"), false, Color3.fromRGB(210, 40, 50), 12 + (buttonW + gap) * 3, bottom, buttonW, 30, 66)

		local function anchorPosition(): UDim2
			return UDim2.fromScale(current.Root.AnchorPoint.X, current.Root.AnchorPoint.Y)
		end
		on(deleteButton.Activated, function()
			if current.Closed then
				return
			end
			ctx.Sound.Play("Click", 0.8)
			trashCount += 1
			setFolderCount(current, "Trash", trashCount)
			closePopup(current, "trash")
		end)
		on(spamButton.Activated, function()
			if current.Closed then
				return
			end
			ctx.Sound.Play("Click", 0.8)
			spamCount += 1
			setFolderCount(current, "Spam", spamCount)
			ctx.FloatText(container, anchorPosition(), pickLine(SPAMMED), Color3.fromRGB(110, 116, 132), 26)
			closePopup(current, "spam")
		end)
		on(replyButton.Activated, function()
			if current.Closed then
				return
			end
			ctx.Sound.Play("Mail", 1.3)
			sentCount += 1
			ctx.FloatText(container, anchorPosition(), pickLine(REPLIES), blue, 30)
			closePopup(current)
		end)
		on(forwardButton.Activated, function()
			if current.Closed then
				return
			end
			ctx.Sound.Play("Mail", 1.15)
			sentCount += 1
			ctx.FloatText(container, anchorPosition(), pickLine(FORWARDS), Color3.fromRGB(140, 60, 220), 28)
			closePopup(current)
		end)
	end

	-- Vue "boîte de réception" : les mails ratés
	showInbox = function(current)
		current.Token += 1
		current.Mode = "Inbox"
		current.Pane:ClearAllChildren()
		local content = frame({ Size = UDim2.fromScale(1, 1), ZIndex = 62, Parent = current.Pane })
		slideIn(content)
		text({ Position = UDim2.fromOffset(12, 8), Size = UDim2.fromOffset(PANE_W - 120, 22), Font = Theme.Fonts.Title, Text = "📥 " .. Locale.T("Inbox"), TextSize = 16, ZIndex = 63, Parent = content })
		text({ AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -12, 0, 10), Size = UDim2.fromOffset(110, 18), Font = Theme.Fonts.Title, Text = Locale.T("%d unread", missed), TextColor3 = missed > 0 and red or inkDim, TextSize = 12, TextXAlignment = Enum.TextXAlignment.Right, ZIndex = 63, Parent = content })
		local list = UIUtil.Create("ScrollingFrame", {
			Position = UDim2.fromOffset(8, 36),
			Size = UDim2.new(1, -16, 1, -42),
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			CanvasSize = UDim2.new(),
			AutomaticCanvasSize = Enum.AutomaticSize.Y,
			ScrollBarThickness = 4,
			ScrollingDirection = Enum.ScrollingDirection.Y,
			ZIndex = 63,
			Parent = content,
		})
		UIUtil.Create("UIListLayout", { Padding = UDim.new(0, 4), SortOrder = Enum.SortOrder.LayoutOrder, Parent = list })
		if #missedList == 0 then
			UIUtil.Label({ Position = UDim2.fromOffset(0, 60), Size = UDim2.new(1, 0, 0, 40), Font = Theme.Fonts.Title, Text = Locale.T("🎉 Inbox zero! Enjoy it, it won't last."), TextColor3 = inkDim, MaxTextSize = 14, TextWrapped = true, ZIndex = 64, Parent = list })
			return
		end
		for index, entry in ipairs(missedList) do
			local email = entry.Email
			local row = UIUtil.Create("TextButton", { Size = UDim2.new(1, -8, 0, 46), BackgroundColor3 = email.Read and white or Color3.fromRGB(236, 243, 255), AutoButtonColor = false, Text = "", LayoutOrder = index, ZIndex = 64, Parent = list })
			UIUtil.Corner(row, 8)
			UIUtil.Stroke(row, line, 1, 0)
			if not email.Read then
				local dot = frame({ AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromOffset(7, 23), Size = UDim2.fromOffset(7, 7), BackgroundColor3 = blue, ZIndex = 65, Parent = row })
				UIUtil.Corner(dot, UDim.new(1, 0))
			end
			avatar(row, email, 30, UDim2.fromOffset(14, 8), 65)
			text({ Position = UDim2.fromOffset(52, 4), Size = UDim2.new(1, -110, 0, 14), Font = email.Read and Theme.Fonts.Body or Theme.Fonts.Title, Text = email.Sender, TextSize = 12, TextTruncate = Enum.TextTruncate.AtEnd, ZIndex = 65, Parent = row })
			local minutes = math.max(1, math.floor((os.clock() - entry.Time) / 60))
			text({ AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -8, 0, 4), Size = UDim2.fromOffset(56, 14), Text = Locale.T("%d min", minutes), TextColor3 = inkDim, TextSize = 10, TextXAlignment = Enum.TextXAlignment.Right, ZIndex = 65, Parent = row })
			text({ Position = UDim2.fromOffset(52, 18), Size = UDim2.new(1, -62, 0, 13), Font = Theme.Fonts.Title, Text = (email.Attachment and "📎 " or "") .. email.Subject, TextColor3 = Color3.fromRGB(50, 56, 72), TextSize = 11, TextTruncate = Enum.TextTruncate.AtEnd, ZIndex = 65, Parent = row })
			text({ Position = UDim2.fromOffset(52, 31), Size = UDim2.new(1, -62, 0, 12), Text = email.Body, TextColor3 = inkDim, TextSize = 10, TextTruncate = Enum.TextTruncate.AtEnd, ZIndex = 65, Parent = row })
			on(row.Activated, function()
				if current.Closed then
					return
				end
				ctx.Sound.Play("Click", 1.1)
				if not email.Read then
					email.Read = true
					missed = math.max(0, missed - 1)
					refreshCounter()
					setFolderCount(current, "Inbox", unreadCount())
				end
				showMessage(current, email, true)
			end)
		end
	end

	local function autoClose(current)
		local token = current.Token
		task.delay(POPUP_AUTO_CLOSE, function()
			if ctx.IsAlive() and current.Token == token then
				closePopup(current)
			end
		end)
	end

	-- Ouvre un mail reçu (depuis une notification)
	local function openMail(email, sx: number, sy: number, from: UDim2)
		closePopup(nil)
		local current = buildWindow(math.clamp(sx, 0.02, 0.98), math.clamp(sy, 0.06, 0.94), from)
		popup = current
		showMessage(current, email, false)
		autoClose(current)
	end

	-- Ouvre la boîte de réception (clic sur le compteur)
	local function openInbox()
		if popup and not popup.Closed then
			local wasInbox = popup.Mode == "Inbox"
			closePopup(popup)
			if wasInbox then
				return
			end
		end
		ctx.Sound.Play("Click", 1)
		local current = buildWindow(0.98, 0.08, UDim2.new(1, -(tickerRight + 60), 0, 16))
		popup = current
		showInbox(current)
	end
	ctx.Connect(counter.Activated, openInbox)

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
			UIUtil.Tween(envelope.Letter, 0.2, { Position = UDim2.new(0.5, 0, 0, -30) }, Enum.EasingStyle.Back)
			task.delay(0.12, function()
				if root.Parent then
					UIUtil.Tween(envelope.Scale, 0.25, { Scale = 1.12 }, Enum.EasingStyle.Quad)
					fadeOut(root, 0.22)
				end
			end)
		else
			-- Ignorée : elle file vers le compteur "non lus" (en haut à droite)
			missed += 1
			table.insert(missedList, 1, { Email = envelope.Email, Time = os.clock() })
			if #missedList > MISSED_KEEP then
				-- Trop vieux : il reste compté (la boîte déborde), mais n'est plus listé
				table.remove(missedList)
			end
			UIUtil.Tween(root, 0.8, {
				Position = UDim2.new(1, -(tickerRight + 50), 0, 14),
				Rotation = -25,
			}, Enum.EasingStyle.Back, Enum.EasingDirection.In)
			UIUtil.Tween(envelope.Scale, 0.8, { Scale = 0.15 }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
			fadeOut(root, 0.8)
		end
		refreshCounter()
		if popup and not popup.Closed then
			setFolderCount(popup, "Inbox", unreadCount())
		end
		Debris:AddItem(root, opened and 0.45 or 0.85)
	end

	local function spawnEmail(info)
		if not ctx.IsAlive() or type(info) ~= "table" or type(info.Id) ~= "string" then
			return
		end
		if envelopes[info.Id] or envelopeCount >= MAX_ENVELOPES then
			return
		end
		local email = buildEmail(pick(Locale.Pick(EMAILS), info.Variant))
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
		local letter = frame({ Name = "Letter", AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 8), Size = UDim2.new(1, -34, 0, 56), BackgroundColor3 = paper, ZIndex = 30, Parent = root })
		UIUtil.Corner(letter, 4)
		UIUtil.Stroke(letter, Color3.fromRGB(210, 214, 226), 1, 0)
		for i = 1, 3 do
			frame({ Position = UDim2.fromOffset(12, 8 + i * 7), Size = UDim2.new(0.7 - i * 0.12, 0, 0, 2), BackgroundColor3 = Color3.fromRGB(200, 204, 216), ZIndex = 30, Parent = letter })
		end

		-- Ombre douce
		local shadow = frame({ Size = UDim2.new(1, 4, 1, 4), Position = UDim2.fromOffset(-2, 5), BackgroundColor3 = Color3.new(0, 0, 0), BackgroundTransparency = 0.8, ZIndex = 29, Parent = root })
		UIUtil.Corner(shadow, 16)

		-- Carte (notification)
		local body = frame({ Name = "Body", Size = UDim2.fromScale(1, 1), BackgroundColor3 = white, ZIndex = 31, Parent = root })
		UIUtil.Corner(body, 14)
		UIUtil.Gradient(body, ColorSequence.new(white, Color3.fromRGB(238, 241, 248)), 90)
		local bodyStroke = UIUtil.Stroke(body, border, 1.5, 0.15)
		-- Liseré coloré à gauche (couleur de l'étiquette)
		local accent = frame({ Size = UDim2.new(0, 4, 1, -24), Position = UDim2.fromOffset(0, 12), BackgroundColor3 = tagColor, ZIndex = 32, Parent = body })
		UIUtil.Corner(accent, 2)

		-- En-tête "DOPAMAIL · maintenant" (comme une notification de téléphone)
		local appIcon = frame({ Position = UDim2.fromOffset(12, 7), Size = UDim2.fromOffset(14, 14), BackgroundColor3 = blue, ZIndex = 33, Parent = body })
		UIUtil.Corner(appIcon, 4)
		UIUtil.Gradient(appIcon, ColorSequence.new(white, Color3.fromRGB(190, 205, 235)), 90)
		UIUtil.Label({ Size = UDim2.fromScale(1, 1), Text = "✉", Font = Theme.Fonts.Title, TextColor3 = white, MaxTextSize = 10, ZIndex = 34, Parent = appIcon })
		text({ Position = UDim2.fromOffset(31, 6), Size = UDim2.fromOffset(120, 16), Font = Theme.Fonts.Title, Text = "DOPAMAIL · " .. Locale.T("now"), TextColor3 = inkDim, TextSize = 10, ZIndex = 33, Parent = body })
		local chip = tagChip(body, email, 15, 34)
		chip.AnchorPoint = Vector2.new(1, 0)
		chip.Position = UDim2.new(1, -10, 0, 6)

		-- Avatar + pastille "non lu"
		avatar(body, email, 38, UDim2.fromOffset(12, 28), 33)
		local dot = frame({ Name = "UnreadDot", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromOffset(15, 31), Size = UDim2.fromOffset(12, 12), BackgroundColor3 = blue, ZIndex = 36, Parent = body })
		UIUtil.Corner(dot, UDim.new(1, 0))
		UIUtil.Stroke(dot, white, 2, 0)

		-- Textes (+ trombone s'il y a une pièce jointe)
		text({ Position = UDim2.fromOffset(58, 26), Size = UDim2.new(1, -90, 0, 16), Font = Theme.Fonts.Title, Text = email.Sender, TextSize = 14, TextTruncate = Enum.TextTruncate.AtEnd, ZIndex = 33, Parent = body })
		if email.Attachment then
			text({ AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -10, 0, 26), Size = UDim2.fromOffset(18, 16), Text = "📎", TextSize = 13, TextXAlignment = Enum.TextXAlignment.Right, ZIndex = 33, Parent = body })
		end
		text({ Position = UDim2.fromOffset(58, 42), Size = UDim2.new(1, -68, 0, 15), Font = Theme.Fonts.Title, Text = email.Subject, TextColor3 = Color3.fromRGB(50, 56, 72), TextSize = 12, TextTruncate = Enum.TextTruncate.AtEnd, ZIndex = 33, Parent = body })
		text({ Position = UDim2.fromOffset(58, 57), Size = UDim2.new(1, -68, 0, 14), Text = email.Body, TextColor3 = inkDim, TextSize = 11, TextTruncate = Enum.TextTruncate.AtEnd, ZIndex = 33, Parent = body })

		-- Barre de temps restant (en bas)
		local lifeBack = frame({ AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 58, 1, -7), Size = UDim2.new(1, -70, 0, 3), BackgroundColor3 = Color3.fromRGB(222, 226, 236), ZIndex = 33, Parent = body })
		UIUtil.Corner(lifeBack, UDim.new(1, 0))
		local lifeBar = frame({ Size = UDim2.fromScale(1, 1), BackgroundColor3 = tagColor, ZIndex = 34, Parent = lifeBack })
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
			envelope.Email.Read = true
			removeEnvelope(envelope, true)
			local mail = envelope.Email
			task.delay(0.14, function()
				if ctx.IsAlive() then
					openMail(mail, envelope.X, envelope.Y, position)
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
				envelope.LifeBar.Size = UDim2.fromScale(math.clamp(left / envelope.Lifetime, 0, 1), 1)
				if left < HURRY_TIME then
					-- Pressée : elle s'agite, étiquette "Vite !" rouge
					if not envelope.Hurry then
						envelope.Hurry = true
						local label = envelope.Chip:FindFirstChild("Label")
						if label and label:IsA("TextLabel") then
							label.Text = Locale.T("⏰ QUICK, READ ME!")
						end
						envelope.Chip.BackgroundColor3 = red
						envelope.LifeBar.BackgroundColor3 = red
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
