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
--   Color       : couleur de la carte en mode "Icônes HD"
--
-- Équilibrage (simulé : 5 clics/s, ~50 % des bonus attrapés, on achète
-- toujours l'amélioration abordable la moins chère) : une nouveauté à
-- l'écran toutes les 1 à 3 min, jamais plus de ~3 min sans achat, 1re
-- visite à l'océan après ~70 min ; la 2e partie est ~2x plus rapide.
----------------------------------------------------------------------
Config.Upgrades = {
	{ Id = "Finger", Name = "Buff Finger", Icon = "👆", Description = "+%s Dopamine per click",
		Cost = 10, CostGrowth = 2.2, MaxLevel = 15, Effect = "Click", Value = 1,
		Color = Color3.fromRGB(255, 196, 0) },
	{ Id = "DVD", Name = "DVD Logo", Icon = "📀", Description = "A bouncing logo. +%s Dopamine per bounce",
		Cost = 110, CostGrowth = 2.2, MaxLevel = 10, Effect = "DVD", Value = 1, Feature = "DVD",
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
	{ Id = "Lofi", Name = "Lofi Beats", Icon = "🎧", Description = "Beats to relax/study to. +%s Dopamine/s",
		Cost = 12000, MaxLevel = 1, Effect = "PerSecond", Value = 40, Feature = "Lofi",
		Color = Color3.fromRGB(120, 90, 200) },
	{ Id = "Press", Name = "Hydraulic Press", Icon = "🗜️", Description = "Crushes stuff. Every level upgrades the press (wood, steel, gold, diamond...). +%s Dopamine/s",
		Cost = 18000, CostGrowth = 1.75, MaxLevel = 10, Effect = "PerSecond", Value = 20, Feature = "Press",
		Color = Color3.fromRGB(255, 200, 0) },
	{ Id = "Achievements", Name = "Achievements", Icon = "🏆", Description = "Unlocks the achievements menu (kept forever)",
		Cost = 25000, MaxLevel = 1, Effect = "Feature", Feature = "Achievements", Permanent = true,
		Color = Color3.fromRGB(150, 60, 220) },
	{ Id = "Pinwheel", Name = "Pinwheel", Icon = "🌀", Description = "It spins. Blow on it! +%s Dopamine/s",
		Cost = 28000, MaxLevel = 1, Effect = "PerSecond", Value = 75, Feature = "Pinwheel",
		Color = Color3.fromRGB(80, 200, 255) },
	{ Id = "SleepMode", Name = "Sleep Mode", Icon = "😴", Description = "Earn more Dopamine while you're away (kept forever)",
		Cost = 20000, CostGrowth = 3, MaxLevel = 5, Effect = "Offline", Value = 1, Permanent = true,
		Color = Color3.fromRGB(90, 110, 200) },
	{ Id = "BubbleWrap", Name = "Bubble Wrap", Icon = "🔘", Description = "Pop the bubbles to earn Dopamine",
		Cost = 30000, MaxLevel = 1, Effect = "Feature", Feature = "BubbleWrap",
		Color = Color3.fromRGB(160, 220, 255) },
	{ Id = "Weather", Name = "Thunderstorm", Icon = "⛈️", Description = "Catch the lightning! +%s Dopamine/s",
		Cost = 33000, MaxLevel = 1, Effect = "PerSecond", Value = 100, Feature = "Weather",
		Color = Color3.fromRGB(30, 110, 200) },
	{ Id = "ItemShop", Name = "Item Shop", Icon = "🧢", Description = "Hats for your button (kept forever)",
		Cost = 55000, MaxLevel = 1, Effect = "Feature", Feature = "ItemShop", Permanent = true,
		Color = Color3.fromRGB(60, 200, 60) },
	{ Id = "Stocks", Name = "Stock Market", Icon = "📈", Description = "Invest your Dopamine. Stonks go up... or not.",
		Cost = 60000, MaxLevel = 1, Effect = "Feature", Feature = "Stocks",
		Color = Color3.fromRGB(20, 160, 90) },
	{ Id = "Boost", Name = "Green Arrow", Icon = "⬆️", Description = "Everything goes up. EVERYTHING. Earnings x%s",
		Cost = 68000, MaxLevel = 1, Effect = "Multiplier", Value = 2, Feature = "Boost",
		Color = Color3.fromRGB(40, 220, 60) },
	{ Id = "LiveStream", Name = "ASMR Stream", Icon = "🥪", Description = "Someone is eating live. +%s Dopamine/s",
		Cost = 100000, MaxLevel = 1, Effect = "PerSecond", Value = 120, Feature = "LiveStream",
		Color = Color3.fromRGB(240, 170, 90) },
	{ Id = "Butter", Name = "Crunchy Butter", Icon = "🧈", Description = "A stick of butter to bite into on stream. *CRUNCH*",
		Cost = 140000, MaxLevel = 1, Effect = "Feature", Feature = "Butter",
		Color = Color3.fromRGB(255, 215, 90) },
	{ Id = "Followers", Name = "Followers", Icon = "👥", Description = "More viewers on the stream. +%s Dopamine/s",
		Cost = 150000, CostGrowth = 1.6, MaxLevel = 15, Effect = "PerSecond", Value = 50, Feature = "Followers",
		Color = Color3.fromRGB(255, 60, 100) },
	{ Id = "PhoneNotifs", Name = "Notifications", Icon = "🔔", Description = "Ding! Ding! Ding! +%s Dopamine/s",
		Cost = 200000, MaxLevel = 1, Effect = "PerSecond", Value = 150, Feature = "PhoneNotifs",
		Color = Color3.fromRGB(255, 70, 70) },
	{ Id = "Combo", Name = "Combo", Icon = "⚡", Description = "Click fast to multiply your clicks (up to x3)",
		Cost = 260000, MaxLevel = 1, Effect = "Feature", Feature = "Combo",
		Color = Color3.fromRGB(255, 220, 0) },
	{ Id = "Email", Name = "Inbox", Icon = "📧", Description = "You have (a lot of) new messages",
		Cost = 320000, MaxLevel = 1, Effect = "Feature", Feature = "Email",
		Color = Color3.fromRGB(0, 120, 255) },
	{ Id = "Quests", Name = "Quests", Icon = "📜", Description = "Unlocks quests (kept forever)",
		Cost = 520000, MaxLevel = 1, Effect = "Feature", Feature = "Quests", Permanent = true,
		Color = Color3.fromRGB(255, 140, 30) },
	{ Id = "Casino", Name = "Slot Machine", Icon = "🎰", Description = "Try your luck (with Dopamine only)",
		Cost = 600000, MaxLevel = 1, Effect = "Feature", Feature = "Casino",
		Color = Color3.fromRGB(200, 0, 60) },
	{ Id = "PressStart", Name = "Turbo Press", Icon = "⚙️", Description = "A START button to crush things yourself",
		Cost = 650000, MaxLevel = 1, Effect = "Feature", Feature = "PressStart",
		Color = Color3.fromRGB(130, 130, 140) },
	{ Id = "LiveChat", Name = "Live Chat", Icon = "💬", Description = "The stream chat goes wild. Clicks x%s",
		Cost = 800000, MaxLevel = 1, Effect = "ClickMultiplier", Value = 3, Feature = "LiveChat",
		Color = Color3.fromRGB(145, 70, 255) },
	{ Id = "ScreenTime", Name = "Screen Time", Icon = "📱", Description = "Find out how much time you've wasted here",
		Cost = 1e6, MaxLevel = 1, Effect = "Feature", Feature = "ScreenTime", Permanent = true,
		Color = Color3.fromRGB(45, 45, 50) },
	{ Id = "LootBox", Name = "Mystery Chest", Icon = "📦", Description = "A chest fills up over time. Open it!",
		Cost = 1.2e6, MaxLevel = 1, Effect = "Feature", Feature = "LootBox",
		Color = Color3.fromRGB(170, 110, 50) },
	{ Id = "EmojiRain", Name = "Emoji Rain", Icon = "😂", Description = "It's raining emojis. +%s Dopamine/s",
		Cost = 1.5e6, MaxLevel = 1, Effect = "PerSecond", Value = 1000, Feature = "EmojiRain",
		Color = Color3.fromRGB(255, 210, 60) },
	{ Id = "HDIcons", Name = "HD Icons", Icon = "✨", Description = "Super shiny icons. Earnings x%s",
		Cost = 1.9e6, MaxLevel = 1, Effect = "Multiplier", Value = 1.5, Feature = "HDIcons",
		Color = Color3.fromRGB(255, 120, 220) },
	{ Id = "GoldenStar", Name = "Golden Star", Icon = "🌟", Description = "Golden stars show up. Catch them!",
		Cost = 2.8e6, MaxLevel = 1, Effect = "Feature", Feature = "GoldenStar",
		Color = Color3.fromRGB(255, 190, 0) },
	{ Id = "NeonMode", Name = "Neon Mode", Icon = "🌈", Description = "The screen goes full neon. Earnings x%s",
		Cost = 4.5e6, MaxLevel = 1, Effect = "Multiplier", Value = 2, Feature = "NeonMode",
		Color = Color3.fromRGB(157, 78, 221) },
	{ Id = "CursorTrail", Name = "Magic Trail", Icon = "💫", Description = "Your mouse leaves sparkles behind. Clicks x%s",
		Cost = 7.5e6, MaxLevel = 1, Effect = "ClickMultiplier", Value = 2, Feature = "CursorTrail",
		Color = Color3.fromRGB(255, 80, 200) },
	{ Id = "Disco", Name = "Disco Ball", Icon = "💃", Description = "It's party time! Earnings x%s",
		Cost = 1.2e7, MaxLevel = 1, Effect = "Multiplier", Value = 2, Feature = "Disco",
		Color = Color3.fromRGB(200, 60, 255) },
	{ Id = "Ocean", Name = "Go to the Ocean", Icon = "🌊", Description = "Let it all go and breathe. Start over with x%s earnings forever",
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
	{ Id = "Clicks100", Name = "Hot Finger", Icon = "👆", Stat = "TotalClicks", Goal = 100, Reward = 50},
	{ Id = "Clicks1K", Name = "Click Addict", Icon = "🔥", Stat = "TotalClicks", Goal = 1000, Reward = 2500},
	{ Id = "Clicks10K", Name = "Tendinitis", Icon = "🩹", Stat = "TotalClicks", Goal = 10000, Reward = 200000},
	{ Id = "Clicks100K", Name = "Human Machine", Icon = "🦿", Stat = "TotalClicks", Goal = 100000, Reward = 1e8},
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
	{ Id = "Stock10", Name = "Wolf of Wall Street", Icon = "🐺", Stat = "StockTrades", Goal = 10, Reward = 150000},
	{ Id = "Chest1", Name = "What's Inside?", Icon = "📦", Stat = "ChestsOpened", Goal = 1, Reward = 600000},
	{ Id = "Chest10", Name = "Collector", Icon = "🗝️", Stat = "ChestsOpened", Goal = 10, Reward = 5e6},
	{ Id = "Cosmetic1", Name = "Stylish", Icon = "🧢", Stat = "CosmeticsBought", Goal = 1, Reward = 25000},
	{ Id = "Cosmetic5", Name = "Fashion Week", Icon = "👑", Stat = "CosmeticsBought", Goal = 5, Reward = 100000},
	{ Id = "Quests5", Name = "Adventurer", Icon = "📜", Stat = "QuestsCompleted", Goal = 5, Reward = 200000},
	{ Id = "Daily3", Name = "Loyal", Icon = "📅", Stat = "DailyClaims", Goal = 3, Reward = 50000},
	{ Id = "Play1h", Name = "Just 5 More Minutes...", Icon = "⏰", Stat = "PlaySeconds", Goal = 3600, Reward = 2e6},
	{ Id = "Play10h", Name = "Go Touch Grass", Icon = "🌳", Stat = "PlaySeconds", Goal = 36000, Reward = 1e8},
	{ Id = "Rebirth1", Name = "Breath of Fresh Air", Icon = "🌊", Stat = "Rebirths", Goal = 1, Reward = 25000},
	{ Id = "Rebirth5", Name = "Total Zen", Icon = "🧘", Stat = "Rebirths", Goal = 5, Reward = 1e9},
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
	-- À venir (mets l'ID quand le badge est créé ; 0 = pas de badge Roblox)
	Earn1M = 0, Earn1B = 0, Earn1T = 0, Buy10 = 0, Buy50 = 0, Bounce100 = 0, Bounce5K = 0,
	Corner1 = 0, Combo1 = 0, Bubble100 = 0, Bubble1K = 0, Golden1 = 0, Golden10 = 0,
	Lightning5 = 0, Notif10 = 0, Email10 = 0, Press25 = 0, Slot25 = 0, SlotWin10 = 0,
	Stock10 = 0, Chest1 = 0, Chest10 = 0, Cosmetic1 = 0, Cosmetic5 = 0, Quests5 = 0,
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
		{ Type = "Casino", Feature = "Casino", Text = "Play the slot machine %s times", Goals = { 3, 5, 10 }, RewardSeconds = 20, MinReward = 300 },
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
	Butter = { Feature = "Butter", MaxPerSecond = 8, ClickFraction = 0.75, Stat = "ButterCrunches" },
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
	{ Id = "Cap", Name = "Red Cap", Icon = "🧢", Slot = "Hat", Cost = 20000},
	{ Id = "PartyHat", Name = "Party Hat", Icon = "🥳", Slot = "Hat", Cost = 80000},
	{ Id = "TopHat", Name = "Top Hat", Icon = "🎩", Slot = "Hat", Cost = 300000},
	{ Id = "Headphones", Name = "Headphones", Icon = "🎧", Slot = "Hat", Cost = 600000},
	{ Id = "Graduation", Name = "Graduation Cap", Icon = "🎓", Slot = "Hat", Cost = 2.5e6},
	{ Id = "Crown", Name = "Crown", Icon = "👑", Slot = "Hat", Cost = 6e6},
	{ Id = "Halo", Name = "Halo", Icon = "😇", Slot = "Hat", Cost = 3e7},
	{ Id = "Unicorn", Name = "Unicorn Horn", Icon = "🦄", Slot = "Hat", Cost = 2e8},
	{ Id = "SkinMint", Name = "Mint Button", Icon = "🟩", Slot = "Skin", Cost = 40000,
		Top = Color3.fromRGB(210, 255, 225), Bottom = Color3.fromRGB(120, 220, 160) },
	{ Id = "SkinSky", Name = "Sky Button", Icon = "🟦", Slot = "Skin", Cost = 150000,
		Top = Color3.fromRGB(215, 240, 255), Bottom = Color3.fromRGB(110, 180, 255) },
	{ Id = "SkinCandy", Name = "Candy Button", Icon = "🍬", Slot = "Skin", Cost = 1.2e6,
		Top = Color3.fromRGB(255, 220, 240), Bottom = Color3.fromRGB(255, 110, 180) },
	{ Id = "SkinGold", Name = "Golden Button", Icon = "🟨", Slot = "Skin", Cost = 1.2e7,
		Top = Color3.fromRGB(255, 240, 160), Bottom = Color3.fromRGB(230, 160, 0) },
	{ Id = "SkinVoid", Name = "Void Button", Icon = "⬛", Slot = "Skin", Cost = 8e7,
		Top = Color3.fromRGB(70, 60, 90), Bottom = Color3.fromRGB(5, 5, 10) },
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
	Playlist = {
		{ Name = "Lofi chill #1", Id = "rbxassetid://105526677737534" },
		{ Name = "Lofi chill #2", Id = "rbxassetid://84166235077508" },
		{ Name = "Lofi chill #3", Id = "rbxassetid://78354523278392" },
		{ Name = "Lofi chill #4", Id = "rbxassetid://73874153787004" },
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
	BaseRate = 0.1, -- 10 % de la production par seconde
	RatePerLevel = 0.1, -- +10 % par niveau de "Mode veille"
	BaseMaxHours = 2,
	HoursPerLevel = 2,
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
-- Les thèmes sont conservés pour toujours (même après l'océan).
----------------------------------------------------------------------
Config.Themes = {
	{ Id = "Classic", Name = "Classic", Icon = "⬜", Cost = 0, GamePassId = 0, Decor = "None", Dark = false,
		Top = Color3.fromRGB(255, 255, 255), Bottom = Color3.fromRGB(226, 226, 226), Accent = Color3.fromRGB(30, 30, 30) },
	{ Id = "Kawaii", Name = "Kawaii", Icon = "🌸", Cost = 50000, GamePassId = 0, Decor = "Kawaii", Dark = false,
		Top = Color3.fromRGB(255, 228, 240), Bottom = Color3.fromRGB(225, 210, 255), Accent = Color3.fromRGB(255, 120, 180) },
	{ Id = "Matcha", Name = "Matcha", Icon = "🍵", Cost = 250000, GamePassId = 0, Decor = "Leaves", Dark = false,
		Top = Color3.fromRGB(236, 248, 228), Bottom = Color3.fromRGB(190, 222, 180), Accent = Color3.fromRGB(90, 150, 80) },
	{ Id = "Sunset", Name = "Sunset", Icon = "🌅", Cost = 1e6, GamePassId = 0, Decor = "Sunset", Dark = false,
		Top = Color3.fromRGB(255, 200, 140), Bottom = Color3.fromRGB(255, 120, 150), Accent = Color3.fromRGB(255, 240, 180) },
	{ Id = "Ocean", Name = "Ocean", Icon = "🐠", Cost = 5e6, GamePassId = 0, Decor = "Bubbles", Dark = false,
		Top = Color3.fromRGB(200, 240, 255), Bottom = Color3.fromRGB(90, 170, 230), Accent = Color3.fromRGB(255, 255, 255) },
	{ Id = "LofiNight", Name = "Lofi Night", Icon = "🌙", Cost = 2.5e7, GamePassId = 0, Decor = "Stars", Dark = true,
		Top = Color3.fromRGB(30, 28, 60), Bottom = Color3.fromRGB(70, 50, 100), Accent = Color3.fromRGB(255, 220, 150) },
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
	},
	-- Règles Roblox : dès que de la Dopamine s'achète avec des Robux, la
	-- machine à sous (jeu de hasard) est désactivée automatiquement.
	DisableCasinoWhenSelling = true,
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

return Config
