--[[
	Config (ModuleScript)
	Emplacement : ReplicatedStorage > Shared > Config

	TOUTE la configuration du jeu est ici : améliorations (et ce qu'elles
	débloquent à l'écran), succès, quêtes, événements, bourse, casino,
	coffres, objets cosmétiques, sons... Modifie les valeurs librement.

	Principe du jeu (style "Stimulation Clicker") : l'écran commence tout
	simple (un bouton, un compteur). Chaque amélioration achetée ajoute
	quelque chose à l'écran (logo DVD, fil d'actu, coureur, presse...),
	jusqu'à la surcharge totale. Puis on peut "Aller à l'océan" (rebirth).

	Ce module est lu par le serveur ET par le client. Le serveur reste la
	seule source de vérité : modifier ce fichier côté client ne change rien.

	Langue : tous les textes affichés (Name, Description, Text...) sont en
	ANGLAIS ici. Leur traduction française est dans Shared > Lang > FR_Config
	(clé = texte anglais exact). Si tu changes un texte ici, change aussi sa
	clé dans FR_Config. Le client les affiche avec Locale.T(upgrade.Name).
]]

local Config = {}

----------------------------------------------------------------------
-- Réglages généraux
----------------------------------------------------------------------
Config.Game = {
	CurrencyName = "Dopamine",
	MaxClicksPerSecond = 20, -- anti-triche : au-delà, les clics sont ignorés
	PassiveTickRate = 0.25, -- intervalle (s) entre deux ajouts de gains passifs
	SyncRate = 0.2, -- intervalle (s) entre deux envois de l'état au client
	MaxDopamine = 1e300, -- plafond de sécurité (évite l'infini)
}

----------------------------------------------------------------------
-- Combo (débloqué par l'amélioration "Combo") : cliquer vite remplit une
-- jauge 0-100 qui multiplie les clics.
----------------------------------------------------------------------
Config.Combo = {
	GainPerClick = 5, -- points de jauge gagnés par clic
	DecayPerSecond = 15, -- points perdus par seconde (il faut > 3 clics/s pour monter)
	MaxMultiplier = 3, -- multiplicateur quand la jauge est pleine
}

----------------------------------------------------------------------
-- Barre d'améliorations (sous le compteur)
----------------------------------------------------------------------
Config.UpgradeBar = {
	RevealAhead = 5, -- nombre d'améliorations PAS ENCORE achetées visibles en avance
}

----------------------------------------------------------------------
-- Améliorations
--
--   Id          : identifiant unique (ne pas changer après publication)
--   Name, Icon  : nom et emoji affichés sur la carte
--   Description : texte de l'infobulle ; "%s" est remplacé par Value formatée
--   Cost        : prix du niveau 1 ; CostGrowth : prix x CostGrowth à chaque niveau
--   MaxLevel    : niveau maximum (1 = achat unique ; nil = infini)
--   Effect      : "Click"            +Value Dopamine par clic (par niveau)
--                 "PerSecond"        +Value Dopamine par seconde (par niveau)
--                 "DVD"              +1 logo DVD rebondissant (par niveau)
--                 "BounceMultiplier" gain par rebond x Value (par niveau)
--                 "ClickMultiplier"  gain par clic x Value (par niveau)
--                 "Multiplier"       TOUS les gains x Value (par niveau)
--                 "Feature"          aucun effet économique, débloque juste Feature
--                 "Detox"            "Aller à l'océan" = rebirth (prix : Config.Rebirth)
--                 "Offline"          améliore la Dopamine hors-ligne (voir Config.Offline)
--   Feature     : ce que l'amélioration fait apparaître à l'écran / débloque
--                 (nom d'un module client dans Client > Stimuli, ou d'un menu)
--   Permanent   : true = conservée après "Aller à l'océan" (menus utiles)
--   Requires    : Id d'une amélioration qu'il faut déjà posséder (améliorations
--                 "d'un carré" : chaussures du runner, vinyles du lofi...)
--   RequiresRebirths : nombre de visites à l'océan nécessaires (nouveautés
--                 débloquées en progressant ; cachées avant)
--   Color       : couleur de la carte en mode "Icônes HD"
--
-- Équilibrage (v9.3, simulé par tests/economy_sim.luau : 6 clics/s, combo,
-- bonus attrapés, achats les plus rentables) : les 5 premières minutes
-- restent rapides (achats toutes les quelques secondes), puis chaque carte
-- coûte environ 1 à 3 min de gains ; les prix des cartes non permanentes sont
-- multipliés après chaque visite à l'océan (voir Config.Rebirth). Les
-- nouveautés RequiresRebirths (1, 2, 3, 5, 8 visites) s'achètent pendant la
-- partie où elles apparaissent. Arcade, machine chanceuse, parterres (1 visite)
-- et coffre mystère (2 visites) ne sont plus là dès le début.
----------------------------------------------------------------------
Config.Upgrades = {
	{ Id = "Finger", Name = "Buff Finger", Icon = "👆", Description = "+%s Dopamine per click",
		Cost = 10, CostGrowth = 2.2, MaxLevel = 15, Effect = "Click", Feature = "Finger", Value = 1,
		Color = Color3.fromRGB(255, 196, 0) },
	{ Id = "DVD", Name = "DVD Logo", Icon = "📀", Description = "A bouncing logo. +%s Dopamine per bounce",
		Cost = 110, CostGrowth = 2.6, MaxLevel = 5, Effect = "DVD", Value = 1, Feature = "DVD",
		Color = Color3.fromRGB(40, 40, 40) },
	{ Id = "NewsTicker", Name = "News Ticker", Icon = "📰", Description = "Absurd news, nonstop. +%s Dopamine/s",
		Cost = 450, MaxLevel = 1, Effect = "PerSecond", Value = 8, Feature = "NewsTicker",
		Color = Color3.fromRGB(230, 30, 40) },
	{ Id = "DailyGift", Name = "Calendar", Icon = "📅", Description = "Unlocks the daily gift (kept forever)",
		Cost = 1200, MaxLevel = 1, Effect = "Feature", Feature = "Daily", Permanent = true,
		Color = Color3.fromRGB(255, 90, 150) },
	{ Id = "DVDSound", Name = "DVD Noise", Icon = "🔊", Description = "Every bounce makes noise. Bounces x%s",
		Cost = 3500, MaxLevel = 1, Effect = "BounceMultiplier", Value = 3, Feature = "DVDSound",
		Color = Color3.fromRGB(0, 170, 255) },
	{ Id = "Runner", Name = "Endless Runner", Icon = "🏃", Description = "A runner game on an endless loop. +%s Dopamine/s",
		Cost = 5500, MaxLevel = 1, Effect = "PerSecond", Value = 25, Feature = "Runner",
		Color = Color3.fromRGB(255, 120, 0) },
	{ Id = "Megaphone", Name = "Megaphone", Icon = "📢", Description = "EVERYTHING IN CAPS!!! Clicks x%s",
		Cost = 6000, MaxLevel = 1, Effect = "ClickMultiplier", Value = 2, Feature = "Megaphone",
		Color = Color3.fromRGB(220, 20, 20) },
	{ Id = "Keyboard", Name = "Mechanical Keyboard", Icon = "⌨️", Description = "Clicky keys. +%s Dopamine per click",
		Cost = 9000, CostGrowth = 2, MaxLevel = 12, Effect = "Click", Feature = "Keyboard", Value = 12,
		Color = Color3.fromRGB(90, 90, 110) },
	{ Id = "Lofi", Name = "Lofi Beats", Icon = "🎧", Description = "Beats to relax/study to. +%s Dopamine/s",
		Cost = 9000, MaxLevel = 1, Effect = "PerSecond", Value = 150, Feature = "Lofi",
		Color = Color3.fromRGB(120, 90, 200) },
	{ Id = "RunnerShoes", Name = "Running Shoes", Icon = "👟", Description = "The runner goes faster. +%s Dopamine/s",
		Cost = 10000, CostGrowth = 1.8, MaxLevel = 10, Effect = "PerSecond", Value = 150, Requires = "Runner",
		Color = Color3.fromRGB(255, 90, 60) },
	{ Id = "Press", Name = "Hydraulic Press", Icon = "🗜️", Description = "Crushes stuff. Every level upgrades the press (wood, steel, gold, diamond...). +%s Dopamine/s",
		Cost = 12000, CostGrowth = 1.75, MaxLevel = 10, Effect = "PerSecond", Value = 150, Feature = "Press",
		Color = Color3.fromRGB(255, 200, 0) },
	{ Id = "Achievements", Name = "Achievements", Icon = "🏆", Description = "Unlocks the achievements menu (kept forever)",
		Cost = 15000, MaxLevel = 1, Effect = "Feature", Feature = "Achievements", Permanent = true,
		Color = Color3.fromRGB(150, 60, 220) },
	{ Id = "Pinwheel", Name = "Pinwheel", Icon = "🌀", Description = "It spins. Blow on it! +%s Dopamine/s",
		Cost = 18000, MaxLevel = 1, Effect = "PerSecond", Value = 90, Feature = "Pinwheel",
		Color = Color3.fromRGB(80, 200, 255) },
	{ Id = "SleepMode", Name = "Sleep Mode", Icon = "😴", Description = "Earn more Dopamine while you're away (kept forever)",
		Cost = 20000, CostGrowth = 3, MaxLevel = 5, Effect = "Offline", Feature = "SleepMode", Value = 1, Permanent = true,
		Color = Color3.fromRGB(90, 110, 200) },
	{ Id = "BubbleWrap", Name = "Bubble Wrap", Icon = "🔘", Description = "Pop the bubbles to earn Dopamine",
		Cost = 25000, MaxLevel = 1, Effect = "Feature", Feature = "BubbleWrap",
		Color = Color3.fromRGB(160, 220, 255) },
	{ Id = "Weather", Name = "Thunderstorm", Icon = "⛈️", Description = "Catch the lightning! +%s Dopamine/s",
		Cost = 30000, MaxLevel = 1, Effect = "PerSecond", Value = 120, Feature = "Weather",
		Color = Color3.fromRGB(30, 110, 200) },
	{ Id = "Vinyl", Name = "Vinyl Collection", Icon = "💿", Description = "More records for the lofi. +%s Dopamine/s",
		Cost = 35000, CostGrowth = 1.8, MaxLevel = 10, Effect = "PerSecond", Value = 250, Requires = "Lofi",
		Color = Color3.fromRGB(150, 110, 230) },
	{ Id = "ItemShop", Name = "Item Shop", Icon = "🧢", Description = "Hats for your button (kept forever)",
		Cost = 40000, MaxLevel = 1, Effect = "Feature", Feature = "ItemShop", Permanent = true,
		Color = Color3.fromRGB(60, 200, 60) },
	{ Id = "Garden", Name = "Dopamine Garden", Icon = "🌻", Description = "Grow flowers and harvest them for Dopamine",
		Cost = 150000, MaxLevel = 1, Effect = "Feature", Feature = "Garden",
		Color = Color3.fromRGB(90, 190, 90) },
	{ Id = "Boost", Name = "Green Arrow", Icon = "⬆️", Description = "Everything goes up. EVERYTHING. Earnings x%s",
		Cost = 180000, MaxLevel = 1, Effect = "Multiplier", Value = 2, Feature = "Boost",
		Color = Color3.fromRGB(40, 220, 60) },
	{ Id = "WindPower", Name = "Wind Power", Icon = "🌬️", Description = "The pinwheel spins faster. +%s Dopamine/s",
		Cost = 300000, CostGrowth = 1.8, MaxLevel = 10, Effect = "PerSecond", Value = 400, Requires = "Pinwheel",
		Color = Color3.fromRGB(120, 210, 255) },
	{ Id = "GardenPlots", Name = "Flower Beds", Icon = "🪴", Description = "One more flower bed in the garden",
		Cost = 400000, CostGrowth = 3, MaxLevel = 5, RequiresRebirths = 1, Effect = "Feature", Feature = "GardenPlots", Requires = "Garden",
		Color = Color3.fromRGB(120, 200, 100) },
	{ Id = "LiveStream", Name = "ASMR Stream", Icon = "🥪", Description = "Someone is eating live. +%s Dopamine/s",
		Cost = 400000, MaxLevel = 1, Effect = "PerSecond", Value = 500, Feature = "LiveStream",
		Color = Color3.fromRGB(240, 170, 90) },
	{ Id = "Butter", Name = "Crunchy Butter", Icon = "🧈", Description = "A stick of butter to bite into on stream. *CRUNCH*",
		Cost = 2e6, MaxLevel = 1, Effect = "Feature", Feature = "Butter",
		Color = Color3.fromRGB(255, 215, 90) },
	{ Id = "Followers", Name = "Followers", Icon = "👥", Description = "More viewers on the stream. +%s Dopamine/s",
		Cost = 2.5e6, CostGrowth = 1.6, MaxLevel = 15, Effect = "PerSecond", Value = 1500, Feature = "Followers",
		Color = Color3.fromRGB(255, 60, 100) },
	{ Id = "PhoneNotifs", Name = "Notifications", Icon = "🔔", Description = "Ding! Ding! Ding! +%s Dopamine/s",
		Cost = 3e6, MaxLevel = 1, Effect = "PerSecond", Value = 1200, Feature = "PhoneNotifs",
		Color = Color3.fromRGB(255, 70, 70) },
	{ Id = "Combo", Name = "Combo", Icon = "⚡", Description = "Click fast to multiply your clicks (up to x3)",
		Cost = 3.5e6, MaxLevel = 1, Effect = "Feature", Feature = "Combo",
		Color = Color3.fromRGB(255, 220, 0) },
	{ Id = "Email", Name = "Inbox", Icon = "📧", Description = "You have (a lot of) new messages",
		Cost = 6e6, MaxLevel = 1, Effect = "Feature", Feature = "Email",
		Color = Color3.fromRGB(0, 120, 255) },
	{ Id = "Mouse", Name = "Gaming Mouse", Icon = "🖱️", Description = "RGB = more clicks. +%s Dopamine per click",
		Cost = 7e6, CostGrowth = 2.1, MaxLevel = 10, Effect = "Click", Feature = "Mouse", Value = 150,
		Color = Color3.fromRGB(60, 200, 255) },
	{ Id = "Quests", Name = "Quests", Icon = "📜", Description = "Unlocks quests (kept forever)",
		Cost = 8e6, MaxLevel = 1, Effect = "Feature", Feature = "Quests", Permanent = true,
		Color = Color3.fromRGB(255, 140, 30) },
	{ Id = "Casino", Name = "Lucky Machine", Icon = "🎰", Description = "Free spins earned by playing. Win Dopamine!",
		Cost = 1.2e7, MaxLevel = 1, RequiresRebirths = 1, Effect = "Feature", Feature = "Casino",
		Color = Color3.fromRGB(200, 0, 60) },
	{ Id = "PressStart", Name = "Turbo Press", Icon = "⚙️", Description = "A START button to crush things yourself",
		Cost = 1.2e7, MaxLevel = 1, Effect = "Feature", Feature = "PressStart",
		Color = Color3.fromRGB(130, 130, 140) },
	{ Id = "LiveChat", Name = "Live Chat", Icon = "💬", Description = "The stream chat goes wild. Clicks x%s",
		Cost = 1.5e7, MaxLevel = 1, Effect = "ClickMultiplier", Value = 3, Feature = "LiveChat",
		Color = Color3.fromRGB(145, 70, 255) },
	{ Id = "StormChaser", Name = "Storm Chaser", Icon = "🌪️", Description = "Bigger storms, more lightning. +%s Dopamine/s",
		Cost = 1.8e7, CostGrowth = 1.9, MaxLevel = 8, Effect = "PerSecond", Value = 6000, Requires = "Weather",
		Color = Color3.fromRGB(70, 90, 160) },
	{ Id = "Minigames", Name = "Arcade", Icon = "🕹️", Description = "Mini-games and duels with the server (kept forever)",
		Cost = 2e7, MaxLevel = 1, RequiresRebirths = 1, Effect = "Feature", Feature = "Minigames", Permanent = true,
		Color = Color3.fromRGB(255, 70, 160) },
	{ Id = "ScreenTime", Name = "Screen Time", Icon = "📱", Description = "Find out how much time you've wasted here",
		Cost = 2e7, MaxLevel = 1, Effect = "Feature", Feature = "ScreenTime", Permanent = true,
		Color = Color3.fromRGB(45, 45, 50) },
	{ Id = "LootBox", Name = "Mystery Chest", Icon = "📦", Description = "A chest fills up over time. Open it!",
		Cost = 1.5e7, MaxLevel = 1, RequiresRebirths = 2, Effect = "Feature", Feature = "LootBox",
		Color = Color3.fromRGB(170, 110, 50) },
	{ Id = "EmojiRain", Name = "Emoji Rain", Icon = "😂", Description = "It's raining emojis. +%s Dopamine/s",
		Cost = 1.5e8, MaxLevel = 1, Effect = "PerSecond", Value = 15000, Feature = "EmojiRain",
		Color = Color3.fromRGB(255, 210, 60) },
	{ Id = "StreamStudio", Name = "Stream Studio", Icon = "🎙️", Description = "Pro mic, ring light, more viewers. +%s Dopamine/s",
		Cost = 1.8e8, CostGrowth = 1.8, MaxLevel = 10, Effect = "PerSecond", Value = 15000, Requires = "LiveStream",
		Color = Color3.fromRGB(255, 80, 120) },
	{ Id = "HDIcons", Name = "HD Icons", Icon = "✨", Description = "Super shiny icons. Earnings x%s",
		Cost = 2e8, MaxLevel = 1, Effect = "Multiplier", Value = 1.5, Feature = "HDIcons",
		Color = Color3.fromRGB(255, 120, 220) },
	{ Id = "GoldenStar", Name = "Golden Star", Icon = "🌟", Description = "Golden stars show up. Catch them!",
		Cost = 2.5e8, MaxLevel = 1, Effect = "Feature", Feature = "GoldenStar",
		Color = Color3.fromRGB(255, 190, 0) },
	{ Id = "MegaFinger", Name = "Mega Finger", Icon = "💪", Description = "+%s Dopamine per click",
		Cost = 3e8, CostGrowth = 2.1, MaxLevel = 10, Effect = "Click", Feature = "MegaFinger", Value = 1500,
		Color = Color3.fromRGB(255, 150, 60) },
	{ Id = "NeonMode", Name = "Neon Mode", Icon = "🌈", Description = "The screen goes full neon. Earnings x%s",
		Cost = 3.5e8, MaxLevel = 1, Effect = "Multiplier", Value = 2, Feature = "NeonMode",
		Color = Color3.fromRGB(157, 78, 221) },
	{ Id = "CursorTrail", Name = "Magic Trail", Icon = "💫", Description = "Your mouse leaves sparkles behind. Clicks x%s",
		Cost = 1e9, MaxLevel = 1, Effect = "ClickMultiplier", Value = 2, Feature = "CursorTrail",
		Color = Color3.fromRGB(255, 80, 200) },
	{ Id = "Disco", Name = "Disco Ball", Icon = "💃", Description = "It's party time! Earnings x%s",
		Cost = 1.5e9, MaxLevel = 1, Effect = "Multiplier", Value = 2, Feature = "Disco",
		Color = Color3.fromRGB(200, 60, 255) },
	-- 🌊 Débloquées par les visites à l'océan (RequiresRebirths)
	{ Id = "DeepFocus", Name = "Deep Focus", Icon = "🧘", Description = "Calm mind, big gains. +%s Dopamine/s",
		Cost = 3e8, CostGrowth = 1.7, MaxLevel = 10, Effect = "PerSecond", Feature = "DeepFocus", Value = 100000, RequiresRebirths = 1,
		Color = Color3.fromRGB(110, 200, 190) },
	{ Id = "Seashell", Name = "Seashell", Icon = "🐚", Description = "The sound of the sea. Earnings x%s",
		Cost = 6e8, MaxLevel = 1, Effect = "Multiplier", Feature = "Seashell", Value = 1.5, RequiresRebirths = 1,
		Color = Color3.fromRGB(255, 190, 170) },
	{ Id = "CoralKeys", Name = "Coral Keyboard", Icon = "🪸", Description = "+%s Dopamine per click",
		Cost = 1e9, CostGrowth = 1.9, MaxLevel = 10, Effect = "Click", Feature = "CoralKeys", Value = 5000, RequiresRebirths = 1,
		Color = Color3.fromRGB(255, 120, 130) },
	{ Id = "DreamMachine", Name = "Dream Machine", Icon = "💤", Description = "Earn while you dream. +%s Dopamine/s",
		Cost = 6e8, CostGrowth = 1.7, MaxLevel = 10, Effect = "PerSecond", Feature = "DreamMachine", Value = 400000, RequiresRebirths = 2,
		Color = Color3.fromRGB(150, 130, 230) },
	{ Id = "Aurora", Name = "Aurora", Icon = "🌌", Description = "The sky lights up. Earnings x%s",
		Cost = 1e9, MaxLevel = 1, Effect = "Multiplier", Feature = "Aurora", Value = 2, RequiresRebirths = 2,
		Color = Color3.fromRGB(80, 220, 180) },
	{ Id = "QuantumFinger", Name = "Quantum Finger", Icon = "⚛️", Description = "Clicks in several universes. +%s Dopamine per click",
		Cost = 1.5e9, CostGrowth = 1.9, MaxLevel = 10, Effect = "Click", Feature = "QuantumFinger", Value = 20000, RequiresRebirths = 3,
		Color = Color3.fromRGB(90, 160, 255) },
	{ Id = "NeuralLink", Name = "Neural Link", Icon = "🧠", Description = "Click with your mind. Clicks x%s",
		Cost = 2.5e9, MaxLevel = 1, Effect = "ClickMultiplier", Feature = "NeuralLink", Value = 3, RequiresRebirths = 3,
		Color = Color3.fromRGB(255, 120, 200) },
	{ Id = "TimeWarp", Name = "Time Warp", Icon = "⏳", Description = "Time flies. Earnings x%s",
		Cost = 3e9, MaxLevel = 1, Effect = "Multiplier", Feature = "TimeWarp", Value = 2, RequiresRebirths = 3,
		Color = Color3.fromRGB(230, 180, 90) },
	{ Id = "GalaxyStream", Name = "Galaxy Stream", Icon = "🌠", Description = "A river of stars. +%s Dopamine/s",
		Cost = 1e10, CostGrowth = 1.7, MaxLevel = 10, Effect = "PerSecond", Feature = "GalaxyStream", Value = 3e6, RequiresRebirths = 5,
		Color = Color3.fromRGB(120, 100, 230) },
	{ Id = "Singularity", Name = "Singularity", Icon = "🕳️", Description = "Everything falls in. Earnings x%s",
		Cost = 2e10, MaxLevel = 1, Effect = "Multiplier", Feature = "Singularity", Value = 3, RequiresRebirths = 5,
		Color = Color3.fromRGB(40, 30, 60) },
	{ Id = "InfiniteScroll", Name = "Infinite Scroll", Icon = "♾️", Description = "It never ends. +%s Dopamine/s",
		Cost = 8e10, CostGrowth = 1.7, MaxLevel = 10, Effect = "PerSecond", Feature = "InfiniteScroll", Value = 1e7, RequiresRebirths = 8,
		Color = Color3.fromRGB(255, 90, 90) },
	{ Id = "Multiverse", Name = "Multiverse", Icon = "🪐", Description = "Infinite you's, infinite clicks. Earnings x%s",
		Cost = 1.5e11, MaxLevel = 1, Effect = "Multiplier", Feature = "Multiverse", Value = 3, RequiresRebirths = 8,
		Color = Color3.fromRGB(200, 120, 255) },
	-- (v11, ECON11) 🌊 Fin de partie : une nouveauté toutes les 2 à 5 visites
	-- jusqu'à la 40e (l'encart « x nouveautés après l'océan » montre toujours
	-- le prochain objectif). Pas de Feature : rien à afficher, juste des gains.
	{ Id = "WhaleSong", Name = "Whale Song", Icon = "🐋", Description = "Deep, slow, powerful. Earnings x%s",
		Cost = 4e11, MaxLevel = 1, Effect = "Multiplier", Value = 2, RequiresRebirths = 10,
		Color = Color3.fromRGB(60, 110, 190) },
	{ Id = "PrivateIsland", Name = "Private Island", Icon = "🏝️", Description = "Your own island, your own rules. +%s Dopamine/s",
		Cost = 3e11, CostGrowth = 1.7, MaxLevel = 10, Effect = "PerSecond", Value = 4e7, RequiresRebirths = 12,
		Color = Color3.fromRGB(70, 200, 170) },
	{ Id = "SirenCall", Name = "Siren Call", Icon = "🧜", Description = "Irresistible. Clicks x%s",
		Cost = 1e12, MaxLevel = 1, Effect = "ClickMultiplier", Value = 3, RequiresRebirths = 15,
		Color = Color3.fromRGB(80, 210, 200) },
	{ Id = "Volcano", Name = "Underwater Volcano", Icon = "🌋", Description = "Pure geothermal Dopamine. +%s Dopamine/s",
		Cost = 1.2e12, CostGrowth = 1.7, MaxLevel = 10, Effect = "PerSecond", Value = 1.5e8, RequiresRebirths = 18,
		Color = Color3.fromRGB(230, 90, 40) },
	{ Id = "Trident", Name = "Golden Trident", Icon = "🔱", Description = "Ruler of the seven seas. Earnings x%s",
		Cost = 2e12, MaxLevel = 1, Effect = "Multiplier", Value = 2, RequiresRebirths = 20,
		Color = Color3.fromRGB(240, 190, 50) },
	{ Id = "SeaDragon", Name = "Sea Dragon", Icon = "🐉", Description = "An ancient friend from the deep. Earnings x%s",
		Cost = 3e12, MaxLevel = 1, Effect = "Multiplier", Value = 2, RequiresRebirths = 25,
		Color = Color3.fromRGB(40, 170, 120) },
	{ Id = "BluePlanet", Name = "Blue Planet", Icon = "🌍", Description = "The whole ocean is on your side. Earnings x%s",
		Cost = 4e12, MaxLevel = 1, Effect = "Multiplier", Value = 2, RequiresRebirths = 30,
		Color = Color3.fromRGB(40, 120, 230) },
	{ Id = "MidnightSun", Name = "Midnight Sun", Icon = "🌅", Description = "It never sets. Earnings x%s",
		Cost = 5e12, MaxLevel = 1, Effect = "Multiplier", Value = 2, RequiresRebirths = 35,
		Color = Color3.fromRGB(255, 150, 60) },
	{ Id = "Nirvana", Name = "Nirvana", Icon = "🪷", Description = "Perfect calm. Everything flows. Earnings x%s",
		Cost = 6e12, MaxLevel = 1, Effect = "Multiplier", Value = 2.5, RequiresRebirths = 40,
		Color = Color3.fromRGB(240, 130, 190) },
	{ Id = "Ocean", Name = "Go to the Ocean", Icon = "🌊", Description = "Let it all go and breathe. Start over with x%s earnings forever (your 🏠 house is kept)",
		Cost = 0, MaxLevel = nil, Effect = "Detox", Feature = nil,
		Color = Color3.fromRGB(0, 140, 200) },
}

----------------------------------------------------------------------
-- Rebirth ("Aller à l'océan")
----------------------------------------------------------------------
-- (v9.3) Réglé avec le simulateur tests/economy_sim.luau (python3 tests/run_tests.py
-- --sim) : joueur actif sans Robux -> R1 ~1 h, R2 ~1 h 05, R3 ~1 h 30, R5 ~1 h 50,
-- R8+ ~2 h 30 ; chaque partie dure au moins autant que la précédente (voir
-- docs/ECONOMIE.md). Avant : R1 en 35 min, puis 1 à 3 min par visite.
--   Prix de la visite n°r+1 : BaseCost x CostGrowth^r x (1 + r)^CostPower
--   Prix des améliorations NON permanentes après r visites :
--     prix x PriceGrowth^r x (1 + r)^PricePower (x3,2 après 1 visite, x6,5
--     après 2, x10,6 après 3, x21 après 5, x42 après 8)
--   Multiplicateur permanent : +MultiplierPerRebirth par visite (x
--     MultiplierDecay à chaque visite suivante : 1 = linéaire)
--
-- (v11, ECON11) « À partir de la 20e visite les chiffres sont beaucoup trop
-- grands (Sx) et c'est beaucoup trop long » : avant, le prix de l'océan
-- prenait x3,5 x (1 + r)^1,55 à chaque visite (1,1 Sx à la 20e) alors que le
-- multiplicateur ne gagnait que +0,5 ; une fois toutes les cartes achetées
-- il ne restait qu'à attendre : R14 = 8 h, R16 = 68 h, R18 = 860 h de jeu.
-- Les visites 1 à 10 ne changent PAS. Ensuite (r > LateFrom visites) :
--   prix de l'océan            x LateCostGrowth par visite (1,6 Qa à la 11e,
--                                6,4 Qa à la 20e, ~100 Qa à la 40e)
--   prix des améliorations      x LatePriceGrowth par visite
--   multiplicateur permanent   x LateMultiplierGrowth par visite (x6 après
--                                10 visites, ~x24 après 20, ~x400 après 40)
-- + de nouvelles cartes tous les 2 à 5 visites (RequiresRebirths 10 à 40)
-- et des 💎 diamants à chaque visite à partir de la 10e (Diamonds).
-- Parties simulées (joueur actif, sans Robux) : R11 à R40 entre 1 h 30 et
-- 2 h 40, de plus en plus courtes (on se sent plus fort) ; R40 en ~80 h de
-- jeu actif au lieu de jamais. Tout dépend seulement de data.Rebirths :
-- aucune sauvegarde à migrer, et prix / multiplicateur n'est jamais pire
-- qu'avant (testé) : personne ne perd rien.
----------------------------------------------------------------------
Config.Rebirth = {
	BaseCost = 5e8, -- prix de la 1re visite à l'océan
	CostGrowth = 3.5, -- chaque visite coûte x3,5 de plus...
	CostPower = 1.55, -- ... et encore x(1 + r)^1,55 en plus
	PriceGrowth = 1, -- (améliorations) x1 par visite...
	PricePower = 1.7, -- ... x(1 + r)^1,7 : les améliorations coûtent plus cher à chaque visite
	MultiplierPerRebirth = 0.5, -- +50 % de gains permanents par visite
	MultiplierDecay = 1, -- (1 = toujours +50 %)
	-- (v11) Fin de partie : après LateFrom visites, tout grandit en proportion
	LateFrom = 10,
	LateCostGrowth = 1.15, -- océan : x1,15 par visite (avant : ~x4,4)
	LatePriceGrowth = 1.13, -- améliorations : x1,13 par visite
	LateMultiplierGrowth = 1.15, -- gains permanents : x1,15 par visite (= +15 %, avant +0,5 sur x6 = +8 %)
	-- 💎 Diamants offerts à chaque visite à partir de la From-ième (BankService) :
	-- Base + 1 par PerVisits visites de plus, au plus Max
	Diamonds = { From = 10, Base = 10, PerVisits = 2, Max = 30 },
}

----------------------------------------------------------------------
-- Récompenses "à l'échelle" : beaucoup de récompenses valent
-- "X secondes de production" pour rester intéressantes à tous les stades.
-- Production estimée = Dopamine/s + (Dopamine/clic * EstimatedClicksPerSecond)
----------------------------------------------------------------------
Config.Rewards = {
	EstimatedClicksPerSecond = 3,
}

-- (v9.3) +1 % au lieu de +2 % : avec ~36 succès et ~40 objets, le bonus
-- restait trop fort dès la 1re partie (x1,7 et x1,8 cumulés)
Config.AchievementBonus = 0.01 -- +1 % de gains permanents par succès débloqué
Config.CosmeticBonus = 0.01 -- +1 % de gains permanents par objet cosmétique possédé

----------------------------------------------------------------------
-- Succès (toujours comptés ; le menu apparaît avec l'amélioration "Succès")
--   Stat : statistique suivie (data.Stats[Stat] ou data[Stat], ex. Rebirths)
----------------------------------------------------------------------
Config.Achievements = {
	{ Id = "Clicks100", Name = "Hot Finger", Icon = "👆", Stat = "TotalClicks", Goal = 100, Reward = 50},
	{ Id = "Clicks1K", Name = "Click Addict", Icon = "🔥", Stat = "TotalClicks", Goal = 1000, Reward = 2500},
	{ Id = "Clicks10K", Name = "Tendinitis", Icon = "🩹", Stat = "TotalClicks", Goal = 10000, Reward = 200000},
	{ Id = "Clicks100K", Name = "Human Machine", Icon = "🦿", Stat = "TotalClicks", Goal = 100000, Reward = 1e7},
	{ Id = "Earn1K", Name = "First Hit", Icon = "💧", Stat = "LifetimeDopamine", Goal = 1000, Reward = 100},
	{ Id = "Earn1M", Name = "Happiness Millionaire", Icon = "💰", Stat = "LifetimeDopamine", Goal = 1e6, Reward = 75000},
	{ Id = "Earn1B", Name = "Neural Billionaire", Icon = "💎", Stat = "LifetimeDopamine", Goal = 1e9, Reward = 5e6},
	{ Id = "Earn1T", Name = "Galaxy Brain", Icon = "🪐", Stat = "LifetimeDopamine", Goal = 1e12, Reward = 1e10},
	{ Id = "Buy10", Name = "Shopping", Icon = "🛒", Stat = "UpgradesBought", Goal = 10, Reward = 250},
	{ Id = "Buy50", Name = "Shopaholic", Icon = "🛍️", Stat = "UpgradesBought", Goal = 50, Reward = 200000},
	{ Id = "Bounce100", Name = "Boing Boing", Icon = "📀", Stat = "Bounces", Goal = 100, Reward = 1500},
	{ Id = "Bounce5K", Name = "Hypnotized", Icon = "😵", Stat = "Bounces", Goal = 5000, Reward = 250000},
	{ Id = "Corner1", Name = "THE CORNER!!!", Icon = "📐", Stat = "DVDCorners", Goal = 1, Reward = 10000},
	{ Id = "Combo1", Name = "Max Combo!", Icon = "⚡", Stat = "CombosMaxed", Goal = 1, Reward = 150000},
	{ Id = "Bubble100", Name = "Pop pop pop", Icon = "🔘", Stat = "BubblesPopped", Goal = 100, Reward = 25000},
	{ Id = "Bubble1K", Name = "Out of Bubble Wrap", Icon = "📦", Stat = "BubblesPopped", Goal = 1000, Reward = 150000},
	{ Id = "Golden1", Name = "Golden Touch", Icon = "🌟", Stat = "GoldenClicks", Goal = 1, Reward = 1e6},
	{ Id = "Golden10", Name = "Gold Digger", Icon = "🏆", Stat = "GoldenClicks", Goal = 10, Reward = 2e6},
	{ Id = "Lightning5", Name = "Lightning Rod", Icon = "⚡", Stat = "LightningClicks", Goal = 5, Reward = 30000},
	{ Id = "Notif10", Name = "Always Online", Icon = "🔔", Stat = "NotifsOpened", Goal = 10, Reward = 175000},
	{ Id = "Email10", Name = "Inbox Zero", Icon = "📧", Stat = "EmailsRead", Goal = 10, Reward = 300000},
	{ Id = "Press25", Name = "Crusher", Icon = "🗜️", Stat = "PressCrushes", Goal = 25, Reward = 300000},
	{ Id = "Slot25", Name = "Weekend Gambler", Icon = "🎰", Stat = "SlotSpins", Goal = 25, Reward = 600000},
	{ Id = "SlotWin10", Name = "Lady Luck", Icon = "🍀", Stat = "SlotWins", Goal = 10, Reward = 1.5e6},
	{ Id = "Garden25", Name = "Green Thumb", Icon = "🌻", Stat = "GardenHarvests", Goal = 25, Reward = 150000},
	{ Id = "Arcade10", Name = "Arcade Champion", Icon = "🕹️", Stat = "MinigamesWon", Goal = 10, Reward = 1e6},
	{ Id = "Chest1", Name = "What's Inside?", Icon = "📦", Stat = "ChestsOpened", Goal = 1, Reward = 600000},
	{ Id = "Chest10", Name = "Collector", Icon = "🗝️", Stat = "ChestsOpened", Goal = 10, Reward = 5e6},
	{ Id = "Cosmetic1", Name = "Stylish", Icon = "🧢", Stat = "CosmeticsBought", Goal = 1, Reward = 25000},
	{ Id = "Cosmetic5", Name = "Fashion Week", Icon = "👑", Stat = "CosmeticsBought", Goal = 5, Reward = 100000},
	{ Id = "Quests5", Name = "Adventurer", Icon = "📜", Stat = "QuestsCompleted", Goal = 5, Reward = 200000},
	{ Id = "Daily3", Name = "Loyal", Icon = "📅", Stat = "DailyClaims", Goal = 3, Reward = 50000},
	{ Id = "Play1h", Name = "Just 5 More Minutes...", Icon = "⏰", Stat = "PlaySeconds", Goal = 3600, Reward = 2e6},
	{ Id = "Play10h", Name = "Go Touch Grass", Icon = "🌳", Stat = "PlaySeconds", Goal = 36000, Reward = 1e7},
	{ Id = "Rebirth1", Name = "Breath of Fresh Air", Icon = "🌊", Stat = "Rebirths", Goal = 1, Reward = 25000},
	-- (v9.3) 5e6 au lieu de 1e9 : donné juste après l'océan, 1e9 sautait tout le début de la partie
	{ Id = "Rebirth5", Name = "Total Zen", Icon = "🧘", Stat = "Rebirths", Goal = 5, Reward = 5e6},
}

----------------------------------------------------------------------
-- 🏅 Badges Roblox des succès
--   Crée un badge par succès sur create.roblox.com > ton expérience >
--   Engagement > Badges, puis colle son ID ici. 0 = pas de badge Roblox
--   (le succès reste visible dans le jeu). Exemple : Clicks100 = 1234567890,
----------------------------------------------------------------------
Config.AchievementBadges = {
	Clicks100 = 351594138014159,
	Clicks1K = 225887959881473,
	Clicks10K = 3805147960891653,
	Clicks100K = 657223704584845,
	Earn1K = 3266069398626666,
	Earn1M = 1525915832986676, -- 💰 Millionnaire du bonheur
	Earn1B = 2880052495031162, -- 💎 Milliardaire neuronal
	Earn1T = 3794921256154986, -- 🪐 Cerveau cosmique
	Buy10 = 3720175929508517, -- 🛒 Shopping
	Buy50 = 1330939500123022, -- 🛍️ Accro aux achats
	-- À venir (mets l'ID quand le badge est créé ; 0 = pas de badge Roblox)
	Bounce100 = 0, Bounce5K = 0,
	Corner1 = 0, Combo1 = 0, Bubble100 = 0, Bubble1K = 0, Golden1 = 0, Golden10 = 0,
	Lightning5 = 0, Notif10 = 0, Email10 = 0, Press25 = 0, Slot25 = 0, SlotWin10 = 0,
	Garden25 = 0, Arcade10 = 0, Chest1 = 0, Chest10 = 0, Cosmetic1 = 0, Cosmetic5 = 0, Quests5 = 0,
	Daily3 = 0, Play1h = 0, Play10h = 0, Rebirth1 = 0, Rebirth5 = 0,
}

----------------------------------------------------------------------
-- Quêtes (3 actives ; une quête finie est remplacée tout de suite)
--   Feature : la quête n'est proposée que si le joueur possède cette Feature
--   Goals : objectifs possibles ; GoalSeconds : objectif "Earn" en secondes de production
--   RewardSeconds / MinReward : récompense ; "%s" de Text = objectif
----------------------------------------------------------------------
Config.Quests = {
	ActiveCount = 3,
	Pool = {
		{ Type = "Clicks", Text = "Click %s times", Goals = { 50, 150, 300, 500 }, RewardSeconds = 15, MinReward = 100 },
		{ Type = "Earn", Text = "Earn %s Dopamine", GoalSeconds = { 120, 300, 600 }, MinGoal = 500, RewardSeconds = 20, MinReward = 150 },
		{ Type = "Buy", Text = "Buy %s upgrades", Goals = { 2, 3, 5 }, RewardSeconds = 30, MinReward = 100 },
		{ Type = "Bounces", Feature = "DVD", Text = "Bounce the DVD %s times", Goals = { 10, 25, 50 }, RewardSeconds = 15, MinReward = 100 },
		{ Type = "Bubbles", Feature = "BubbleWrap", Text = "Pop %s bubbles", Goals = { 30, 60, 100 }, RewardSeconds = 20, MinReward = 200 },
		{ Type = "Spawns", Feature = "PhoneNotifs", Text = "Click %s notifications, emails or lightning bolts", Goals = { 3, 5, 8 }, RewardSeconds = 30, MinReward = 300 },
		{ Type = "Combo", Feature = "Combo", Text = "Fill the combo meter %s times", Goals = { 1, 2, 3 }, RewardSeconds = 30, MinReward = 300 },
		{ Type = "Casino", Feature = "Casino", Text = "Spin the lucky machine %s times", Goals = { 2, 3, 5 }, RewardSeconds = 20, MinReward = 300 },
		{ Type = "Harvest", Feature = "Garden", Text = "Harvest %s flowers", Goals = { 3, 5, 10 }, RewardSeconds = 25, MinReward = 300 },
		{ Type = "Chests", Feature = "LootBox", Text = "Open %s chest(s)", Goals = { 1, 2 }, RewardSeconds = 30, MinReward = 500 },
	},
}

----------------------------------------------------------------------
-- Récompense quotidienne (jour UTC) — débloquée par "Calendrier"
----------------------------------------------------------------------
Config.Daily = {
	BaseRewardSeconds = 120,
	StreakBonusSeconds = 60,
	MaxStreakBonus = 7,
	MinReward = 250,
}

----------------------------------------------------------------------
-- Dopamine Rush : x2 sur tous les gains, pour TOUT le serveur
----------------------------------------------------------------------
Config.Events = {
	Rush = {
		Name = "DOPAMINE RUSH",
		Multiplier = 2,
		Duration = 30,
		MinInterval = 150,
		MaxInterval = 300,
	},
	StudioSpeedup = 5, -- dans Studio, les événements arrivent X fois plus vite
}

----------------------------------------------------------------------
-- Objets qui apparaissent et qu'il faut cliquer vite (validés par le serveur)
--   Feature : n'apparaissent que si le joueur possède cette Feature
--   Stat : statistique incrémentée à chaque clic réussi
----------------------------------------------------------------------
Config.Spawners = {
	Golden = { Feature = "GoldenStar", MinInterval = 40, MaxInterval = 90, Lifetime = 6, RewardSeconds = 30, MinReward = 300, Stat = "GoldenClicks" },
	Lightning = { Feature = "Weather", MinInterval = 15, MaxInterval = 35, Lifetime = 2.5, RewardSeconds = 8, MinReward = 50, Stat = "LightningClicks" },
	Notif = { Feature = "PhoneNotifs", MinInterval = 8, MaxInterval = 20, Lifetime = 6, RewardSeconds = 3, MinReward = 20, Stat = "NotifsOpened" },
	Donation = { Feature = "LiveStream", RequiresFollow = true, MinInterval = 25, MaxInterval = 50, Lifetime = 10, RewardSeconds = 10, MinReward = 30, Stat = "Donations" },
	Email = { Feature = "Email", MinInterval = 20, MaxInterval = 45, Lifetime = 15, RewardSeconds = 8, MinReward = 50, Stat = "EmailsRead" },
}
Config.MaxPendingSpawnsPerKind = 3

----------------------------------------------------------------------
-- Interactions "satisfaisantes" (RemoteEvent Interact)
--   MaxPerSecond : limite (seau de jetons) ; Cooldown : temps entre 2 récompenses
--   ClickFraction : récompense = gain par clic x ClickFraction
--   RewardSeconds / MinReward : récompense = X secondes de production
----------------------------------------------------------------------
Config.Interactions = {
	Bubble = { Feature = "BubbleWrap", MaxPerSecond = 12, ClickFraction = 0.5, Stat = "BubblesPopped" },
	Spin = { Feature = "Pinwheel", Cooldown = 2, RewardSeconds = 0.5, MinReward = 5, Stat = "Spins" },
	Headline = { Feature = "NewsTicker", Cooldown = 8, RewardSeconds = 2, MinReward = 5, Stat = "HeadlinesClicked" },
	Follow = { Feature = "LiveStream", OneTime = true, RewardSeconds = 30, MinReward = 100, Stat = "Follows" },
	Butter = { Feature = "Butter", MaxPerSecond = 8, ClickFraction = 3, Stat = "ButterCrunches" },
	Press = { Feature = "PressStart", Cooldown = 3, RewardSeconds = 1, MinReward = 20, Stat = "PressCrushes" },
}

----------------------------------------------------------------------
-- Logo DVD (plusieurs logos : un par niveau de l'amélioration "Logo DVD")
--   Positions "normalisées" (0 à 1 = largeur/hauteur de l'écran).
----------------------------------------------------------------------
Config.DVD = {
	Speed = 0.16, -- fraction de l'écran parcourue par seconde
	SpeedVariation = 0.25, -- chaque logo va +/- 25 % plus vite
	LogoSize = Vector2.new(150, 80), -- taille en pixels "design" (1280x720)
	LogoImage = "", -- "rbxassetid://..." (image BLANCHE) ou vide = logo dessiné en code
	BaseBounceValue = 2, -- Dopamine par rebond (avant multiplicateurs)
	MaxBouncesPerTick = 20, -- sécurité anti-abus par logo et par tick serveur
	CornerTolerance = 0.002,
	ClickCooldown = 6,
	ClickRewardSeconds = 3,
	ClickMinReward = 5,
	JackpotRewardSeconds = 60,
	JackpotMinReward = 500,
	Colors = {
		Color3.fromRGB(255, 46, 136),
		Color3.fromRGB(0, 200, 255),
		Color3.fromRGB(157, 78, 221),
		Color3.fromRGB(40, 200, 40),
		Color3.fromRGB(255, 190, 0),
		Color3.fromRGB(255, 110, 20),
	},
}

----------------------------------------------------------------------
-- Ancienne bourse (retirée) : les actions encore détenues sont remboursées
-- une fois à StartPrice l'unité (voir GameService). Gardé pour ce calcul.
----------------------------------------------------------------------
Config.Stocks = {
	Feature = "Stocks",
	Symbol = "DOPA",
	StartPrice = 100,
	Volatility = 0.03, -- variation aléatoire par mise à jour (3 %)
	MeanReversion = 0.002, -- tendance (faible) à revenir vers StartPrice : trop forte, elle rend le cours prévisible
	Fee = 0.05, -- frais prélevés à l'achat ET à la vente (5 %) : empêche l'achat/vente en boucle
	MinPrice = 5,
	MaxPrice = 2000,
	UpdateInterval = 1, -- secondes
	HistoryLength = 60, -- points affichés sur le graphique
	Fractions = { 0.1, 0.25, 0.5, 1 }, -- part de sa Dopamine qu'on peut investir
	TradeCooldown = 0.5,
}

----------------------------------------------------------------------
-- 🎰 Machine chanceuse : des TOURS GRATUITS (jetons gagnés en jouant,
-- jamais achetables). On ne mise rien : aucun pari avec une monnaie qui
-- s'achète en Robux (règles Roblox sur les jeux d'argent).
--   Un jeton toutes les TokenInterval secondes de jeu (max MaxTokens).
--   Gains en "secondes de production" (Pair = 2 symboles, Triple = 3).
----------------------------------------------------------------------
Config.Casino = {
	Enabled = true,
	Feature = "Casino",
	TokenInterval = 300, -- secondes de jeu par jeton (1 toutes les 5 min)
	MaxTokens = 10,
	StartTokens = 3, -- jetons offerts quand on débloque la machine
	Cooldown = 1.5,
	MissRewardSeconds = 3, -- petit lot de consolation si rien ne sort
	MinReward = 50,
	Symbols = {
		-- v9 : 1 jeton toutes les 5 min, donc chaque tour rapporte un peu plus
		{ Id = "Cherry", Icon = "🍒", Weight = 30, Pair = 12, Triple = 90 },
		{ Id = "Lemon", Icon = "🍋", Weight = 25, Pair = 15, Triple = 135 },
		{ Id = "Bell", Icon = "🔔", Weight = 20, Pair = 18, Triple = 180 },
		{ Id = "Diamond", Icon = "💎", Weight = 12, Pair = 27, Triple = 360 },
		{ Id = "Seven", Icon = "7️⃣", Weight = 8, Pair = 38, Triple = 720 },
		{ Id = "Brain", Icon = "🧠", Weight = 5, Pair = 60, Triple = 1800 },
	},
}

----------------------------------------------------------------------
-- 🌻 Jardin de Dopamine (remplace la bourse) : des fleurs poussent dans
-- des parterres ; on les cueille une fois écloses (gain = secondes de production)
--   Plots = parterres de base (+1 par niveau de "Flower Beds")
----------------------------------------------------------------------
Config.Garden = {
	Feature = "Garden",
	BasePlots = 3,
	HarvestCooldown = 0.3,
	Flowers = {
		-- v9 : pousse plus lente (x2), récolte un peu plus grosse
		-- v9.3 : récolte / 2 (8 parterres rapportaient 2,5x la production à eux seuls)
		{ Id = "Daisy", Name = "Daisy", Icon = "🌼", GrowSeconds = 60, RewardSeconds = 10, Weight = 40 },
		{ Id = "Tulip", Name = "Tulip", Icon = "🌷", GrowSeconds = 120, RewardSeconds = 23, Weight = 30 },
		{ Id = "Rose", Name = "Rose", Icon = "🌹", GrowSeconds = 240, RewardSeconds = 50, Weight = 18 },
		{ Id = "Sunflower", Name = "Sunflower", Icon = "🌻", GrowSeconds = 480, RewardSeconds = 120, Weight = 9 },
		{ Id = "Lotus", Name = "Golden Lotus", Icon = "🪷", GrowSeconds = 840, RewardSeconds = 260, Weight = 3 },
	},
	MinReward = 30,
	-- v9.8 (GARDEN98) 🌷 jardin de la maison en ville, aménagé LIBREMENT (mode
	-- édition du jardin : GardenEdit ; données data.Garden.Level / Pieces / Layout,
	-- vérifiées par GardenService, règles partagées : Shared/GardenSnapshot).
	-- Agrandissements achetés avec la Dopamine (niveau 0 = de base) : zone
	-- utilisable plus grande (dans la parcelle), plus de places de déco
	-- (Config.House.GardenSlots au niveau 0), plus d'objets de jardin posés
	-- et un aménagement offert (Bonus).
	BasePieces = 8, -- objets de jardin posés au niveau 0
	Expansion = {
		{ Level = 1, Name = "Blooming garden", Icon = "🌸", Cost = 5e5, DecorSlots = 8, Pieces = 16, Bonus = "RoseArch" },
		{ Level = 2, Name = "Big garden", Icon = "🌳", Cost = 5e7, RequiresRebirths = 1, DecorSlots = 10, Pieces = 26, Bonus = "Greenhouse" },
		{ Level = 3, Name = "Dream park", Icon = "🏞️", Cost = 5e9, RequiresRebirths = 3, DecorSlots = 12, Pieces = 40, Bonus = "KoiPond" },
	},
	-- Objets de jardin (plusieurs exemplaires, jusqu'à Max) : achetés avec la
	-- Dopamine, rangés dans l'inventaire du jardin, posés où l'on veut.
	-- W x D = empreinte au sol (studs) ; Flat = plat (on marche / pose dessus).
	Pieces = {
		{ Id = "TerracottaPot", Name = "Terracotta flower pot", Icon = "🪴", Cost = 2500, W = 1.9, D = 1.9, Max = 20 },
		{ Id = "SteppingStones", Name = "Stepping stones", Icon = "🪨", Cost = 6000, W = 2.8, D = 7, Max = 12, Flat = true },
		{ Id = "FlowerUrn", Name = "Stone flower urn", Icon = "🏺", Cost = 12000, W = 2.4, D = 2.4, Max = 12 },
		{ Id = "RoseBush", Name = "Rose bush", Icon = "🌹", Cost = 15000, W = 2.8, D = 2.8, Max = 12 },
		{ Id = "GardenLantern", Name = "Garden lantern", Icon = "🏮", Cost = 20000, W = 1.3, D = 1.3, Max = 12 },
		{ Id = "LavenderPlanter", Name = "Lavender planter", Icon = "💜", Cost = 25000, W = 4.8, D = 1.9, Max = 10 },
		{ Id = "HydrangeaBush", Name = "Hydrangea bush", Icon = "💠", Cost = 30000, W = 3.3, D = 3.3, Max = 10 },
		{ Id = "BirdHouse", Name = "Birdhouse", Icon = "🐦", Cost = 35000, W = 1.5, D = 1.5, Max = 6 },
		{ Id = "HangingBasket", Name = "Hanging basket", Icon = "🧺", Cost = 40000, W = 1.8, D = 1.8, Max = 8 },
		{ Id = "RoundFlowerBed", Name = "Round flower bed", Icon = "🌺", Cost = 45000, W = 5.8, D = 5.8, Max = 6 },
		{ Id = "GardenBench", Name = "Wooden garden bench", Icon = "🪑", Cost = 60000, W = 5.6, D = 2.4, Max = 6 },
		{ Id = "VegetablePatch", Name = "Vegetable patch", Icon = "🥕", Cost = 80000, W = 6.4, D = 3.8, Max = 6 },
		{ Id = "PicnicTable", Name = "Picnic table", Icon = "🧺", Cost = 150000, W = 5.4, D = 5, Max = 4 },
		{ Id = "Sundial", Name = "Sundial", Icon = "☀️", Cost = 250000, W = 2.4, D = 2.4, Max = 3 },
		{ Id = "RoseArbor", Name = "Rose arbor", Icon = "🌸", Cost = 1.5e6, RequiresRebirths = 1, W = 5.4, D = 2.4, Max = 4 },
		{ Id = "GardenSwing", Name = "Garden swing", Icon = "🌼", Cost = 4e6, RequiresRebirths = 1, W = 5.8, D = 3.4, Max = 2 },
		{ Id = "StoneStatue", Name = "Stone angel statue", Icon = "🗿", Cost = 2e7, RequiresRebirths = 2, W = 3, D = 3, Max = 3 },
		{ Id = "Gazebo", Name = "White gazebo", Icon = "🛖", Cost = 8e7, RequiresRebirths = 3, W = 10.5, D = 10.5, Max = 1 },
		{ Id = "TieredFountain", Name = "Tiered fountain", Icon = "⛲", Cost = 3e8, RequiresRebirths = 3, W = 9.2, D = 9.2, Max = 2 },
	},
}

----------------------------------------------------------------------
-- Coffre mystère : se recharge avec le temps de jeu
----------------------------------------------------------------------
Config.LootBox = {
	Feature = "LootBox",
	ChargeInterval = 120, -- secondes de jeu pour gagner un coffre
	MaxStored = 5,
	OpenCooldown = 1,
	Tiers = {
		{ Id = "Common", Name = "Common", Weight = 60, RewardSeconds = 5, Color = Color3.fromRGB(150, 150, 150) },
		{ Id = "Rare", Name = "Rare", Weight = 25, RewardSeconds = 15, Color = Color3.fromRGB(30, 140, 255) },
		{ Id = "Epic", Name = "Epic", Weight = 12, RewardSeconds = 45, Color = Color3.fromRGB(170, 60, 255) },
		{ Id = "Legendary", Name = "LEGENDARY", Weight = 3, RewardSeconds = 200, Color = Color3.fromRGB(255, 180, 0) },
	},
}

----------------------------------------------------------------------
-- Boutique d'objets (cosmétiques du bouton, conservés pour toujours)
--   Slot "Hat"  : emoji posé au-dessus du bouton
--   Slot "Skin" : couleurs du bouton (dégradé Top -> Bottom)
----------------------------------------------------------------------
Config.Cosmetics = {
	-- (v9.3) Seuls 8 objets sont là dès le début ; les autres arrivent avec
	-- les visites à l'océan (RequiresRebirths = 1, 2, 3, 5, 8) et coûtent de
	-- plus en plus cher (prix d'origine x5 / x30 / x100 / x300 / x1000 / x3000)
	{ Id = "Cap", Name = "Red Cap", Icon = "🧢", Slot = "Hat", Cost = 100000},
	{ Id = "PartyHat", Name = "Party Hat", Icon = "🥳", Slot = "Hat", Cost = 400000},
	{ Id = "TopHat", Name = "Top Hat", Icon = "🎩", Slot = "Hat", Cost = 1e7, RequiresRebirths = 1},
	{ Id = "Headphones", Name = "Headphones", Icon = "🎧", Slot = "Hat", Cost = 2e7, RequiresRebirths = 1},
	{ Id = "Graduation", Name = "Graduation Cap", Icon = "🎓", Slot = "Hat", Cost = 2.5e8, RequiresRebirths = 2},
	{ Id = "Crown", Name = "Crown", Icon = "👑", Slot = "Hat", Cost = 6e8, RequiresRebirths = 2},
	{ Id = "Halo", Name = "Halo", Icon = "😇", Slot = "Hat", Cost = 1e10, RequiresRebirths = 3},
	{ Id = "Unicorn", Name = "Unicorn Horn", Icon = "🦄", Slot = "Hat", Cost = 2e11, RequiresRebirths = 5},
	{ Id = "Bow", Name = "Pink Bow", Icon = "🎀", Slot = "Hat", Cost = 3e7, RequiresRebirths = 1 },
	{ Id = "Wizard", Name = "Wizard Hat", Icon = "🧙", Slot = "Hat", Cost = 5e9, RequiresRebirths = 3 },
	{ Id = "Astronaut", Name = "Space Helmet", Icon = "🚀", Slot = "Hat", Cost = 2e10, RequiresRebirths = 3 },
	{ Id = "Tiara", Name = "Diamond Tiara", Icon = "💎", Slot = "Hat", Cost = 4e11, RequiresRebirths = 5 },
	{ Id = "Flame", Name = "Flame Crown", Icon = "🔥", Slot = "Hat", Cost = 1e13, RequiresRebirths = 8 },
	{ Id = "Planet", Name = "Tiny Planet", Icon = "🪐", Slot = "Hat", Cost = 1e14, RequiresRebirths = 8 },
	{ Id = "SkinMint", Name = "Mint Button", Icon = "🟩", Slot = "Skin", Cost = 200000,
		Top = Color3.fromRGB(210, 255, 225), Bottom = Color3.fromRGB(120, 220, 160) },
	{ Id = "SkinSky", Name = "Sky Button", Icon = "🟦", Slot = "Skin", Cost = 750000,
		Top = Color3.fromRGB(215, 240, 255), Bottom = Color3.fromRGB(110, 180, 255) },
	{ Id = "SkinCandy", Name = "Candy Button", Icon = "🍬", Slot = "Skin", Cost = 4e7, RequiresRebirths = 1,
		Top = Color3.fromRGB(255, 220, 240), Bottom = Color3.fromRGB(255, 110, 180) },
	{ Id = "SkinGold", Name = "Golden Button", Icon = "🟨", Slot = "Skin", Cost = 1.2e9, RequiresRebirths = 2,
		Top = Color3.fromRGB(255, 240, 160), Bottom = Color3.fromRGB(230, 160, 0) },
	{ Id = "SkinVoid", Name = "Void Button", Icon = "⬛", Slot = "Skin", Cost = 2.5e10, RequiresRebirths = 3,
		Top = Color3.fromRGB(70, 60, 90), Bottom = Color3.fromRGB(5, 5, 10) },
	{ Id = "SkinOcean", Name = "Ocean Button", Icon = "🌊", Slot = "Skin", Cost = 2e11, RequiresRebirths = 5,
		Top = Color3.fromRGB(190, 240, 255), Bottom = Color3.fromRGB(20, 130, 200) },
	{ Id = "SkinSakura", Name = "Sakura Button", Icon = "🌸", Slot = "Skin", Cost = 1.5e12, RequiresRebirths = 5,
		Top = Color3.fromRGB(255, 235, 245), Bottom = Color3.fromRGB(245, 150, 190) },
	{ Id = "SkinAurora", Name = "Aurora Button", Icon = "🌌", Slot = "Skin", Cost = 4e13, RequiresRebirths = 8,
		Top = Color3.fromRGB(150, 255, 210), Bottom = Color3.fromRGB(110, 60, 200) },
	{ Id = "SkinDiamond", Name = "Diamond Button", Icon = "💠", Slot = "Skin", Cost = 3e14, RequiresRebirths = 8,
		Top = Color3.fromRGB(240, 255, 255), Bottom = Color3.fromRGB(120, 200, 255) },
	-- v9.2 : chapeaux et boutons "cool" (dessinés par Client > Components >
	-- CosmeticArt ; Pattern = motif dessiné par-dessus le dégradé du bouton)
	{ Id = "Snapback", Name = "Backwards snapback", Icon = "🧢", Slot = "Hat", Cost = 250000 },
	{ Id = "NinjaBand", Name = "Ninja headband", Icon = "🥷", Slot = "Hat", Cost = 750000 },
	{ Id = "GamerHeadset", Name = "Gamer headset", Icon = "🎧", Slot = "Hat", Cost = 1.5e7, RequiresRebirths = 1 },
	{ Id = "PirateHat", Name = "Pirate hat", Icon = "🏴", Slot = "Hat", Cost = 2e8, RequiresRebirths = 2 },
	{ Id = "RacingHelmet", Name = "Racing helmet", Icon = "⛑️", Slot = "Hat", Cost = 2.5e9, RequiresRebirths = 3 },
	{ Id = "VikingHelmet", Name = "Viking helmet", Icon = "🛡️", Slot = "Hat", Cost = 5e10, RequiresRebirths = 5 },
	{ Id = "DinoHood", Name = "Dino hood", Icon = "🦖", Slot = "Hat", Cost = 2.5e11, RequiresRebirths = 5 },
	{ Id = "RobotVisor", Name = "Robot visor", Icon = "🤖", Slot = "Hat", Cost = 6e12, RequiresRebirths = 8 },
	{ Id = "SkinCarbon", Name = "Carbon Button", Icon = "⬛", Slot = "Skin", Cost = 300000, Pattern = "Carbon",
		Top = Color3.fromRGB(96, 100, 112), Bottom = Color3.fromRGB(34, 36, 44) },
	{ Id = "SkinCamo", Name = "Camo Button", Icon = "🌲", Slot = "Skin", Cost = 1.2e6, Pattern = "Camo",
		Top = Color3.fromRGB(160, 184, 120), Bottom = Color3.fromRGB(90, 116, 70) },
	{ Id = "SkinBasketball", Name = "Basketball Button", Icon = "🏀", Slot = "Skin", Cost = 2.5e7, RequiresRebirths = 1, Pattern = "Basketball",
		Top = Color3.fromRGB(255, 176, 90), Bottom = Color3.fromRGB(226, 110, 40) },
	{ Id = "SkinController", Name = "Controller Button", Icon = "🎮", Slot = "Skin", Cost = 4e8, RequiresRebirths = 2, Pattern = "Controller",
		Top = Color3.fromRGB(130, 130, 160), Bottom = Color3.fromRGB(60, 60, 90) },
	{ Id = "SkinFlames", Name = "Flames Button", Icon = "🔥", Slot = "Skin", Cost = 7.5e9, RequiresRebirths = 3, Pattern = "Flames",
		Top = Color3.fromRGB(70, 60, 80), Bottom = Color3.fromRGB(30, 24, 36) },
	{ Id = "SkinLava", Name = "Lava Button", Icon = "🌋", Slot = "Skin", Cost = 5e11, RequiresRebirths = 5, Pattern = "Lava",
		Top = Color3.fromRGB(90, 60, 60), Bottom = Color3.fromRGB(40, 24, 28) },
	{ Id = "SkinGalaxy", Name = "Galaxy Button", Icon = "🌠", Slot = "Skin", Cost = 1.2e13, RequiresRebirths = 8, Pattern = "Galaxy",
		Top = Color3.fromRGB(90, 70, 190), Bottom = Color3.fromRGB(20, 16, 60) },
	{ Id = "SkinCircuit", Name = "Neon Circuit Button", Icon = "💻", Slot = "Skin", Cost = 1e14, RequiresRebirths = 8, Pattern = "Circuit",
		Top = Color3.fromRGB(30, 60, 70), Bottom = Color3.fromRGB(8, 20, 30) },
}

----------------------------------------------------------------------
-- Temps d'écran
----------------------------------------------------------------------
Config.ScreenTime = {
	DaysKept = 7,
}

----------------------------------------------------------------------
-- Classement global (deux OrderedDataStore : Dopamine gagnée et renaissances)
----------------------------------------------------------------------
Config.Leaderboard = {
	StoreName = "DopamineLeaderboard_v2", -- Dopamine gagnée depuis toujours
	RebirthStoreName = "RebirthLeaderboard_v1", -- nombre de renaissances (visites à l'océan)
	UpdateInterval = 60, -- secondes entre deux lectures / écritures du top mondial
	Size = 10, -- nombre de joueurs dans chaque top mondial
	CrossLookupCacheTime = 300, -- secondes : garde la "valeur croisée" (renaissances d'un top Dopamine...)
}

----------------------------------------------------------------------
-- Sauvegarde
----------------------------------------------------------------------
Config.DataStore = {
	Name = "DopamineClickerData_v2", -- change le nom pour repartir de zéro
	AutoSaveInterval = 60,
	MaxRetries = 4,
}

----------------------------------------------------------------------
-- Sons : remplace par tes propres IDs ("rbxassetid://123456789").
-- Laisse "" pour désactiver un son.
-- Les "rbxasset://sounds/..." sont des sons intégrés à Roblox (toujours dispo).
----------------------------------------------------------------------
Config.Sounds = {
	Click = { Id = "rbxasset://sounds/clickfast.wav", Volume = 0.5 },
	Buy = { Id = "rbxasset://sounds/electronicpingshort.wav", Volume = 0.6 },
	Error = { Id = "rbxasset://sounds/clickfast.wav", Volume = 0.3 },
	Bounce = { Id = "rbxasset://sounds/clickfast.wav", Volume = 0.2 },
	Bonus = { Id = "rbxasset://sounds/electronicpingshort.wav", Volume = 0.6 },
	Achievement = { Id = "rbxasset://sounds/electronicpingshort.wav", Volume = 0.8 },
	Jackpot = { Id = "rbxasset://sounds/electronicpingshort.wav", Volume = 1 },
	Golden = { Id = "rbxasset://sounds/swoosh.wav", Volume = 0.6 },
	Rush = { Id = "rbxasset://sounds/swoosh.wav", Volume = 0.8 },
	Detox = { Id = "rbxasset://sounds/swoosh.wav", Volume = 1 },
	Open = { Id = "rbxasset://sounds/swoosh.wav", Volume = 0.3 },
	Pop = { Id = "rbxassetid://140323850218372", Volume = 0.6 },
	Crunch = { Id = "rbxassetid://119687340156238", Volume = 0.8 }, -- beurre croustillant
	Crush = { Id = "rbxasset://sounds/swoosh.wav", Volume = 0.5 },
	Thunder = { Id = "rbxasset://sounds/swoosh.wav", Volume = 0.7 },
	Notif = { Id = "rbxasset://sounds/electronicpingshort.wav", Volume = 0.4 },
	Mail = { Id = "rbxasset://sounds/electronicpingshort.wav", Volume = 0.4 },
	SlotSpin = { Id = "rbxasset://sounds/clickfast.wav", Volume = 0.3 },
	SlotWin = { Id = "rbxasset://sounds/electronicpingshort.wav", Volume = 0.9 },
	Chest = { Id = "rbxasset://sounds/swoosh.wav", Volume = 0.7 },
	Cash = { Id = "rbxasset://sounds/electronicpingshort.wav", Volume = 0.5 },
	Megaphone = { Id = "rbxasset://sounds/swoosh.wav", Volume = 0.4 },
}

----------------------------------------------------------------------
-- Musique lofi (jouée quand "Lofi Beats" est débloqué, réglable dans ⚙️)
--   Mets des IDs de musiques PUBLIQUES utilisables dans tous les jeux :
--   Studio > Boîte à outils (Toolbox) > Audio > cherche "lofi" / "chill",
--   filtre par créateur "Roblox" (musiques sous licence, gratuites), clic
--   droit > "Copier l'ID de l'élément", puis colle "rbxassetid://ID" ici.
--   Les pistes avec Id = "" sont ignorées.
----------------------------------------------------------------------
Config.Music = {
	DefaultVolume = 0.35,
	Shuffle = true,
	-- Key = identifiant sauvegardé (réglage "MusicTrack" : "Shuffle" = aléatoire, sinon une Key)
	Playlist = {
		{ Key = "Lofi1", Name = "Rainy Window", Id = "rbxassetid://105526677737534" },
		{ Key = "Lofi2", Name = "Late Night Study", Id = "rbxassetid://84166235077508" },
		{ Key = "Lofi3", Name = "Coffee & Clouds", Id = "rbxassetid://78354523278392" },
		{ Key = "Lofi4", Name = "Sleepy Cat", Id = "rbxassetid://73874153787004" },
		{ Key = "Lofi5", Name = "Pastel Sunset", Id = "rbxassetid://72831582143889" },
		{ Key = "Lofi6", Name = "Midnight Train", Id = "rbxassetid://114453445428505" },
		{ Key = "Lofi7", Name = "Cozy Blanket", Id = "rbxassetid://97124296300129" },
		{ Key = "Lofi8", Name = "Starry Lo-fi", Id = "rbxassetid://121078850554967" },
	},

}

----------------------------------------------------------------------
-- 🎵 Instruments de la SCÈNE MUSICALE de la place (v9.9 MUSIC99, v11 MUSIC11).
--   (v11) CHAQUE INSTRUMENT A SON PROPRE TIMBRE. Avant, tous les
--   instruments mélodiques jouaient le MÊME échantillon à la même hauteur
--   avec de légers effets : tout sonnait comme "le piano". Maintenant,
--   chaque instrument = un mélange de couches + sa propre chaîne d'effets
--   Roblox (MusicSynth) :
--     🎹 piano : fondamentale + harmoniques + petit "marteau", réverbération
--        de salle, les notes graves durent plus longtemps ;
--     🎸 guitare : saturation forte + "baffle" (aigus coupés) + médiator ;
--     🎸 basse : très grave + octave + attaque au doigt, compresseur ;
--     🎶 xylophone : lame de bois (harmonique à la douzième), très court ;
--     🎛️ synthé : 2 oscillateurs désaccordés + chorus, flanger, trémolo, écho,
--        notes tenues (impulsions répétées) ;
--     🥁 batterie : grosse caisse "808" (hauteur qui CHUTE), caisse claire
--        en bruit + corps, charleston très aigu filtré, cymbales longues,
--        toms qui "tombent" ; 🎧 DJ : scratch, corne, montée, drop.
--   Hauteur : PlaybackSpeed = 2^((note - BaseNote) / 12) (un demi-ton =
--   x1,0595 ; notes MIDI : Do central C4 = 60, La 440 Hz = A4 = 69).
--   Sons par défaut : UNIQUEMENT des sons INTÉGRÉS à Roblox
--   ("rbxasset://sounds/...", livrés avec chaque installation ; voir Samples).
--   Pour de VRAIS sons d'instruments :
--     Studio > Boîte à outils (Toolbox) > Audio, ou le Creator Store ;
--     cherche "piano note C4", "electric guitar note", "bass note",
--     "xylophone", "synth", "kick", "snare", "hi hat", "crash"... ; filtre par
--     créateur "Roblox" (sons sous licence, gratuits, utilisables dans tous
--     les jeux) ; écoute ; clic droit > "Copier l'ID de l'élément" ; colle
--     "rbxassetid://ID" dans SampleId ; mets dans BaseNote la note que joue
--     l'échantillon (souvent écrite dans son nom, ex. "C4" = 60) ; pour un
--     vrai échantillon, mets aussi Layers = { { 0, 1 } } et Attack = {} (le
--     son est déjà riche), MinSpeed = 0.25 et MaxSpeed = 4.
--   SampleId : un nom de Samples ("Ping"…) ou un identifiant complet.
--   Garde "" pour couper un instrument. Volume : 0..1 (multiplié par le
--   volume des effets du joueur, ⚙️). Decay : (s) le son s'éteint en fondu.
--   Layers : { demi-tons, volume, centièmes de demi-ton?, x Decay? } joués
--     ensemble (désaccord léger = son plus large).
--   Attack : bruits d'attaque sans hauteur { Sample, vitesse, volume, Decay }.
--   Pulse (synthé) : la note est rejouée Count fois toutes les Every s
--     (Fade = volume gardé à chaque fois) : son "tenu".
--   MinSpeed / MaxSpeed : hors de ces vitesses, la note est jouée une
--   octave plus haut / plus bas (même nom de note : l'harmonie reste juste).
--   Batterie / DJ : chaque pièce = une liste de couches
--   { Sample, vitesse, volume, Decay, Delay?, VitesseFinale?, DuréeGlissé? }
--   (VitesseFinale : la hauteur glisse vers elle = grosse caisse, toms).
----------------------------------------------------------------------
Config.Instruments = {
	Volume = 0.8, -- volume général de la scène
	RollOffMin = 16, -- (studs) son 3D : plein volume jusqu'ici…
	RollOffMax = 140, -- …silence au-delà (on n'entend la scène que de près)
	-- 📻 radio lofi (Config.Music.Playlist) sur les enceintes de la scène
	Radio = { Volume = 0.65, RollOffMin = 18, RollOffMax = 120 },
	-- sons intégrés à Roblox (dossier "content/sounds" de chaque installation)
	Samples = {
		Ping = "rbxasset://sounds/electronicpingshort.wav", -- note pure (oscillateur)
		Click = "rbxasset://sounds/clickfast.wav", -- clic sec (attaques)
		Swoosh = "rbxasset://sounds/swoosh.wav", -- souffle (bruit : caisse claire, cymbales)
		Button = "rbxasset://sounds/button.wav", -- petit "toc" (lames de bois)
		Thud = "rbxasset://sounds/action_jump_land.mp3", -- choc sourd (grosse caisse)
		Splash = "rbxasset://sounds/impact_water.mp3", -- éclaboussure (bruit : crash, timbre)
		Wind = "rbxasset://sounds/action_falling.mp3", -- vent (bruit aigu : charleston)
	},
	Piano = { SampleId = "Ping", BaseNote = 76, Volume = 0.62, Decay = 2.4, MinSpeed = 0.2, MaxSpeed = 3.2, KeyTrack = true,
		Layers = { { 0, 1 }, { 12, 0.2, 3 }, { 19, 0.05, -4, 0.5 } },
		Attack = { { "Click", 1.9, 0.09, 0.05 } } },
	Guitar = { SampleId = "Ping", BaseNote = 76, Volume = 0.42, Decay = 1.5, MinSpeed = 0.2, MaxSpeed = 2.6, Distortion = 0.72,
		Layers = { { 0, 1 }, { 0, 0.6, 11 }, { -12, 0.4, -6 } },
		Attack = { { "Click", 2.6, 0.1, 0.04 } } },
	Bass = { SampleId = "Ping", BaseNote = 76, Volume = 0.8, Decay = 1.1, MinSpeed = 0.09, MaxSpeed = 1.2,
		Layers = { { 0, 1 }, { 12, 0.45 } },
		Attack = { { "Click", 0.75, 0.22, 0.06 } } },
	Xylophone = { SampleId = "Ping", BaseNote = 76, Volume = 0.6, Decay = 0.5, MinSpeed = 0.3, MaxSpeed = 3.6,
		Layers = { { 0, 1 }, { 19, 0.3, 0, 0.45 }, { 24, 0.08, 0, 0.3 } },
		Attack = { { "Click", 1.5, 0.26, 0.05 }, { "Button", 1.2, 0.12, 0.05 } } },
	Synth = { SampleId = "Ping", BaseNote = 76, Volume = 0.42, Decay = 1.3, MinSpeed = 0.2, MaxSpeed = 3,
		Layers = { { 0, 0.75, -9 }, { 0, 0.75, 9 }, { -12, 0.5 }, { 12, 0.12, 5 } },
		Attack = {},
		Pulse = { Every = 0.17, Count = 3, Fade = 0.62 } },
	Drums = {
		Volume = 0.8,
		Kick = { { "Ping", 0.2, 1, 0.45, 0, 0.075, 0.09 }, { "Click", 0.55, 0.5, 0.05 }, { "Thud", 0.9, 0.45, 0.3 } },
		Snare = { { "Swoosh", 3.4, 0.55, 0.2 }, { "Splash", 2.6, 0.32, 0.18 }, { "Ping", 0.34, 0.45, 0.12, 0, 0.27, 0.05 }, { "Click", 1.3, 0.45, 0.04 } },
		HatClosed = { { "Swoosh", 8, 0.3, 0.05 }, { "Wind", 6, 0.22, 0.05 }, { "Click", 4, 0.08, 0.02 } },
		HatOpen = { { "Swoosh", 6.5, 0.3, 0.42 }, { "Wind", 5, 0.22, 0.4 } },
		TomHigh = { { "Ping", 0.37, 0.8, 0.42, 0, 0.3, 0.12 }, { "Click", 0.8, 0.35, 0.04 }, { "Splash", 1.4, 0.1, 0.12 } },
		TomMid = { { "Ping", 0.29, 0.85, 0.5, 0, 0.235, 0.14 }, { "Click", 0.7, 0.35, 0.04 }, { "Splash", 1.2, 0.1, 0.14 } },
		TomFloor = { { "Ping", 0.22, 0.9, 0.62, 0, 0.175, 0.16 }, { "Click", 0.6, 0.38, 0.05 }, { "Splash", 1.0, 0.1, 0.16 } },
		Crash = { { "Swoosh", 2.4, 0.48, 1.7 }, { "Splash", 1.7, 0.4, 1.6 }, { "Wind", 3, 0.22, 1.4 }, { "Ping", 4.3, 0.05, 0.8 } },
		Ride = { { "Ping", 3.05, 0.16, 0.9 }, { "Ping", 4.41, 0.09, 0.7 }, { "Swoosh", 7, 0.12, 0.25 }, { "Click", 3.5, 0.1, 0.03 } },
	},
	DJ = {
		Volume = 0.8,
		Scratch = { { "Swoosh", 3, 0.5, 0.16, 0, 0.9, 0.14 }, { "Swoosh", 0.9, 0.45, 0.2, 0.15, 2.6, 0.16 }, { "Click", 1.6, 0.2, 0.03 } },
		Horn = { { "Ping", 1, 0.45, 0.22 }, { "Ping", 1.26, 0.35, 0.22 }, { "Ping", 1, 0.45, 0.22, 0.17 }, { "Ping", 1.26, 0.35, 0.22, 0.17 }, { "Ping", 1, 0.5, 0.5, 0.34 }, { "Ping", 1.26, 0.4, 0.5, 0.34 } },
		Riser = { { "Swoosh", 0.4, 0.5, 1.8, 0, 2.6, 1.7 }, { "Wind", 0.8, 0.35, 1.8, 0, 3.5, 1.7 }, { "Ping", 0.5, 0.18, 1.8, 0, 2, 1.7 } },
		Drop = { { "Ping", 0.16, 1, 1.1, 0, 0.04, 0.7 }, { "Thud", 0.7, 0.6, 0.6 }, { "Splash", 0.7, 0.4, 1.2 }, { "Click", 0.3, 0.6, 0.08 } },
	},
}

----------------------------------------------------------------------
-- Sons de clic au choix (⚙️ Paramètres). Le choix est sauvegardé.
----------------------------------------------------------------------
Config.ClickSounds = {
	{ Id = "Default", Name = "Classic", Sound = "rbxasset://sounds/clickfast.wav", Volume = 0.5 },
	{ Id = "Keyboard1", Name = "Keyboard 1", Sound = "rbxassetid://127105730240202", Volume = 0.7 },
	{ Id = "Keyboard2", Name = "Keyboard 2", Sound = "rbxassetid://72826565018765", Volume = 0.7 },
	{ Id = "Keyboard3", Name = "Keyboard 3", Sound = "rbxassetid://96591611478915", Volume = 0.7 },
	{ Id = "Keyboard4", Name = "Keyboard 4", Sound = "rbxassetid://113108830240353", Volume = 0.7 },
	{ Id = "Keyboard5", Name = "Keyboard 5", Sound = "rbxassetid://125615721658437", Volume = 0.7 },
}

----------------------------------------------------------------------
-- Dopamine hors-ligne : quand tu reviens, tu gagnes une partie de ta
-- production pendant ton absence. L'amélioration "Mode veille" l'améliore.
--   Taux = BaseRate + RatePerLevel x niveau ; Durée max = BaseMaxHours + HoursPerLevel x niveau
----------------------------------------------------------------------
Config.Offline = {
	-- (v9.3) plus modeste : 35 % pendant 7 h au mieux (avant : 60 % pendant 12 h)
	BaseRate = 0.1, -- 10 % de la production par seconde
	RatePerLevel = 0.05, -- +5 % par niveau de "Mode veille"
	BaseMaxHours = 2,
	HoursPerLevel = 1,
	MinSeconds = 60, -- en dessous d'une minute d'absence : rien
}

----------------------------------------------------------------------
-- Thèmes (fonds d'écran), achetables avec la Dopamine et/ou des Robux.
--   Cost       : prix en Dopamine (0 = gratuit ; nil = uniquement Robux)
--   GamePassId : Game Pass Roblox qui débloque ce thème (0 = pas de Robux)
--   Premium    : true = aussi débloqué par le Game Pass "VIP"
--   Top/Bottom : dégradé du fond ; Accent : couleur des décorations
--   Decor      : animation du fond ("None", "Kawaii", "Stars", "Sunset",
--                "Leaves", "Bubbles", "Candy", "Grid")
--   Dark       : true = textes clairs (fond sombre)
--   RequiresRebirths : (v9.3) visites à l'océan nécessaires pour l'acheter
--                (vérifié par le serveur : Formulas.IsThemeUnlocked)
-- Les thèmes sont conservés pour toujours (même après l'océan).
----------------------------------------------------------------------
Config.Themes = {
	{ Id = "Classic", Name = "Classic", Icon = "⬜", Cost = 0, GamePassId = 0, Decor = "None", Dark = false,
		Top = Color3.fromRGB(255, 255, 255), Bottom = Color3.fromRGB(226, 226, 226), Accent = Color3.fromRGB(30, 30, 30) },
	{ Id = "Kawaii", Name = "Kawaii", Icon = "🌸", Cost = 250000, GamePassId = 0, Decor = "Kawaii", Dark = false,
		Top = Color3.fromRGB(255, 228, 240), Bottom = Color3.fromRGB(225, 210, 255), Accent = Color3.fromRGB(255, 120, 180) },
	{ Id = "Matcha", Name = "Matcha", Icon = "🍵", Cost = 1.2e6, GamePassId = 0, Decor = "Leaves", Dark = false,
		Top = Color3.fromRGB(236, 248, 228), Bottom = Color3.fromRGB(190, 222, 180), Accent = Color3.fromRGB(90, 150, 80) },
	{ Id = "Sunset", Name = "Sunset", Icon = "🌅", Cost = 3e7, RequiresRebirths = 1, GamePassId = 0, Decor = "Sunset", Dark = false,
		Top = Color3.fromRGB(255, 200, 140), Bottom = Color3.fromRGB(255, 120, 150), Accent = Color3.fromRGB(255, 240, 180) },
	{ Id = "Ocean", Name = "Ocean", Icon = "🐠", Cost = 1e8, RequiresRebirths = 1, GamePassId = 0, Decor = "Bubbles", Dark = false,
		Top = Color3.fromRGB(200, 240, 255), Bottom = Color3.fromRGB(90, 170, 230), Accent = Color3.fromRGB(255, 255, 255) },
	{ Id = "LofiNight", Name = "Lofi Night", Icon = "🌙", Cost = 2.5e9, RequiresRebirths = 2, GamePassId = 0, Decor = "Stars", Dark = true,
		Top = Color3.fromRGB(30, 28, 60), Bottom = Color3.fromRGB(70, 50, 100), Accent = Color3.fromRGB(255, 220, 150) },
	-- v9.2 : thèmes "cool" (skatepark en ville, setup de gamer RGB, station spatiale)
	{ Id = "Street", Name = "Street", Icon = "🛹", Cost = 3e10, RequiresRebirths = 3, GamePassId = 0, Decor = "Street", Dark = false,
		Top = Color3.fromRGB(150, 206, 255), Bottom = Color3.fromRGB(226, 236, 248), Accent = Color3.fromRGB(255, 120, 60) },
	{ Id = "Gamer", Name = "Gamer", Icon = "🎮", Cost = 5e11, RequiresRebirths = 5, GamePassId = 0, Decor = "Gamer", Dark = true,
		Top = Color3.fromRGB(14, 12, 34), Bottom = Color3.fromRGB(36, 20, 70), Accent = Color3.fromRGB(0, 230, 255) },
	{ Id = "SpaceStation", Name = "Space Station", Icon = "🛰️", Cost = 1e13, RequiresRebirths = 8, GamePassId = 0, Decor = "Station", Dark = true,
		Top = Color3.fromRGB(8, 10, 30), Bottom = Color3.fromRGB(26, 34, 76), Accent = Color3.fromRGB(120, 220, 255) },
	{ Id = "Candy", Name = "Candy", Icon = "🍭", Cost = nil, GamePassId = 1995902528, Premium = true, Decor = "Candy", Dark = false,
		Top = Color3.fromRGB(255, 240, 250), Bottom = Color3.fromRGB(180, 235, 255), Accent = Color3.fromRGB(255, 90, 170) },
	{ Id = "Synthwave", Name = "Synthwave", Icon = "🌆", Cost = nil, GamePassId = 1997480274, Premium = true, Decor = "Grid", Dark = true,
		Top = Color3.fromRGB(40, 10, 70), Bottom = Color3.fromRGB(255, 70, 150), Accent = Color3.fromRGB(0, 230, 255) },
}

----------------------------------------------------------------------
-- 💎 Boutique Robux
--   Crée les Game Passes / Developer Products sur le Creator Dashboard
--   (create.roblox.com > ton expérience > Monétisation), puis colle leurs
--   IDs ici. Un ID à 0 = l'offre est cachée dans la boutique.
--   PriceHint : prix affiché si Roblox ne répond pas (le vrai prix vient de
--   MarketplaceService:GetProductInfo).
----------------------------------------------------------------------
Config.Monetization = {
	-- Game Passes (achat unique, pour toujours)
	GamePasses = {
		{ Id = "X10", Name = "Dopamine x10", Icon = "🚀", Description = "All your earnings x10, forever",
			GamePassId = 1997900250, PriceHint = 499, Multiplier = 10 },
		{ Id = "X2", Name = "Dopamine x2", Icon = "⚡", Description = "All your earnings x2, forever",
			GamePassId = 1994066500, PriceHint = 149, Multiplier = 2 },
		{ Id = "AutoClick", Name = "Auto-Click", Icon = "🤖", Description = "Your button clicks itself (5 clicks/s)",
			GamePassId = 1994456537, PriceHint = 249, AutoClicksPerSecond = 5 },
		{ Id = "VIP", Name = "VIP", Icon = "👑", Description = "+25% earnings, every Premium theme and a VIP tag",
			GamePassId = 1995974515, PriceHint = 399, Multiplier = 1.25, UnlockPremiumThemes = true },
	},
	-- Developer Products (achetables plusieurs fois)
	--   Kind "Dopamine" : Seconds de production (au moins Minimum)
	--   Kind "Boost"    : multiplicateur temporaire (Multiplier pendant Duration s)
	--   Kind "ServerRush" : lance un Dopamine Rush pour TOUT le serveur
	--   Kind "Tickets"  : Tickets = nombre de 🎟️ tickets d'arcade donnés (onglet 🎟️ Tickets)
	--   Kind "Combo"    : Tickets 🎟️ + Seconds de production (au moins Minimum)
	--   Kind "Stylish"  : objet stylé (cosmétique) — PAS encore codé côté serveur
	--   Champs optionnels : Tag = ruban de mise en avant ("💰 BEST VALUE"...),
	--   ComingSoon = true : carte "BIENTÔT" (bouton désactivé, jamais d'achat) ;
	--   pour l'activer : colle l'ID (ProductId) et mets ComingSoon = false.
	Products = {
		{ Id = "PackS", Name = "Small Dose", Icon = "💧", Description = "10 minutes of production",
			ProductId = 3714590050, PriceHint = 25, Kind = "Dopamine", Seconds = 600, Minimum = 5000 },
		{ Id = "PackM", Name = "Big Dose", Icon = "💦", Description = "1 hour of production",
			ProductId = 3714590426, PriceHint = 99, Kind = "Dopamine", Seconds = 3600, Minimum = 50000 },
		{ Id = "PackL", Name = "Overdose", Icon = "🌊", Description = "8 hours of production",
			ProductId = 3714590833, PriceHint = 399, Kind = "Dopamine", Seconds = 28800, Minimum = 500000 },
		{ Id = "Boost2", Name = "Boost x2", Icon = "⏱️", Description = "Earnings x2 for 15 minutes",
			ProductId = 3714591469, PriceHint = 49, Kind = "Boost", Multiplier = 2, Duration = 900 },
		{ Id = "Boost5", Name = "Boost x5", Icon = "🔥", Description = "Earnings x5 for 10 minutes",
			ProductId = 3714591784, PriceHint = 129, Kind = "Boost", Multiplier = 5, Duration = 600 },
		{ Id = "ServerRush", Name = "Rush for Everyone", Icon = "🎉", Description = "Dopamine Rush x2 for the whole server",
			ProductId = 3714592189, PriceHint = 79, Kind = "ServerRush" },

		-- 🎟️ Tickets d'arcade (dépensés dans la boutique à tickets de l'🕹️ Arcade ;
		-- jamais misés en duel : les duels se jouent en 🏆 trophées, jamais vendus)
		{ Id = "Tickets5", Name = "Pocket tickets", Icon = "🎟️", Description = "5 arcade tickets",
			ProductId = 3714962647, PriceHint = 10, Kind = "Tickets", Tickets = 5 },
		{ Id = "Tickets10", Name = "Ticket strip", Icon = "🎫", Description = "10 arcade tickets",
			ProductId = 3714962696, PriceHint = 19, Kind = "Tickets", Tickets = 10 },
		{ Id = "Tickets25", Name = "Ticket bundle", Icon = "🎁", Description = "25 arcade tickets",
			ProductId = 3714962739, PriceHint = 45, Kind = "Tickets", Tickets = 25 },
		{ Id = "Tickets50", Name = "Ticket basket", Icon = "🧺", Description = "50 arcade tickets",
			ProductId = 3714962804, PriceHint = 85, Kind = "Tickets", Tickets = 50, Tag = "⭐ POPULAR" },
		{ Id = "Tickets100", Name = "Ticket crate", Icon = "📦", Description = "100 arcade tickets",
			ProductId = 3714962854, PriceHint = 159, Kind = "Tickets", Tickets = 100, Tag = "💰 BEST VALUE" },

		-- 🔜 BIENTÔT : combos (tickets + Dopamine). Le serveur sait déjà les
		-- donner : colle l'ID et mets ComingSoon = false pour les vendre.
		{ Id = "ComboStarter", Name = "Starter combo", Icon = "🎒", Description = "20 tickets + 30 minutes of production",
			ProductId = 0, PriceHint = 49, Kind = "Combo", Tickets = 20, Seconds = 1800, Minimum = 20000, ComingSoon = true },
		{ Id = "ComboMega", Name = "Mega combo", Icon = "💥", Description = "60 tickets + 2 hours of production",
			ProductId = 0, PriceHint = 149, Kind = "Combo", Tickets = 60, Seconds = 7200, Minimum = 200000, ComingSoon = true },
		{ Id = "ComboUltimate", Name = "Ultimate combo", Icon = "🌟", Description = "150 tickets + 8 hours of production",
			ProductId = 0, PriceHint = 399, Kind = "Combo", Tickets = 150, Seconds = 28800, Minimum = 1000000, ComingSoon = true },

		-- 🔜 BIENTÔT : objets stylés (cosmétiques, sans bonus de gains). À coder
		-- avant la vente (voir docs/MONETISATION.md) ; Style = effet visé.
		{ Id = "StyleGoldenTrail", Name = "Golden trail", Icon = "✨", Description = "Golden sparkles follow your cursor",
			ProductId = 0, PriceHint = 99, Kind = "Stylish", Style = "CursorTrail", ComingSoon = true },
		{ Id = "StyleRainbowAura", Name = "Rainbow aura", Icon = "🌈", Description = "Every click bursts into a rainbow ring",
			ProductId = 0, PriceHint = 149, Kind = "Stylish", Style = "ClickAura", ComingSoon = true },
		{ Id = "StyleNeonTag", Name = "Neon name tag", Icon = "🏷️", Description = "A glowing neon tag next to your name",
			ProductId = 0, PriceHint = 79, Kind = "Stylish", Style = "NameTag", ComingSoon = true },
		{ Id = "StyleDiamondSkin", Name = "Diamond button", Icon = "💎", Description = "Your big button, cut like a diamond",
			ProductId = 0, PriceHint = 199, Kind = "Stylish", Style = "ButtonSkin", ComingSoon = true },
		{ Id = "StyleProfileFrame", Name = "Animated frame", Icon = "🖼️", Description = "An animated frame around your avatar",
			ProductId = 0, PriceHint = 129, Kind = "Stylish", Style = "ProfileFrame", ComingSoon = true },
	},
	-- Types de produits que le SERVEUR sait accorder (MonetizationService) :
	-- une offre d'un autre type reste "BIENTÔT" dans la boutique, même avec un
	-- ID (on ne vend jamais ce qu'on ne sait pas donner).
	ReadyKinds = { Dopamine = true, Boost = true, ServerRush = true, Tickets = true, Combo = true },
	-- Petites fenêtres "offre" (OfferPopup) : proposées de temps en temps,
	-- jamais pendant une fenêtre ouverte, fermables, max MaxPerSession
	Offers = {
		FirstDelay = 300, -- (s) première offre après 5 min de jeu
		Interval = 720, -- (s) au moins 12 min entre deux offres
		MaxPerSession = 4,
		Products = { "Boost2", "PackM", "Boost5", "PackS", "PackL" },
		GamePasses = { "X2", "AutoClick", "X10" },
	},
	-- La machine chanceuse ne fait plus miser de Dopamine (tours gratuits) :
	-- elle reste ouverte même quand de la Dopamine s'achète en Robux.
	-- (true = la fermer quand même dans ce cas)
	DisableCasinoWhenSelling = false,
}

----------------------------------------------------------------------
-- 🏠 Ma maison : une pièce kawaii en coupe à décorer (bouton à droite
-- de "Click me"). Tout est gardé pour toujours (même après l'océan).
--   Les objets POSÉS dans la pièce donnent du Confort : chaque point de
--   Confort = +ComfortBonusPerPoint sur TOUS les gains (plafond MaxComfortBonus).
--   Sizes      : maisons, dans l'ordre (plus grande = plus de pièces). Une
--                maison est une grille de pièces vue en coupe (maison de
--                poupée) : Floors étages x Columns pièces par étage.
--                Width = largeur relative d'une pièce, RoomItems = objets
--                posés max PAR pièce, Exterior = style dessiné de la façade
--                ("Cottage" | "Townhouse" | "Loft" | "Mansion").
--   RoomTypes  : types de pièces (salon, chambre, cuisine...). Les objets
--                "préférés" d'une pièce (Categories / Items) y donnent
--                +HarmonyBonus de confort. Wallpaper / Floor (+ Trim / Mood
--                facultatifs) = le "look" du type (v9.6) : appliqué tout seul
--                à l'achat de la pièce et quand on change son type (sauf un
--                style choisi à la main), GRATUIT et débloqué pour cette pièce
--                même s'il n'est pas acheté.
--   RoomCost   : prix de la pièce n°2, x RoomCostGrowth pour chaque suivante.
--   Wallpapers : papiers peints (Pattern = "Plain" | "Stripes" | "Checker" |
--                "Dots" | "Hearts" | "Stars" | "Clouds" | "Bricks" | "Wood" |
--                "Waves" ; A = couleur de fond, B = couleur du motif)
--   Floors     : sols (Pattern = "Plain" | "Checker" | "Wood" | "Tiles" |
--                "Carpet" | "Marble" | "Herringbone" ; A = fond, B = motif)
--   Items      : Category = Id de Categories ; Placement "Floor" (zone du bas)
--                ou "Wall" (zone du haut) ; Size = taille d'affichage de base
--                (px de maquette, 40..160) ; Cost = prix du 1er exemplaire,
--                x CostGrowth par exemplaire déjà possédé ; Comfort = 1..25 ;
--                MaxOwned = nombre max d'exemplaires (nil = illimité).
--   Le 1er papier peint, le 1er sol et la 1re taille sont gratuits.
--   Icônes : un seul emoji (pas de séquence ZWJ ni de couleur de peau).
----------------------------------------------------------------------
Config.House = {
	-- (v9.3) Rendements décroissants (Formulas.GetHouseBonus) : les premiers
	-- points valent +0,2 % chacun, puis de moins en moins ; +75 % à 750 points
	-- de confort, jamais plus de +150 % (avant : +100 % dès 200 points)
	ComfortBonusPerPoint = 0.002, -- +0,2 % de TOUS les gains par point (les premiers points)
	MaxComfortBonus = 1.5, -- limite jamais atteinte : +150 %
	WallRatio = 0.46, -- haut de la pièce = murs, bas = sol (rendu client + limites du serveur)
	-- Petits objets "de sol" : on peut aussi les poser SUR un meuble (table,
	-- bureau, étagère, lit, canapé...) : ils peuvent alors monter jusqu'à
	-- TabletopMinY. Règle (Formulas.CanGoOnFurniture) : objet au sol, pas un
	-- meuble ni une porte, Size <= TabletopMaxSize ; Tabletop = true / false
	-- sur un objet force la règle (valise sur une armoire, gros ours sur le
	-- lit, pas d'aspirateur sur la table...)
	TabletopMaxSize = 80,
	TabletopMinY = 0.12,
	-- (anciennes sauvegardes : les objets de Size <= 70 restent acceptés en hauteur)
	LegacyTabletopSize = 70,

	Sizes = {
		{ Id = "Studio", Name = "Cozy studio", Icon = "🏠", Cost = 0, Floors = 1, Columns = 2,
			Width = 1.0, RoomItems = 30, Exterior = "Cottage" },
		{ Id = "Apartment", Name = "Sweet apartment", Icon = "🏡", Cost = 2e8, RequiresRebirths = 1, Floors = 2, Columns = 2,
			Width = 1.05, RoomItems = 34, Exterior = "Townhouse" },
		{ Id = "Loft", Name = "Dreamy loft", Icon = "🏘️", Cost = 5e10, RequiresRebirths = 3, Floors = 2, Columns = 3,
			Width = 1.2, RoomItems = 40, Exterior = "Loft" },
		{ Id = "Mansion", Name = "Kawaii mansion", Icon = "🏰", Cost = 5e12, RequiresRebirths = 5, Floors = 3, Columns = 4,
			Width = 1.25, RoomItems = 48, Exterior = "Mansion" },
	},

	-- (v9.6) 🏎️ Garage du manoir (CarService, "buyGarage") : aile à 3 places
	-- devant le manoir (côté droit vu de la rue), porte qui s'ouvre quand on
	-- arrive en voiture, voitures possédées garées dedans (Config.Cars)
	Garage = { Id = "Garage", Name = "Mansion garage", Icon = "🏎️", Cost = 8e12, RequiresRebirths = 5, RequiresSize = "Mansion", Bays = 3 },

	-- (v9.3) Paliers des visites à l'océan : un objet / un style (papier peint,
	-- sol, boiserie, ambiance, vue, façade, toit, jardin) SANS RequiresRebirths
	-- reçoit le palier de son prix de base (Cost >= palier.Cost), puis son prix
	-- est multiplié par Price (calculé une fois au chargement, voir la fin du
	-- fichier : entry.BaseCost garde le prix d'origine). Au début, il ne reste
	-- que les ~100 petits objets pas chers.
	RebirthGates = {
		{ Cost = 8e3, Rebirths = 1, Price = 3 },
		{ Cost = 6e4, Rebirths = 2, Price = 6 },
		{ Cost = 5e5, Rebirths = 3, Price = 9 },
		{ Cost = 5e6, Rebirths = 5, Price = 18 },
		{ Cost = 5e7, Rebirths = 8, Price = 34 },
	},

	RoomCost = 60000, -- 2e pièce
	RoomCostGrowth = 6, -- x6 pour chaque pièce suivante
	HarmonyBonus = 0.5, -- +50 % de confort pour un objet "préféré" de sa pièce

	RoomTypes = {
		{ Id = "Living", Name = "Living room", Icon = "🛋️", Wallpaper = "PinkStripes", Floor = "PlumChecker",
			Categories = { "Decor" }, Items = { "Sofa", "Beanbag", "Fireplace", "RetroTV", "HomeCinema", "Bookshelf", "DrawerCabinet",
				"Armchair", "CoffeeTable", "TVStand", "SideTable", "HeartArmchair", "CatSofa", "CloudRug", "KotatsuTable" } },
		{ Id = "Bedroom", Name = "Bedroom", Icon = "🛏️", Wallpaper = "LilacDots", Floor = "PinkCarpet", Trim = "LavenderTrim",
			Categories = { "Lights" }, Items = { "LoftBed", "CloudBed", "CanopyBed", "Nightstand", "Wardrobe", "VanityTable", "TeddyBear", "BigBear",
				"DoubleBed", "Dresser", "HeartPillow", "MoonPillow", "BlanketStack", "HeartRug", "Pouf", "Mannequin", "CrystalThrone",
				"BunkBed", "RaceCarBed", "LockerCabinet" } },
		{ Id = "Kitchen", Name = "Kitchen", Icon = "🍳", Wallpaper = "MintGingham", Floor = "PeachChecker", Trim = "SnowTrim",
			Categories = { "Kitchen" }, Items = { "DiningTable", "DiningChair", "KitchenIsland", "BarStool", "CafeTable", "BarTable" } },
		{ Id = "Bathroom", Name = "Bathroom", Icon = "🛁", Wallpaper = "BabyBlueWaves", Floor = "SkyTiles", Trim = "SnowTrim",
			Categories = {}, Items = { "Toilet", "Shower", "Bathtub", "HeartMirror", "RubberDucky", "Vase", "ScentedCandle" } },
		{ Id = "KidsRoom", Name = "Kids room", Icon = "🧸", RequiresRebirths = 1, Wallpaper = "PeachHearts", Floor = "SoftCream", Trim = "ButterTrim",
			Categories = { "Toys" }, Items = { "MushroomStool", "FloorCushion", "ToyChest", "HeartRug", "StarGarland",
				"BunkBed", "RaceCarBed", "BrickTable", "RaceTrackRug", "HeroPoster", "ComicPoster", "DinoEggLamp" } },
		{ Id = "GameRoom", Name = "Game room", Icon = "🎮", RequiresRebirths = 1, Wallpaper = "NeonGrid", Floor = "StarryCarpet", Trim = "ElectricBlueTrim",
			Mood = "NeonNight",
			Categories = { "Electronics", "Gaming" }, Items = { "GamingChair", "Beanbag", "BoardGame", "BarTable", "BarStool",
				"GamerChair", "GamingDesk", "GamerBeanbag", "LightningNeon" } },
		{ Id = "Greenhouse", Name = "Greenhouse", Icon = "🌿", RequiresRebirths = 1, Wallpaper = "MatchaLatte", Floor = "MeadowGrass", Trim = "MintTrim",
			Mood = "FreshForest",
			Categories = { "Plants" }, Items = { "Fountain", "WindChime", "GardenBench", "PicnicTable", "Lemonade" } },
		{ Id = "PetRoom", Name = "Pet corner", Icon = "🐾", RequiresRebirths = 2, Wallpaper = "VanillaCream", Floor = "HoneyHerringbone", Trim = "HoneyTrim",
			Categories = { "Pets" }, Items = { "Aquarium", "KnittedRug" } },
		{ Id = "Library", Name = "Library", Icon = "📚", RequiresRebirths = 2, Wallpaper = "HoneyPanels", Floor = "CherryWood", Trim = "WalnutTrim",
			Mood = "CozyLamp",
			Categories = {}, Items = { "Bookshelf", "StudyDesk", "DeskGlobe", "WallShelf", "MapPoster", "Telescope",
				"MantelClock", "CuckooClock", "Laptop", "WoodenChair", "FloorLamp", "SecretDoor",
				"BigDesk", "BookStack", "Typewriter", "DeskLamp", "RockingChair", "FloatingShelf", "LadderShelf", "RetroComputer", "KittyClock" } },
		{ Id = "MusicRoom", Name = "Music room", Icon = "🎹", RequiresRebirths = 3, Wallpaper = "LavenderLove", Floor = "WalnutHerringbone",
			Categories = {}, Items = { "GrandPiano", "PinkGuitar", "RecordPlayer", "KaraokeMic", "Speaker", "ToyDrum",
				"RetroRadio", "CatHeadphones", "DiscoBall", "MusicBox", "Harp", "Jukebox", "Xylophone", "NeonStar",
				"GuitarAmp", "ElectricGuitar", "DrumKit", "DJBooth", "RGBHeadset" } },
		{ Id = "Spa", Name = "Spa", Icon = "♨️", RequiresRebirths = 3, Wallpaper = "CloudySky", Floor = "CloudMarble", Trim = "SnowTrim",
			Categories = {}, Items = { "HotSpring", "Bathtub", "Shower", "Fountain", "ScentedCandle", "OilLamp",
				"Bamboo", "Hibiscus", "Vase", "Beanbag", "EggChair", "Bonsai", "LotusBowl", "SwanStatue", "Hammock", "CloudRug" } },
		{ Id = "Attic", Name = "Starry attic", Icon = "🌙", RequiresRebirths = 5, Wallpaper = "GalaxyDream", Floor = "RoseQuartz", Mood = "Moonlight",
			Categories = {}, Items = { "Telescope", "FloatingPlanet", "GlowStars", "MoonGarland", "MoonLamp",
				"StarNightLight", "ShootingStarWindow", "GalaxyWindow", "CrystalBall", "Suitcase", "StorageBox", "Ladder",
				"SnowGlobe", "MushroomLamp", "StarGarland", "JellyfishLamp", "Hologram", "Owl",
				"PlanetMobile", "RocketModel", "Observatory", "RocketLavaLamp" } },
		-- v9.2 : pièces "cool"
		{ Id = "SportsRoom", Name = "Sports room", Icon = "🏀", RequiresRebirths = 5, Wallpaper = "RacingStripes", Floor = "SportsCourt", Trim = "RacingRedTrim",
			Mood = "Stadium",
			Categories = { "Sports" }, Items = { "LockerCabinet", "GamerBeanbag", "Surfboard", "BMXBike", "JerseyFrame",
				"TrophyShelf", "GoldenTrophy", "Motorbike", "RaceTrackRug" } },
		{ Id = "SpaceBase", Name = "Space base", Icon = "🛰️", RequiresRebirths = 8, Wallpaper = "DeepSpace", Floor = "MetalPlate", Trim = "ChromeTrim",
			Categories = { "Adventure" }, Items = { "Telescope", "ToyRocket", "ToyRobot", "Hologram", "FloatingPlanet",
				"GalaxyWindow", "UFOLamp", "VRHeadset", "GamerPC", "RocketLavaLamp" } },
	},

	Wallpapers = {
		{ Id = "PinkStripes", Name = "Pink stripes", Icon = "🎀", Cost = 0, Pattern = "Stripes",
			A = Color3.fromRGB(255, 214, 229), B = Color3.fromRGB(255, 186, 211) },
		{ Id = "VanillaCream", Name = "Vanilla cream", Icon = "🍦", Cost = 500, Pattern = "Plain",
			A = Color3.fromRGB(255, 246, 230), B = Color3.fromRGB(250, 232, 205) },
		{ Id = "LilacDots", Name = "Lilac polka dots", Icon = "🟣", Cost = 2000, Pattern = "Dots",
			A = Color3.fromRGB(234, 222, 255), B = Color3.fromRGB(206, 186, 250) },
		{ Id = "MintGingham", Name = "Mint gingham", Icon = "🍃", Cost = 6000, Pattern = "Checker",
			A = Color3.fromRGB(224, 248, 236), B = Color3.fromRGB(188, 236, 212) },
		{ Id = "PeachHearts", Name = "Peach hearts", Icon = "🍑", Cost = 15000, Pattern = "Hearts",
			A = Color3.fromRGB(255, 231, 216), B = Color3.fromRGB(255, 178, 172) },
		{ Id = "CloudySky", Name = "Cloudy sky", Icon = "☁️", Cost = 40000, Pattern = "Clouds",
			A = Color3.fromRGB(200, 230, 255), B = Color3.fromRGB(255, 255, 255) },
		{ Id = "BabyBlueWaves", Name = "Baby blue waves", Icon = "🌊", Cost = 100000, Pattern = "Waves",
			A = Color3.fromRGB(216, 237, 255), B = Color3.fromRGB(172, 212, 250) },
		{ Id = "StrawberryBricks", Name = "Strawberry milk bricks", Icon = "🍓", Cost = 250000, Pattern = "Bricks",
			A = Color3.fromRGB(255, 212, 222), B = Color3.fromRGB(244, 172, 192) },
		{ Id = "HoneyPanels", Name = "Honey wood panels", Icon = "🍯", Cost = 600000, Pattern = "Wood",
			A = Color3.fromRGB(242, 208, 164), B = Color3.fromRGB(222, 182, 132) },
		{ Id = "StarryNight", Name = "Starry night", Icon = "🌙", Cost = 1.5e6, Pattern = "Stars",
			A = Color3.fromRGB(78, 68, 128), B = Color3.fromRGB(255, 236, 160) },
		{ Id = "CottonCandy", Name = "Cotton candy stripes", Icon = "🍬", Cost = 4e6, Pattern = "Stripes",
			A = Color3.fromRGB(255, 222, 244), B = Color3.fromRGB(204, 230, 255) },
		{ Id = "LavenderLove", Name = "Lavender love", Icon = "💜", Cost = 1e7, Pattern = "Hearts",
			A = Color3.fromRGB(238, 227, 255), B = Color3.fromRGB(214, 162, 240) },
		{ Id = "MatchaLatte", Name = "Matcha latte", Icon = "🍵", Cost = 2.5e7, Pattern = "Dots",
			A = Color3.fromRGB(230, 241, 212), B = Color3.fromRGB(172, 206, 142) },
		{ Id = "SunsetWaves", Name = "Sunset waves", Icon = "🌅", Cost = 6e7, Pattern = "Waves",
			A = Color3.fromRGB(255, 216, 184), B = Color3.fromRGB(255, 162, 182) },
		{ Id = "GalaxyDream", Name = "Galaxy dream", Icon = "🌌", Cost = 1.5e8, Pattern = "Stars",
			A = Color3.fromRGB(64, 44, 106), B = Color3.fromRGB(255, 184, 240) },
		{ Id = "PastelClouds", Name = "Pastel dream clouds", Icon = "🦄", Cost = 4e8, Pattern = "Clouds",
			A = Color3.fromRGB(246, 214, 242), B = Color3.fromRGB(255, 255, 255) },
		-- v9.1 : nouveaux motifs (écossais, fleurs, arlequin, chevrons, lunes)
		{ Id = "MintPlaid", Name = "Mint plaid", Icon = "🌿", Cost = 3500, Pattern = "Plaid",
			A = Color3.fromRGB(226, 247, 236), B = Color3.fromRGB(150, 214, 184) },
		{ Id = "DaisyMeadow", Name = "Daisy meadow", Icon = "🌼", Cost = 9000, Pattern = "Flowers",
			A = Color3.fromRGB(255, 250, 222), B = Color3.fromRGB(255, 255, 255) },
		{ Id = "BerryHarlequin", Name = "Berry harlequin", Icon = "🫐", Cost = 30000, Pattern = "Diamonds",
			A = Color3.fromRGB(250, 226, 244), B = Color3.fromRGB(226, 168, 214) },
		{ Id = "LemonChevron", Name = "Lemon chevron", Icon = "🍋", Cost = 70000, Pattern = "Chevron",
			A = Color3.fromRGB(255, 250, 226), B = Color3.fromRGB(255, 222, 128) },
		{ Id = "SleepyMoons", Name = "Sleepy moons", Icon = "🌛", Cost = 180000, Pattern = "Moons",
			A = Color3.fromRGB(214, 222, 255), B = Color3.fromRGB(255, 240, 180) },
		{ Id = "RosePlaid", Name = "Rose plaid", Icon = "🌹", Cost = 450000, Pattern = "Plaid",
			A = Color3.fromRGB(255, 228, 234), B = Color3.fromRGB(240, 150, 176) },
		{ Id = "SakuraBlossoms", Name = "Sakura blossoms", Icon = "🌸", Cost = 1e6, Pattern = "Flowers",
			A = Color3.fromRGB(255, 232, 240), B = Color3.fromRGB(255, 176, 206) },
		{ Id = "MidnightMoons", Name = "Midnight moons", Icon = "🌙", Cost = 8e6, Pattern = "Moons",
			A = Color3.fromRGB(70, 62, 124), B = Color3.fromRGB(255, 226, 150) },
		{ Id = "LilacHarlequin", Name = "Lilac harlequin", Icon = "🔮", Cost = 5e7, Pattern = "Diamonds",
			A = Color3.fromRGB(238, 228, 255), B = Color3.fromRGB(190, 160, 244) },
		{ Id = "RainbowChevron", Name = "Rainbow chevron", Icon = "🌈", Cost = 9e8, Pattern = "Chevron",
			A = Color3.fromRGB(236, 240, 255), B = Color3.fromRGB(255, 176, 214) },
		-- v9.2 : murs "cool" (carbone, camouflage, espace, graffiti, grille néon,
		-- bandes de course, éclairs, briques de rue, drapeau à damier)
		{ Id = "StoneGrey", Name = "Stone grey", Icon = "🪨", Cost = 1200, Pattern = "Plain",
			A = Color3.fromRGB(214, 220, 228), B = Color3.fromRGB(150, 160, 176) },
		{ Id = "NavyBlue", Name = "Navy blue", Icon = "⚓", Cost = 4000, Pattern = "Plain",
			A = Color3.fromRGB(64, 84, 138), B = Color3.fromRGB(40, 56, 104) },
		{ Id = "CheckeredFlag", Name = "Checkered flag", Icon = "🏁", Cost = 9000, Pattern = "Flag",
			A = Color3.fromRGB(246, 246, 250), B = Color3.fromRGB(44, 46, 58) },
		{ Id = "StreetBrick", Name = "Street brick", Icon = "🧱", Cost = 20000, Pattern = "Bricks",
			A = Color3.fromRGB(96, 70, 70), B = Color3.fromRGB(176, 88, 72) },
		{ Id = "LightningBolts", Name = "Lightning bolts", Icon = "⚡", Cost = 35000, Pattern = "Bolts",
			A = Color3.fromRGB(58, 74, 132), B = Color3.fromRGB(255, 214, 70) },
		{ Id = "ForestCamo", Name = "Forest camo", Icon = "🌲", Cost = 60000, Pattern = "Camo",
			A = Color3.fromRGB(122, 146, 96), B = Color3.fromRGB(70, 92, 60) },
		{ Id = "RacingStripes", Name = "Racing stripes", Icon = "🏎️", Cost = 120000, Pattern = "Racing",
			A = Color3.fromRGB(46, 52, 70), B = Color3.fromRGB(236, 60, 60) },
		{ Id = "CarbonFibre", Name = "Carbon fibre", Icon = "⬛", Cost = 250000, Pattern = "Carbon",
			A = Color3.fromRGB(42, 44, 52), B = Color3.fromRGB(78, 82, 96) },
		{ Id = "GraffitiWall", Name = "Graffiti wall", Icon = "🎨", Cost = 800000, Pattern = "Graffiti",
			A = Color3.fromRGB(196, 196, 206), B = Color3.fromRGB(255, 90, 160) },
		{ Id = "ArcticCamo", Name = "Arctic camo", Icon = "🧊", Cost = 1.8e6, Pattern = "Camo",
			A = Color3.fromRGB(232, 238, 246), B = Color3.fromRGB(150, 164, 186) },
		{ Id = "DeepSpace", Name = "Deep space", Icon = "🌠", Cost = 5e6, Pattern = "Planets",
			A = Color3.fromRGB(24, 26, 64), B = Color3.fromRGB(120, 200, 255) },
		{ Id = "NeonGrid", Name = "Neon grid", Icon = "🟦", Cost = 1.2e7, Pattern = "NeonGrid",
			A = Color3.fromRGB(20, 18, 46), B = Color3.fromRGB(0, 230, 255) },
		{ Id = "LavaCamo", Name = "Lava camo", Icon = "🔥", Cost = 7e7, Pattern = "Camo",
			A = Color3.fromRGB(60, 40, 44), B = Color3.fromRGB(255, 110, 50) },
	},

	Floors = {
		{ Id = "PlumChecker", Name = "Plum checker", Icon = "🍇", Cost = 0, Pattern = "Checker",
			A = Color3.fromRGB(188, 132, 192), B = Color3.fromRGB(152, 100, 162) },
		{ Id = "LightOak", Name = "Light oak", Icon = "🪵", Cost = 600, Pattern = "Wood",
			A = Color3.fromRGB(236, 206, 166), B = Color3.fromRGB(214, 180, 136) },
		{ Id = "SoftCream", Name = "Soft cream", Icon = "🥛", Cost = 1500, Pattern = "Plain",
			A = Color3.fromRGB(250, 238, 222), B = Color3.fromRGB(238, 222, 202) },
		{ Id = "PinkCarpet", Name = "Fluffy pink carpet", Icon = "🌸", Cost = 5000, Pattern = "Carpet",
			A = Color3.fromRGB(255, 202, 222), B = Color3.fromRGB(245, 182, 206) },
		{ Id = "MintTiles", Name = "Mint tiles", Icon = "🧼", Cost = 12000, Pattern = "Tiles",
			A = Color3.fromRGB(212, 245, 230), B = Color3.fromRGB(172, 226, 206) },
		{ Id = "HoneyHerringbone", Name = "Honey herringbone", Icon = "🐝", Cost = 35000, Pattern = "Herringbone",
			A = Color3.fromRGB(232, 188, 124), B = Color3.fromRGB(206, 158, 98) },
		{ Id = "CloudMarble", Name = "Cloud marble", Icon = "☁️", Cost = 90000, Pattern = "Marble",
			A = Color3.fromRGB(248, 246, 252), B = Color3.fromRGB(216, 210, 236) },
		{ Id = "LilacShag", Name = "Lilac shag carpet", Icon = "💜", Cost = 250000, Pattern = "Carpet",
			A = Color3.fromRGB(216, 196, 246), B = Color3.fromRGB(196, 172, 236) },
		{ Id = "CherryWood", Name = "Cherry wood", Icon = "🍒", Cost = 700000, Pattern = "Wood",
			A = Color3.fromRGB(204, 124, 112), B = Color3.fromRGB(172, 96, 90) },
		{ Id = "PeachChecker", Name = "Peach checker", Icon = "🍑", Cost = 2e6, Pattern = "Checker",
			A = Color3.fromRGB(255, 222, 202), B = Color3.fromRGB(255, 190, 170) },
		{ Id = "SkyTiles", Name = "Sky tiles", Icon = "💙", Cost = 6e6, Pattern = "Tiles",
			A = Color3.fromRGB(206, 231, 255), B = Color3.fromRGB(166, 206, 246) },
		{ Id = "RoseQuartz", Name = "Rose quartz marble", Icon = "💗", Cost = 2e7, Pattern = "Marble",
			A = Color3.fromRGB(250, 216, 226), B = Color3.fromRGB(230, 172, 196) },
		{ Id = "WalnutHerringbone", Name = "Walnut herringbone", Icon = "🌰", Cost = 6e7, Pattern = "Herringbone",
			A = Color3.fromRGB(152, 108, 82), B = Color3.fromRGB(122, 84, 64) },
		{ Id = "GoldenMarble", Name = "Golden marble", Icon = "👑", Cost = 3e8, Pattern = "Marble",
			A = Color3.fromRGB(255, 241, 196), B = Color3.fromRGB(232, 196, 112) },
		-- v9.1 : terrazzo, mosaïque, gazon, nuages, moquette étoilée
		{ Id = "PinkTerrazzo", Name = "Pink terrazzo", Icon = "🍧", Cost = 3000, Pattern = "Terrazzo",
			A = Color3.fromRGB(255, 232, 238), B = Color3.fromRGB(240, 150, 186) },
		{ Id = "MintMosaic", Name = "Mint mosaic", Icon = "🧩", Cost = 20000, Pattern = "Mosaic",
			A = Color3.fromRGB(214, 246, 232), B = Color3.fromRGB(150, 218, 196) },
		{ Id = "MeadowGrass", Name = "Meadow grass", Icon = "🌱", Cost = 60000, Pattern = "Grass",
			A = Color3.fromRGB(176, 228, 150), B = Color3.fromRGB(128, 198, 118) },
		{ Id = "CreamTerrazzo", Name = "Vanilla terrazzo", Icon = "🍨", Cost = 150000, Pattern = "Terrazzo",
			A = Color3.fromRGB(252, 244, 230), B = Color3.fromRGB(196, 170, 226) },
		{ Id = "CloudNine", Name = "Cloud nine", Icon = "☁️", Cost = 500000, Pattern = "Clouds",
			A = Color3.fromRGB(206, 228, 255), B = Color3.fromRGB(255, 255, 255) },
		{ Id = "StarryCarpet", Name = "Starry carpet", Icon = "⭐", Cost = 3e6, Pattern = "Starry",
			A = Color3.fromRGB(86, 74, 150), B = Color3.fromRGB(255, 230, 150) },
		{ Id = "OceanMosaic", Name = "Ocean mosaic", Icon = "🐚", Cost = 1.2e7, Pattern = "Mosaic",
			A = Color3.fromRGB(196, 232, 250), B = Color3.fromRGB(110, 184, 226) },
		{ Id = "AuroraStars", Name = "Aurora starlight", Icon = "🌌", Cost = 8e8, Pattern = "Starry",
			A = Color3.fromRGB(58, 48, 118), B = Color3.fromRGB(170, 255, 214) },
		-- v9.2 : sols "cool" (béton, tapis de sport, chêne foncé, terrain de
		-- basket, pelouse de foot, tôle, route, roche de lave)
		{ Id = "SkateConcrete", Name = "Skatepark concrete", Icon = "🛹", Cost = 6000, Pattern = "Concrete",
			A = Color3.fromRGB(196, 200, 208), B = Color3.fromRGB(150, 156, 168) },
		{ Id = "GymMats", Name = "Gym mats", Icon = "🤸", Cost = 15000, Pattern = "Tiles",
			A = Color3.fromRGB(70, 130, 210), B = Color3.fromRGB(40, 70, 130) },
		{ Id = "DarkOak", Name = "Dark oak", Icon = "🌳", Cost = 40000, Pattern = "Wood",
			A = Color3.fromRGB(120, 84, 62), B = Color3.fromRGB(96, 66, 50) },
		{ Id = "SportsCourt", Name = "Basketball court", Icon = "🏀", Cost = 150000, Pattern = "Court",
			A = Color3.fromRGB(232, 178, 116), B = Color3.fromRGB(255, 255, 255) },
		{ Id = "FootballTurf", Name = "Football turf", Icon = "⚽", Cost = 300000, Pattern = "Turf",
			A = Color3.fromRGB(96, 186, 96), B = Color3.fromRGB(70, 160, 76) },
		{ Id = "MetalPlate", Name = "Diamond metal plate", Icon = "🔩", Cost = 600000, Pattern = "TreadPlate",
			A = Color3.fromRGB(170, 178, 192), B = Color3.fromRGB(226, 232, 242) },
		{ Id = "RoadAsphalt", Name = "Road asphalt", Icon = "🛣️", Cost = 2e6, Pattern = "Road",
			A = Color3.fromRGB(70, 74, 84), B = Color3.fromRGB(255, 214, 80) },
		{ Id = "LavaRock", Name = "Lava rock", Icon = "🌋", Cost = 5e7, Pattern = "Lava",
			A = Color3.fromRGB(56, 44, 50), B = Color3.fromRGB(255, 120, 40) },
	},

	-- v9.1 🎨 Personnalisation (tout est sauvegardé par le serveur) --------
	-- Couleurs des objets posés (entry.C) : gratuites ; la couleur principale
	-- du dessin prend la teinte Color (les ombres et reflets suivent)
	Tints = {
		{ Id = "Pink", Name = "Bubblegum", Icon = "💗", Color = Color3.fromRGB(255, 140, 190) },
		{ Id = "Peach", Name = "Peach", Icon = "🍑", Color = Color3.fromRGB(255, 176, 138) },
		{ Id = "Butter", Name = "Butter", Icon = "💛", Color = Color3.fromRGB(255, 218, 110) },
		{ Id = "Mint", Name = "Mint", Icon = "💚", Color = Color3.fromRGB(116, 218, 176) },
		{ Id = "Sky", Name = "Sky", Icon = "💙", Color = Color3.fromRGB(126, 192, 255) },
		{ Id = "Lilac", Name = "Lilac", Icon = "💜", Color = Color3.fromRGB(180, 146, 246) },
		{ Id = "Berry", Name = "Berry", Icon = "🍒", Color = Color3.fromRGB(222, 66, 128) },
		{ Id = "Choco", Name = "Chocolate", Icon = "🍫", Color = Color3.fromRGB(150, 100, 78) },
		{ Id = "Snow", Name = "Snow white", Icon = "🤍", Color = Color3.fromRGB(246, 244, 252) },
		{ Id = "Night", Name = "Midnight", Icon = "🌑", Color = Color3.fromRGB(86, 80, 150) },
		{ Id = "Gold", Name = "Gold", Icon = "👑", Color = Color3.fromRGB(240, 194, 70), RequiresRebirths = 1 },
	},

	-- Boiseries d'une pièce : plinthe, moulure du plafond, cadre de fenêtre
	Trims = {
		{ Id = "Cream", Name = "Vanilla cream", Icon = "🍦", Cost = 0, Color = Color3.fromRGB(255, 247, 236) },
		{ Id = "SnowTrim", Name = "Snow white", Icon = "🤍", Cost = 800, Color = Color3.fromRGB(250, 250, 255) },
		{ Id = "BubblegumTrim", Name = "Bubblegum pink", Icon = "💗", Cost = 3000, Color = Color3.fromRGB(255, 166, 204) },
		{ Id = "MintTrim", Name = "Mint", Icon = "💚", Cost = 8000, Color = Color3.fromRGB(150, 222, 192) },
		{ Id = "SkyTrim", Name = "Sky blue", Icon = "💙", Cost = 20000, Color = Color3.fromRGB(156, 204, 250) },
		{ Id = "LavenderTrim", Name = "Lavender", Icon = "💜", Cost = 50000, Color = Color3.fromRGB(198, 170, 246) },
		{ Id = "ButterTrim", Name = "Butter yellow", Icon = "💛", Cost = 120000, Color = Color3.fromRGB(255, 224, 128) },
		{ Id = "HoneyTrim", Name = "Honey wood", Icon = "🍯", Cost = 300000, Color = Color3.fromRGB(214, 164, 120) },
		{ Id = "WalnutTrim", Name = "Walnut", Icon = "🌰", Cost = 900000, Color = Color3.fromRGB(140, 96, 74) },
		{ Id = "RoseGoldTrim", Name = "Rose gold", Icon = "🌹", Cost = 4e6, Color = Color3.fromRGB(236, 168, 158) },
		{ Id = "GoldTrim", Name = "Royal gold", Icon = "👑", Cost = 4e7, Color = Color3.fromRGB(240, 196, 88) },
		{ Id = "MidnightTrim", Name = "Midnight", Icon = "🌑", Cost = 3e8, Color = Color3.fromRGB(78, 68, 124) },
		-- v9.2 : boiseries "cool"
		{ Id = "SlateTrim", Name = "Slate grey", Icon = "🩶", Cost = 2000, Color = Color3.fromRGB(120, 130, 146) },
		{ Id = "ElectricBlueTrim", Name = "Electric blue", Icon = "🔷", Cost = 15000, Color = Color3.fromRGB(60, 140, 255) },
		{ Id = "RacingRedTrim", Name = "Racing red", Icon = "🟥", Cost = 70000, Color = Color3.fromRGB(226, 56, 60) },
		{ Id = "CamoGreenTrim", Name = "Army green", Icon = "🪖", Cost = 200000, Color = Color3.fromRGB(104, 124, 80) },
		{ Id = "CarbonTrim", Name = "Carbon black", Icon = "⬛", Cost = 1.5e6, Color = Color3.fromRGB(46, 48, 58) },
		{ Id = "ChromeTrim", Name = "Chrome", Icon = "🔩", Cost = 1.2e7, Color = Color3.fromRGB(196, 204, 218) },
	},

	-- Ambiance (lumière) d'une pièce : voile coloré (Tint, force Amount),
	-- 2e couleur du dégradé (Tint2), couleur des lampes (Light), luminosité
	-- (Brightness, 1 = normal) et petit effet animé (Effect)
	Moods = {
		{ Id = "Sunny", Name = "Sunny day", Icon = "☀️", Cost = 0, Tint = Color3.fromRGB(255, 250, 230),
			Tint2 = Color3.fromRGB(255, 250, 230), Amount = 0, Light = Color3.fromRGB(255, 244, 222), Brightness = 1, Effect = "None" },
		{ Id = "CozyLamp", Name = "Cozy lamplight", Icon = "🕯️", Cost = 5000, Tint = Color3.fromRGB(255, 176, 96),
			Tint2 = Color3.fromRGB(255, 214, 150), Amount = 0.16, Light = Color3.fromRGB(255, 196, 120), Brightness = 0.9, Effect = "Rays" },
		{ Id = "GoldenHour", Name = "Golden hour", Icon = "🌅", Cost = 25000, Tint = Color3.fromRGB(255, 150, 90),
			Tint2 = Color3.fromRGB(255, 120, 170), Amount = 0.2, Light = Color3.fromRGB(255, 180, 120), Brightness = 0.95, Effect = "Rays" },
		{ Id = "Moonlight", Name = "Moonlight", Icon = "🌙", Cost = 80000, Tint = Color3.fromRGB(60, 70, 170),
			Tint2 = Color3.fromRGB(120, 110, 210), Amount = 0.34, Light = Color3.fromRGB(170, 190, 255), Brightness = 0.55, Effect = "Sparkles" },
		{ Id = "CottonCandy", Name = "Cotton candy", Icon = "🍭", Cost = 250000, Tint = Color3.fromRGB(255, 140, 200),
			Tint2 = Color3.fromRGB(140, 200, 255), Amount = 0.2, Light = Color3.fromRGB(255, 190, 230), Brightness = 1, Effect = "Hearts" },
		{ Id = "FreshForest", Name = "Fresh forest", Icon = "🍃", Cost = 600000, Tint = Color3.fromRGB(110, 210, 140),
			Tint2 = Color3.fromRGB(220, 255, 170), Amount = 0.18, Light = Color3.fromRGB(210, 255, 200), Brightness = 0.95, Effect = "Leaves" },
		{ Id = "UnderTheSea", Name = "Under the sea", Icon = "🫧", Cost = 2e6, Tint = Color3.fromRGB(60, 170, 230),
			Tint2 = Color3.fromRGB(90, 230, 220), Amount = 0.3, Light = Color3.fromRGB(150, 230, 255), Brightness = 0.75, Effect = "Bubbles" },
		{ Id = "DiscoParty", Name = "Disco party", Icon = "🪩", Cost = 6e6, Tint = Color3.fromRGB(120, 60, 180),
			Tint2 = Color3.fromRGB(255, 80, 180), Amount = 0.36, Light = Color3.fromRGB(255, 140, 240), Brightness = 0.5, Effect = "Disco" },
		{ Id = "Aurora", Name = "Northern lights", Icon = "🌌", Cost = 2e7, Tint = Color3.fromRGB(40, 60, 140),
			Tint2 = Color3.fromRGB(80, 230, 180), Amount = 0.32, Light = Color3.fromRGB(160, 255, 220), Brightness = 0.6, Effect = "Aurora" },
		{ Id = "FairyDust", Name = "Fairy dust", Icon = "✨", Cost = 8e7, Tint = Color3.fromRGB(190, 120, 255),
			Tint2 = Color3.fromRGB(255, 200, 250), Amount = 0.24, Light = Color3.fromRGB(230, 190, 255), Brightness = 0.85, Effect = "Sparkles" },
		{ Id = "RainbowGlow", Name = "Rainbow glow", Icon = "🌈", Cost = 3e8, Tint = Color3.fromRGB(255, 120, 160),
			Tint2 = Color3.fromRGB(120, 200, 255), Amount = 0.22, Light = Color3.fromRGB(255, 230, 240), Brightness = 1, Effect = "Rainbow" },
		-- v9.2 : ambiances "cool" (RGB de gamer, projecteurs de stade, braises
		-- de volcan, orage, néon de nuit)
		{ Id = "NeonNight", Name = "Neon night", Icon = "🌃", Cost = 40000, Tint = Color3.fromRGB(60, 80, 170),
			Tint2 = Color3.fromRGB(0, 200, 230), Amount = 0.22, Light = Color3.fromRGB(120, 230, 255), Brightness = 0.7, Effect = "Neon" },
		{ Id = "Stadium", Name = "Stadium lights", Icon = "🏟️", Cost = 150000, Tint = Color3.fromRGB(200, 230, 255),
			Tint2 = Color3.fromRGB(120, 200, 120), Amount = 0.12, Light = Color3.fromRGB(240, 250, 255), Brightness = 1.05, Effect = "Floodlights" },
		{ Id = "GamerRGB", Name = "Gamer RGB", Icon = "🎮", Cost = 1e6, Tint = Color3.fromRGB(110, 60, 200),
			Tint2 = Color3.fromRGB(0, 170, 230), Amount = 0.2, Light = Color3.fromRGB(180, 120, 255), Brightness = 0.7, Effect = "RGB" },
		{ Id = "Thunderstorm", Name = "Thunderstorm", Icon = "⛈️", Cost = 4e6, Tint = Color3.fromRGB(60, 70, 120),
			Tint2 = Color3.fromRGB(100, 110, 150), Amount = 0.28, Light = Color3.fromRGB(200, 214, 255), Brightness = 0.6, Effect = "Storm" },
		{ Id = "VolcanoGlow", Name = "Volcano glow", Icon = "🌋", Cost = 4e7, Tint = Color3.fromRGB(120, 30, 20),
			Tint2 = Color3.fromRGB(255, 120, 40), Amount = 0.3, Light = Color3.fromRGB(255, 160, 90), Brightness = 0.7, Effect = "Embers" },
	},

	-- Vue par la fenêtre de la pièce (Kind = dessin : HouseViews)
	Views = {
		{ Id = "Garden", Name = "Sunny garden", Icon = "🌤️", Cost = 0, Kind = "Garden",
			Sky = Color3.fromRGB(150, 214, 255), Horizon = Color3.fromRGB(255, 226, 240), Ground = Color3.fromRGB(150, 222, 150) },
		{ Id = "PinkSunset", Name = "Pink sunset", Icon = "🌇", Cost = 3000, Kind = "Sunset",
			Sky = Color3.fromRGB(255, 150, 190), Horizon = Color3.fromRGB(255, 214, 150), Ground = Color3.fromRGB(190, 120, 170) },
		{ Id = "CitySkyline", Name = "City skyline", Icon = "🏙️", Cost = 12000, Kind = "City",
			Sky = Color3.fromRGB(170, 200, 255), Horizon = Color3.fromRGB(240, 220, 255), Ground = Color3.fromRGB(170, 160, 210) },
		{ Id = "BeachView", Name = "Beach & sea", Icon = "🏝️", Cost = 40000, Kind = "Beach",
			Sky = Color3.fromRGB(140, 214, 255), Horizon = Color3.fromRGB(110, 200, 230), Ground = Color3.fromRGB(255, 228, 170) },
		{ Id = "SnowyPines", Name = "Snowy pines", Icon = "❄️", Cost = 120000, Kind = "Snow",
			Sky = Color3.fromRGB(196, 214, 255), Horizon = Color3.fromRGB(236, 240, 255), Ground = Color3.fromRGB(250, 252, 255) },
		{ Id = "SakuraHills", Name = "Sakura hills", Icon = "🌸", Cost = 400000, Kind = "Sakura",
			Sky = Color3.fromRGB(190, 220, 255), Horizon = Color3.fromRGB(255, 226, 238), Ground = Color3.fromRGB(170, 226, 160) },
		{ Id = "MountainLake", Name = "Mountain lake", Icon = "🏔️", Cost = 1.2e6, Kind = "Mountains",
			Sky = Color3.fromRGB(150, 200, 255), Horizon = Color3.fromRGB(226, 240, 255), Ground = Color3.fromRGB(120, 196, 220) },
		{ Id = "CoralReef", Name = "Coral reef", Icon = "🐠", Cost = 4e6, Kind = "Underwater",
			Sky = Color3.fromRGB(70, 170, 220), Horizon = Color3.fromRGB(120, 220, 230), Ground = Color3.fromRGB(240, 214, 170) },
		{ Id = "Candyland", Name = "Candyland", Icon = "🍬", Cost = 1.5e7, Kind = "Candy",
			Sky = Color3.fromRGB(255, 200, 236), Horizon = Color3.fromRGB(255, 240, 200), Ground = Color3.fromRGB(255, 170, 210) },
		{ Id = "OuterSpace", Name = "Outer space", Icon = "🪐", Cost = 6e7, Kind = "Space",
			Sky = Color3.fromRGB(30, 24, 70), Horizon = Color3.fromRGB(90, 50, 140), Ground = Color3.fromRGB(200, 196, 220) },
		{ Id = "RainbowSky", Name = "Rainbow sky", Icon = "🌈", Cost = 2.5e8, Kind = "Rainbow",
			Sky = Color3.fromRGB(170, 220, 255), Horizon = Color3.fromRGB(255, 240, 250), Ground = Color3.fromRGB(255, 255, 255) },
		-- v9.2 : vues "cool"
		{ Id = "SkatePark", Name = "Skate park", Icon = "🛹", Cost = 25000, Kind = "SkatePark",
			Sky = Color3.fromRGB(140, 206, 255), Horizon = Color3.fromRGB(230, 244, 255), Ground = Color3.fromRGB(196, 200, 210) },
		{ Id = "StadiumView", Name = "Stadium", Icon = "🏟️", Cost = 250000, Kind = "Stadium",
			Sky = Color3.fromRGB(120, 180, 250), Horizon = Color3.fromRGB(220, 236, 255), Ground = Color3.fromRGB(90, 180, 90) },
		{ Id = "RacetrackView", Name = "Racetrack", Icon = "🏁", Cost = 800000, Kind = "Racetrack",
			Sky = Color3.fromRGB(150, 210, 255), Horizon = Color3.fromRGB(236, 246, 255), Ground = Color3.fromRGB(120, 196, 110) },
		{ Id = "LaunchPad", Name = "Rocket launch", Icon = "🚀", Cost = 8e6, Kind = "Launch",
			Sky = Color3.fromRGB(110, 170, 240), Horizon = Color3.fromRGB(255, 214, 170), Ground = Color3.fromRGB(200, 190, 170) },
		{ Id = "DinoValley", Name = "Dino valley", Icon = "🦕", Cost = 3e7, Kind = "Dino",
			Sky = Color3.fromRGB(160, 214, 250), Horizon = Color3.fromRGB(255, 236, 196), Ground = Color3.fromRGB(110, 180, 96) },
		{ Id = "VolcanoView", Name = "Volcano island", Icon = "🌋", Cost = 1.2e8, Kind = "Volcano",
			Sky = Color3.fromRGB(90, 60, 90), Horizon = Color3.fromRGB(255, 140, 90), Ground = Color3.fromRGB(70, 60, 66) },
	},

	-- 🏡 Extérieur (toute la maison) : couleur de la façade et du toit (Color
	-- nil = couleurs d'origine du bâtiment), motif du toit, déco du jardin
	Facades = {
		{ Id = "ClassicFacade", Name = "Original colours", Icon = "🏠", Cost = 0 },
		{ Id = "StrawberryFacade", Name = "Strawberry milk", Icon = "🍓", Cost = 20000, RequiresRebirths = 0, Color = Color3.fromRGB(255, 208, 222) },
		{ Id = "MintFacade", Name = "Mint ice cream", Icon = "🍃", Cost = 60000, Color = Color3.fromRGB(200, 240, 222) },
		{ Id = "SkyFacade", Name = "Baby blue", Icon = "💙", Cost = 150000, Color = Color3.fromRGB(204, 228, 255) },
		{ Id = "LavenderFacade", Name = "Lavender", Icon = "💜", Cost = 400000, Color = Color3.fromRGB(226, 212, 255) },
		{ Id = "ButterFacade", Name = "Butter cake", Icon = "🧈", Cost = 1e6, Color = Color3.fromRGB(255, 240, 190) },
		{ Id = "PeachFacade", Name = "Peach sorbet", Icon = "🍑", Cost = 2.5e6, Color = Color3.fromRGB(255, 220, 196) },
		{ Id = "CocoaFacade", Name = "Hot cocoa", Icon = "☕", Cost = 8e6, Color = Color3.fromRGB(190, 146, 120) },
		{ Id = "SnowFacade", Name = "Snow castle", Icon = "🏔️", Cost = 3e7, Color = Color3.fromRGB(248, 248, 255) },
		{ Id = "MidnightFacade", Name = "Midnight sky", Icon = "🌃", Cost = 2e8, Color = Color3.fromRGB(110, 100, 170) },
		-- v9.2 : façades "cool"
		{ Id = "SlateFacade", Name = "Slate grey", Icon = "🩶", Cost = 35000, Color = Color3.fromRGB(170, 180, 196) },
		{ Id = "DenimFacade", Name = "Denim blue", Icon = "👖", Cost = 250000, Color = Color3.fromRGB(110, 140, 200) },
		{ Id = "ArmyFacade", Name = "Army green", Icon = "🪖", Cost = 1.5e6, Color = Color3.fromRGB(140, 160, 110) },
		{ Id = "RacingFacade", Name = "Racing red", Icon = "🏎️", Cost = 5e6, Color = Color3.fromRGB(226, 90, 84) },
		{ Id = "CarbonFacade", Name = "Carbon black", Icon = "⬛", Cost = 5e7, Color = Color3.fromRGB(74, 76, 90) },
	},
	Roofs = {
		{ Id = "ClassicRoof", Name = "Original colours", Icon = "🏠", Cost = 0 },
		{ Id = "BubblegumRoof", Name = "Bubblegum", Icon = "💗", Cost = 15000, RequiresRebirths = 0, Color = Color3.fromRGB(255, 140, 188) },
		{ Id = "LilacRoof", Name = "Lilac", Icon = "💜", Cost = 45000, Color = Color3.fromRGB(180, 150, 240) },
		{ Id = "MintRoof", Name = "Mint", Icon = "💚", Cost = 120000, Color = Color3.fromRGB(110, 206, 170) },
		{ Id = "SkyRoof", Name = "Sky blue", Icon = "💙", Cost = 300000, Color = Color3.fromRGB(116, 180, 246) },
		{ Id = "SunnyRoof", Name = "Sunny yellow", Icon = "🌻", Cost = 800000, Color = Color3.fromRGB(255, 204, 90) },
		{ Id = "CoralRoof", Name = "Coral", Icon = "🪸", Cost = 2e6, Color = Color3.fromRGB(255, 130, 116) },
		{ Id = "ChocolateRoof", Name = "Chocolate", Icon = "🍫", Cost = 6e6, Color = Color3.fromRGB(140, 92, 76) },
		{ Id = "SnowRoof", Name = "Snowy white", Icon = "⛄", Cost = 2e7, Color = Color3.fromRGB(242, 244, 255) },
		{ Id = "GoldRoof", Name = "Royal gold", Icon = "👑", Cost = 1e8, Color = Color3.fromRGB(240, 190, 70) },
		-- v9.2 : toits "cool"
		{ Id = "NavyRoof", Name = "Navy blue", Icon = "⚓", Cost = 25000, Color = Color3.fromRGB(60, 80, 140) },
		{ Id = "BlazeRoof", Name = "Blaze orange", Icon = "🟧", Cost = 200000, Color = Color3.fromRGB(255, 140, 50) },
		{ Id = "ArmyRoof", Name = "Army green", Icon = "🪖", Cost = 900000, Color = Color3.fromRGB(96, 116, 76) },
		{ Id = "RacingRoof", Name = "Racing red", Icon = "🏎️", Cost = 4e6, Color = Color3.fromRGB(214, 50, 56) },
		{ Id = "CarbonRoof", Name = "Carbon black", Icon = "⬛", Cost = 3e7, Color = Color3.fromRGB(52, 54, 66) },
	},
	RoofStyles = {
		{ Id = "PlainRoof", Name = "Classic tiles", Icon = "🧱", Cost = 0, Pattern = "None" },
		{ Id = "HeartRoof", Name = "Love hearts", Icon = "💕", Cost = 30000, RequiresRebirths = 0, Pattern = "Hearts" },
		{ Id = "PolkaRoof", Name = "Polka dots", Icon = "🔴", Cost = 90000, Pattern = "Dots" },
		{ Id = "CandyRoof", Name = "Candy stripes", Icon = "🍬", Cost = 250000, Pattern = "Stripes" },
		{ Id = "StarRoof", Name = "Twinkle stars", Icon = "⭐", Cost = 700000, Pattern = "Stars" },
		{ Id = "FlowerRoof", Name = "Flower garden", Icon = "🌷", Cost = 2e6, Pattern = "Flowers" },
		{ Id = "SnowyRoof", Name = "Snowy caps", Icon = "❄️", Cost = 7e6, Pattern = "Snow" },
		{ Id = "MermaidRoof", Name = "Mermaid scales", Icon = "🧜", Cost = 4e7, Pattern = "Scales" },
		-- v9.2 : motifs "cool"
		{ Id = "CheckerRoof", Name = "Race flag", Icon = "🏁", Cost = 60000, Pattern = "Checkered" },
		{ Id = "BoltRoof", Name = "Lightning bolts", Icon = "⚡", Cost = 400000, Pattern = "Bolts" },
		{ Id = "CamoRoof", Name = "Camo", Icon = "🌲", Cost = 3e6, Pattern = "Camo" },
		{ Id = "FlameRoof", Name = "Hot flames", Icon = "🔥", Cost = 2e7, Pattern = "Flames" },
	},
	-- Déco du jardin devant la maison (GardenSlots au plus, dans l'ordre choisi)
	GardenSlots = 6,
	GardenDecor = {
		{ Id = "TulipBed", Name = "Tulip bed", Icon = "🌷", Cost = 8000 },
		{ Id = "GardenGnome", Name = "Garden gnome", Icon = "🧙", Cost = 20000 },
		{ Id = "PinkFlamingo", Name = "Pink flamingo", Icon = "🦩", Cost = 45000 },
		{ Id = "Birdbath", Name = "Bird bath", Icon = "🐦", Cost = 100000 },
		{ Id = "Beehive", Name = "Honey beehive", Icon = "🐝", Cost = 220000 },
		{ Id = "DuckPond", Name = "Duck pond", Icon = "🦆", Cost = 500000 },
		{ Id = "PumpkinPatch", Name = "Pumpkin patch", Icon = "🎃", Cost = 1.1e6 },
		{ Id = "Snowman", Name = "Happy snowman", Icon = "⛄", Cost = 2.4e6 },
		{ Id = "WishingWell", Name = "Wishing well", Icon = "🪣", Cost = 5e6 },
		{ Id = "Trampoline", Name = "Trampoline", Icon = "🤸", Cost = 1.2e7 },
		{ Id = "RainbowArch", Name = "Rainbow arch", Icon = "🌈", Cost = 5e7 },
		{ Id = "UnicornStatue", Name = "Unicorn statue", Icon = "🦄", Cost = 3e8 },
		-- v9.2 : déco de jardin "cool"
		{ Id = "YardHoop", Name = "Driveway hoop", Icon = "🏀", Cost = 30000 },
		{ Id = "CampTent", Name = "Camping tent", Icon = "⛺", Cost = 80000 },
		{ Id = "BBQGrill", Name = "Barbecue grill", Icon = "🍖", Cost = 300000 },
		{ Id = "YardGoal", Name = "Football goal", Icon = "🥅", Cost = 900000 },
		{ Id = "SkateRamp", Name = "Skate ramp", Icon = "🛹", Cost = 3.5e6 },
		{ Id = "Treehouse", Name = "Treehouse", Icon = "🌳", Cost = 2e7 },
		{ Id = "DinoStatue", Name = "Dino statue", Icon = "🦕", Cost = 1.5e8 },
	},

	Categories = {
		{ Id = "Furniture", Name = "Furniture", Icon = "🛋️" },
		{ Id = "Decor", Name = "Decor", Icon = "🖼️" },
		{ Id = "Toys", Name = "Toys", Icon = "🧸" },
		{ Id = "Plants", Name = "Plants", Icon = "🪴" },
		{ Id = "Electronics", Name = "Electronics", Icon = "📺" },
		{ Id = "Kitchen", Name = "Kitchen", Icon = "🍰" },
		{ Id = "Doors", Name = "Doors", Icon = "🚪" },
		{ Id = "Windows", Name = "Windows", Icon = "🪟" },
		{ Id = "Lights", Name = "Lights", Icon = "💡" },
		{ Id = "Pets", Name = "Pets", Icon = "🐾" },
		-- v9.2 : jeux vidéo, sport, aventure (espace, dinos, pirates, ninjas) ;
		-- Tint = fond de la vignette dans la boutique
		{ Id = "Gaming", Name = "Gaming", Icon = "🎮", Tint = Color3.fromRGB(212, 236, 255) },
		{ Id = "Sports", Name = "Sports", Icon = "🏀", Tint = Color3.fromRGB(255, 226, 204) },
		{ Id = "Adventure", Name = "Adventure", Icon = "🚀", Tint = Color3.fromRGB(226, 226, 255) },
		-- v9.5 🖥️ "Dopamine Setup" : les stimuli du clicker deviennent de vrais
		-- objets de la maison (voir la fin de Items)
		{ Id = "Setup", Name = "Dopamine Setup", Icon = "🖥️", Tint = Color3.fromRGB(222, 214, 255) },
		-- v9.8 💎 Luxe : les objets de rêve (jacuzzi, piano, mur d'aquarium,
		-- tunnel aquarium, trône d'or, dragon...) ; voir la fin de Items
		{ Id = "Luxury", Name = "Luxury", Icon = "💎", Tint = Color3.fromRGB(255, 236, 200) },
	},

	Items = {
		-- 🛋️ Meubles
		{ Id = "WoodenChair", Name = "Wooden chair", Icon = "🪑", Category = "Furniture", Placement = "Floor", Size = 70,
			Cost = 600, CostGrowth = 1.25, Comfort = 1 },
		{ Id = "StorageBox", Name = "Storage box", Icon = "📦", Category = "Furniture", Placement = "Floor", Size = 60,
			Cost = 900, CostGrowth = 1.2, Comfort = 1, Tabletop = true },
		{ Id = "Ladder", Name = "Wooden ladder", Icon = "🪜", Category = "Furniture", Placement = "Floor", Size = 120,
			Cost = 1500, CostGrowth = 1.3, Comfort = 1, MaxOwned = 3 },
		{ Id = "Nightstand", Name = "Cute nightstand", Icon = "🌛", Category = "Furniture", Placement = "Floor", Size = 55,
			Cost = 2000, CostGrowth = 1.25, Comfort = 2 },
		{ Id = "Suitcase", Name = "Travel suitcase", Icon = "🧳", Category = "Furniture", Placement = "Floor", Size = 70,
			Cost = 2500, CostGrowth = 1.25, Comfort = 2, Tabletop = true },
		{ Id = "Toilet", Name = "Royal toilet", Icon = "🚽", Category = "Furniture", Placement = "Floor", Size = 75,
			Cost = 3000, CostGrowth = 1.5, Comfort = 2, MaxOwned = 2 },
		{ Id = "DrawerCabinet", Name = "Drawer cabinet", Icon = "🗄️", Category = "Furniture", Placement = "Floor", Size = 90,
			Cost = 4000, CostGrowth = 1.3, Comfort = 3 },
		{ Id = "LoftBed", Name = "Loft bed", Icon = "🛏️", Category = "Furniture", Placement = "Floor", Size = 120,
			Cost = 5000, CostGrowth = 1.25, Comfort = 6 },
		{ Id = "StudyDesk", Name = "Study desk", Icon = "✏️", Category = "Furniture", Placement = "Floor", Size = 110,
			Cost = 7000, CostGrowth = 1.3, Comfort = 4 },
		{ Id = "Bookshelf", Name = "Bookshelf", Icon = "📚", Category = "Furniture", Placement = "Floor", Size = 110,
			Cost = 9000, CostGrowth = 1.3, Comfort = 5 },
		{ Id = "Sofa", Name = "Comfy sofa", Icon = "🛋️", Category = "Furniture", Placement = "Floor", Size = 140,
			Cost = 12000, CostGrowth = 1.3, Comfort = 7 },
		{ Id = "Beanbag", Name = "Peach beanbag", Icon = "🍑", Category = "Furniture", Placement = "Floor", Size = 80,
			Cost = 15000, CostGrowth = 1.3, Comfort = 5 },
		{ Id = "VanityTable", Name = "Vanity table", Icon = "💄", Category = "Furniture", Placement = "Floor", Size = 110,
			Cost = 30000, CostGrowth = 1.35, Comfort = 5 },
		{ Id = "Wardrobe", Name = "Pastel wardrobe", Icon = "👗", Category = "Furniture", Placement = "Floor", Size = 130,
			Cost = 45000, CostGrowth = 1.35, Comfort = 6 },
		{ Id = "GamingChair", Name = "Gaming chair", Icon = "💺", Category = "Furniture", Placement = "Floor", Size = 90,
			Cost = 60000, CostGrowth = 1.35, Comfort = 6 },
		{ Id = "Shower", Name = "Rain shower", Icon = "🚿", Category = "Furniture", Placement = "Floor", Size = 110,
			Cost = 90000, CostGrowth = 1.5, Comfort = 6, MaxOwned = 2 },
		{ Id = "Bathtub", Name = "Bubble bathtub", Icon = "🛁", Category = "Furniture", Placement = "Floor", Size = 130,
			Cost = 250000, CostGrowth = 1.4, Comfort = 9 },
		{ Id = "Fireplace", Name = "Cozy fireplace", Icon = "🔥", Category = "Furniture", Placement = "Floor", Size = 130,
			Cost = 1.5e6, CostGrowth = 1.45, Comfort = 12 },
		{ Id = "CanopyBed", Name = "Princess canopy bed", Icon = "👑", Category = "Furniture", Placement = "Floor", Size = 150,
			Cost = 5e6, CostGrowth = 1.5, Comfort = 14 },
		{ Id = "CloudBed", Name = "Cloud bed", Icon = "☁️", Category = "Furniture", Placement = "Floor", Size = 150,
			Cost = 2e7, CostGrowth = 1.5, Comfort = 17 },
		{ Id = "HotSpring", Name = "Hot spring tub", Icon = "♨️", Category = "Furniture", Placement = "Floor", Size = 150,
			Cost = 1.5e8, CostGrowth = 1.55, Comfort = 22 },

		-- 🖼️ Déco
		{ Id = "KnittedRug", Name = "Knitted rug", Icon = "🧶", Category = "Decor", Placement = "Floor", Size = 90,
			Cost = 500, CostGrowth = 1.2, Comfort = 1 },
		{ Id = "HeartSticker", Name = "Heart sticker", Icon = "💖", Category = "Decor", Placement = "Wall", Size = 50,
			Cost = 600, CostGrowth = 1.2, Comfort = 1 },
		{ Id = "GiantBow", Name = "Giant bow", Icon = "🎀", Category = "Decor", Placement = "Wall", Size = 60,
			Cost = 700, CostGrowth = 1.2, Comfort = 1 },
		{ Id = "WallCalendar", Name = "Wall calendar", Icon = "📅", Category = "Decor", Placement = "Wall", Size = 55,
			Cost = 1000, CostGrowth = 1.25, Comfort = 1 },
		{ Id = "FramedPicture", Name = "Framed picture", Icon = "🖼️", Category = "Decor", Placement = "Wall", Size = 80,
			Cost = 1200, CostGrowth = 1.25, Comfort = 2 },
		{ Id = "Balloons", Name = "Balloon bunch", Icon = "🎈", Category = "Decor", Placement = "Wall", Size = 70,
			Cost = 1500, CostGrowth = 1.2, Comfort = 1 },
		{ Id = "MantelClock", Name = "Mantel clock", Icon = "🕰️", Category = "Decor", Placement = "Floor", Size = 60,
			Cost = 2000, CostGrowth = 1.25, Comfort = 2 },
		{ Id = "MapPoster", Name = "World map poster", Icon = "🗺️", Category = "Decor", Placement = "Wall", Size = 90,
			Cost = 2500, CostGrowth = 1.25, Comfort = 2 },
		{ Id = "PartyBunting", Name = "Party bunting", Icon = "🎉", Category = "Decor", Placement = "Wall", Size = 140,
			Cost = 3000, CostGrowth = 1.25, Comfort = 1 },
		{ Id = "HeartMirror", Name = "Heart mirror", Icon = "🪞", Category = "Decor", Placement = "Wall", Size = 80,
			Cost = 3500, CostGrowth = 1.3, Comfort = 3 },
		{ Id = "GiftPile", Name = "Gift pile", Icon = "🎁", Category = "Decor", Placement = "Floor", Size = 70,
			Cost = 5000, CostGrowth = 1.25, Comfort = 2 },
		{ Id = "Vase", Name = "Amphora vase", Icon = "🏺", Category = "Decor", Placement = "Floor", Size = 60,
			Cost = 6000, CostGrowth = 1.3, Comfort = 3 },
		{ Id = "GlowStars", Name = "Glow-in-the-dark stars", Icon = "💫", Category = "Decor", Placement = "Wall", Size = 60,
			Cost = 8000, CostGrowth = 1.25, Comfort = 2 },
		{ Id = "DreamCatcher", Name = "Dream catcher", Icon = "🪶", Category = "Decor", Placement = "Wall", Size = 70,
			Cost = 10000, CostGrowth = 1.3, Comfort = 3 },
		{ Id = "CuckooClock", Name = "Cuckoo clock", Icon = "🐦", Category = "Decor", Placement = "Wall", Size = 70,
			Cost = 15000, CostGrowth = 1.3, Comfort = 3, MaxOwned = 2 },
		{ Id = "DeskGlobe", Name = "Desk globe", Icon = "🌍", Category = "Decor", Placement = "Floor", Size = 55,
			Cost = 20000, CostGrowth = 1.3, Comfort = 3 },
		{ Id = "PhotoString", Name = "Polaroid string", Icon = "📸", Category = "Decor", Placement = "Wall", Size = 120,
			Cost = 25000, CostGrowth = 1.3, Comfort = 4 },
		{ Id = "WallShelf", Name = "Cute wall shelf", Icon = "🗃️", Category = "Decor", Placement = "Wall", Size = 110,
			Cost = 28000, CostGrowth = 1.3, Comfort = 4 },
		{ Id = "WindChime", Name = "Wind chime", Icon = "🎐", Category = "Decor", Placement = "Wall", Size = 60,
			Cost = 30000, CostGrowth = 1.3, Comfort = 3 },
		{ Id = "MoonGarland", Name = "Moon garland", Icon = "🌙", Category = "Decor", Placement = "Wall", Size = 80,
			Cost = 45000, CostGrowth = 1.3, Comfort = 4 },
		{ Id = "CarpStreamer", Name = "Carp streamer", Icon = "🎏", Category = "Decor", Placement = "Wall", Size = 90,
			Cost = 120000, CostGrowth = 1.35, Comfort = 5 },
		{ Id = "Aquarium", Name = "Aquarium", Icon = "🐠", Category = "Decor", Placement = "Floor", Size = 110,
			Cost = 150000, CostGrowth = 1.35, Comfort = 8 },
		{ Id = "Pinata", Name = "Piñata", Icon = "🪅", Category = "Decor", Placement = "Wall", Size = 80,
			Cost = 250000, CostGrowth = 1.35, Comfort = 6 },
		{ Id = "GoldenTrophy", Name = "Golden trophy", Icon = "🏆", Category = "Decor", Placement = "Floor", Size = 60,
			Cost = 400000, CostGrowth = 1.4, Comfort = 7 },
		{ Id = "CrystalBall", Name = "Crystal ball", Icon = "🔮", Category = "Decor", Placement = "Floor", Size = 55,
			Cost = 800000, CostGrowth = 1.4, Comfort = 8 },
		{ Id = "MoaiStatue", Name = "Moai statue", Icon = "🗿", Category = "Decor", Placement = "Floor", Size = 110,
			Cost = 5e6, CostGrowth = 1.45, Comfort = 13 },
		{ Id = "Fountain", Name = "Indoor fountain", Icon = "⛲", Category = "Decor", Placement = "Floor", Size = 140,
			Cost = 1.2e7, CostGrowth = 1.5, Comfort = 15 },
		{ Id = "GiantGem", Name = "Giant gem", Icon = "💎", Category = "Decor", Placement = "Floor", Size = 70,
			Cost = 8e7, CostGrowth = 1.55, Comfort = 20 },
		{ Id = "FloatingPlanet", Name = "Floating planet", Icon = "🪐", Category = "Decor", Placement = "Wall", Size = 100,
			Cost = 3e8, CostGrowth = 1.6, Comfort = 24 },

		-- 🧸 Jouets
		{ Id = "YoYo", Name = "Yo-yo", Icon = "🪀", Category = "Toys", Placement = "Floor", Size = 40,
			Cost = 500, CostGrowth = 1.2, Comfort = 1 },
		{ Id = "BeachBall", Name = "Beach ball", Icon = "🏐", Category = "Toys", Placement = "Floor", Size = 50,
			Cost = 600, CostGrowth = 1.2, Comfort = 1 },
		{ Id = "RubberDucky", Name = "Rubber ducky", Icon = "🦆", Category = "Toys", Placement = "Floor", Size = 40,
			Cost = 700, CostGrowth = 1.2, Comfort = 1 },
		{ Id = "TeddyBear", Name = "Teddy bear", Icon = "🧸", Category = "Toys", Placement = "Floor", Size = 70,
			Cost = 800, CostGrowth = 1.2, Comfort = 2 },
		{ Id = "PuzzlePieces", Name = "Puzzle pieces", Icon = "🧩", Category = "Toys", Placement = "Floor", Size = 50,
			Cost = 1200, CostGrowth = 1.2, Comfort = 1 },
		{ Id = "BunnyPlush", Name = "Bunny plush", Icon = "🐰", Category = "Toys", Placement = "Floor", Size = 60,
			Cost = 1500, CostGrowth = 1.2, Comfort = 2 },
		{ Id = "Kite", Name = "Rainbow kite", Icon = "🪁", Category = "Toys", Placement = "Wall", Size = 80,
			Cost = 2500, CostGrowth = 1.25, Comfort = 2 },
		{ Id = "GiantDice", Name = "Giant dice", Icon = "🎲", Category = "Toys", Placement = "Floor", Size = 50,
			Cost = 3000, CostGrowth = 1.25, Comfort = 2 },
		{ Id = "KittyPlush", Name = "Kitty plush", Icon = "🐱", Category = "Toys", Placement = "Floor", Size = 60,
			Cost = 4000, CostGrowth = 1.25, Comfort = 3 },
		{ Id = "PuppyPlush", Name = "Puppy plush", Icon = "🐶", Category = "Toys", Placement = "Floor", Size = 60,
			Cost = 5000, CostGrowth = 1.25, Comfort = 3 },
		{ Id = "FroggyPlush", Name = "Froggy plush", Icon = "🐸", Category = "Toys", Placement = "Floor", Size = 55,
			Cost = 8000, CostGrowth = 1.25, Comfort = 3 },
		{ Id = "DinoPlush", Name = "Dino plush", Icon = "🦖", Category = "Toys", Placement = "Floor", Size = 70,
			Cost = 9000, CostGrowth = 1.3, Comfort = 3 },
		{ Id = "MagicWand", Name = "Magic wand", Icon = "🪄", Category = "Toys", Placement = "Floor", Size = 50,
			Cost = 10000, CostGrowth = 1.3, Comfort = 3 },
		{ Id = "HamsterPlush", Name = "Hamster plush", Icon = "🐹", Category = "Toys", Placement = "Floor", Size = 50,
			Cost = 12000, CostGrowth = 1.3, Comfort = 3 },
		{ Id = "ToyRobot", Name = "Toy robot", Icon = "🤖", Category = "Toys", Placement = "Floor", Size = 70,
			Cost = 15000, CostGrowth = 1.3, Comfort = 4 },
		{ Id = "PenguinPlush", Name = "Penguin plush", Icon = "🐧", Category = "Toys", Placement = "Floor", Size = 60,
			Cost = 18000, CostGrowth = 1.3, Comfort = 3 },
		{ Id = "ToyDrum", Name = "Toy drum", Icon = "🥁", Category = "Toys", Placement = "Floor", Size = 60,
			Cost = 20000, CostGrowth = 1.3, Comfort = 3 },
		{ Id = "PandaPlush", Name = "Panda plush", Icon = "🐼", Category = "Toys", Placement = "Floor", Size = 70,
			Cost = 25000, CostGrowth = 1.3, Comfort = 4 },
		{ Id = "NestingDolls", Name = "Nesting dolls", Icon = "🪆", Category = "Toys", Placement = "Floor", Size = 60,
			Cost = 40000, CostGrowth = 1.3, Comfort = 4 },
		{ Id = "PinkGuitar", Name = "Pink guitar", Icon = "🎸", Category = "Toys", Placement = "Floor", Size = 90,
			Cost = 60000, CostGrowth = 1.3, Comfort = 5 },
		{ Id = "BigBear", Name = "Giant bear plush", Icon = "🐻", Category = "Toys", Placement = "Floor", Size = 110,
			Cost = 90000, CostGrowth = 1.35, Comfort = 6, Tabletop = true },
		{ Id = "RockingHorse", Name = "Rocking horse", Icon = "🐴", Category = "Toys", Placement = "Floor", Size = 100,
			Cost = 120000, CostGrowth = 1.4, Comfort = 5 },
		{ Id = "ToyTrain", Name = "Toy train", Icon = "🚂", Category = "Toys", Placement = "Floor", Size = 90,
			Cost = 180000, CostGrowth = 1.35, Comfort = 6 },
		{ Id = "UnicornPlush", Name = "Unicorn plush", Icon = "🦄", Category = "Toys", Placement = "Floor", Size = 80,
			Cost = 300000, CostGrowth = 1.4, Comfort = 8 },
		{ Id = "BlanketFort", Name = "Blanket fort", Icon = "⛺", Category = "Toys", Placement = "Floor", Size = 150,
			Cost = 450000, CostGrowth = 1.4, Comfort = 10 },
		{ Id = "DollCastle", Name = "Dollhouse castle", Icon = "🏯", Category = "Toys", Placement = "Floor", Size = 120,
			Cost = 1.5e6, CostGrowth = 1.45, Comfort = 11 },
		{ Id = "CarouselHorse", Name = "Carousel horse", Icon = "🎠", Category = "Toys", Placement = "Floor", Size = 130,
			Cost = 6e6, CostGrowth = 1.5, Comfort = 14 },
		{ Id = "ToyRocket", Name = "Toy rocket", Icon = "🚀", Category = "Toys", Placement = "Floor", Size = 110,
			Cost = 1.2e7, CostGrowth = 1.5, Comfort = 15 },
		{ Id = "FerrisWheel", Name = "Mini ferris wheel", Icon = "🎡", Category = "Toys", Placement = "Floor", Size = 150,
			Cost = 4e7, CostGrowth = 1.55, Comfort = 18 },

		-- 🪴 Plantes
		{ Id = "Sprout", Name = "Little sprout", Icon = "🌱", Category = "Plants", Placement = "Floor", Size = 40,
			Cost = 500, CostGrowth = 1.2, Comfort = 1 },
		{ Id = "TulipPot", Name = "Tulip pot", Icon = "🌷", Category = "Plants", Placement = "Floor", Size = 50,
			Cost = 900, CostGrowth = 1.2, Comfort = 1 },
		{ Id = "TinyCactus", Name = "Tiny cactus", Icon = "🌵", Category = "Plants", Placement = "Floor", Size = 50,
			Cost = 1400, CostGrowth = 1.2, Comfort = 2 },
		{ Id = "DaisyPot", Name = "Daisy pot", Icon = "🌼", Category = "Plants", Placement = "Floor", Size = 50,
			Cost = 2000, CostGrowth = 1.2, Comfort = 2 },
		{ Id = "PottedPlant", Name = "Potted plant", Icon = "🪴", Category = "Plants", Placement = "Floor", Size = 80,
			Cost = 3000, CostGrowth = 1.25, Comfort = 3 },
		{ Id = "HangingHerbs", Name = "Hanging herbs", Icon = "🌿", Category = "Plants", Placement = "Wall", Size = 70,
			Cost = 5000, CostGrowth = 1.25, Comfort = 2 },
		{ Id = "HangingPothos", Name = "Hanging pothos", Icon = "🎍", Category = "Plants", Placement = "Wall", Size = 80,
			Cost = 9000, CostGrowth = 1.3, Comfort = 3 },
		{ Id = "Sunflower", Name = "Sunflower", Icon = "🌻", Category = "Plants", Placement = "Floor", Size = 80,
			Cost = 7000, CostGrowth = 1.25, Comfort = 3 },
		{ Id = "Bouquet", Name = "Flower bouquet", Icon = "💐", Category = "Plants", Placement = "Floor", Size = 60,
			Cost = 12000, CostGrowth = 1.3, Comfort = 4 },
		{ Id = "RedRose", Name = "Red rose", Icon = "🌹", Category = "Plants", Placement = "Floor", Size = 50,
			Cost = 20000, CostGrowth = 1.3, Comfort = 4 },
		{ Id = "Monstera", Name = "Monstera", Icon = "🍃", Category = "Plants", Placement = "Floor", Size = 100,
			Cost = 25000, CostGrowth = 1.3, Comfort = 4 },
		{ Id = "Hibiscus", Name = "Hibiscus", Icon = "🌺", Category = "Plants", Placement = "Floor", Size = 60,
			Cost = 35000, CostGrowth = 1.3, Comfort = 4 },
		{ Id = "LuckyClover", Name = "Lucky clover", Icon = "🍀", Category = "Plants", Placement = "Floor", Size = 45,
			Cost = 50000, CostGrowth = 1.3, Comfort = 5 },
		{ Id = "Terrarium", Name = "Glass terrarium", Icon = "🐌", Category = "Plants", Placement = "Floor", Size = 60,
			Cost = 60000, CostGrowth = 1.35, Comfort = 5 },
		{ Id = "CherryBlossom", Name = "Cherry blossom branch", Icon = "🌸", Category = "Plants", Placement = "Floor", Size = 90,
			Cost = 80000, CostGrowth = 1.35, Comfort = 6 },
		{ Id = "MiniPine", Name = "Mini pine tree", Icon = "🌲", Category = "Plants", Placement = "Floor", Size = 120,
			Cost = 150000, CostGrowth = 1.35, Comfort = 6 },
		{ Id = "GiantMushroom", Name = "Giant mushroom", Icon = "🍄", Category = "Plants", Placement = "Floor", Size = 90,
			Cost = 300000, CostGrowth = 1.4, Comfort = 7 },
		{ Id = "IndoorTree", Name = "Indoor tree", Icon = "🌳", Category = "Plants", Placement = "Floor", Size = 140,
			Cost = 600000, CostGrowth = 1.4, Comfort = 9 },
		{ Id = "Bamboo", Name = "Wishing bamboo", Icon = "🎋", Category = "Plants", Placement = "Floor", Size = 130,
			Cost = 1.2e6, CostGrowth = 1.45, Comfort = 10 },
		{ Id = "PalmTree", Name = "Palm tree", Icon = "🌴", Category = "Plants", Placement = "Floor", Size = 150,
			Cost = 2.5e6, CostGrowth = 1.45, Comfort = 12 },
		{ Id = "HolidayTree", Name = "Holiday tree", Icon = "🎄", Category = "Plants", Placement = "Floor", Size = 140,
			Cost = 8e6, CostGrowth = 1.5, Comfort = 15 },

		-- 📺 Électronique
		{ Id = "RotaryPhone", Name = "Rotary phone", Icon = "☎️", Category = "Electronics", Placement = "Floor", Size = 50,
			Cost = 1800, CostGrowth = 1.2, Comfort = 1 },
		{ Id = "RetroRadio", Name = "Retro radio", Icon = "📻", Category = "Electronics", Placement = "Floor", Size = 60,
			Cost = 2000, CostGrowth = 1.25, Comfort = 2 },
		{ Id = "Smartphone", Name = "Smartphone", Icon = "📱", Category = "Electronics", Placement = "Floor", Size = 40,
			Cost = 5000, CostGrowth = 1.25, Comfort = 2 },
		{ Id = "InstantCamera", Name = "Instant camera", Icon = "📷", Category = "Electronics", Placement = "Floor", Size = 50,
			Cost = 8000, CostGrowth = 1.25, Comfort = 2 },
		{ Id = "Laptop", Name = "Laptop", Icon = "💻", Category = "Electronics", Placement = "Floor", Size = 70,
			Cost = 15000, CostGrowth = 1.3, Comfort = 3 },
		{ Id = "RetroHandheld", Name = "Pocket game", Icon = "👾", Category = "Electronics", Placement = "Floor", Size = 45,
			Cost = 18000, CostGrowth = 1.3, Comfort = 3 },
		{ Id = "RetroTV", Name = "Retro TV", Icon = "📺", Category = "Electronics", Placement = "Floor", Size = 100,
			Cost = 25000, CostGrowth = 1.3, Comfort = 5, Tabletop = true },
		{ Id = "RecordPlayer", Name = "Record player", Icon = "🎶", Category = "Electronics", Placement = "Floor", Size = 70,
			Cost = 28000, CostGrowth = 1.3, Comfort = 4 },
		{ Id = "CatHeadphones", Name = "Cat headphones", Icon = "🎧", Category = "Electronics", Placement = "Floor", Size = 50,
			Cost = 30000, CostGrowth = 1.3, Comfort = 3 },
		{ Id = "Speaker", Name = "Bass speaker", Icon = "🔊", Category = "Electronics", Placement = "Floor", Size = 70,
			Cost = 40000, CostGrowth = 1.3, Comfort = 4 },
		{ Id = "RobotVacuum", Name = "Robot vacuum", Icon = "🧹", Category = "Electronics", Placement = "Floor", Size = 60,
			Cost = 42000, CostGrowth = 1.3, Comfort = 4, Tabletop = false },
		{ Id = "AirConditioner", Name = "Air conditioner", Icon = "❄️", Category = "Electronics", Placement = "Wall", Size = 110,
			Cost = 45000, CostGrowth = 1.35, Comfort = 5 },
		{ Id = "DesktopPC", Name = "Desktop PC", Icon = "🖥️", Category = "Electronics", Placement = "Floor", Size = 90,
			Cost = 60000, CostGrowth = 1.35, Comfort = 5, Tabletop = true },
		{ Id = "GameConsole", Name = "Game console", Icon = "🎮", Category = "Electronics", Placement = "Floor", Size = 60,
			Cost = 100000, CostGrowth = 1.35, Comfort = 6 },
		{ Id = "KaraokeMic", Name = "Karaoke mic", Icon = "🎤", Category = "Electronics", Placement = "Floor", Size = 50,
			Cost = 150000, CostGrowth = 1.35, Comfort = 5 },
		{ Id = "ArcadeMachine", Name = "Arcade machine", Icon = "🕹️", Category = "Electronics", Placement = "Floor", Size = 120,
			Cost = 800000, CostGrowth = 1.4, Comfort = 10 },
		{ Id = "Projector", Name = "Movie projector", Icon = "📽️", Category = "Electronics", Placement = "Floor", Size = 90,
			Cost = 1.5e6, CostGrowth = 1.45, Comfort = 11, Tabletop = true },
		{ Id = "GrandPiano", Name = "Grand piano", Icon = "🎹", Category = "Electronics", Placement = "Floor", Size = 140,
			Cost = 2.5e6, CostGrowth = 1.45, Comfort = 12 },
		{ Id = "Telescope", Name = "Star telescope", Icon = "🔭", Category = "Electronics", Placement = "Floor", Size = 100,
			Cost = 4e6, CostGrowth = 1.45, Comfort = 12 },
		{ Id = "SlotMachine", Name = "Mini slot machine", Icon = "🎰", Category = "Electronics", Placement = "Floor", Size = 110,
			Cost = 1e7, CostGrowth = 1.5, Comfort = 14 },
		{ Id = "SatelliteDish", Name = "Satellite dish", Icon = "📡", Category = "Electronics", Placement = "Wall", Size = 80,
			Cost = 2e7, CostGrowth = 1.5, Comfort = 15 },
		{ Id = "VRGoggles", Name = "VR goggles", Icon = "🥽", Category = "Electronics", Placement = "Floor", Size = 50,
			Cost = 4e7, CostGrowth = 1.55, Comfort = 17 },
		{ Id = "HomeCinema", Name = "Home cinema", Icon = "🎬", Category = "Electronics", Placement = "Floor", Size = 150,
			Cost = 2e8, CostGrowth = 1.6, Comfort = 23 },

		-- 🍰 Cuisine
		{ Id = "CocoaMug", Name = "Cocoa mug", Icon = "☕", Category = "Kitchen", Placement = "Floor", Size = 40,
			Cost = 600, CostGrowth = 1.2, Comfort = 1 },
		{ Id = "StrawberryMilk", Name = "Strawberry milk", Icon = "🍓", Category = "Kitchen", Placement = "Floor", Size = 40,
			Cost = 800, CostGrowth = 1.2, Comfort = 1 },
		{ Id = "Watermelon", Name = "Watermelon", Icon = "🍉", Category = "Kitchen", Placement = "Floor", Size = 50,
			Cost = 1000, CostGrowth = 1.2, Comfort = 1 },
		{ Id = "Teapot", Name = "Teapot", Icon = "🫖", Category = "Kitchen", Placement = "Floor", Size = 50,
			Cost = 1200, CostGrowth = 1.2, Comfort = 2 },
		{ Id = "DonutBox", Name = "Donut box", Icon = "🍩", Category = "Kitchen", Placement = "Floor", Size = 50,
			Cost = 1500, CostGrowth = 1.2, Comfort = 1 },
		{ Id = "Pudding", Name = "Wobbly pudding", Icon = "🍮", Category = "Kitchen", Placement = "Floor", Size = 45,
			Cost = 2000, CostGrowth = 1.2, Comfort = 2 },
		{ Id = "StrawberryCake", Name = "Strawberry cake", Icon = "🍰", Category = "Kitchen", Placement = "Floor", Size = 50,
			Cost = 2500, CostGrowth = 1.25, Comfort = 2 },
		{ Id = "CroissantBasket", Name = "Croissant basket", Icon = "🥐", Category = "Kitchen", Placement = "Floor", Size = 50,
			Cost = 2800, CostGrowth = 1.25, Comfort = 2 },
		{ Id = "BubbleTea", Name = "Bubble tea", Icon = "🧋", Category = "Kitchen", Placement = "Floor", Size = 45,
			Cost = 3000, CostGrowth = 1.25, Comfort = 2 },
		{ Id = "CupcakeStand", Name = "Cupcake stand", Icon = "🧁", Category = "Kitchen", Placement = "Floor", Size = 55,
			Cost = 4000, CostGrowth = 1.25, Comfort = 2 },
		{ Id = "RamenBowl", Name = "Ramen bowl", Icon = "🍜", Category = "Kitchen", Placement = "Floor", Size = 50,
			Cost = 6000, CostGrowth = 1.25, Comfort = 3 },
		{ Id = "OnigiriPlate", Name = "Onigiri plate", Icon = "🍙", Category = "Kitchen", Placement = "Floor", Size = 45,
			Cost = 6500, CostGrowth = 1.25, Comfort = 2 },
		{ Id = "HoneyPot", Name = "Honey pot", Icon = "🍯", Category = "Kitchen", Placement = "Floor", Size = 45,
			Cost = 7000, CostGrowth = 1.25, Comfort = 2 },
		{ Id = "BentoBox", Name = "Bento box", Icon = "🍱", Category = "Kitchen", Placement = "Floor", Size = 50,
			Cost = 9000, CostGrowth = 1.25, Comfort = 3 },
		{ Id = "CookieJar", Name = "Cookie jar", Icon = "🍪", Category = "Kitchen", Placement = "Floor", Size = 50,
			Cost = 20000, CostGrowth = 1.3, Comfort = 3 },
		{ Id = "Fridge", Name = "Pastel fridge", Icon = "🧊", Category = "Kitchen", Placement = "Floor", Size = 120,
			Cost = 30000, CostGrowth = 1.35, Comfort = 5 },
		{ Id = "Stove", Name = "Cooking stove", Icon = "🍳", Category = "Kitchen", Placement = "Floor", Size = 100,
			Cost = 50000, CostGrowth = 1.35, Comfort = 5 },
		{ Id = "SushiPlatter", Name = "Sushi platter", Icon = "🍣", Category = "Kitchen", Placement = "Floor", Size = 60,
			Cost = 70000, CostGrowth = 1.3, Comfort = 5 },
		{ Id = "BirthdayCake", Name = "Birthday cake", Icon = "🎂", Category = "Kitchen", Placement = "Floor", Size = 70,
			Cost = 250000, CostGrowth = 1.35, Comfort = 7 },
		{ Id = "PancakeTower", Name = "Pancake tower", Icon = "🥞", Category = "Kitchen", Placement = "Floor", Size = 60,
			Cost = 400000, CostGrowth = 1.4, Comfort = 7 },
		{ Id = "GiantLollipop", Name = "Giant lollipop", Icon = "🍭", Category = "Kitchen", Placement = "Floor", Size = 90,
			Cost = 900000, CostGrowth = 1.4, Comfort = 9 },
		{ Id = "SundaeBar", Name = "Sundae bar", Icon = "🍨", Category = "Kitchen", Placement = "Floor", Size = 90,
			Cost = 2e6, CostGrowth = 1.45, Comfort = 11 },
		{ Id = "ChocolateFountain", Name = "Chocolate fountain", Icon = "🍫", Category = "Kitchen", Placement = "Floor", Size = 100,
			Cost = 6e6, CostGrowth = 1.45, Comfort = 13 },
		{ Id = "ShavedIceMachine", Name = "Shaved ice machine", Icon = "🍧", Category = "Kitchen", Placement = "Floor", Size = 100,
			Cost = 3e7, CostGrowth = 1.55, Comfort = 16 },

		-- 🚪 Portes (posées au sol, contre le mur)
		{ Id = "WoodenDoor", Name = "Wooden door", Icon = "🚪", Category = "Doors", Placement = "Floor", Size = 130,
			Cost = 1000, CostGrowth = 1.5, Comfort = 1, MaxOwned = 3 },
		{ Id = "MouseHole", Name = "Mouse hole", Icon = "🐭", Category = "Doors", Placement = "Floor", Size = 40,
			Cost = 3000, CostGrowth = 1.5, Comfort = 2, MaxOwned = 3 },
		{ Id = "GardenDoor", Name = "Garden door", Icon = "🏡", Category = "Doors", Placement = "Floor", Size = 130,
			Cost = 20000, CostGrowth = 1.5, Comfort = 3, MaxOwned = 2 },
		{ Id = "HeartDoor", Name = "Heart door", Icon = "💗", Category = "Doors", Placement = "Floor", Size = 130,
			Cost = 60000, CostGrowth = 1.5, Comfort = 5, MaxOwned = 2 },
		{ Id = "ShojiDoor", Name = "Sliding shoji door", Icon = "🎎", Category = "Doors", Placement = "Floor", Size = 130,
			Cost = 150000, CostGrowth = 1.5, Comfort = 6, MaxOwned = 2 },
		{ Id = "ToriiGate", Name = "Torii gate", Icon = "⛩️", Category = "Doors", Placement = "Floor", Size = 150,
			Cost = 500000, CostGrowth = 1.6, Comfort = 8, MaxOwned = 2 },
		{ Id = "SecretDoor", Name = "Secret bookshelf door", Icon = "🔑", Category = "Doors", Placement = "Floor", Size = 130,
			Cost = 900000, CostGrowth = 1.55, Comfort = 9, MaxOwned = 1 },
		{ Id = "Elevator", Name = "Private elevator", Icon = "🛗", Category = "Doors", Placement = "Floor", Size = 140,
			Cost = 2e6, CostGrowth = 1.6, Comfort = 10, MaxOwned = 1 },
		{ Id = "CandyDoor", Name = "Candy door", Icon = "🍬", Category = "Doors", Placement = "Floor", Size = 130,
			Cost = 8e6, CostGrowth = 1.6, Comfort = 13, MaxOwned = 2 },
		{ Id = "DreamPortal", Name = "Dream portal", Icon = "🌀", Category = "Doors", Placement = "Floor", Size = 150,
			Cost = 1e8, CostGrowth = 1.7, Comfort = 21, MaxOwned = 1 },

		-- 🪟 Fenêtres (au mur)
		{ Id = "CurtainWindow", Name = "Window with curtains", Icon = "🪟", Category = "Windows", Placement = "Wall", Size = 110,
			Cost = 1500, CostGrowth = 1.4, Comfort = 2, MaxOwned = 4 },
		{ Id = "CloudyWindow", Name = "Cloudy window", Icon = "⛅", Category = "Windows", Placement = "Wall", Size = 110,
			Cost = 6000, CostGrowth = 1.4, Comfort = 3, MaxOwned = 3 },
		{ Id = "RainyWindow", Name = "Rainy window", Icon = "🌧️", Category = "Windows", Placement = "Wall", Size = 110,
			Cost = 25000, CostGrowth = 1.4, Comfort = 4, MaxOwned = 3 },
		{ Id = "SunsetWindow", Name = "Sunset window", Icon = "🌇", Category = "Windows", Placement = "Wall", Size = 120,
			Cost = 150000, CostGrowth = 1.45, Comfort = 6, MaxOwned = 3 },
		{ Id = "PortholeWindow", Name = "Ocean porthole", Icon = "🐬", Category = "Windows", Placement = "Wall", Size = 100,
			Cost = 300000, CostGrowth = 1.45, Comfort = 7, MaxOwned = 3 },
		{ Id = "CityNightWindow", Name = "City night window", Icon = "🌃", Category = "Windows", Placement = "Wall", Size = 120,
			Cost = 600000, CostGrowth = 1.45, Comfort = 8, MaxOwned = 3 },
		{ Id = "SakuraWindow", Name = "Sakura window", Icon = "💮", Category = "Windows", Placement = "Wall", Size = 120,
			Cost = 1.2e6, CostGrowth = 1.45, Comfort = 9, MaxOwned = 2 },
		{ Id = "MountainWindow", Name = "Mountain view", Icon = "🏔️", Category = "Windows", Placement = "Wall", Size = 130,
			Cost = 3e6, CostGrowth = 1.5, Comfort = 11, MaxOwned = 2 },
		{ Id = "BeachWindow", Name = "Beach view", Icon = "🏖️", Category = "Windows", Placement = "Wall", Size = 130,
			Cost = 1.5e7, CostGrowth = 1.5, Comfort = 15, MaxOwned = 2 },
		{ Id = "ShootingStarWindow", Name = "Shooting star window", Icon = "🌠", Category = "Windows", Placement = "Wall", Size = 130,
			Cost = 6e7, CostGrowth = 1.55, Comfort = 19, MaxOwned = 2 },
		{ Id = "GalaxyWindow", Name = "Galaxy window", Icon = "🌌", Category = "Windows", Placement = "Wall", Size = 140,
			Cost = 4e8, CostGrowth = 1.6, Comfort = 24, MaxOwned = 2 },

		-- 💡 Lumières
		{ Id = "ScentedCandle", Name = "Scented candle", Icon = "🕯️", Category = "Lights", Placement = "Floor", Size = 40,
			Cost = 700, CostGrowth = 1.2, Comfort = 1 },
		{ Id = "HangingBulb", Name = "Hanging bulb", Icon = "💡", Category = "Lights", Placement = "Wall", Size = 50,
			Cost = 1200, CostGrowth = 1.2, Comfort = 1 },
		{ Id = "FairyLights", Name = "Fairy lights", Icon = "✨", Category = "Lights", Placement = "Wall", Size = 140,
			Cost = 4000, CostGrowth = 1.25, Comfort = 3 },
		{ Id = "PaperLantern", Name = "Paper lantern", Icon = "🏮", Category = "Lights", Placement = "Wall", Size = 70,
			Cost = 10000, CostGrowth = 1.3, Comfort = 3 },
		{ Id = "FloorLamp", Name = "Tall floor lamp", Icon = "🌟", Category = "Lights", Placement = "Floor", Size = 130,
			Cost = 15000, CostGrowth = 1.3, Comfort = 3 },
		{ Id = "OilLamp", Name = "Little oil lamp", Icon = "🪔", Category = "Lights", Placement = "Floor", Size = 50,
			Cost = 25000, CostGrowth = 1.3, Comfort = 4 },
		{ Id = "StarNightLight", Name = "Star night-light", Icon = "⭐", Category = "Lights", Placement = "Floor", Size = 60,
			Cost = 60000, CostGrowth = 1.3, Comfort = 5 },
		{ Id = "SparklerLights", Name = "Sparkler lights", Icon = "🎇", Category = "Lights", Placement = "Wall", Size = 80,
			Cost = 90000, CostGrowth = 1.35, Comfort = 5 },
		{ Id = "CloudLamp", Name = "Cloud lamp", Icon = "💭", Category = "Lights", Placement = "Wall", Size = 90,
			Cost = 150000, CostGrowth = 1.35, Comfort = 6 },
		{ Id = "NeonHeart", Name = "Neon heart sign", Icon = "💞", Category = "Lights", Placement = "Wall", Size = 90,
			Cost = 200000, CostGrowth = 1.35, Comfort = 7 },
		{ Id = "MoonLamp", Name = "Moon lamp", Icon = "🌕", Category = "Lights", Placement = "Floor", Size = 70,
			Cost = 400000, CostGrowth = 1.4, Comfort = 8 },
		{ Id = "DiscoBall", Name = "Disco ball", Icon = "💿", Category = "Lights", Placement = "Wall", Size = 80,
			Cost = 600000, CostGrowth = 1.4, Comfort = 8, MaxOwned = 2 },
		{ Id = "RainbowProjector", Name = "Rainbow projector", Icon = "🌈", Category = "Lights", Placement = "Wall", Size = 100,
			Cost = 1e6, CostGrowth = 1.4, Comfort = 10 },
		{ Id = "LavaLamp", Name = "Lava lamp", Icon = "🌋", Category = "Lights", Placement = "Floor", Size = 60,
			Cost = 3e6, CostGrowth = 1.45, Comfort = 12 },
		{ Id = "UFOLamp", Name = "UFO lamp", Icon = "🛸", Category = "Lights", Placement = "Wall", Size = 90,
			Cost = 6e6, CostGrowth = 1.45, Comfort = 13 },
		{ Id = "CrystalChandelier", Name = "Crystal chandelier", Icon = "💠", Category = "Lights", Placement = "Wall", Size = 120,
			Cost = 3e7, CostGrowth = 1.55, Comfort = 17 },
		{ Id = "PocketSun", Name = "Pocket sun", Icon = "☀️", Category = "Lights", Placement = "Wall", Size = 100,
			Cost = 1e9, CostGrowth = 1.7, Comfort = 25, MaxOwned = 1 },

		-- 🐾 Animaux (ils bougent !)
		{ Id = "Chick", Name = "Baby chick", Icon = "🐤", Category = "Pets", Placement = "Floor", Size = 40,
			Cost = 1200, CostGrowth = 1.2, Comfort = 1 },
		{ Id = "Goldfish", Name = "Goldfish bowl", Icon = "🐟", Category = "Pets", Placement = "Floor", Size = 55,
			Cost = 2500, CostGrowth = 1.25, Comfort = 2 },
		{ Id = "SleepyCat", Name = "Sleepy cat", Icon = "🐈", Category = "Pets", Placement = "Floor", Size = 70,
			Cost = 8000, CostGrowth = 1.3, Comfort = 3 },
		{ Id = "Turtle", Name = "Tiny turtle", Icon = "🐢", Category = "Pets", Placement = "Floor", Size = 50,
			Cost = 15000, CostGrowth = 1.3, Comfort = 3 },
		{ Id = "Puppy", Name = "Happy puppy", Icon = "🐕", Category = "Pets", Placement = "Floor", Size = 75,
			Cost = 30000, CostGrowth = 1.3, Comfort = 4 },
		{ Id = "Bunny", Name = "Fluffy bunny", Icon = "🐇", Category = "Pets", Placement = "Floor", Size = 60,
			Cost = 60000, CostGrowth = 1.35, Comfort = 5 },
		{ Id = "Hamster", Name = "Hamster wheel", Icon = "🐁", Category = "Pets", Placement = "Floor", Size = 70,
			Cost = 120000, CostGrowth = 1.35, Comfort = 5 },
		{ Id = "Parrot", Name = "Parrot on a perch", Icon = "🦜", Category = "Pets", Placement = "Floor", Size = 110,
			Cost = 300000, CostGrowth = 1.4, Comfort = 7 },
		{ Id = "Fox", Name = "Fluffy fox", Icon = "🦊", Category = "Pets", Placement = "Floor", Size = 80,
			Cost = 1.5e6, CostGrowth = 1.45, Comfort = 10 },
		{ Id = "Dragon", Name = "Baby dragon", Icon = "🐉", Category = "Pets", Placement = "Floor", Size = 120,
			Cost = 5e7, CostGrowth = 1.6, Comfort = 18 },
		-- 🐾 Pour les animaux (niche, arbre à chat...) : les animaux vont s'en servir
		{ Id = "PetBowl", Name = "Food bowl", Icon = "🥣", Category = "Pets", Placement = "Floor", Size = 40,
			Cost = 3000, CostGrowth = 1.2, Comfort = 1, Tabletop = false },
		{ Id = "PetToys", Name = "Pet toy basket", Icon = "🎾", Category = "Pets", Placement = "Floor", Size = 50,
			Cost = 6000, CostGrowth = 1.25, Comfort = 2 },
		{ Id = "PetBed", Name = "Cozy pet bed", Icon = "🧺", Category = "Pets", Placement = "Floor", Size = 70,
			Cost = 9000, CostGrowth = 1.3, Comfort = 3 },
		{ Id = "ScratchingPost", Name = "Scratching post", Icon = "🪵", Category = "Pets", Placement = "Floor", Size = 90,
			Cost = 18000, CostGrowth = 1.3, Comfort = 3 },
		{ Id = "PetFountain", Name = "Pet water fountain", Icon = "💧", Category = "Pets", Placement = "Floor", Size = 50,
			Cost = 25000, CostGrowth = 1.3, Comfort = 3, Tabletop = false },
		{ Id = "DogHouse", Name = "Dog house", Icon = "🦴", Category = "Pets", Placement = "Floor", Size = 110,
			Cost = 45000, CostGrowth = 1.35, Comfort = 5 },
		{ Id = "BirdCage", Name = "Bird cage", Icon = "🕊️", Category = "Pets", Placement = "Floor", Size = 100,
			Cost = 90000, CostGrowth = 1.35, Comfort = 5 },
		{ Id = "CatTree", Name = "Cat tree", Icon = "😺", Category = "Pets", Placement = "Floor", Size = 140,
			Cost = 160000, CostGrowth = 1.4, Comfort = 7 },

		-- v9 🍽️ Tables et meubles à dessus VIDE : on y pose ce qu'on veut
		{ Id = "SideTable", Name = "Round side table", Icon = "🟤", Category = "Furniture", Placement = "Floor", Size = 60,
			Cost = 800, CostGrowth = 1.2, Comfort = 1 },
		{ Id = "CafeTable", Name = "Round café table", Icon = "☕", Category = "Furniture", Placement = "Floor", Size = 85,
			Cost = 1800, CostGrowth = 1.25, Comfort = 2 },
		{ Id = "CoffeeTable", Name = "Coffee table", Icon = "🗞️", Category = "Furniture", Placement = "Floor", Size = 110,
			Cost = 3500, CostGrowth = 1.25, Comfort = 2 },
		{ Id = "DiningTable", Name = "Dining table", Icon = "🍽️", Category = "Furniture", Placement = "Floor", Size = 140,
			Cost = 6000, CostGrowth = 1.3, Comfort = 3 },
		{ Id = "BarTable", Name = "Tall bar table", Icon = "🍹", Category = "Furniture", Placement = "Floor", Size = 90,
			Cost = 12000, CostGrowth = 1.3, Comfort = 3 },
		{ Id = "Dresser", Name = "Pastel dresser", Icon = "👚", Category = "Furniture", Placement = "Floor", Size = 110,
			Cost = 20000, CostGrowth = 1.3, Comfort = 4 },
		{ Id = "TVStand", Name = "TV stand", Icon = "📼", Category = "Furniture", Placement = "Floor", Size = 120,
			Cost = 25000, CostGrowth = 1.3, Comfort = 4 },
		{ Id = "KitchenIsland", Name = "Kitchen island", Icon = "🧂", Category = "Furniture", Placement = "Floor", Size = 140,
			Cost = 60000, CostGrowth = 1.35, Comfort = 5 },
		{ Id = "PicnicTable", Name = "Picnic table", Icon = "🧺", Category = "Furniture", Placement = "Floor", Size = 150,
			Cost = 120000, CostGrowth = 1.35, Comfort = 6 },
		{ Id = "BigDesk", Name = "Big wooden desk", Icon = "🖋️", Category = "Furniture", Placement = "Floor", Size = 150,
			Cost = 600000, CostGrowth = 1.4, Comfort = 9 },
		-- v9 🪑 Sièges (à la table, sur les côtés, ou n'importe où)
		{ Id = "MushroomStool", Name = "Mushroom stool", Icon = "🍄", Category = "Furniture", Placement = "Floor", Size = 55,
			Cost = 900, CostGrowth = 1.2, Comfort = 1 },
		{ Id = "FloorCushion", Name = "Floor cushions", Icon = "🍡", Category = "Furniture", Placement = "Floor", Size = 50,
			Cost = 1000, CostGrowth = 1.2, Comfort = 1 },
		{ Id = "DiningChair", Name = "Dining chair", Icon = "🪑", Category = "Furniture", Placement = "Floor", Size = 85,
			Cost = 2200, CostGrowth = 1.2, Comfort = 2 },
		{ Id = "BarStool", Name = "Bar stool", Icon = "🥤", Category = "Furniture", Placement = "Floor", Size = 85,
			Cost = 8000, CostGrowth = 1.25, Comfort = 2 },
		{ Id = "Armchair", Name = "Cozy armchair", Icon = "🛋️", Category = "Furniture", Placement = "Floor", Size = 100,
			Cost = 35000, CostGrowth = 1.3, Comfort = 5 },
		{ Id = "GardenBench", Name = "Garden bench", Icon = "🏞️", Category = "Furniture", Placement = "Floor", Size = 120,
			Cost = 80000, CostGrowth = 1.3, Comfort = 5 },
		{ Id = "RockingChair", Name = "Rocking chair", Icon = "🧶", Category = "Furniture", Placement = "Floor", Size = 105,
			Cost = 250000, CostGrowth = 1.35, Comfort = 7 },
		{ Id = "DoubleBed", Name = "Big comfy bed", Icon = "🛏️", Category = "Furniture", Placement = "Floor", Size = 155,
			Cost = 4e6, CostGrowth = 1.45, Comfort = 13 },
		{ Id = "EggChair", Name = "Hanging egg chair", Icon = "🥚", Category = "Furniture", Placement = "Floor", Size = 130,
			Cost = 9e6, CostGrowth = 1.5, Comfort = 14 },
		-- v9 Petits objets à poser partout (tables, étagères, lit, canapé...)
		{ Id = "BookStack", Name = "Book stack", Icon = "📖", Category = "Decor", Placement = "Floor", Size = 45,
			Cost = 900, CostGrowth = 1.2, Comfort = 1 },
		{ Id = "HeartPillow", Name = "Heart pillow", Icon = "💝", Category = "Decor", Placement = "Floor", Size = 50,
			Cost = 1100, CostGrowth = 1.2, Comfort = 1 },
		{ Id = "MoonPillow", Name = "Moon pillow", Icon = "🌛", Category = "Decor", Placement = "Floor", Size = 50,
			Cost = 2000, CostGrowth = 1.2, Comfort = 2 },
		{ Id = "PhotoFrame", Name = "Photo frame", Icon = "🖼️", Category = "Decor", Placement = "Floor", Size = 45,
			Cost = 2400, CostGrowth = 1.2, Comfort = 2 },
		{ Id = "FloatingShelf", Name = "Floating shelf", Icon = "🔖", Category = "Decor", Placement = "Wall", Size = 110,
			Cost = 5000, CostGrowth = 1.25, Comfort = 2 },
		{ Id = "BlanketStack", Name = "Blanket stack", Icon = "🧣", Category = "Decor", Placement = "Floor", Size = 60,
			Cost = 9000, CostGrowth = 1.25, Comfort = 3 },
		{ Id = "PiggyBank", Name = "Piggy bank", Icon = "🐷", Category = "Decor", Placement = "Floor", Size = 45,
			Cost = 30000, CostGrowth = 1.3, Comfort = 3 },
		{ Id = "SnowGlobe", Name = "Snow globe", Icon = "☃️", Category = "Decor", Placement = "Floor", Size = 50,
			Cost = 450000, CostGrowth = 1.4, Comfort = 7 },
		{ Id = "MusicBox", Name = "Ballerina music box", Icon = "🎵", Category = "Decor", Placement = "Floor", Size = 55,
			Cost = 1.8e6, CostGrowth = 1.45, Comfort = 10 },
		{ Id = "MiniAquarium", Name = "Mini aquarium", Icon = "🐡", Category = "Decor", Placement = "Floor", Size = 70,
			Cost = 4.5e6, CostGrowth = 1.45, Comfort = 12 },
		{ Id = "JewelryBox", Name = "Royal jewelry box", Icon = "💍", Category = "Decor", Placement = "Floor", Size = 55,
			Cost = 6e8, CostGrowth = 1.6, Comfort = 23 },
		{ Id = "FruitBowl", Name = "Fruit bowl", Icon = "🍎", Category = "Kitchen", Placement = "Floor", Size = 45,
			Cost = 700, CostGrowth = 1.2, Comfort = 1 },
		{ Id = "PizzaPlate", Name = "Pizza plate", Icon = "🍕", Category = "Kitchen", Placement = "Floor", Size = 45,
			Cost = 1300, CostGrowth = 1.2, Comfort = 1 },
		{ Id = "Lemonade", Name = "Lemonade pitcher", Icon = "🍋", Category = "Kitchen", Placement = "Floor", Size = 50,
			Cost = 1600, CostGrowth = 1.2, Comfort = 1 },
		{ Id = "TeaSet", Name = "Tea set", Icon = "🍵", Category = "Kitchen", Placement = "Floor", Size = 55,
			Cost = 3200, CostGrowth = 1.2, Comfort = 2 },
		{ Id = "SaladBowl", Name = "Salad bowl", Icon = "🥗", Category = "Kitchen", Placement = "Floor", Size = 45,
			Cost = 5000, CostGrowth = 1.25, Comfort = 2 },
		{ Id = "Toaster", Name = "Happy toaster", Icon = "🍞", Category = "Kitchen", Placement = "Floor", Size = 50,
			Cost = 6500, CostGrowth = 1.25, Comfort = 2 },
		{ Id = "MacaronTower", Name = "Macaron tower", Icon = "🍬", Category = "Kitchen", Placement = "Floor", Size = 60,
			Cost = 22000, CostGrowth = 1.3, Comfort = 3 },
		{ Id = "Microwave", Name = "Cute microwave", Icon = "🍿", Category = "Kitchen", Placement = "Floor", Size = 65,
			Cost = 38000, CostGrowth = 1.3, Comfort = 4 },
		{ Id = "FlowerVase", Name = "Vase of flowers", Icon = "🏵️", Category = "Plants", Placement = "Floor", Size = 60,
			Cost = 11000, CostGrowth = 1.25, Comfort = 3 },
		{ Id = "Bonsai", Name = "Tiny bonsai", Icon = "🌳", Category = "Plants", Placement = "Floor", Size = 60,
			Cost = 180000, CostGrowth = 1.35, Comfort = 6 },
		{ Id = "DeskLamp", Name = "Desk lamp", Icon = "💡", Category = "Lights", Placement = "Floor", Size = 55,
			Cost = 7500, CostGrowth = 1.25, Comfort = 2 },
		{ Id = "MushroomLamp", Name = "Mushroom lamp", Icon = "🍄", Category = "Lights", Placement = "Floor", Size = 55,
			Cost = 110000, CostGrowth = 1.35, Comfort = 5 },
		{ Id = "Candelabra", Name = "Crystal candelabra", Icon = "🕯️", Category = "Lights", Placement = "Floor", Size = 70,
			Cost = 5e7, CostGrowth = 1.55, Comfort = 19 },
		{ Id = "AlarmClock", Name = "Alarm clock", Icon = "⏰", Category = "Electronics", Placement = "Floor", Size = 40,
			Cost = 4200, CostGrowth = 1.2, Comfort = 2 },
		{ Id = "Typewriter", Name = "Typewriter", Icon = "⌨️", Category = "Electronics", Placement = "Floor", Size = 60,
			Cost = 50000, CostGrowth = 1.3, Comfort = 4 },
		{ Id = "DeskFan", Name = "Desk fan", Icon = "🌬️", Category = "Electronics", Placement = "Floor", Size = 55,
			Cost = 85000, CostGrowth = 1.3, Comfort = 4 },
		{ Id = "DrawingTablet", Name = "Drawing tablet", Icon = "✍️", Category = "Electronics", Placement = "Floor", Size = 55,
			Cost = 260000, CostGrowth = 1.35, Comfort = 6 },
		{ Id = "BoardGame", Name = "Board game", Icon = "♟️", Category = "Toys", Placement = "Floor", Size = 50,
			Cost = 14000, CostGrowth = 1.25, Comfort = 3 },
		{ Id = "WhalePlush", Name = "Whale plush", Icon = "🐳", Category = "Toys", Placement = "Floor", Size = 55,
			Cost = 16000, CostGrowth = 1.25, Comfort = 3 },
		{ Id = "OctopusPlush", Name = "Octopus plush", Icon = "🐙", Category = "Toys", Placement = "Floor", Size = 55,
			Cost = 65000, CostGrowth = 1.3, Comfort = 4 },
		{ Id = "Kitten", Name = "Calico kitten", Icon = "🐱", Category = "Pets", Placement = "Floor", Size = 60,
			Cost = 45000, CostGrowth = 1.3, Comfort = 4 },
		{ Id = "Hedgehog", Name = "Tiny hedgehog", Icon = "🦔", Category = "Pets", Placement = "Floor", Size = 50,
			Cost = 350000, CostGrowth = 1.35, Comfort = 6 },

		-- v9.1 🛍️ 48 nouveaux objets (dessins : Art/Cozy91, Art/Fun91, Art/Nature91)
		{ Id = "ToyChest", Name = "Toy chest", Icon = "🧰", Category = "Furniture", Placement = "Floor", Size = 80,
			Cost = 4500, CostGrowth = 1.25, Comfort = 3 },
		{ Id = "Pouf", Name = "Fluffy pouf", Icon = "🍥", Category = "Furniture", Placement = "Floor", Size = 55,
			Cost = 2600, CostGrowth = 1.2, Comfort = 2 },
		{ Id = "LadderShelf", Name = "Ladder shelf", Icon = "🪜", Category = "Furniture", Placement = "Floor", Size = 120,
			Cost = 14000, CostGrowth = 1.3, Comfort = 3 },
		{ Id = "KotatsuTable", Name = "Kotatsu table", Icon = "🍊", Category = "Furniture", Placement = "Floor", Size = 130,
			Cost = 40000, CostGrowth = 1.3, Comfort = 5 },
		{ Id = "HeartArmchair", Name = "Heart armchair", Icon = "💗", Category = "Furniture", Placement = "Floor", Size = 100,
			Cost = 90000, CostGrowth = 1.3, Comfort = 6 },
		{ Id = "Hammock", Name = "Cozy hammock", Icon = "🌴", Category = "Furniture", Placement = "Floor", Size = 140,
			Cost = 180000, CostGrowth = 1.35, Comfort = 7 },
		{ Id = "CatSofa", Name = "Kitty sofa", Icon = "😸", Category = "Furniture", Placement = "Floor", Size = 150,
			Cost = 3.5e6, CostGrowth = 1.45, Comfort = 13 },
		{ Id = "CrystalThrone", Name = "Crystal throne", Icon = "💎", Category = "Furniture", Placement = "Floor", Size = 140,
			Cost = 4e8, CostGrowth = 1.6, Comfort = 25 },
		{ Id = "HeartRug", Name = "Heart rug", Icon = "💞", Category = "Decor", Placement = "Floor", Size = 100,
			Cost = 2800, CostGrowth = 1.2, Comfort = 2, Tabletop = false },
		{ Id = "StarGarland", Name = "Star garland", Icon = "🌟", Category = "Decor", Placement = "Wall", Size = 130,
			Cost = 6500, CostGrowth = 1.25, Comfort = 2 },
		{ Id = "KittyClock", Name = "Kitty wall clock", Icon = "🕐", Category = "Decor", Placement = "Wall", Size = 70,
			Cost = 11000, CostGrowth = 1.25, Comfort = 3, MaxOwned = 2 },
		{ Id = "Tapestry", Name = "Rainbow tapestry", Icon = "🌈", Category = "Decor", Placement = "Wall", Size = 100,
			Cost = 16000, CostGrowth = 1.25, Comfort = 3 },
		{ Id = "ButterflyFrame", Name = "Butterfly frame", Icon = "🦋", Category = "Decor", Placement = "Wall", Size = 70,
			Cost = 38000, CostGrowth = 1.3, Comfort = 4 },
		{ Id = "CloudRug", Name = "Cloud rug", Icon = "☁️", Category = "Decor", Placement = "Floor", Size = 130,
			Cost = 55000, CostGrowth = 1.3, Comfort = 4, Tabletop = false },
		{ Id = "Mannequin", Name = "Dress form", Icon = "👗", Category = "Decor", Placement = "Floor", Size = 110,
			Cost = 95000, CostGrowth = 1.3, Comfort = 5 },
		{ Id = "Harp", Name = "Golden harp", Icon = "🎼", Category = "Decor", Placement = "Floor", Size = 120,
			Cost = 8e6, CostGrowth = 1.5, Comfort = 14 },
		{ Id = "SwanStatue", Name = "Swan statue", Icon = "🦢", Category = "Decor", Placement = "Floor", Size = 90,
			Cost = 1.8e7, CostGrowth = 1.5, Comfort = 16 },
		{ Id = "CrownCushion", Name = "Crown on a cushion", Icon = "👑", Category = "Decor", Placement = "Floor", Size = 50,
			Cost = 1.2e8, CostGrowth = 1.55, Comfort = 21 },
		{ Id = "ToyBlocks", Name = "Alphabet blocks", Icon = "🔤", Category = "Toys", Placement = "Floor", Size = 50,
			Cost = 1700, CostGrowth = 1.2, Comfort = 1 },
		{ Id = "Xylophone", Name = "Toy xylophone", Icon = "🎶", Category = "Toys", Placement = "Floor", Size = 60,
			Cost = 7500, CostGrowth = 1.25, Comfort = 2 },
		{ Id = "JackInTheBox", Name = "Jack-in-the-box", Icon = "🤡", Category = "Toys", Placement = "Floor", Size = 60,
			Cost = 24000, CostGrowth = 1.3, Comfort = 4 },
		{ Id = "ToyCar", Name = "Pink toy car", Icon = "🚗", Category = "Toys", Placement = "Floor", Size = 70,
			Cost = 48000, CostGrowth = 1.3, Comfort = 4 },
		{ Id = "PlushPile", Name = "Plush pile", Icon = "🧸", Category = "Toys", Placement = "Floor", Size = 90,
			Cost = 700000, CostGrowth = 1.4, Comfort = 9 },
		{ Id = "SucculentTrio", Name = "Succulent trio", Icon = "🌵", Category = "Plants", Placement = "Floor", Size = 55,
			Cost = 4800, CostGrowth = 1.2, Comfort = 2 },
		{ Id = "LavenderPot", Name = "Lavender pot", Icon = "💜", Category = "Plants", Placement = "Floor", Size = 55,
			Cost = 13000, CostGrowth = 1.25, Comfort = 3 },
		{ Id = "HangingTerrarium", Name = "Hanging terrarium", Icon = "🍃", Category = "Plants", Placement = "Wall", Size = 70,
			Cost = 32000, CostGrowth = 1.3, Comfort = 4 },
		{ Id = "LotusBowl", Name = "Lotus bowl", Icon = "🪷", Category = "Plants", Placement = "Floor", Size = 60,
			Cost = 140000, CostGrowth = 1.35, Comfort = 6 },
		{ Id = "RainbowTree", Name = "Rainbow tree", Icon = "🌈", Category = "Plants", Placement = "Floor", Size = 150,
			Cost = 2.5e8, CostGrowth = 1.6, Comfort = 25 },
		{ Id = "RetroComputer", Name = "Retro computer", Icon = "💾", Category = "Electronics", Placement = "Floor", Size = 70,
			Cost = 34000, CostGrowth = 1.3, Comfort = 4, Tabletop = true },
		{ Id = "Jukebox", Name = "Jukebox", Icon = "📀", Category = "Electronics", Placement = "Floor", Size = 130,
			Cost = 3.2e6, CostGrowth = 1.45, Comfort = 13 },
		{ Id = "PinballMachine", Name = "Pinball machine", Icon = "🎯", Category = "Electronics", Placement = "Floor", Size = 130,
			Cost = 1.2e7, CostGrowth = 1.5, Comfort = 15 },
		{ Id = "Hologram", Name = "Holo projector", Icon = "🌐", Category = "Electronics", Placement = "Floor", Size = 70,
			Cost = 6e7, CostGrowth = 1.55, Comfort = 19 },
		{ Id = "Popsicles", Name = "Popsicle trio", Icon = "🍦", Category = "Kitchen", Placement = "Floor", Size = 45,
			Cost = 3900, CostGrowth = 1.2, Comfort = 2 },
		{ Id = "WaffleMaker", Name = "Waffle maker", Icon = "🧇", Category = "Kitchen", Placement = "Floor", Size = 55,
			Cost = 8800, CostGrowth = 1.25, Comfort = 2 },
		{ Id = "DumplingSteamer", Name = "Dumpling steamer", Icon = "🥟", Category = "Kitchen", Placement = "Floor", Size = 50,
			Cost = 15000, CostGrowth = 1.25, Comfort = 3 },
		{ Id = "KitchenSink", Name = "Kitchen sink", Icon = "🚰", Category = "Kitchen", Placement = "Floor", Size = 100,
			Cost = 26000, CostGrowth = 1.3, Comfort = 4, Tabletop = false },
		{ Id = "GingerbreadHouse", Name = "Gingerbread house", Icon = "🏠", Category = "Kitchen", Placement = "Floor", Size = 70,
			Cost = 520000, CostGrowth = 1.4, Comfort = 8 },
		{ Id = "TulipLamp", Name = "Tulip lamp", Icon = "🌷", Category = "Lights", Placement = "Floor", Size = 60,
			Cost = 19000, CostGrowth = 1.25, Comfort = 3 },
		{ Id = "JellyfishLamp", Name = "Jellyfish lamp", Icon = "🎐", Category = "Lights", Placement = "Floor", Size = 70,
			Cost = 330000, CostGrowth = 1.35, Comfort = 7 },
		{ Id = "NeonStar", Name = "Neon star sign", Icon = "⭐", Category = "Lights", Placement = "Wall", Size = 90,
			Cost = 750000, CostGrowth = 1.4, Comfort = 8 },
		{ Id = "ArchWindow", Name = "Arched window", Icon = "🌙", Category = "Windows", Placement = "Wall", Size = 120,
			Cost = 45000, CostGrowth = 1.4, Comfort = 5, MaxOwned = 3 },
		{ Id = "StainedGlass", Name = "Stained glass window", Icon = "🪟", Category = "Windows", Placement = "Wall", Size = 120,
			Cost = 2.2e6, CostGrowth = 1.45, Comfort = 10, MaxOwned = 2 },
		{ Id = "DutchDoor", Name = "Pastel dutch door", Icon = "🚪", Category = "Doors", Placement = "Floor", Size = 130,
			Cost = 8000, CostGrowth = 1.5, Comfort = 2, MaxOwned = 2 },
		{ Id = "CastleGate", Name = "Castle gate", Icon = "🏰", Category = "Doors", Placement = "Floor", Size = 150,
			Cost = 4e7, CostGrowth = 1.6, Comfort = 18, MaxOwned = 1 },
		{ Id = "Duckling", Name = "Little duckling", Icon = "🐥", Category = "Pets", Placement = "Floor", Size = 40,
			Cost = 5500, CostGrowth = 1.2, Comfort = 2 },
		{ Id = "Penguin", Name = "Little penguin", Icon = "🐧", Category = "Pets", Placement = "Floor", Size = 60,
			Cost = 220000, CostGrowth = 1.35, Comfort = 6 },
		{ Id = "Axolotl", Name = "Axolotl tank", Icon = "🦎", Category = "Pets", Placement = "Floor", Size = 70,
			Cost = 900000, CostGrowth = 1.4, Comfort = 9 },
		{ Id = "Owl", Name = "Sleepy owl", Icon = "🦉", Category = "Pets", Placement = "Floor", Size = 70,
			Cost = 3.6e6, CostGrowth = 1.45, Comfort = 12 },

		-- v9.2 🎮🏀🚀 51 objets "cool" : jeux vidéo, sport, véhicules, dinos,
		-- espace, robots, musique rock, pirates, ninjas (dessins : Art/Cool92*)
		-- 🎮 Jeux vidéo
		{ Id = "RGBHeadset", Name = "Gamer headset", Icon = "🎧", Category = "Gaming", Placement = "Floor", Size = 45,
			Cost = 18000, CostGrowth = 1.25, Comfort = 3 },
		{ Id = "ConsoleSet", Name = "Console & controllers", Icon = "🎮", Category = "Gaming", Placement = "Floor", Size = 60,
			Cost = 40000, CostGrowth = 1.3, Comfort = 4 },
		{ Id = "NeonGG", Name = "GG neon sign", Icon = "🕹️", Category = "Gaming", Placement = "Wall", Size = 80,
			Cost = 60000, CostGrowth = 1.3, Comfort = 4 },
		{ Id = "GamerPC", Name = "RGB gaming PC", Icon = "🖥️", Category = "Gaming", Placement = "Floor", Size = 80,
			Cost = 150000, CostGrowth = 1.35, Comfort = 6 },
		{ Id = "BigScreenTV", Name = "Giant gaming TV", Icon = "📺", Category = "Gaming", Placement = "Wall", Size = 140,
			Cost = 900000, CostGrowth = 1.4, Comfort = 9 },
		{ Id = "NeonArcade", Name = "Neon arcade cabinet", Icon = "👾", Category = "Gaming", Placement = "Floor", Size = 125,
			Cost = 2.5e6, CostGrowth = 1.45, Comfort = 11 },
		{ Id = "VRHeadset", Name = "Pro VR headset", Icon = "🥽", Category = "Gaming", Placement = "Floor", Size = 60,
			Cost = 3.5e6, CostGrowth = 1.45, Comfort = 11 },
		{ Id = "RacingRig", Name = "Racing sim rig", Icon = "🏎️", Category = "Gaming", Placement = "Floor", Size = 130,
			Cost = 9e6, CostGrowth = 1.5, Comfort = 14 },
		-- 🛋️ Meubles cool : tables, sièges, lits
		{ Id = "GamerBeanbag", Name = "Gamer beanbag", Icon = "🟣", Category = "Furniture", Placement = "Floor", Size = 80,
			Cost = 30000, CostGrowth = 1.3, Comfort = 4 },
		{ Id = "LockerCabinet", Name = "Sports locker", Icon = "🔒", Category = "Furniture", Placement = "Floor", Size = 120,
			Cost = 45000, CostGrowth = 1.3, Comfort = 4 },
		{ Id = "BrickTable", Name = "Building-block table", Icon = "🧱", Category = "Furniture", Placement = "Floor", Size = 120,
			Cost = 60000, CostGrowth = 1.3, Comfort = 5 },
		{ Id = "GamerChair", Name = "Racing gaming chair", Icon = "💺", Category = "Furniture", Placement = "Floor", Size = 95,
			Cost = 120000, CostGrowth = 1.35, Comfort = 6 },
		{ Id = "GamingDesk", Name = "Gaming desk", Icon = "⌨️", Category = "Furniture", Placement = "Floor", Size = 150,
			Cost = 250000, CostGrowth = 1.35, Comfort = 7 },
		{ Id = "BunkBed", Name = "Bunk bed", Icon = "🛏️", Category = "Furniture", Placement = "Floor", Size = 150,
			Cost = 1.5e6, CostGrowth = 1.45, Comfort = 12 },
		{ Id = "RaceCarBed", Name = "Race car bed", Icon = "🏁", Category = "Furniture", Placement = "Floor", Size = 155,
			Cost = 3e7, CostGrowth = 1.5, Comfort = 18 },
		-- 🏀 Sport
		{ Id = "Dumbbells", Name = "Dumbbells", Icon = "🏋️", Category = "Sports", Placement = "Floor", Size = 45,
			Cost = 6000, CostGrowth = 1.2, Comfort = 2 },
		{ Id = "SportsBallBin", Name = "Ball basket", Icon = "⚽", Category = "Sports", Placement = "Floor", Size = 70,
			Cost = 9000, CostGrowth = 1.25, Comfort = 2 },
		{ Id = "SkateRack", Name = "Skateboard rack", Icon = "🛹", Category = "Sports", Placement = "Wall", Size = 100,
			Cost = 30000, CostGrowth = 1.3, Comfort = 4 },
		{ Id = "BasketHoop", Name = "Basketball hoop", Icon = "🏀", Category = "Sports", Placement = "Floor", Size = 140,
			Cost = 45000, CostGrowth = 1.3, Comfort = 5 },
		{ Id = "FootballGoal", Name = "Mini football goal", Icon = "🥅", Category = "Sports", Placement = "Floor", Size = 130,
			Cost = 70000, CostGrowth = 1.3, Comfort = 5 },
		{ Id = "JerseyFrame", Name = "Framed jersey", Icon = "👕", Category = "Sports", Placement = "Wall", Size = 85,
			Cost = 150000, CostGrowth = 1.35, Comfort = 6 },
		{ Id = "BoxingBag", Name = "Boxing bag", Icon = "🥊", Category = "Sports", Placement = "Floor", Size = 130,
			Cost = 200000, CostGrowth = 1.35, Comfort = 6 },
		{ Id = "Surfboard", Name = "Surfboard", Icon = "🏄", Category = "Sports", Placement = "Floor", Size = 130,
			Cost = 350000, CostGrowth = 1.35, Comfort = 7 },
		{ Id = "BMXBike", Name = "BMX bike", Icon = "🚲", Category = "Sports", Placement = "Floor", Size = 110,
			Cost = 500000, CostGrowth = 1.4, Comfort = 8 },
		{ Id = "TrophyShelf", Name = "Trophy shelf", Icon = "🏆", Category = "Sports", Placement = "Wall", Size = 110,
			Cost = 1.2e6, CostGrowth = 1.4, Comfort = 10 },
		-- 🚗 Véhicules, dinos, ninjas (jouets)
		{ Id = "TRexPlush", Name = "T-rex plush", Icon = "🦖", Category = "Toys", Placement = "Floor", Size = 75,
			Cost = 7000, CostGrowth = 1.25, Comfort = 3 },
		{ Id = "NinjaPlush", Name = "Ninja plush", Icon = "🥷", Category = "Toys", Placement = "Floor", Size = 60,
			Cost = 11000, CostGrowth = 1.25, Comfort = 3 },
		{ Id = "RCCar", Name = "RC monster truck", Icon = "🚙", Category = "Toys", Placement = "Floor", Size = 55,
			Cost = 12000, CostGrowth = 1.25, Comfort = 3 },
		{ Id = "ToyGarage", Name = "Toy car garage", Icon = "🚗", Category = "Toys", Placement = "Floor", Size = 100,
			Cost = 25000, CostGrowth = 1.3, Comfort = 4 },
		-- 🖼️ Déco cool
		{ Id = "HeroPoster", Name = "Superhero poster", Icon = "🦸", Category = "Decor", Placement = "Wall", Size = 80,
			Cost = 5000, CostGrowth = 1.2, Comfort = 2 },
		{ Id = "ComicPoster", Name = "Comic POW poster", Icon = "💥", Category = "Decor", Placement = "Wall", Size = 80,
			Cost = 14000, CostGrowth = 1.25, Comfort = 2 },
		{ Id = "RaceTrackRug", Name = "Race track rug", Icon = "🛣️", Category = "Decor", Placement = "Floor", Size = 140,
			Cost = 20000, CostGrowth = 1.25, Comfort = 3 },
		{ Id = "SharkTank", Name = "Shark aquarium", Icon = "🦈", Category = "Decor", Placement = "Floor", Size = 140,
			Cost = 2.5e7, CostGrowth = 1.5, Comfort = 17 },
		-- 💡 Lumières cool
		{ Id = "LightningNeon", Name = "Lightning neon sign", Icon = "⚡", Category = "Lights", Placement = "Wall", Size = 70,
			Cost = 20000, CostGrowth = 1.25, Comfort = 3 },
		{ Id = "DinoEggLamp", Name = "Dino egg lamp", Icon = "🥚", Category = "Lights", Placement = "Floor", Size = 50,
			Cost = 35000, CostGrowth = 1.3, Comfort = 4 },
		{ Id = "RocketLavaLamp", Name = "Rocket lava lamp", Icon = "🟠", Category = "Lights", Placement = "Floor", Size = 60,
			Cost = 95000, CostGrowth = 1.3, Comfort = 5 },
		-- 🎸 Musique rock (électronique)
		{ Id = "GuitarAmp", Name = "Guitar amp", Icon = "🔊", Category = "Electronics", Placement = "Floor", Size = 70,
			Cost = 55000, CostGrowth = 1.3, Comfort = 4 },
		{ Id = "ElectricGuitar", Name = "Flame electric guitar", Icon = "🎸", Category = "Electronics", Placement = "Floor", Size = 110,
			Cost = 280000, CostGrowth = 1.35, Comfort = 7 },
		{ Id = "DrumKit", Name = "Rock drum kit", Icon = "🥁", Category = "Electronics", Placement = "Floor", Size = 140,
			Cost = 4e6, CostGrowth = 1.45, Comfort = 12 },
		{ Id = "DJBooth", Name = "DJ booth", Icon = "🎛️", Category = "Electronics", Placement = "Floor", Size = 130,
			Cost = 1.5e7, CostGrowth = 1.5, Comfort = 16 },
		-- 🚀 Aventure : espace, robots, dinos, pirates, ninjas
		{ Id = "NinjaBanner", Name = "Ninja scroll", Icon = "📜", Category = "Adventure", Placement = "Wall", Size = 90,
			Cost = 40000, CostGrowth = 1.3, Comfort = 4 },
		{ Id = "VolcanoModel", Name = "Volcano model", Icon = "🌋", Category = "Adventure", Placement = "Floor", Size = 70,
			Cost = 70000, CostGrowth = 1.3, Comfort = 4 },
		{ Id = "PlanetMobile", Name = "Solar system mobile", Icon = "🪐", Category = "Adventure", Placement = "Wall", Size = 110,
			Cost = 90000, CostGrowth = 1.3, Comfort = 5 },
		{ Id = "PirateShip", Name = "Pirate ship model", Icon = "⛵", Category = "Adventure", Placement = "Floor", Size = 70,
			Cost = 180000, CostGrowth = 1.35, Comfort = 6 },
		{ Id = "PirateChest", Name = "Pirate treasure chest", Icon = "💰", Category = "Adventure", Placement = "Floor", Size = 85,
			Cost = 450000, CostGrowth = 1.4, Comfort = 8 },
		{ Id = "RocketModel", Name = "Launch rocket model", Icon = "🚀", Category = "Adventure", Placement = "Floor", Size = 120,
			Cost = 900000, CostGrowth = 1.4, Comfort = 9 },
		{ Id = "Observatory", Name = "Observatory telescope", Icon = "🔭", Category = "Adventure", Placement = "Floor", Size = 130,
			Cost = 2.5e6, CostGrowth = 1.45, Comfort = 11 },
		{ Id = "AstronautStatue", Name = "Astronaut statue", Icon = "🌕", Category = "Adventure", Placement = "Floor", Size = 120,
			Cost = 1.2e7, CostGrowth = 1.5, Comfort = 15 },
		{ Id = "DinoSkeleton", Name = "Dino skeleton", Icon = "🦴", Category = "Adventure", Placement = "Floor", Size = 150,
			Cost = 6e7, CostGrowth = 1.55, Comfort = 20 },
		{ Id = "Motorbike", Name = "Chrome motorbike", Icon = "🏍️", Category = "Adventure", Placement = "Floor", Size = 140,
			Cost = 1.5e8, CostGrowth = 1.55, Comfort = 21 },
		{ Id = "MechRobot", Name = "Giant mech robot", Icon = "🤖", Category = "Adventure", Placement = "Floor", Size = 135,
			Cost = 4e8, CostGrowth = 1.6, Comfort = 24 },

		-- v9.5 🖥️ "Dopamine Setup" : chaque stimulus débloqué dans le clicker
		-- devient un objet de la maison, vivant et cliquable en 3D (dessins :
		-- Art/Setup95 ; modèles 3D : House3DSetup ; vie : World/LiveProps).
		--   RequiresUpgrade = Id d'une amélioration (Config.Upgrades) : il faut en
		--     posséder au moins 1 niveau (data.Upgrades[id] >= 1) pour ACHETER
		--     l'objet (vérifié par HouseService et HouseCommon) ; un objet déjà
		--     acheté reste à soi, même après l'océan.
		--   RequiresRebirths : écrit en clair (0 = tout de suite) : le prix de base
		--     est ensuite multiplié par le palier (RebirthGates : x3 / x6 / x9...).
		--   Setup = comportement "live" (lu par la 3D) :
		--     Kind  = "Desk" | "Keyboard" | "Mouse" | "TV" | "TVStand" | "HiFi" |
		--             "Windmill" | "Press" | "BubbleWrap" | "LiveStudio" | "NewsTV" | "Plant"
		--     Tier  = rang dans sa famille (1 = le plus petit)
		--     Screens = nombre d'écrans ; Feeds = ce qu'affiche chaque écran
		--             ("Runner" | "Live" | "DVD" | "News") ; Curved / RGB (bureau ultime)
		--     Size  = "S" | "M" | "L" | "XL" ; Mount = "Floor" (au sol) |
		--             "Surface" (posé sur un meuble) | "Stand" (écran sur pied /
		--             sur un meuble) | "Wall" (au mur, support compris)
		--     Seat  = true : chaise gamer intégrée (le personnage s'y assoit)
		--     Flower = Id de Config.Garden.Flowers (plantes du jardin)
		--   Dessus des bureaux / du meuble télé / de la table à papier bulle :
		--     House/HouseSurfaces (clavier, souris, petite télé, plantes y montent)
		-- 🖥️ Bureaux gamer (écrans : coureur, live ; + d'écrans avec les visites)
		{ Id = "SetupDeskSolo", Name = "Gamer desk setup", Icon = "🖥️", Category = "Setup", Placement = "Floor", Size = 140,
			Cost = 50000, CostGrowth = 1.35, Comfort = 5, MaxOwned = 3, Tabletop = false,
			RequiresUpgrade = "Runner", RequiresRebirths = 0,
			Setup = { Kind = "Desk", Tier = 1, Screens = 1, Feeds = { "Runner" }, Size = "M", Mount = "Floor", Seat = true } },
		{ Id = "SetupDeskDuo", Name = "Dual-screen setup", Icon = "💻", Category = "Setup", Placement = "Floor", Size = 150,
			Cost = 200000, CostGrowth = 1.35, Comfort = 8, MaxOwned = 3, Tabletop = false,
			RequiresUpgrade = "Runner", RequiresRebirths = 1,
			Setup = { Kind = "Desk", Tier = 2, Screens = 2, Feeds = { "Runner", "Live" }, Size = "L", Mount = "Floor", Seat = true } },
		{ Id = "SetupDeskTrio", Name = "Triple-screen battlestation", Icon = "📊", Category = "Setup", Placement = "Floor", Size = 155,
			Cost = 800000, CostGrowth = 1.4, Comfort = 12, MaxOwned = 3, Tabletop = false,
			RequiresUpgrade = "Runner", RequiresRebirths = 2,
			Setup = { Kind = "Desk", Tier = 3, Screens = 3, Feeds = { "Live", "Runner", "Live" }, Size = "L", Mount = "Floor", Seat = true } },
		{ Id = "SetupDeskUltra", Name = "Ultimate RGB battlestation", Icon = "🌈", Category = "Setup", Placement = "Floor", Size = 160,
			Cost = 8e6, CostGrowth = 1.45, Comfort = 18, MaxOwned = 3, Tabletop = false,
			RequiresUpgrade = "Runner", RequiresRebirths = 4,
			Setup = { Kind = "Desk", Tier = 4, Screens = 5, Feeds = { "Live", "News", "Runner", "DVD", "Live" }, Curved = true, RGB = true,
				Size = "XL", Mount = "Floor", Seat = true } },
		-- ⌨️🖱️ Sur le bureau : chaque touche / clic = un vrai clic
		{ Id = "SetupKeyboard", Name = "RGB mechanical keyboard", Icon = "⌨️", Category = "Setup", Placement = "Floor", Size = 60,
			Cost = 15000, CostGrowth = 1.3, Comfort = 3, Tabletop = true, RequiresUpgrade = "Keyboard", RequiresRebirths = 0,
			Setup = { Kind = "Keyboard", Tier = 1, Size = "S", Mount = "Surface" } },
		{ Id = "SetupMouse", Name = "Gaming mouse & pad", Icon = "🖱️", Category = "Setup", Placement = "Floor", Size = 45,
			Cost = 5e6, CostGrowth = 1.35, Comfort = 8, Tabletop = true, RequiresUpgrade = "Mouse", RequiresRebirths = 0,
			Setup = { Kind = "Mouse", Tier = 1, Size = "S", Mount = "Surface" } },
		-- 📺 Télés : le logo DVD rebondit dessus
		{ Id = "SetupTVStand", Name = "Neon TV cabinet", Icon = "📼", Category = "Setup", Placement = "Floor", Size = 130,
			Cost = 15000, CostGrowth = 1.3, Comfort = 3, Tabletop = false, RequiresRebirths = 0,
			Setup = { Kind = "TVStand", Tier = 1, Size = "L", Mount = "Floor" } },
		{ Id = "SetupTVSmall", Name = "Little DVD TV", Icon = "📺", Category = "Setup", Placement = "Floor", Size = 70,
			Cost = 8000, CostGrowth = 1.25, Comfort = 2, Tabletop = true, RequiresUpgrade = "DVD", RequiresRebirths = 0,
			Setup = { Kind = "TV", Tier = 1, Screens = 1, Feeds = { "DVD" }, Size = "S", Mount = "Stand" } },
		{ Id = "SetupTVMedium", Name = "DVD flat TV", Icon = "📺", Category = "Setup", Placement = "Floor", Size = 100,
			Cost = 60000, CostGrowth = 1.3, Comfort = 5, Tabletop = true, RequiresUpgrade = "DVD", RequiresRebirths = 1,
			Setup = { Kind = "TV", Tier = 2, Screens = 1, Feeds = { "DVD" }, Size = "M", Mount = "Stand" } },
		{ Id = "SetupTVLarge", Name = "Big DVD TV", Icon = "📺", Category = "Setup", Placement = "Floor", Size = 130,
			Cost = 400000, CostGrowth = 1.35, Comfort = 9, Tabletop = true, RequiresUpgrade = "DVD", RequiresRebirths = 2,
			Setup = { Kind = "TV", Tier = 3, Screens = 1, Feeds = { "DVD" }, Size = "L", Mount = "Stand" } },
		{ Id = "SetupTVGiant", Name = "Giant DVD cinema TV", Icon = "📺", Category = "Setup", Placement = "Floor", Size = 155,
			Cost = 5e6, CostGrowth = 1.45, Comfort = 15, Tabletop = false, RequiresUpgrade = "DVD", RequiresRebirths = 4,
			Setup = { Kind = "TV", Tier = 4, Screens = 1, Feeds = { "DVD" }, Size = "XL", Mount = "Stand" } },
		{ Id = "SetupTVWallMedium", Name = "Wall DVD TV", Icon = "📺", Category = "Setup", Placement = "Wall", Size = 100,
			Cost = 70000, CostGrowth = 1.3, Comfort = 5, RequiresUpgrade = "DVD", RequiresRebirths = 1,
			Setup = { Kind = "TV", Tier = 2, Screens = 1, Feeds = { "DVD" }, Size = "M", Mount = "Wall" } },
		{ Id = "SetupTVWallLarge", Name = "Big wall DVD TV", Icon = "📺", Category = "Setup", Placement = "Wall", Size = 130,
			Cost = 450000, CostGrowth = 1.35, Comfort = 9, RequiresUpgrade = "DVD", RequiresRebirths = 2,
			Setup = { Kind = "TV", Tier = 3, Screens = 1, Feeds = { "DVD" }, Size = "L", Mount = "Wall" } },
		{ Id = "SetupTVWallGiant", Name = "Giant wall DVD TV", Icon = "📺", Category = "Setup", Placement = "Wall", Size = 155,
			Cost = 5.5e6, CostGrowth = 1.45, Comfort = 15, RequiresUpgrade = "DVD", RequiresRebirths = 4,
			Setup = { Kind = "TV", Tier = 4, Screens = 1, Feeds = { "DVD" }, Size = "XL", Mount = "Wall" } },
		{ Id = "SetupNewsTV", Name = "Breaking news screen", Icon = "📰", Category = "Setup", Placement = "Wall", Size = 100,
			Cost = 9000, CostGrowth = 1.25, Comfort = 2, RequiresUpgrade = "NewsTicker", RequiresRebirths = 0,
			Setup = { Kind = "NewsTV", Tier = 1, Screens = 1, Feeds = { "News" }, Size = "M", Mount = "Wall" } },
		-- 🎧 Chaînes hi-fi (musique lofi du jeu : lecture / morceau suivant)
		{ Id = "SetupHiFiBoombox", Name = "Lofi boombox", Icon = "📻", Category = "Setup", Placement = "Floor", Size = 65,
			Cost = 20000, CostGrowth = 1.3, Comfort = 3, Tabletop = true, RequiresUpgrade = "Lofi", RequiresRebirths = 0,
			Setup = { Kind = "HiFi", Tier = 1, Size = "S", Mount = "Surface" } },
		{ Id = "SetupHiFiCD", Name = "CD hi-fi system", Icon = "💿", Category = "Setup", Placement = "Floor", Size = 80,
			Cost = 90000, CostGrowth = 1.3, Comfort = 6, Tabletop = true, RequiresUpgrade = "Lofi", RequiresRebirths = 1,
			Setup = { Kind = "HiFi", Tier = 2, Size = "M", Mount = "Surface" } },
		{ Id = "SetupHiFiVinyl", Name = "Vinyl turntable & speakers", Icon = "🎶", Category = "Setup", Placement = "Floor", Size = 125,
			Cost = 500000, CostGrowth = 1.35, Comfort = 10, Tabletop = false, RequiresUpgrade = "Lofi", RequiresRebirths = 2,
			Setup = { Kind = "HiFi", Tier = 3, Size = "L", Mount = "Floor" } },
		{ Id = "SetupHiFiStudio", Name = "Lofi studio wall", Icon = "🎚️", Category = "Setup", Placement = "Floor", Size = 155,
			Cost = 6e6, CostGrowth = 1.45, Comfort = 16, MaxOwned = 3, Tabletop = false, RequiresUpgrade = "Lofi", RequiresRebirths = 4,
			Setup = { Kind = "HiFi", Tier = 4, Size = "XL", Mount = "Floor" } },
		-- 🌀🗜️🔘🎥 Les autres stimuli, en vrai
		{ Id = "SetupWindmill", Name = "Garden windmill", Icon = "🌀", Category = "Setup", Placement = "Floor", Size = 135,
			Cost = 60000, CostGrowth = 1.35, Comfort = 5, MaxOwned = 3, Tabletop = false, RequiresUpgrade = "Pinwheel", RequiresRebirths = 0,
			Setup = { Kind = "Windmill", Tier = 1, Size = "L", Mount = "Floor" } },
		{ Id = "SetupPress", Name = "Real hydraulic press", Icon = "🗜️", Category = "Setup", Placement = "Floor", Size = 130,
			Cost = 50000, CostGrowth = 1.35, Comfort = 5, MaxOwned = 3, Tabletop = false, RequiresUpgrade = "Press", RequiresRebirths = 0,
			Setup = { Kind = "Press", Tier = 1, Size = "L", Mount = "Floor" } },
		{ Id = "SetupBubbleWrap", Name = "Bubble wrap table", Icon = "🔘", Category = "Setup", Placement = "Floor", Size = 110,
			Cost = 80000, CostGrowth = 1.35, Comfort = 5, MaxOwned = 3, Tabletop = false, RequiresUpgrade = "BubbleWrap", RequiresRebirths = 0,
			Setup = { Kind = "BubbleWrap", Tier = 1, Size = "M", Mount = "Floor" } },
		{ Id = "SetupLiveStudio", Name = "Live streaming corner", Icon = "🎥", Category = "Setup", Placement = "Floor", Size = 145,
			Cost = 1.5e6, CostGrowth = 1.4, Comfort = 10, MaxOwned = 3, Tabletop = false, RequiresUpgrade = "LiveStream", RequiresRebirths = 0,
			Setup = { Kind = "LiveStudio", Tier = 1, Screens = 1, Feeds = { "Live" }, Size = "L", Mount = "Floor" } },
		-- 🌼 Plantes du Jardin de Dopamine (en pot, lumineuses) : de plus en plus rares
		{ Id = "SetupPlantDaisy", Name = "Dopamine daisy", Icon = "🌼", Category = "Setup", Placement = "Floor", Size = 55,
			Cost = 200000, CostGrowth = 1.3, Comfort = 4, Tabletop = true, RequiresUpgrade = "Garden", RequiresRebirths = 0,
			Setup = { Kind = "Plant", Tier = 1, Flower = "Daisy", Size = "S", Mount = "Surface" } },
		{ Id = "SetupPlantTulip", Name = "Dopamine tulip", Icon = "🌷", Category = "Setup", Placement = "Floor", Size = 60,
			Cost = 450000, CostGrowth = 1.3, Comfort = 5, Tabletop = true, RequiresUpgrade = "Garden", RequiresRebirths = 0,
			Setup = { Kind = "Plant", Tier = 2, Flower = "Tulip", Size = "S", Mount = "Surface" } },
		{ Id = "SetupPlantRose", Name = "Dopamine rose", Icon = "🌹", Category = "Setup", Placement = "Floor", Size = 65,
			Cost = 400000, CostGrowth = 1.35, Comfort = 7, Tabletop = true, RequiresUpgrade = "Garden", RequiresRebirths = 1,
			Setup = { Kind = "Plant", Tier = 3, Flower = "Rose", Size = "S", Mount = "Surface" } },
		{ Id = "SetupPlantSunflower", Name = "Dopamine sunflower", Icon = "🌻", Category = "Setup", Placement = "Floor", Size = 90,
			Cost = 1e6, CostGrowth = 1.4, Comfort = 10, Tabletop = true, RequiresUpgrade = "Garden", RequiresRebirths = 2,
			Setup = { Kind = "Plant", Tier = 4, Flower = "Sunflower", Size = "M", Mount = "Floor" } },
		{ Id = "SetupPlantLotus", Name = "Golden dopamine lotus", Icon = "🪷", Category = "Setup", Placement = "Floor", Size = 75,
			Cost = 4e6, CostGrowth = 1.45, Comfort = 14, Tabletop = true, RequiresUpgrade = "Garden", RequiresRebirths = 3,
			Setup = { Kind = "Plant", Tier = 5, Flower = "Lotus", Size = "M", Mount = "Surface" } },

		-- v9.8 🛍️ CATALOG98 : 68 nouveaux objets, du tout simple à l'incroyable,
		-- pas seulement kawaii : moderne / minimaliste, loft industriel, luxe,
		-- gamer, sport, nature, tech, et les objets de rêve (tunnel aquarium,
		-- cascade intérieure, dragon d'or...). Dessins : Art/Modern98 +
		-- Art/Luxe98 ; modèles 3D : House3DLuxe ; dessus : HouseSurfaces.
		-- Pas de RequiresRebirths : le palier vient du prix (RebirthGates).
		-- 🛋️ Moderne / minimaliste / loft
		{ Id = "SimpleChair", Name = "Simple white chair", Icon = "🪑", Category = "Furniture", Placement = "Floor", Size = 75,
			Cost = 700, CostGrowth = 1.25, Comfort = 1 },
		{ Id = "CoatRack", Name = "Standing coat rack", Icon = "🧥", Category = "Furniture", Placement = "Floor", Size = 115,
			Cost = 1500, CostGrowth = 1.25, Comfort = 1, MaxOwned = 4 },
		{ Id = "BarrelTable", Name = "Barrel side table", Icon = "🛢️", Category = "Furniture", Placement = "Floor", Size = 65,
			Cost = 2500, CostGrowth = 1.25, Comfort = 2 },
		{ Id = "ModernBarStool", Name = "Modern bar stool", Icon = "🪑", Category = "Furniture", Placement = "Floor", Size = 90,
			Cost = 3500, CostGrowth = 1.25, Comfort = 2 },
		{ Id = "OakDesk", Name = "Minimalist oak desk", Icon = "🖋️", Category = "Furniture", Placement = "Floor", Size = 130,
			Cost = 4500, CostGrowth = 1.3, Comfort = 2 },
		{ Id = "MediaConsole", Name = "Walnut media console", Icon = "🗄️", Category = "Furniture", Placement = "Floor", Size = 130,
			Cost = 6500, CostGrowth = 1.3, Comfort = 3 },
		{ Id = "GlassCoffeeTable", Name = "Glass coffee table", Icon = "☕", Category = "Furniture", Placement = "Floor", Size = 115,
			Cost = 14000, CostGrowth = 1.3, Comfort = 4 },
		{ Id = "LoftShelf", Name = "Industrial pipe shelf", Icon = "🔩", Category = "Furniture", Placement = "Floor", Size = 140,
			Cost = 20000, CostGrowth = 1.3, Comfort = 5 },
		{ Id = "PlatformBed", Name = "Low platform bed", Icon = "🛌", Category = "Furniture", Placement = "Floor", Size = 155,
			Cost = 25000, CostGrowth = 1.3, Comfort = 5 },
		{ Id = "Workbench", Name = "Loft workbench table", Icon = "🛠️", Category = "Furniture", Placement = "Floor", Size = 150,
			Cost = 30000, CostGrowth = 1.3, Comfort = 5 },
		{ Id = "SectionalSofa", Name = "Modern sectional sofa", Icon = "🛋️", Category = "Furniture", Placement = "Floor", Size = 158,
			Cost = 40000, CostGrowth = 1.3, Comfort = 6 },
		{ Id = "Chesterfield", Name = "Leather Chesterfield sofa", Icon = "🛋️", Category = "Furniture", Placement = "Floor", Size = 150,
			Cost = 65000, CostGrowth = 1.35, Comfort = 7 },
		{ Id = "BookshelfWall", Name = "Library bookshelf wall", Icon = "📚", Category = "Furniture", Placement = "Floor", Size = 155,
			Cost = 90000, CostGrowth = 1.35, Comfort = 7, MaxOwned = 4 },
		{ Id = "MarbleIsland", Name = "Marble kitchen island", Icon = "🍽️", Category = "Furniture", Placement = "Floor", Size = 150,
			Cost = 600000, CostGrowth = 1.4, Comfort = 10, MaxOwned = 3 },
		-- 🖼️ Déco
		{ Id = "RoundMirror", Name = "Round wall mirror", Icon = "🪞", Category = "Decor", Placement = "Wall", Size = 75,
			Cost = 2500, CostGrowth = 1.25, Comfort = 2 },
		{ Id = "AbstractCanvas", Name = "Abstract canvas", Icon = "🎨", Category = "Decor", Placement = "Wall", Size = 100,
			Cost = 5000, CostGrowth = 1.25, Comfort = 2 },
		-- (demandé par RECIPES98 : son modèle 3D est R.BigWallMirror dans House3DObjects)
		{ Id = "BigWallMirror", Name = "Big wall mirror", Icon = "🪞", Category = "Decor", Placement = "Wall", Size = 130,
			Cost = 14000, CostGrowth = 1.3, Comfort = 3 },
		{ Id = "GrandfatherClock", Name = "Grandfather clock", Icon = "🕰️", Category = "Decor", Placement = "Floor", Size = 140,
			Cost = 250000, CostGrowth = 1.4, Comfort = 8, MaxOwned = 3 },
		-- 💡 Lumières
		{ Id = "EdisonPendant", Name = "Edison bulb pendant", Icon = "💡", Category = "Lights", Placement = "Wall", Size = 90,
			Cost = 4000, CostGrowth = 1.25, Comfort = 2 },
		{ Id = "ArcFloorLamp", Name = "Arc floor lamp", Icon = "🔦", Category = "Lights", Placement = "Floor", Size = 145,
			Cost = 9000, CostGrowth = 1.3, Comfort = 4 },
		{ Id = "DopaNeon", Name = "DOPA neon sign", Icon = "✨", Category = "Lights", Placement = "Wall", Size = 100,
			Cost = 25000, CostGrowth = 1.3, Comfort = 4 },
		{ Id = "InfinityMirror", Name = "Infinity mirror", Icon = "🌀", Category = "Lights", Placement = "Wall", Size = 90,
			Cost = 150000, CostGrowth = 1.35, Comfort = 7 },
		{ Id = "PlanetariumDome", Name = "Planetarium dome lamp", Icon = "🌌", Category = "Lights", Placement = "Floor", Size = 110,
			Cost = 1.8e6, CostGrowth = 1.45, Comfort = 12, Tabletop = false },
		{ Id = "GrandChandelier", Name = "Grand crystal chandelier", Icon = "🕯️", Category = "Lights", Placement = "Wall", Size = 155,
			Cost = 3e6, CostGrowth = 1.45, Comfort = 13, MaxOwned = 3 },
		-- 🪴 Plantes
		{ Id = "SnakePlant", Name = "Snake plant", Icon = "🪴", Category = "Plants", Placement = "Floor", Size = 70,
			Cost = 1200, CostGrowth = 1.2, Comfort = 1 },
		{ Id = "FiddleFig", Name = "Fiddle-leaf fig", Icon = "🌿", Category = "Plants", Placement = "Floor", Size = 130,
			Cost = 5000, CostGrowth = 1.25, Comfort = 3 },
		{ Id = "BirdOfParadise", Name = "Bird of paradise", Icon = "🌺", Category = "Plants", Placement = "Floor", Size = 145,
			Cost = 12000, CostGrowth = 1.3, Comfort = 4 },
		{ Id = "MapleBonsai", Name = "Red maple bonsai", Icon = "🍁", Category = "Plants", Placement = "Floor", Size = 65,
			Cost = 20000, CostGrowth = 1.3, Comfort = 4 },
		{ Id = "OliveTree", Name = "Potted olive tree", Icon = "🫒", Category = "Plants", Placement = "Floor", Size = 140,
			Cost = 150000, CostGrowth = 1.35, Comfort = 7 },
		{ Id = "MossWall", Name = "Living moss wall", Icon = "🌱", Category = "Plants", Placement = "Wall", Size = 140,
			Cost = 400000, CostGrowth = 1.4, Comfort = 8 },
		-- 📺 Tech
		{ Id = "SmartSpeaker", Name = "Smart speaker", Icon = "🔊", Category = "Electronics", Placement = "Floor", Size = 40,
			Cost = 1500, CostGrowth = 1.2, Comfort = 1 },
		{ Id = "CameraDrone", Name = "Camera drone", Icon = "🚁", Category = "Electronics", Placement = "Floor", Size = 55,
			Cost = 25000, CostGrowth = 1.3, Comfort = 4 },
		{ Id = "Printer3D", Name = "3D printer", Icon = "🖨️", Category = "Electronics", Placement = "Floor", Size = 75,
			Cost = 50000, CostGrowth = 1.3, Comfort = 5 },
		{ Id = "ButlerRobot", Name = "Butler robot", Icon = "🤖", Category = "Electronics", Placement = "Floor", Size = 120,
			Cost = 2.5e6, CostGrowth = 1.45, Comfort = 12, MaxOwned = 3 },
		-- 🍰 Cuisine
		{ Id = "StandMixer", Name = "Stand mixer", Icon = "🥣", Category = "Kitchen", Placement = "Floor", Size = 55,
			Cost = 3000, CostGrowth = 1.25, Comfort = 2 },
		{ Id = "EspressoMachine", Name = "Espresso machine", Icon = "☕", Category = "Kitchen", Placement = "Floor", Size = 55,
			Cost = 6000, CostGrowth = 1.25, Comfort = 3 },
		{ Id = "SteelFridge", Name = "Double-door steel fridge", Icon = "🧊", Category = "Kitchen", Placement = "Floor", Size = 140,
			Cost = 200000, CostGrowth = 1.4, Comfort = 8, MaxOwned = 2 },
		-- 🎮 Gamer
		{ Id = "HexPanels", Name = "Hexagon LED panels", Icon = "🔷", Category = "Gaming", Placement = "Wall", Size = 110,
			Cost = 45000, CostGrowth = 1.3, Comfort = 5 },
		{ Id = "FoosballTable", Name = "Foosball table", Icon = "⚽", Category = "Gaming", Placement = "Floor", Size = 140,
			Cost = 120000, CostGrowth = 1.35, Comfort = 7, MaxOwned = 2 },
		{ Id = "AirHockey", Name = "Air hockey table", Icon = "🏒", Category = "Gaming", Placement = "Floor", Size = 150,
			Cost = 350000, CostGrowth = 1.4, Comfort = 8, MaxOwned = 2 },
		{ Id = "ClawMachine", Name = "Claw machine", Icon = "🕹️", Category = "Gaming", Placement = "Floor", Size = 130,
			Cost = 800000, CostGrowth = 1.4, Comfort = 10, MaxOwned = 3 },
		{ Id = "TwinArcade", Name = "Twin neon arcade", Icon = "👾", Category = "Gaming", Placement = "Floor", Size = 150,
			Cost = 3e6, CostGrowth = 1.45, Comfort = 12, MaxOwned = 3 },
		{ Id = "VRStation", Name = "VR free-roam station", Icon = "🥽", Category = "Gaming", Placement = "Floor", Size = 150,
			Cost = 6e6, CostGrowth = 1.5, Comfort = 15, MaxOwned = 2 },
		{ Id = "RacingCockpit", Name = "Pro racing cockpit", Icon = "🏁", Category = "Gaming", Placement = "Floor", Size = 155,
			Cost = 1.8e7, CostGrowth = 1.5, Comfort = 17, MaxOwned = 2 },
		-- 🏀 Sport
		{ Id = "YogaMat", Name = "Yoga mat & gym ball", Icon = "🧘", Category = "Sports", Placement = "Floor", Size = 110,
			Cost = 3000, CostGrowth = 1.25, Comfort = 2, Tabletop = false },
		{ Id = "PingPongTable", Name = "Ping-pong table", Icon = "🏓", Category = "Sports", Placement = "Floor", Size = 155,
			Cost = 45000, CostGrowth = 1.3, Comfort = 5, MaxOwned = 2 },
		{ Id = "RowingMachine", Name = "Rowing machine", Icon = "🚣", Category = "Sports", Placement = "Floor", Size = 150,
			Cost = 90000, CostGrowth = 1.35, Comfort = 6, MaxOwned = 3 },
		{ Id = "WeightBench", Name = "Weight bench & rack", Icon = "🏋️", Category = "Sports", Placement = "Floor", Size = 150,
			Cost = 150000, CostGrowth = 1.35, Comfort = 7, MaxOwned = 3 },
		{ Id = "Treadmill", Name = "Treadmill", Icon = "🏃", Category = "Sports", Placement = "Floor", Size = 140,
			Cost = 250000, CostGrowth = 1.4, Comfort = 8, MaxOwned = 3 },
		{ Id = "ClimbingWall", Name = "Climbing wall", Icon = "🧗", Category = "Sports", Placement = "Wall", Size = 150,
			Cost = 700000, CostGrowth = 1.4, Comfort = 9, MaxOwned = 3 },
		-- 💎 Luxe et objets incroyables
		{ Id = "VelvetChaise", Name = "Velvet chaise longue", Icon = "💜", Category = "Luxury", Placement = "Floor", Size = 140,
			Cost = 120000, CostGrowth = 1.35, Comfort = 7 },
		{ Id = "MarbleStatue", Name = "Marble statue", Icon = "🏛️", Category = "Luxury", Placement = "Floor", Size = 130,
			Cost = 500000, CostGrowth = 1.4, Comfort = 9, Tabletop = false },
		{ Id = "KingBed", Name = "King-size bed", Icon = "🛏️", Category = "Luxury", Placement = "Floor", Size = 160,
			Cost = 600000, CostGrowth = 1.4, Comfort = 10, MaxOwned = 3 },
		{ Id = "PoolTable", Name = "Pool table", Icon = "🎱", Category = "Luxury", Placement = "Floor", Size = 155,
			Cost = 900000, CostGrowth = 1.4, Comfort = 10, MaxOwned = 2 },
		{ Id = "AmethystGeode", Name = "Giant amethyst geode", Icon = "💎", Category = "Luxury", Placement = "Floor", Size = 90,
			Cost = 1e6, CostGrowth = 1.45, Comfort = 10, Tabletop = false },
		{ Id = "ModernFireplace", Name = "Linear wall fireplace", Icon = "🔥", Category = "Luxury", Placement = "Wall", Size = 150,
			Cost = 1.5e6, CostGrowth = 1.45, Comfort = 11, MaxOwned = 3 },
		{ Id = "CinemaRecliners", Name = "Cinema recliner row", Icon = "🍿", Category = "Luxury", Placement = "Floor", Size = 160,
			Cost = 2e6, CostGrowth = 1.45, Comfort = 12, MaxOwned = 3 },
		{ Id = "WhitePiano", Name = "White concert piano", Icon = "🎹", Category = "Luxury", Placement = "Floor", Size = 150,
			Cost = 4e6, CostGrowth = 1.45, Comfort = 13, MaxOwned = 2 },
		{ Id = "Jacuzzi", Name = "Bubbling jacuzzi", Icon = "🫧", Category = "Luxury", Placement = "Floor", Size = 155,
			Cost = 8e6, CostGrowth = 1.5, Comfort = 15, MaxOwned = 2 },
		{ Id = "AquariumWall", Name = "Aquarium wall", Icon = "🐠", Category = "Luxury", Placement = "Floor", Size = 160,
			Cost = 1.2e7, CostGrowth = 1.5, Comfort = 16, MaxOwned = 3 },
		{ Id = "RollercoasterModel", Name = "Mini rollercoaster", Icon = "🎢", Category = "Luxury", Placement = "Floor", Size = 150,
			Cost = 1.5e7, CostGrowth = 1.5, Comfort = 17, MaxOwned = 2 },
		{ Id = "GoldThrone", Name = "Golden throne", Icon = "👑", Category = "Luxury", Placement = "Floor", Size = 140,
			Cost = 2e7, CostGrowth = 1.5, Comfort = 17, MaxOwned = 2 },
		{ Id = "IndoorWaterfall", Name = "Indoor waterfall", Icon = "💧", Category = "Luxury", Placement = "Floor", Size = 150,
			Cost = 3e7, CostGrowth = 1.55, Comfort = 19, MaxOwned = 2 },
		{ Id = "CapsuleBed", Name = "Space capsule bed", Icon = "🛸", Category = "Luxury", Placement = "Floor", Size = 160,
			Cost = 4e7, CostGrowth = 1.55, Comfort = 20, MaxOwned = 2 },
		{ Id = "DragonStatue", Name = "Golden dragon statue", Icon = "🐉", Category = "Luxury", Placement = "Floor", Size = 150,
			Cost = 6e7, CostGrowth = 1.55, Comfort = 21, MaxOwned = 2 },
		{ Id = "AquariumTunnel", Name = "Aquarium tunnel", Icon = "🐟", Category = "Luxury", Placement = "Floor", Size = 160,
			Cost = 1.2e8, CostGrowth = 1.6, Comfort = 23, MaxOwned = 2 },
		-- 📺 XXL (pour DESK98 : House3DSetup les dessine d'après Setup ; Scale =
		-- largeur de l'écran par rapport à la télé géante, Cinema = projecteur +
		-- toile). La télé montre le live du clicker.
		{ Id = "SetupTVCinemaXXL", Name = "XXL cinema TV", Icon = "📺", Category = "Setup", Placement = "Floor", Size = 160,
			Cost = 2.2e7, CostGrowth = 1.5, Comfort = 19, MaxOwned = 2, Tabletop = false, RequiresUpgrade = "DVD", RequiresRebirths = 5,
			Setup = { Kind = "TV", Tier = 5, Screens = 1, Feeds = { "Live" }, Size = "XL", Mount = "Stand", Scale = 1.5 } },
		{ Id = "SetupTVWallXXL", Name = "XXL wall TV", Icon = "📺", Category = "Setup", Placement = "Wall", Size = 160,
			Cost = 2.5e7, CostGrowth = 1.5, Comfort = 19, MaxOwned = 2, RequiresUpgrade = "DVD", RequiresRebirths = 5,
			Setup = { Kind = "TV", Tier = 5, Screens = 1, Feeds = { "Live" }, Size = "XL", Mount = "Wall", Scale = 1.5 } },
		{ Id = "SetupCinemaScreen", Name = "Home cinema screen", Icon = "🎬", Category = "Setup", Placement = "Wall", Size = 160,
			Cost = 8e7, CostGrowth = 1.55, Comfort = 22, MaxOwned = 2, RequiresUpgrade = "DVD", RequiresRebirths = 8,
			Setup = { Kind = "TV", Tier = 6, Screens = 1, Feeds = { "Live" }, Size = "XL", Mount = "Wall", Scale = 2.2, Cinema = true } },
	},
}

----------------------------------------------------------------------
-- 🚗 Voitures (v9.6, CarService) : achetées à la concession de Dopamine
-- Town (ou via "Car" : "buy"), gardées pour toujours (même après l'océan),
-- conduites en ville (bouton "🚗 Ma voiture" ou le garage du manoir).
--   List   : Id, Name, Icon, Cost (Dopamine), RequiresRebirths, Kind (modèle
--            3D de CarModels), DefaultColor (Id de Colors), Desc
--   Colors : peintures (changer la couleur est gratuit)
-- Conduite : MaxSpeed en studs/s, une voiture par joueur, rangée toute
-- seule après IdleDespawn secondes sans conducteur.
----------------------------------------------------------------------
Config.Cars = {
	MaxSpeed = 56, -- studs/s en marche avant (v10 : 50 -> 56, autoroute ; x CarModels.Stats)
	ReverseSpeed = 18, -- studs/s en marche arrière
	IdleDespawn = 60, -- s sans conducteur -> la voiture rentre au garage
	SpawnCooldown = 4, -- s entre deux "🚗 Ma voiture"
	HonkCooldown = 1.5, -- s entre deux "💨" (klaxon VISUEL : aucun son)
	List = {
		{ Id = "BubbleCar", Name = "Bubble car", Icon = "🍬", Cost = 1.5e6, RequiresRebirths = 0, Kind = "BubbleCar", DefaultColor = "Bubblegum",
			Desc = "A tiny round kawaii car" },
		{ Id = "CityCar", Name = "City car", Icon = "🚗", Cost = 8e7, RequiresRebirths = 1, Kind = "CityCar", DefaultColor = "Sky",
			Desc = "Small, cute and easy to park" },
		{ Id = "Hatchback", Name = "Hatchback", Icon = "🚘", Cost = 1.2e9, RequiresRebirths = 1, Kind = "Hatchback", DefaultColor = "Mint",
			Desc = "Five doors and a roof spoiler" },
		{ Id = "Pickup", Name = "Pickup truck", Icon = "🛻", Cost = 2e10, RequiresRebirths = 2, Kind = "Pickup", DefaultColor = "Tangerine",
			Desc = "Big wheels and a cargo bed" },
		{ Id = "SUV", Name = "Family SUV", Icon = "🚙", Cost = 1.5e11, RequiresRebirths = 3, Kind = "SUV", DefaultColor = "Pearl",
			Desc = "Tall, comfy, roof rails and spare wheel" },
		{ Id = "Van", Name = "Camper van", Icon = "🚐", Cost = 8e11, RequiresRebirths = 3, Kind = "Van", DefaultColor = "Lilac",
			Desc = "Two-tone camper for road trips" },
		{ Id = "SportsCar", Name = "Sports roadster", Icon = "🏎️", Cost = 5e12, RequiresRebirths = 4, Kind = "SportsCar", DefaultColor = "Cherry",
			Desc = "Convertible, rear wing, twin exhausts" },
		{ Id = "Limo", Name = "Stretch limo", Icon = "🎩", Cost = 2e13, RequiresRebirths = 5, Kind = "Limo", DefaultColor = "Midnight",
			Desc = "The longest car in town, chrome everywhere" },
	},
	Colors = {
		{ Id = "Bubblegum", Name = "Bubblegum pink", Color = Color3.fromRGB(255, 150, 196) },
		{ Id = "Cherry", Name = "Cherry red", Color = Color3.fromRGB(220, 44, 64) },
		{ Id = "Tangerine", Name = "Tangerine", Color = Color3.fromRGB(255, 140, 60) },
		{ Id = "Sunny", Name = "Sunny yellow", Color = Color3.fromRGB(255, 212, 80) },
		{ Id = "Mint", Name = "Mint", Color = Color3.fromRGB(120, 214, 176) },
		{ Id = "Racing", Name = "Racing green", Color = Color3.fromRGB(34, 110, 76) },
		{ Id = "Sky", Name = "Sky blue", Color = Color3.fromRGB(120, 186, 250) },
		{ Id = "Denim", Name = "Denim blue", Color = Color3.fromRGB(56, 90, 170) },
		{ Id = "Lilac", Name = "Lilac", Color = Color3.fromRGB(186, 156, 246) },
		{ Id = "Pearl", Name = "Pearl white", Color = Color3.fromRGB(246, 244, 240) },
		{ Id = "Silver", Name = "Silver", Color = Color3.fromRGB(176, 182, 192) },
		{ Id = "Midnight", Name = "Midnight black", Color = Color3.fromRGB(38, 38, 48) },
		-- (v10, CARS10) teintes en plus
		{ Id = "Coral", Name = "Coral", Color = Color3.fromRGB(255, 118, 104) },
		{ Id = "Burgundy", Name = "Burgundy", Color = Color3.fromRGB(122, 26, 44) },
		{ Id = "Lemon", Name = "Lemon", Color = Color3.fromRGB(240, 236, 110) },
		{ Id = "Olive", Name = "Olive", Color = Color3.fromRGB(110, 118, 70) },
		{ Id = "Teal", Name = "Teal", Color = Color3.fromRGB(34, 150, 156) },
		{ Id = "Navy", Name = "Navy blue", Color = Color3.fromRGB(28, 40, 88) },
		{ Id = "Violet", Name = "Violet", Color = Color3.fromRGB(116, 64, 176) },
		{ Id = "Sand", Name = "Sand beige", Color = Color3.fromRGB(214, 196, 160) },
		{ Id = "Gunmetal", Name = "Gunmetal grey", Color = Color3.fromRGB(84, 88, 98) },
		{ Id = "Copper", Name = "Copper", Color = Color3.fromRGB(184, 104, 64) },
	},
	----------------------------------------------------------------
	-- 🔧 (v10, CARS10) Préparation et personnalisation ("🔧 Garage tuning"
	-- dans "Mes voitures") : tout est acheté PAR VOITURE, payé en Dopamine
	-- UNE fois (on peut ensuite revenir gratuitement à une option déjà
	-- achetée), vérifié par CarService (data.Cars.Mods / Unlocked / Tuning).
	-- Prix = Price x prix de la voiture (au moins MinPrice) ; la 1re entrée
	-- de chaque liste est gratuite (l'origine). RequiresRebirths = verrou.
	--   Tuning : 3 niveaux par pièce ; effets dans CarModels.Stats (courses).
	--   Mods   : options visuelles (CarModels.Build les applique).
	----------------------------------------------------------------
	MinPrice = 20000,
	PlatePrice = 0.01, -- plaque personnalisée (texte filtré par TextService)
	PlateMaxLength = 8,
	Tuning = {
		MaxLevel = 3,
		Parts = {
			{ Id = "Engine", Name = "Engine", Icon = "🔧", Desc = "Top speed and acceleration", Price = { 0.08, 0.2, 0.45 }, RequiresRebirths = { 0, 1, 2 } },
			{ Id = "Tyres", Name = "Tyres", Icon = "🛞", Desc = "Grip and braking", Price = { 0.05, 0.14, 0.32 }, RequiresRebirths = { 0, 1, 2 } },
			{ Id = "Suspension", Name = "Suspension", Icon = "🌀", Desc = "Steering, stability and drift control", Price = { 0.05, 0.14, 0.32 }, RequiresRebirths = { 0, 1, 2 } },
		},
	},
	Mods = {
		-- finition de la peinture
		Finish = {
			{ Id = "Gloss", Name = "Gloss", Price = 0 },
			{ Id = "Metallic", Name = "Metallic", Price = 0.03 },
			{ Id = "Matte", Name = "Matte", Price = 0.04 },
			{ Id = "Pearl", Name = "Pearl", Price = 0.06, RequiresRebirths = 2 },
		},
		-- toit bicolore ("Auto" = celui du modèle, "Body" = couleur de caisse,
		-- sinon une teinte de Colors : même Id)
		Roof = {
			{ Id = "Auto", Name = "Original", Price = 0 },
			{ Id = "Body", Name = "Body colour", Price = 0.01 },
			{ Id = "Midnight", Name = "Gloss black", Price = 0.02 },
			{ Id = "Pearl", Name = "White", Price = 0.02 },
			{ Id = "Silver", Name = "Silver", Price = 0.02 },
			{ Id = "Bubblegum", Name = "Bubblegum pink", Price = 0.02 },
			{ Id = "Carbon", Name = "Carbon fibre", Price = 0.05, RequiresRebirths = 1 },
		},
		-- jantes (dessin)
		Rims = {
			{ Id = "Stock", Name = "Original", Price = 0 },
			{ Id = "Sport", Name = "Sport 5-spoke", Price = 0.03 },
			{ Id = "Mesh", Name = "Mesh", Price = 0.04 },
			{ Id = "Split", Name = "Split 6-spoke", Price = 0.04 },
			{ Id = "Turbine", Name = "Turbine", Price = 0.05, RequiresRebirths = 1 },
			{ Id = "DeepDish", Name = "Deep dish", Price = 0.05, RequiresRebirths = 1 },
			{ Id = "Retro", Name = "Retro hubcap", Price = 0.03 },
			{ Id = "Star", Name = "Star 3-spoke", Price = 0.06, RequiresRebirths = 2 },
		},
		RimColor = {
			{ Id = "Auto", Name = "Original", Price = 0 },
			{ Id = "Chrome", Name = "Chrome", Price = 0.01, Color = Color3.fromRGB(214, 218, 226) },
			{ Id = "Black", Name = "Gloss black", Price = 0.01, Color = Color3.fromRGB(30, 31, 36) },
			{ Id = "White", Name = "White", Price = 0.01, Color = Color3.fromRGB(246, 246, 248) },
			{ Id = "Gold", Name = "Gold", Price = 0.02, Color = Color3.fromRGB(214, 172, 80) },
			{ Id = "Bronze", Name = "Bronze", Price = 0.02, Color = Color3.fromRGB(150, 104, 62) },
			{ Id = "Red", Name = "Red", Price = 0.02, Color = Color3.fromRGB(206, 40, 52) },
			{ Id = "Pink", Name = "Pink", Price = 0.02, Color = Color3.fromRGB(255, 120, 180) },
			{ Id = "Body", Name = "Body colour", Price = 0.02 },
		},
		Tyre = {
			{ Id = "Road", Name = "Road", Price = 0 },
			{ Id = "LowProfile", Name = "Low profile", Price = 0.02 },
			{ Id = "Whitewall", Name = "Whitewall", Price = 0.02 },
			{ Id = "RedLine", Name = "Red line", Price = 0.02 },
			{ Id = "OffRoad", Name = "All-terrain", Price = 0.03 },
		},
		Splitter = {
			{ Id = "None", Name = "Original", Price = 0 },
			{ Id = "Lip", Name = "Front lip", Price = 0.02 },
			{ Id = "Race", Name = "Race splitter", Price = 0.04, RequiresRebirths = 1 },
		},
		Skirts = {
			{ Id = "None", Name = "Original", Price = 0 },
			{ Id = "Sport", Name = "Side skirts", Price = 0.03 },
		},
		Spoiler = {
			{ Id = "Stock", Name = "Original", Price = 0 },
			{ Id = "None", Name = "No spoiler", Price = 0 },
			{ Id = "Lip", Name = "Lip spoiler", Price = 0.02 },
			{ Id = "Duck", Name = "Ducktail", Price = 0.03 },
			{ Id = "Wing", Name = "Rear wing", Price = 0.05, RequiresRebirths = 1 },
			{ Id = "GT", Name = "GT wing", Price = 0.08, RequiresRebirths = 3 },
		},
		Tint = {
			{ Id = "Clear", Name = "Original", Price = 0 },
			{ Id = "Light", Name = "Light tint", Price = 0.01 },
			{ Id = "Dark", Name = "Dark tint", Price = 0.02 },
			{ Id = "Limo", Name = "Limo black", Price = 0.03 },
		},
		-- néon doux sous la caisse (Neon translucide, aucune lumière)
		Glow = {
			{ Id = "None", Name = "None", Price = 0 },
			{ Id = "Pink", Name = "Pink glow", Price = 0.05, Color = Color3.fromRGB(255, 110, 190) },
			{ Id = "Cyan", Name = "Cyan glow", Price = 0.05, Color = Color3.fromRGB(80, 220, 255) },
			{ Id = "Violet", Name = "Violet glow", Price = 0.05, Color = Color3.fromRGB(170, 110, 255) },
			{ Id = "Mint", Name = "Mint glow", Price = 0.05, Color = Color3.fromRGB(100, 240, 180) },
			{ Id = "Amber", Name = "Amber glow", Price = 0.05, Color = Color3.fromRGB(255, 180, 70) },
			{ Id = "White", Name = "White glow", Price = 0.06, Color = Color3.fromRGB(240, 244, 255), RequiresRebirths = 1 },
		},
		Interior = {
			{ Id = "Charcoal", Name = "Charcoal", Price = 0, Color = Color3.fromRGB(58, 52, 58) },
			{ Id = "Cream", Name = "Cream leather", Price = 0.02, Color = Color3.fromRGB(226, 212, 186) },
			{ Id = "Tan", Name = "Tan leather", Price = 0.02, Color = Color3.fromRGB(170, 112, 70) },
			{ Id = "Red", Name = "Racing red", Price = 0.02, Color = Color3.fromRGB(164, 32, 44) },
			{ Id = "Pink", Name = "Candy pink", Price = 0.02, Color = Color3.fromRGB(236, 130, 176) },
			{ Id = "Blue", Name = "Ocean blue", Price = 0.02, Color = Color3.fromRGB(46, 84, 150) },
		},
	},
	-- ordre des rubriques dans l'atelier (Mods)
	ModKinds = { "Finish", "Roof", "Rims", "RimColor", "Tyre", "Splitter", "Skirts", "Spoiler", "Tint", "Glow", "Interior" },
}

----------------------------------------------------------------------
-- 🍦 Nourriture de Dopamine Town (v9.8, FAIR98 ; FoodService) : achetée
-- aux stands (place, fête foraine, coin gourmand), tenue en main, mangée
-- bouchée par bouchée ; la dernière bouchée donne un BOOST de Dopamine
-- (x Multiplier pendant Duration s, vérifié par le serveur).
--   Prix : PriceFactor x la valeur du boost ((Multiplier - 1) x Duration
--          secondes de production), au moins MinPrice : manger rapporte
--          un peu plus que ça ne coûte, sans remplacer les Game Passes.
--   Cumul (FoodRules.Stack) : un seul boost "nourriture" à la fois ; un
--          aliment plus fort remplace le multiplicateur (le reste est
--          converti), un aliment moins fort ou égal prolonge (converti) ;
--          jamais plus de MaxSeconds restantes, jamais plus que MaxMultiplier.
--   Items : Id, Name, Icon, Multiplier, Duration (s), Bites (bouchées),
--           Color / Crumb (miettes), Desc
----------------------------------------------------------------------
Config.Food = {
	PriceFactor = 0.7,
	MinPrice = 40,
	MaxSeconds = 300,
	MaxMultiplier = 2,
	BiteCooldown = 0.55, -- s entre deux bouchées
	BuyCooldown = 1.5, -- s entre deux achats
	BuyDistance = 16, -- studs max entre l'avatar et le stand
	Items = {
		{ Id = "IceCream", Name = "Ice cream cone", Icon = "🍦", Multiplier = 1.5, Duration = 90, Bites = 4,
			Color = Color3.fromRGB(255, 176, 206), Crumb = Color3.fromRGB(226, 176, 112), Desc = "Two scoops, strawberry and mint" },
		{ Id = "CandyFloss", Name = "Candy floss", Icon = "🍭", Multiplier = 1.5, Duration = 120, Bites = 4,
			Color = Color3.fromRGB(255, 190, 224), Crumb = Color3.fromRGB(255, 200, 230), Desc = "A pink cloud on a stick" },
		{ Id = "Churros", Name = "Churros", Icon = "🥖", Multiplier = 1.4, Duration = 150, Bites = 3,
			Color = Color3.fromRGB(214, 150, 80), Crumb = Color3.fromRGB(236, 196, 120), Desc = "Crunchy, with sugar and cinnamon" },
		{ Id = "Popcorn", Name = "Popcorn", Icon = "🍿", Multiplier = 1.3, Duration = 180, Bites = 5,
			Color = Color3.fromRGB(255, 244, 214), Crumb = Color3.fromRGB(255, 240, 190), Desc = "A striped box of buttery popcorn" },
		{ Id = "Crepe", Name = "Crêpe", Icon = "🥞", Multiplier = 1.6, Duration = 120, Bites = 4,
			Color = Color3.fromRGB(236, 196, 130), Crumb = Color3.fromRGB(120, 76, 50), Desc = "Rolled crêpe with chocolate" },
		{ Id = "PizzaSlice", Name = "Pizza slice", Icon = "🍕", Multiplier = 1.8, Duration = 90, Bites = 4,
			Color = Color3.fromRGB(255, 206, 110), Crumb = Color3.fromRGB(214, 90, 60), Desc = "Cheesy slice with pepperoni" },
		{ Id = "Taco", Name = "Taco", Icon = "🌮", Multiplier = 1.8, Duration = 100, Bites = 4,
			Color = Color3.fromRGB(240, 196, 100), Crumb = Color3.fromRGB(110, 190, 90), Desc = "Crispy shell, salad and tomato" },
		{ Id = "Milkshake", Name = "Milkshake", Icon = "🥤", Multiplier = 2, Duration = 60, Bites = 4,
			Color = Color3.fromRGB(255, 200, 220), Crumb = Color3.fromRGB(255, 236, 244), Desc = "Strawberry shake with whipped cream" },
		{ Id = "HotDog", Name = "Hot dog", Icon = "🌭", Multiplier = 1.6, Duration = 150, Bites = 4,
			Color = Color3.fromRGB(226, 110, 80), Crumb = Color3.fromRGB(236, 190, 120), Desc = "With mustard and ketchup" },
		{ Id = "CandyApple", Name = "Candy apple", Icon = "🍎", Multiplier = 1.4, Duration = 180, Bites = 3,
			Color = Color3.fromRGB(214, 36, 56), Crumb = Color3.fromRGB(255, 120, 130), Desc = "A shiny red caramel apple" },
		{ Id = "Donut", Name = "Donut", Icon = "🍩", Multiplier = 1.5, Duration = 120, Bites = 3,
			Color = Color3.fromRGB(255, 150, 196), Crumb = Color3.fromRGB(214, 160, 100), Desc = "Pink glaze and sprinkles" },
	},
}
Config.FoodById = {}
for index, food in ipairs(Config.Food.Items) do
	food.Order = index
	Config.FoodById[food.Id] = food
end

----------------------------------------------------------------------
-- 🏁 Courses de rue (v10 RACE10, v11 RACE11 ; RaceService / Shared/RaceRules /
-- Shared/RaceRoutes / Client/World/RaceClient + RaceHud + RaceMenu) : 2 à 8
-- coureurs, des pilotes IA complètent la grille jusqu'à MinGrid. Vitesses en
-- studs/s.
--   Récompenses : secondes de production (Formulas.ScaledReward) selon la
--   place, x (1 + HumanBonus par adversaire humain, au plus MaxHumanBonus),
--   x SoloFactor sans adversaire humain ; DailyRewarded courses payées par
--   jour (ensuite : records, XP et trophées seulement). Voir RaceRules.
--   Anti-triche (serveur) : ordre des portes, temps minimal par tronçon,
--   vitesse plausible (nitro comprise), téléportation, être au volant.
--   (v11) Nitro : charges données par le serveur (1 au départ, + dérapages et
--   aspiration), boost court de la vitesse de pointe ; XP et rangs (Bronze ->
--   Diamant, cosmétiques) ; médailles par parcours (temps de référence) ;
--   fantôme de ton meilleur tour ; historique des courses.
----------------------------------------------------------------------
Config.Race = {
	MaxRacers = 8,
	MinGrid = 4, -- IA ajoutées jusqu'à 4 voitures sur la grille
	LobbySeconds = 20, -- attente après la 1re inscription
	LateJoinSeconds = 8, -- une inscription tardive laisse au moins 8 s
	GridSeconds = 3.5, -- mise en place sur la grille avant le 3-2-1 (caméra de présentation)
	CountdownSeconds = 3,
	FinishGrace = 35, -- s laissées aux autres après le 1er humain arrivé
	MaxSeconds = 480, -- durée max d'une course
	JoinRange = 45, -- studs : distance max du point de rendez-vous (à pied)
	ResetCooldown = 3, -- s entre deux "retour à la porte"
	OffCarGrace = 5, -- s hors de sa voiture -> abandon
	CheckpointSpacing = 170, -- studs entre deux portes
	-- (v11) grille de départ (studs) : voitures à l'échelle Roblox (CARS11)
	Grid = { First = 13, Row = 24, Side = 5.2 }, -- (CARS11 : voitures x1,3, limousine 19,8 de long)
	Rewards = {
		Seconds = { 120, 80, 55 }, -- 1er, 2e, 3e (secondes de production)
		FinishSeconds = 35, -- arrivé 4e ou plus
		MinReward = 250,
		HumanBonus = 0.1, -- +10 % par adversaire humain
		MaxHumanBonus = 0.3,
		SoloFactor = 0.75, -- seulement des IA en face
		DailyRewarded = 8, -- courses récompensées par jour
	},
	Anti = {
		SpeedMargin = 1.3, -- vitesse mesurée max = vitesse de pointe x 1,3 (+ AbsSlack)
		AbsSlack = 8,
		TeleportStuds = 70, -- saut instantané -> remis à la dernière porte
		MaxStrikes = 3, -- au 3e saut : disqualifié
		SegmentFactor = 1.15, -- tronçon plus rapide que longueur / (pointe x 1,15) : disqualifié
	},
	-- (v11) nitro : +Boost de vitesse de pointe pendant Seconds ; charges : Start
	-- au départ, au plus Max ; la jauge se remplit en dérapant (DriftPoints
	-- points = 1 charge) et dans l'aspiration d'une voiture (DraftSeconds s = 1 charge)
	Nitro = { Start = 1, Max = 3, Boost = 0.18, Seconds = 2.6, DriftPoints = 1400, DraftSeconds = 7 },
	-- (v11) dérapage mesuré par le serveur : angle de glisse (degrés) et vitesse minimale
	Drift = { MinAngle = 9, MaxAngle = 65, MinSpeed = 22 },
	-- (v11) XP de course (rang cosmétique, sans effet sur l'économie)
	Xp = {
		Finish = 40, -- arrivé
		Place = { 60, 40, 25 }, -- bonus 1er / 2e / 3e
		PerHuman = 10, -- par adversaire humain
		MaxHuman = 30,
		Medal = { 30, 20, 10 }, -- or / argent / bronze
		Record = 20, -- nouveau record personnel
		Dnf = 8, -- abandon (participation)
		Overtake = 3, -- par dépassement (au plus MaxOvertakes)
		MaxOvertakes = 8,
	},
	-- (v11) rangs : 3 divisions (III -> I) par palier, Diamant au sommet
	Ranks = {
		{ Id = "Bronze", Name = "Bronze", Icon = "🥉", Min = 0, Color = { 214, 140, 82 } },
		{ Id = "Silver", Name = "Silver", Icon = "🥈", Min = 600, Color = { 200, 210, 226 } },
		{ Id = "Gold", Name = "Gold", Icon = "🥇", Min = 1800, Color = { 255, 204, 60 } },
		{ Id = "Platinum", Name = "Platinum", Icon = "💠", Min = 4000, Color = { 120, 230, 220 } },
		{ Id = "Diamond", Name = "Diamond", Icon = "💎", Min = 8000, Color = { 140, 200, 255 } },
	},
	-- (v11) médailles : temps de référence (pilote parfait, Par.TopSpeed) x facteur
	Medals = { Gold = 1.06, Silver = 1.18, Bronze = 1.35 },
	Par = { TopSpeed = 66, Accel = 30 },
	HistorySize = 20, -- dernières courses gardées (stats, graphe)
	AI = {
		LatAccel = 30, -- (studs/s²) virages
		Brake = 38, -- (studs/s²) freinage anticipé
		Skill = { 0.9, 0.93, 0.95, 0.97, 0.91, 0.94, 0.96 },
		RubberBoost = 0.06, -- au plus +6 % derrière le 1er humain (jamais au-delà de sa vitesse de pointe)
		RubberSlow = 0.1, -- au plus -10 % devant tous les humains
		RubberRange = 500, -- (studs) écart pour l'effet maximal
		FairFinish = 0.12, -- aucun élastique dans les derniers 12 % de la course
		Draft = 0.04, -- (v11) aspiration : +4 % derrière une voiture (8..30 studs)
		Launch = { 0.15, 0.45 }, -- (v11) temps de réaction au départ (s)
		Names = { "Nina Turbo", "Max Vroom", "Lou Drift", "Sam Nitro", "Zoé Flash", "Téo Pistons", "Lina Rocket" },
	},
	Routes = {
		{ Id = "City", Name = "City circuit", Icon = "🏙️", Laps = 2, Desc = "Two laps around downtown", Color = { 255, 214, 90 } },
		{ Id = "Highway", Name = "Highway sprint", Icon = "🛣️", Laps = 1, Sprint = true, Desc = "Flat out on the highway", Color = { 90, 210, 255 } },
		{ Id = "Districts", Name = "District loop", Icon = "🏘️", Laps = 1, Desc = "Through every district", Color = { 120, 236, 150 } },
		{ Id = "Night", Name = "Night race", Icon = "🌙", Laps = 1, Night = true, Desc = "The grand tour, under the stars", Color = { 196, 140, 255 } },
		-- (v11, RACE11)
		{ Id = "Belt", Name = "Ring road Grand Prix", Icon = "🏎️", Laps = 1, Desc = "One fast lap of the ring avenue", Color = { 255, 120, 90 } },
		{ Id = "Loft", Name = "Warehouse circuit", Icon = "🏭", Laps = 3, Desc = "Three tight laps among the lofts", Color = { 255, 150, 210 } },
		{ Id = "Endurance", Name = "Highway endurance", Icon = "🌀", Laps = 1, Desc = "The whole highway loop, nitro ready", Color = { 110, 240, 230 } },
	},
}
Config.RaceRoutesById = {}
for index, route in ipairs(Config.Race.Routes) do
	route.Order = index
	Config.RaceRoutesById[route.Id] = route
end

----------------------------------------------------------------------
-- 🏦 (v11, BANK11) Banque Dopamine, 💎 DIAMANTS et CASSES (cartoon, sans
-- armes). Règles pures : Shared/Diamonds (monnaie, coffre, change, boutique
-- de luxe) et Shared/HeistRules (récompenses, plafonds, mini-jeux) ;
-- serveur : BankService + HeistKit (aussi utilisé par le train).
--   - Les 💎 se gagnent aux casses (banque, convoi du train), sont gardés
--     pour toujours (jamais remis à zéro par l'océan) et s'échangent contre
--     des objets de LUXE (Luxury) ou un peu de Dopamine (Exchange, plafonné).
--   - Poche (Wallet) / coffre (Vault) : le coffre rapporte des intérêts
--     (Vault.*) à réclamer une fois par jour au guichet.
--   - Récompense en Dopamine d'un casse = secondes de production (comme les
--     courses), x bonus d'équipe, x part du butin livrée ; plafond par jour.
----------------------------------------------------------------------
Config.Bank = {
	Diamonds = {
		DailyCap = 80, -- 💎 max gagnés par jour aux casses (intérêts à part)
		MaxBalance = 1000000, -- garde-fou (poche + coffre)
		HistorySize = 30, -- lignes de l'historique gardées
	},
	Vault = {
		InterestRate = 0.02, -- +2 % du coffre par jour...
		MinForInterest = 10, -- ... dès 10 💎 au coffre (au moins 1 💎)
		InterestMax = 10, -- ... au plus 10 💎 par jour
		MaxMove = 100000, -- dépôt / retrait max par opération
	},
	Exchange = {
		SecondsPerDiamond = 30, -- 1 💎 = 30 s de production en Dopamine
		DailyMax = 15, -- 💎 échangeables par jour
		MinPerDiamond = 500, -- Dopamine minimale pour 1 💎
	},
	Heist = {
		LobbySeconds = 30, -- attente de l'équipe (le chef peut lancer avant)
		MaxCrew = 4,
		BagCapacity = 3, -- piles de butin par sac
		CarrySlow = 0.85, -- vitesse de marche avec un sac sur le dos
		MinFill = 0.2, -- part minimale du butin livrée pour être payé
		CrewBonus = 0.1, -- +10 % par coéquipier...
		MaxCrewBonus = 0.3, -- ... au plus +30 %
		Range = 5, -- (studs) marge des vérifications de distance
		MaxSpeed = 150, -- (studs/s) au-delà : téléportation -> le sac tombe
		HackLength = 5, -- symboles du code à recopier
		HackMinSeconds = 3, -- temps minimal pour pirater
		DrillSeconds = 22, -- durée du perçage (hors blocages)
		DrillJams = 2, -- blocages à débloquer (E) pendant le perçage
		CrowbarTaps = 12, -- coups de pied-de-biche pour forcer une porte
		CrowbarMinInterval = 0.08,
		GrabSeconds = 1.5, -- (s) maintenir E sur une pile de butin
		Kinds = {
			-- Seconds : secondes de production (sac plein, seul) ; Diamonds = { min, max } (part vide -> pleine) ;
			-- Daily : casses payés par jour ; Cooldown / FailCooldown : (s) entre deux casses du serveur ;
			-- Duration : (s) chrono après le déclenchement de l'alarme
			Bank = { Name = "Bank heist", Icon = "🏦", Seconds = 120, Diamonds = { 8, 20 }, Daily = 3, Cooldown = 600, FailCooldown = 300, Duration = 210 },
			Train = { Name = "Diamond convoy", Icon = "🚂", Seconds = 90, Diamonds = { 5, 14 }, Daily = 4, Cooldown = 1200, FailCooldown = 600, Duration = 210 },
		},
	},
	-- 💎 Boutique de luxe. Kind : "Wear" (porté en ville, vu de tous ; Slot =
	-- Head | Face | Neck | Wrist | Back | Aura), "Title" (titre au-dessus de la
	-- tête), "Paint" (peinture de voiture : atelier CarWorkshop / CarService
	-- via BankService:OwnsLuxury), "Furniture" (objet de maison : ajouté à
	-- data.House.Items). Price en 💎 ; NeedHeists = casses réussis requis.
	Luxury = {
		{ Id = "GoldWatch", Name = "Gold watch", Icon = "⌚", Kind = "Wear", Slot = "Wrist", Price = 30, Desc = "A heavy gold watch that sparkles" },
		{ Id = "GoldChain", Name = "Gold chain", Icon = "📿", Kind = "Wear", Slot = "Neck", Price = 35, Desc = "A thick 24-carat chain" },
		{ Id = "GoldShades", Name = "Gold sunglasses", Icon = "🕶️", Kind = "Wear", Slot = "Face", Price = 40, Desc = "Gold frames, mirror lenses" },
		{ Id = "DiamondMonocle", Name = "Diamond monocle", Icon = "🧐", Kind = "Wear", Slot = "Face", Price = 55, Desc = "Very distinguished" },
		{ Id = "MogulHat", Name = "Tycoon top hat", Icon = "🎩", Kind = "Wear", Slot = "Head", Price = 70, Desc = "Black silk with a diamond band" },
		{ Id = "VelvetCape", Name = "Royal velvet cape", Icon = "🦸", Kind = "Wear", Slot = "Back", Price = 80, Desc = "Crimson velvet with ermine trim" },
		{ Id = "DiamondNecklace", Name = "Diamond necklace", Icon = "💎", Kind = "Wear", Slot = "Neck", Price = 90, Desc = "A river of diamonds" },
		{ Id = "DiamondCrown", Name = "Diamond crown", Icon = "👑", Kind = "Wear", Slot = "Head", Price = 150, Desc = "Gold, velvet and twelve diamonds" },
		{ Id = "SparkleAura", Name = "Diamond sparkle aura", Icon = "✨", Kind = "Wear", Slot = "Aura", Price = 160, Desc = "Tiny diamonds swirl around you" },
		{ Id = "CrystalWings", Name = "Crystal wings", Icon = "🪽", Kind = "Wear", Slot = "Back", Price = 220, Desc = "Shimmering wings that flap softly" },
		{ Id = "GoldenAura", Name = "Golden halo aura", Icon = "🌟", Kind = "Wear", Slot = "Aura", Price = 260, Desc = "A golden ring of light at your feet" },
		{ Id = "TitleDealer", Name = "Title: Diamond dealer", Icon = "💎", Kind = "Title", Slot = "Title", Price = 25, Title = "💎 Diamond dealer", Desc = "Shown above your head in town" },
		{ Id = "TitleBanker", Name = "Title: Banker", Icon = "🏦", Kind = "Title", Slot = "Title", Price = 25, Title = "🏦 Banker", Desc = "Shown above your head in town" },
		{ Id = "TitleMastermind", Name = "Title: Mastermind", Icon = "🕶️", Kind = "Title", Slot = "Title", Price = 40, NeedHeists = 3, Title = "🕶️ Mastermind", Desc = "After 3 successful heists" },
		{ Id = "TitleTycoon", Name = "Title: Tycoon", Icon = "👑", Kind = "Title", Slot = "Title", Price = 300, Title = "👑 Tycoon", Desc = "The richest title in town" },
		{ Id = "PaintDiamond", Name = "Diamond pearl paint", Icon = "🤍", Kind = "Paint", Price = 60, Color = Color3.fromRGB(236, 244, 255), Desc = "Pearly white with diamond flakes" },
		{ Id = "PaintGold", Name = "24-carat gold paint", Icon = "🟡", Kind = "Paint", Price = 90, Color = Color3.fromRGB(232, 180, 52), Desc = "Real gold leaf look" },
		{ Id = "PaintChrome", Name = "Mirror chrome paint", Icon = "🪩", Kind = "Paint", Price = 120, Color = Color3.fromRGB(206, 214, 226), Desc = "Like a mirror on wheels" },
		{ Id = "PaintStarry", Name = "Starry black paint", Icon = "🌌", Kind = "Paint", Price = 150, Color = Color3.fromRGB(22, 20, 40), Desc = "Deep black with gold stars" },
	},
}
Config.BankLuxuryById = {}
for index, item in ipairs(Config.Bank.Luxury) do
	item.Order = index
	Config.BankLuxuryById[item.Id] = item
end

----------------------------------------------------------------------
-- Index calculés automatiquement (ne pas modifier)
----------------------------------------------------------------------
Config.UpgradesById = {}
Config.FeatureToUpgrade = {} -- [Feature] = Id de l'amélioration qui la débloque
for index, upgrade in ipairs(Config.Upgrades) do
	upgrade.Order = index
	upgrade.CostGrowth = upgrade.CostGrowth or 1
	Config.UpgradesById[upgrade.Id] = upgrade
	if upgrade.Feature then
		Config.FeatureToUpgrade[upgrade.Feature] = upgrade.Id
	end
end

Config.AchievementsById = {}
for _, achievement in ipairs(Config.Achievements) do
	achievement.BadgeId = achievement.BadgeId or Config.AchievementBadges[achievement.Id] or 0
	Config.AchievementsById[achievement.Id] = achievement
end

Config.CosmeticsById = {}
for index, cosmetic in ipairs(Config.Cosmetics) do
	cosmetic.Order = index
	Config.CosmeticsById[cosmetic.Id] = cosmetic
end

Config.ThemesById = {}
for index, theme in ipairs(Config.Themes) do
	theme.Order = index
	Config.ThemesById[theme.Id] = theme
end

Config.GamePassesById = {}
for _, pass in ipairs(Config.Monetization.GamePasses) do
	Config.GamePassesById[pass.Id] = pass
end

Config.ProductsById = {}
Config.ProductsByProductId = {} -- [ProductId Roblox] = offre
for _, product in ipairs(Config.Monetization.Products) do
	Config.ProductsById[product.Id] = product
	if product.ProductId ~= 0 then
		Config.ProductsByProductId[product.ProductId] = product
	end
end

-- true si au moins une offre Robux est configurée (ID ~= 0)
Config.IsSellingForRobux = false
for _, pass in ipairs(Config.Monetization.GamePasses) do
	if pass.GamePassId ~= 0 then
		Config.IsSellingForRobux = true
	end
end
for _, product in ipairs(Config.Monetization.Products) do
	if product.ProductId ~= 0 then
		Config.IsSellingForRobux = true
	end
end
for _, theme in ipairs(Config.Themes) do
	if theme.GamePassId ~= 0 then
		Config.IsSellingForRobux = true
	end
end

Config.CasinoSymbolsById = {}
for _, symbol in ipairs(Config.Casino.Symbols) do
	Config.CasinoSymbolsById[symbol.Id] = symbol
end

-- 🏠 Maison
Config.HouseSizesById = {}
for index, size in ipairs(Config.House.Sizes) do
	size.Order = index -- plus grand = plus grande maison
	size.MaxRooms = size.Floors * size.Columns
	Config.HouseSizesById[size.Id] = size
end

-- Types de pièces : objets / catégories préférés en tables { [id] = true }
Config.HouseRoomTypesById = {}
for index, roomType in ipairs(Config.House.RoomTypes) do
	roomType.Order = index
	roomType.FavoriteCategories = {}
	for _, categoryId in ipairs(roomType.Categories) do
		roomType.FavoriteCategories[categoryId] = true
	end
	roomType.FavoriteItems = {}
	for _, itemId in ipairs(roomType.Items) do
		roomType.FavoriteItems[itemId] = true
	end
	Config.HouseRoomTypesById[roomType.Id] = roomType
end

Config.HouseWallpapersById = {}
for index, wallpaper in ipairs(Config.House.Wallpapers) do
	wallpaper.Order = index
	Config.HouseWallpapersById[wallpaper.Id] = wallpaper
end

Config.HouseFloorsById = {}
for index, floor in ipairs(Config.House.Floors) do
	floor.Order = index
	Config.HouseFloorsById[floor.Id] = floor
end

Config.HouseCategoriesById = {}
for index, category in ipairs(Config.House.Categories) do
	category.Order = index
	Config.HouseCategoriesById[category.Id] = category
end

Config.HouseItemsById = {}
Config.HouseItemsByCategory = {} -- [categoryId] = { objets dans l'ordre de la config }
for _, category in ipairs(Config.House.Categories) do
	Config.HouseItemsByCategory[category.Id] = {}
end
for index, item in ipairs(Config.House.Items) do
	item.Order = index
	item.CostGrowth = item.CostGrowth or 1
	Config.HouseItemsById[item.Id] = item
	local list = Config.HouseItemsByCategory[item.Category]
	if list then
		table.insert(list, item)
	end
end

-- (v9.1) Personnalisation : un "genre" par axe. Scope "Room" = choisi par
-- pièce (champ Field de la pièce), "House" = toute la maison (champ Field de
-- data.House), "Garden" = liste de déco du jardin ; Owned = table des
-- entrées achetées dans data.House ; la 1re entrée de chaque liste est
-- gratuite (Cost 0) sauf pour le jardin
Config.HouseLookKinds = {
	Trim = { List = Config.House.Trims, Owned = "OwnedTrims", Scope = "Room", Field = "Trim" },
	Mood = { List = Config.House.Moods, Owned = "OwnedMoods", Scope = "Room", Field = "Mood" },
	View = { List = Config.House.Views, Owned = "OwnedViews", Scope = "Room", Field = "View" },
	Facade = { List = Config.House.Facades, Owned = "OwnedFacades", Scope = "House", Field = "Facade" },
	Roof = { List = Config.House.Roofs, Owned = "OwnedRoofs", Scope = "House", Field = "Roof" },
	RoofStyle = { List = Config.House.RoofStyles, Owned = "OwnedRoofStyles", Scope = "House", Field = "RoofStyle" },
	Garden = { List = Config.House.GardenDecor, Owned = "OwnedGarden", Scope = "Garden", Field = "Garden" },
}
Config.HouseLooksById = {} -- [kind] = { [id] = entrée }
for kind, def in pairs(Config.HouseLookKinds) do
	local byId = {}
	for index, entry in ipairs(def.List) do
		entry.Order = index
		entry.Cost = entry.Cost or 0
		byId[entry.Id] = entry
	end
	def.ById = byId
	def.Kind = kind
	Config.HouseLooksById[kind] = byId
end
-- (v9.3) Paliers des visites à l'océan de la maison (Config.House.RebirthGates) :
-- chaque objet / style sans RequiresRebirths reçoit le palier de son prix de
-- base, puis son prix est multiplié par le Price du palier. Fait UNE fois ici
-- (serveur et client voient les mêmes prix ; BaseCost = prix d'origine).
do
	local gates = Config.House.RebirthGates
	local function priceFor(rebirths: number): number
		local price = 1
		for _, gate in ipairs(gates) do
			if rebirths >= gate.Rebirths then
				price = gate.Price or price
			end
		end
		return price
	end
	local function applyGate(entry)
		if type(entry) ~= "table" or type(entry.Cost) ~= "number" or entry.BaseCost ~= nil then
			return
		end
		entry.BaseCost = entry.Cost
		local rebirths = tonumber(entry.RequiresRebirths)
		if not rebirths then
			rebirths = 0
			for _, gate in ipairs(gates) do
				if entry.Cost >= gate.Cost then
					rebirths = math.max(rebirths, gate.Rebirths)
				end
			end
			entry.RequiresRebirths = rebirths
		end
		if entry.Cost > 0 then
			-- arrondi à 2 chiffres significatifs (prix lisibles)
			local price = entry.Cost * priceFor(rebirths)
			local unit = 10 ^ math.max(0, math.floor(math.log10(price)) - 1)
			entry.Cost = math.floor(price / unit + 0.5) * unit
		end
	end
	for _, item in ipairs(Config.House.Items) do
		applyGate(item)
	end
	for _, entry in ipairs(Config.House.Wallpapers) do
		applyGate(entry)
	end
	for _, entry in ipairs(Config.House.Floors) do
		applyGate(entry)
	end
	for _, def in pairs(Config.HouseLookKinds) do
		for _, entry in ipairs(def.List) do
			applyGate(entry)
		end
	end
end

Config.HouseTrimsById = Config.HouseLooksById.Trim
Config.HouseMoodsById = Config.HouseLooksById.Mood
Config.HouseViewsById = Config.HouseLooksById.View
Config.HouseTintsById = {}
for index, tint in ipairs(Config.House.Tints) do
	tint.Order = index
	Config.HouseTintsById[tint.Id] = tint
end

-- 🚗 Voitures (v9.6)
Config.CarsById = {}
for index, car in ipairs(Config.Cars.List) do
	car.Order = index
	Config.CarsById[car.Id] = car
end
Config.CarColorsById = {}
for index, paint in ipairs(Config.Cars.Colors) do
	paint.Order = index
	Config.CarColorsById[paint.Id] = paint
end
-- (v10, CARS10) options de l'atelier : [kind][id] = entrée ; pièces de préparation
Config.CarModsById = {}
for kind, list in pairs(Config.Cars.Mods) do
	local byId = {}
	for index, entry in ipairs(list) do
		entry.Order = index
		entry.Kind = kind
		byId[entry.Id] = entry
	end
	Config.CarModsById[kind] = byId
end
Config.CarTuningById = {}
for index, part in ipairs(Config.Cars.Tuning.Parts) do
	part.Order = index
	Config.CarTuningById[part.Id] = part
end

return Config
