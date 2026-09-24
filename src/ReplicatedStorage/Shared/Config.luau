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
--   Feature     : ce que l'amélioration fait apparaître à l'écran / débloque
--                 (nom d'un module client dans Client > Stimuli, ou d'un menu)
--   Permanent   : true = conservée après "Aller à l'océan" (menus utiles)
--   Color       : couleur de la carte en mode "Icônes HD"
--
-- Équilibrage (simulé : 5 clics/s, ~50 % des bonus attrapés, on achète
-- toujours l'amélioration abordable la moins chère) : une nouveauté à
-- l'écran toutes les 1 à 3 min, jamais plus de ~3 min sans achat, 1re
-- visite à l'océan après ~70 min ; la 2e partie est ~2x plus rapide.
----------------------------------------------------------------------
Config.Upgrades = {
	{ Id = "Finger", Name = "Doigt musclé", Icon = "👆", Description = "+%s Dopamine par clic",
		Cost = 10, CostGrowth = 2.2, MaxLevel = 15, Effect = "Click", Value = 1,
		Color = Color3.fromRGB(255, 196, 0) },
	{ Id = "DVD", Name = "Logo DVD", Icon = "📀", Description = "Un logo qui rebondit. +%s Dopamine à chaque rebond",
		Cost = 110, CostGrowth = 2.2, MaxLevel = 10, Effect = "DVD", Value = 1, Feature = "DVD",
		Color = Color3.fromRGB(40, 40, 40) },
	{ Id = "NewsTicker", Name = "Fil d'actu", Icon = "📰", Description = "Des infos absurdes en continu. +%s Dopamine / s",
		Cost = 450, MaxLevel = 1, Effect = "PerSecond", Value = 8, Feature = "NewsTicker",
		Color = Color3.fromRGB(230, 30, 40) },
	{ Id = "DailyGift", Name = "Calendrier", Icon = "📅", Description = "Débloque le cadeau quotidien (conservé pour toujours)",
		Cost = 1200, MaxLevel = 1, Effect = "Feature", Feature = "Daily", Permanent = true,
		Color = Color3.fromRGB(255, 90, 150) },
	{ Id = "DVDSound", Name = "Bruit du DVD", Icon = "🔊", Description = "Chaque rebond fait du bruit. Rebonds x%s",
		Cost = 3500, MaxLevel = 1, Effect = "BounceMultiplier", Value = 3, Feature = "DVDSound",
		Color = Color3.fromRGB(0, 170, 255) },
	{ Id = "Runner", Name = "Coureur infini", Icon = "🏃", Description = "Un jeu de course tourne en boucle. +%s Dopamine / s",
		Cost = 5500, MaxLevel = 1, Effect = "PerSecond", Value = 25, Feature = "Runner",
		Color = Color3.fromRGB(255, 120, 0) },
	{ Id = "Megaphone", Name = "Mégaphone", Icon = "📢", Description = "TOUT EN MAJUSCULES !!! Clics x%s",
		Cost = 6000, MaxLevel = 1, Effect = "ClickMultiplier", Value = 2, Feature = "Megaphone",
		Color = Color3.fromRGB(220, 20, 20) },
	{ Id = "Lofi", Name = "Lofi Beats", Icon = "🎧", Description = "Pour étudier et se détendre. +%s Dopamine / s",
		Cost = 12000, MaxLevel = 1, Effect = "PerSecond", Value = 40, Feature = "Lofi",
		Color = Color3.fromRGB(120, 90, 200) },
	{ Id = "Press", Name = "Presse hydraulique", Icon = "🗜️", Description = "Écrase des trucs, c'est satisfaisant. +%s Dopamine / s",
		Cost = 18000, CostGrowth = 1.75, MaxLevel = 10, Effect = "PerSecond", Value = 20, Feature = "Press",
		Color = Color3.fromRGB(255, 200, 0) },
	{ Id = "Achievements", Name = "Succès", Icon = "🏆", Description = "Débloque le menu des succès (conservé pour toujours)",
		Cost = 25000, MaxLevel = 1, Effect = "Feature", Feature = "Achievements", Permanent = true,
		Color = Color3.fromRGB(150, 60, 220) },
	{ Id = "Pinwheel", Name = "Moulin à vent", Icon = "🌀", Description = "Il tourne. Souffle dessus ! +%s Dopamine / s",
		Cost = 28000, MaxLevel = 1, Effect = "PerSecond", Value = 75, Feature = "Pinwheel",
		Color = Color3.fromRGB(80, 200, 255) },
	{ Id = "BubbleWrap", Name = "Papier bulle", Icon = "🔘", Description = "Éclate les bulles pour gagner de la Dopamine",
		Cost = 30000, MaxLevel = 1, Effect = "Feature", Feature = "BubbleWrap",
		Color = Color3.fromRGB(160, 220, 255) },
	{ Id = "Weather", Name = "Orage", Icon = "⛈️", Description = "Attrape les éclairs ! +%s Dopamine / s",
		Cost = 33000, MaxLevel = 1, Effect = "PerSecond", Value = 100, Feature = "Weather",
		Color = Color3.fromRGB(30, 110, 200) },
	{ Id = "ItemShop", Name = "Boutique d'objets", Icon = "🧢", Description = "Des chapeaux pour ton bouton (conservé pour toujours)",
		Cost = 55000, MaxLevel = 1, Effect = "Feature", Feature = "ItemShop", Permanent = true,
		Color = Color3.fromRGB(60, 200, 60) },
	{ Id = "Stocks", Name = "Bourse", Icon = "📈", Description = "Investis ta Dopamine. Ça monte... ou pas.",
		Cost = 60000, MaxLevel = 1, Effect = "Feature", Feature = "Stocks",
		Color = Color3.fromRGB(20, 160, 90) },
	{ Id = "Boost", Name = "Flèche verte", Icon = "⬆️", Description = "Tout augmente. TOUT. Gains x%s",
		Cost = 68000, MaxLevel = 1, Effect = "Multiplier", Value = 2, Feature = "Boost",
		Color = Color3.fromRGB(40, 220, 60) },
	{ Id = "LiveStream", Name = "Live ASMR", Icon = "🥪", Description = "Quelqu'un mange en direct. +%s Dopamine / s",
		Cost = 100000, MaxLevel = 1, Effect = "PerSecond", Value = 120, Feature = "LiveStream",
		Color = Color3.fromRGB(240, 170, 90) },
	{ Id = "Followers", Name = "Abonnés", Icon = "👥", Description = "Plus de spectateurs sur le live. +%s Dopamine / s",
		Cost = 150000, CostGrowth = 1.6, MaxLevel = 15, Effect = "PerSecond", Value = 50, Feature = "Followers",
		Color = Color3.fromRGB(255, 60, 100) },
	{ Id = "PhoneNotifs", Name = "Notifications", Icon = "🔔", Description = "Ding ! Ding ! Ding ! +%s Dopamine / s",
		Cost = 200000, MaxLevel = 1, Effect = "PerSecond", Value = 150, Feature = "PhoneNotifs",
		Color = Color3.fromRGB(255, 70, 70) },
	{ Id = "Combo", Name = "Combo", Icon = "⚡", Description = "Clique vite pour multiplier tes clics (jusqu'à x3)",
		Cost = 260000, MaxLevel = 1, Effect = "Feature", Feature = "Combo",
		Color = Color3.fromRGB(255, 220, 0) },
	{ Id = "Email", Name = "Boîte mail", Icon = "📧", Description = "Tu as (beaucoup) de nouveaux messages",
		Cost = 320000, MaxLevel = 1, Effect = "Feature", Feature = "Email",
		Color = Color3.fromRGB(0, 120, 255) },
	{ Id = "Quests", Name = "Quêtes", Icon = "📜", Description = "Débloque les quêtes (conservé pour toujours)",
		Cost = 520000, MaxLevel = 1, Effect = "Feature", Feature = "Quests", Permanent = true,
		Color = Color3.fromRGB(255, 140, 30) },
	{ Id = "Casino", Name = "Machine à sous", Icon = "🎰", Description = "Tente ta chance (avec ta Dopamine uniquement)",
		Cost = 600000, MaxLevel = 1, Effect = "Feature", Feature = "Casino",
		Color = Color3.fromRGB(200, 0, 60) },
	{ Id = "PressStart", Name = "Presse turbo", Icon = "⚙️", Description = "Un bouton START pour écraser toi-même",
		Cost = 650000, MaxLevel = 1, Effect = "Feature", Feature = "PressStart",
		Color = Color3.fromRGB(130, 130, 140) },
	{ Id = "LiveChat", Name = "Chat en direct", Icon = "💬", Description = "Le chat du live s'emballe. Clics x%s",
		Cost = 800000, MaxLevel = 1, Effect = "ClickMultiplier", Value = 3, Feature = "LiveChat",
		Color = Color3.fromRGB(145, 70, 255) },
	{ Id = "ScreenTime", Name = "Temps d'écran", Icon = "📱", Description = "Découvre combien de temps tu as perdu ici",
		Cost = 1e6, MaxLevel = 1, Effect = "Feature", Feature = "ScreenTime", Permanent = true,
		Color = Color3.fromRGB(45, 45, 50) },
	{ Id = "LootBox", Name = "Coffre mystère", Icon = "📦", Description = "Un coffre se remplit avec le temps. Ouvre-le !",
		Cost = 1.2e6, MaxLevel = 1, Effect = "Feature", Feature = "LootBox",
		Color = Color3.fromRGB(170, 110, 50) },
	{ Id = "EmojiRain", Name = "Pluie d'emojis", Icon = "😂", Description = "Il pleut des emojis. +%s Dopamine / s",
		Cost = 1.5e6, MaxLevel = 1, Effect = "PerSecond", Value = 1000, Feature = "EmojiRain",
		Color = Color3.fromRGB(255, 210, 60) },
	{ Id = "HDIcons", Name = "Icônes HD", Icon = "✨", Description = "Des icônes toutes brillantes. Gains x%s",
		Cost = 1.9e6, MaxLevel = 1, Effect = "Multiplier", Value = 1.5, Feature = "HDIcons",
		Color = Color3.fromRGB(255, 120, 220) },
	{ Id = "GoldenStar", Name = "Étoile dorée", Icon = "🌟", Description = "Des étoiles dorées apparaissent. Attrape-les !",
		Cost = 2.8e6, MaxLevel = 1, Effect = "Feature", Feature = "GoldenStar",
		Color = Color3.fromRGB(255, 190, 0) },
	{ Id = "Leaderboard", Name = "Classement", Icon = "🥇", Description = "Compare-toi au monde entier (conservé pour toujours)",
		Cost = 3.8e6, MaxLevel = 1, Effect = "Feature", Feature = "Leaderboard", Permanent = true,
		Color = Color3.fromRGB(0, 150, 220) },
	{ Id = "NeonMode", Name = "Mode néon", Icon = "🌈", Description = "L'écran passe en mode néon. Gains x%s",
		Cost = 4.5e6, MaxLevel = 1, Effect = "Multiplier", Value = 2, Feature = "NeonMode",
		Color = Color3.fromRGB(157, 78, 221) },
	{ Id = "CursorTrail", Name = "Traînée magique", Icon = "💫", Description = "Ta souris laisse des étincelles. Clics x%s",
		Cost = 7.5e6, MaxLevel = 1, Effect = "ClickMultiplier", Value = 2, Feature = "CursorTrail",
		Color = Color3.fromRGB(255, 80, 200) },
	{ Id = "Disco", Name = "Boule disco", Icon = "💃", Description = "C'est la fête ! Gains x%s",
		Cost = 1.2e7, MaxLevel = 1, Effect = "Multiplier", Value = 2, Feature = "Disco",
		Color = Color3.fromRGB(200, 60, 255) },
	{ Id = "Ocean", Name = "Aller à l'océan", Icon = "🌊", Description = "Tout lâcher et respirer. Recommence avec des gains x%s pour toujours",
		Cost = 0, MaxLevel = nil, Effect = "Detox", Feature = nil,
		Color = Color3.fromRGB(0, 140, 200) },
}

----------------------------------------------------------------------
-- Rebirth ("Aller à l'océan")
----------------------------------------------------------------------
Config.Rebirth = {
	BaseCost = 4.5e7, -- prix de la 1re visite à l'océan
	CostGrowth = 2.5, -- chaque visite coûte x2,5 de plus
	MultiplierPerRebirth = 0.5, -- +50 % de gains permanents par visite
}

----------------------------------------------------------------------
-- Récompenses "à l'échelle" : beaucoup de récompenses valent
-- "X secondes de production" pour rester intéressantes à tous les stades.
-- Production estimée = Dopamine/s + (Dopamine/clic * EstimatedClicksPerSecond)
----------------------------------------------------------------------
Config.Rewards = {
	EstimatedClicksPerSecond = 3,
}

Config.AchievementBonus = 0.02 -- +2 % de gains permanents par succès débloqué
Config.CosmeticBonus = 0.02 -- +2 % de gains permanents par objet cosmétique possédé

----------------------------------------------------------------------
-- Succès (toujours comptés ; le menu apparaît avec l'amélioration "Succès")
--   Stat : statistique suivie (data.Stats[Stat] ou data[Stat], ex. Rebirths)
----------------------------------------------------------------------
Config.Achievements = {
	{ Id = "Clicks100", Name = "Doigt chaud", Icon = "👆", Stat = "TotalClicks", Goal = 100, Reward = 50},
	{ Id = "Clicks1K", Name = "Clic addict", Icon = "🔥", Stat = "TotalClicks", Goal = 1000, Reward = 2500},
	{ Id = "Clicks10K", Name = "Tendinite", Icon = "🩹", Stat = "TotalClicks", Goal = 10000, Reward = 200000},
	{ Id = "Clicks100K", Name = "Machine humaine", Icon = "🦿", Stat = "TotalClicks", Goal = 100000, Reward = 1e8},
	{ Id = "Earn1K", Name = "Premier shoot", Icon = "💧", Stat = "LifetimeDopamine", Goal = 1000, Reward = 100},
	{ Id = "Earn1M", Name = "Millionnaire du bonheur", Icon = "💰", Stat = "LifetimeDopamine", Goal = 1e6, Reward = 75000},
	{ Id = "Earn1B", Name = "Milliardaire neuronal", Icon = "💎", Stat = "LifetimeDopamine", Goal = 1e9, Reward = 5e6},
	{ Id = "Earn1T", Name = "Cerveau cosmique", Icon = "🪐", Stat = "LifetimeDopamine", Goal = 1e12, Reward = 1e10},
	{ Id = "Buy10", Name = "Shopping", Icon = "🛒", Stat = "UpgradesBought", Goal = 10, Reward = 250},
	{ Id = "Buy50", Name = "Accro aux achats", Icon = "🛍️", Stat = "UpgradesBought", Goal = 50, Reward = 200000},
	{ Id = "Bounce100", Name = "Ça rebondit", Icon = "📀", Stat = "Bounces", Goal = 100, Reward = 1500},
	{ Id = "Bounce5K", Name = "Hypnotisé", Icon = "😵", Stat = "Bounces", Goal = 5000, Reward = 250000},
	{ Id = "Corner1", Name = "LE COIN !!!", Icon = "📐", Stat = "DVDCorners", Goal = 1, Reward = 10000},
	{ Id = "Combo1", Name = "Combo max !", Icon = "⚡", Stat = "CombosMaxed", Goal = 1, Reward = 150000},
	{ Id = "Bubble100", Name = "Pop pop pop", Icon = "🔘", Stat = "BubblesPopped", Goal = 100, Reward = 25000},
	{ Id = "Bubble1K", Name = "Plus de papier bulle", Icon = "📦", Stat = "BubblesPopped", Goal = 1000, Reward = 150000},
	{ Id = "Golden1", Name = "Main en or", Icon = "🌟", Stat = "GoldenClicks", Goal = 1, Reward = 1e6},
	{ Id = "Golden10", Name = "Chercheur d'or", Icon = "🏆", Stat = "GoldenClicks", Goal = 10, Reward = 2e6},
	{ Id = "Lightning5", Name = "Paratonnerre", Icon = "⚡", Stat = "LightningClicks", Goal = 5, Reward = 30000},
	{ Id = "Notif10", Name = "Toujours connecté", Icon = "🔔", Stat = "NotifsOpened", Goal = 10, Reward = 175000},
	{ Id = "Email10", Name = "Inbox zéro", Icon = "📧", Stat = "EmailsRead", Goal = 10, Reward = 300000},
	{ Id = "Press25", Name = "Écraseur", Icon = "🗜️", Stat = "PressCrushes", Goal = 25, Reward = 300000},
	{ Id = "Slot25", Name = "Joueur du dimanche", Icon = "🎰", Stat = "SlotSpins", Goal = 25, Reward = 600000},
	{ Id = "SlotWin10", Name = "La chance sourit", Icon = "🍀", Stat = "SlotWins", Goal = 10, Reward = 1.5e6},
	{ Id = "Stock10", Name = "Loup de la bourse", Icon = "🐺", Stat = "StockTrades", Goal = 10, Reward = 150000},
	{ Id = "Chest1", Name = "Qu'y a-t-il dedans ?", Icon = "📦", Stat = "ChestsOpened", Goal = 1, Reward = 600000},
	{ Id = "Chest10", Name = "Collectionneur", Icon = "🗝️", Stat = "ChestsOpened", Goal = 10, Reward = 5e6},
	{ Id = "Cosmetic1", Name = "Stylé", Icon = "🧢", Stat = "CosmeticsBought", Goal = 1, Reward = 25000},
	{ Id = "Cosmetic5", Name = "Fashion week", Icon = "👑", Stat = "CosmeticsBought", Goal = 5, Reward = 100000},
	{ Id = "Quests5", Name = "Aventurier", Icon = "📜", Stat = "QuestsCompleted", Goal = 5, Reward = 200000},
	{ Id = "Daily3", Name = "Fidèle", Icon = "📅", Stat = "DailyClaims", Goal = 3, Reward = 50000},
	{ Id = "Play1h", Name = "Juste 5 minutes...", Icon = "⏰", Stat = "PlaySeconds", Goal = 3600, Reward = 2e6},
	{ Id = "Play10h", Name = "Il faut sortir", Icon = "🌳", Stat = "PlaySeconds", Goal = 36000, Reward = 1e8},
	{ Id = "Rebirth1", Name = "Bol d'air", Icon = "🌊", Stat = "Rebirths", Goal = 1, Reward = 25000},
	{ Id = "Rebirth5", Name = "Zen absolu", Icon = "🧘", Stat = "Rebirths", Goal = 5, Reward = 1e9},
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
		{ Type = "Clicks", Text = "Fais %s clics", Goals = { 50, 150, 300, 500 }, RewardSeconds = 15, MinReward = 100 },
		{ Type = "Earn", Text = "Gagne %s Dopamine", GoalSeconds = { 120, 300, 600 }, MinGoal = 500, RewardSeconds = 20, MinReward = 150 },
		{ Type = "Buy", Text = "Achète %s améliorations", Goals = { 2, 3, 5 }, RewardSeconds = 30, MinReward = 100 },
		{ Type = "Bounces", Feature = "DVD", Text = "Fais rebondir le DVD %s fois", Goals = { 10, 25, 50 }, RewardSeconds = 15, MinReward = 100 },
		{ Type = "Bubbles", Feature = "BubbleWrap", Text = "Éclate %s bulles", Goals = { 30, 60, 100 }, RewardSeconds = 20, MinReward = 200 },
		{ Type = "Spawns", Feature = "PhoneNotifs", Text = "Clique %s notifications, mails ou éclairs", Goals = { 3, 5, 8 }, RewardSeconds = 30, MinReward = 300 },
		{ Type = "Combo", Feature = "Combo", Text = "Remplis la jauge de combo %s fois", Goals = { 1, 2, 3 }, RewardSeconds = 30, MinReward = 300 },
		{ Type = "Casino", Feature = "Casino", Text = "Joue %s fois à la machine à sous", Goals = { 3, 5, 10 }, RewardSeconds = 20, MinReward = 300 },
		{ Type = "Chests", Feature = "LootBox", Text = "Ouvre %s coffre(s)", Goals = { 1, 2 }, RewardSeconds = 30, MinReward = 500 },
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
-- Bourse (un cours commun à tout le serveur)
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
-- Machine à sous (UNIQUEMENT avec la Dopamine du jeu, jamais de Robux)
--   Triple : gain si 3 symboles identiques (x mise)
--   Pair   : gain si exactement 2 symboles identiques (x mise)
--   Taux de retour visé : ~90-95 % (le jeu gagne un peu, comme un vrai casino)
----------------------------------------------------------------------
Config.Casino = {
	Enabled = true,
	Feature = "Casino",
	BetFractions = { 0.01, 0.05, 0.1, 0.25 },
	MinBet = 10,
	Cooldown = 1.5,
	Symbols = {
		{ Id = "Cherry", Icon = "🍒", Weight = 30, Pair = 0.5, Triple = 6 },
		{ Id = "Lemon", Icon = "🍋", Weight = 25, Pair = 0.8, Triple = 10 },
		{ Id = "Bell", Icon = "🔔", Weight = 20, Pair = 1, Triple = 12 },
		{ Id = "Diamond", Icon = "💎", Weight = 12, Pair = 1.5, Triple = 25 },
		{ Id = "Seven", Icon = "7️⃣", Weight = 8, Pair = 2, Triple = 60 },
		{ Id = "Brain", Icon = "🧠", Weight = 5, Pair = 3, Triple = 200 },
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
		{ Id = "Common", Name = "Commun", Weight = 60, RewardSeconds = 5, Color = Color3.fromRGB(150, 150, 150) },
		{ Id = "Rare", Name = "Rare", Weight = 25, RewardSeconds = 15, Color = Color3.fromRGB(30, 140, 255) },
		{ Id = "Epic", Name = "Épique", Weight = 12, RewardSeconds = 45, Color = Color3.fromRGB(170, 60, 255) },
		{ Id = "Legendary", Name = "LÉGENDAIRE", Weight = 3, RewardSeconds = 200, Color = Color3.fromRGB(255, 180, 0) },
	},
}

----------------------------------------------------------------------
-- Boutique d'objets (cosmétiques du bouton, conservés pour toujours)
--   Slot "Hat"  : emoji posé au-dessus du bouton
--   Slot "Skin" : couleurs du bouton (dégradé Top -> Bottom)
----------------------------------------------------------------------
Config.Cosmetics = {
	{ Id = "Cap", Name = "Casquette rouge", Icon = "🧢", Slot = "Hat", Cost = 20000},
	{ Id = "PartyHat", Name = "Chapeau de fête", Icon = "🥳", Slot = "Hat", Cost = 80000},
	{ Id = "TopHat", Name = "Haut-de-forme", Icon = "🎩", Slot = "Hat", Cost = 300000},
	{ Id = "Headphones", Name = "Casque audio", Icon = "🎧", Slot = "Hat", Cost = 600000},
	{ Id = "Graduation", Name = "Toque de diplômé", Icon = "🎓", Slot = "Hat", Cost = 2.5e6},
	{ Id = "Crown", Name = "Couronne", Icon = "👑", Slot = "Hat", Cost = 6e6},
	{ Id = "Halo", Name = "Auréole", Icon = "😇", Slot = "Hat", Cost = 3e7},
	{ Id = "Unicorn", Name = "Corne de licorne", Icon = "🦄", Slot = "Hat", Cost = 2e8},
	{ Id = "SkinMint", Name = "Bouton menthe", Icon = "🟩", Slot = "Skin", Cost = 40000,
		Top = Color3.fromRGB(210, 255, 225), Bottom = Color3.fromRGB(120, 220, 160) },
	{ Id = "SkinSky", Name = "Bouton ciel", Icon = "🟦", Slot = "Skin", Cost = 150000,
		Top = Color3.fromRGB(215, 240, 255), Bottom = Color3.fromRGB(110, 180, 255) },
	{ Id = "SkinCandy", Name = "Bouton bonbon", Icon = "🍬", Slot = "Skin", Cost = 1.2e6,
		Top = Color3.fromRGB(255, 220, 240), Bottom = Color3.fromRGB(255, 110, 180) },
	{ Id = "SkinGold", Name = "Bouton en or", Icon = "🟨", Slot = "Skin", Cost = 1.2e7,
		Top = Color3.fromRGB(255, 240, 160), Bottom = Color3.fromRGB(230, 160, 0) },
	{ Id = "SkinVoid", Name = "Bouton du néant", Icon = "⬛", Slot = "Skin", Cost = 8e7,
		Top = Color3.fromRGB(70, 60, 90), Bottom = Color3.fromRGB(5, 5, 10) },
}

----------------------------------------------------------------------
-- Temps d'écran
----------------------------------------------------------------------
Config.ScreenTime = {
	DaysKept = 7,
}

----------------------------------------------------------------------
-- Classement global
----------------------------------------------------------------------
Config.Leaderboard = {
	StoreName = "DopamineLeaderboard_v2",
	UpdateInterval = 60,
	Size = 10,
}

----------------------------------------------------------------------
-- Sauvegarde
----------------------------------------------------------------------
Config.DataStore = {
	Name = "DopamineClickerData_v2", -- change le nom pour repartir de zéro
	AutoSaveInterval = 120,
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
	Pop = { Id = "rbxasset://sounds/clickfast.wav", Volume = 0.5 },
	Crush = { Id = "rbxasset://sounds/swoosh.wav", Volume = 0.5 },
	Thunder = { Id = "rbxasset://sounds/swoosh.wav", Volume = 0.7 },
	Notif = { Id = "rbxasset://sounds/electronicpingshort.wav", Volume = 0.4 },
	Mail = { Id = "rbxasset://sounds/electronicpingshort.wav", Volume = 0.4 },
	SlotSpin = { Id = "rbxasset://sounds/clickfast.wav", Volume = 0.3 },
	SlotWin = { Id = "rbxasset://sounds/electronicpingshort.wav", Volume = 0.9 },
	Chest = { Id = "rbxasset://sounds/swoosh.wav", Volume = 0.7 },
	Cash = { Id = "rbxasset://sounds/electronicpingshort.wav", Volume = 0.5 },
	Megaphone = { Id = "rbxasset://sounds/swoosh.wav", Volume = 0.4 },
	Music = { Id = "", Volume = 0.3 }, -- musique lofi en boucle (mets ton ID)
}

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
	Config.AchievementsById[achievement.Id] = achievement
end

Config.CosmeticsById = {}
for index, cosmetic in ipairs(Config.Cosmetics) do
	cosmetic.Order = index
	Config.CosmeticsById[cosmetic.Id] = cosmetic
end

Config.CasinoSymbolsById = {}
for _, symbol in ipairs(Config.Casino.Symbols) do
	Config.CasinoSymbolsById[symbol.Id] = symbol
end

return Config
