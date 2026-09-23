--[[
	Config (ModuleScript)
	Emplacement : ReplicatedStorage > Shared > Config

	TOUTE la configuration du jeu est ici : améliorations, succès, quêtes,
	événements, sons, rebirth... Modifie les valeurs librement, le reste du
	code s'adapte automatiquement.

	Ce module est lu par le serveur ET par le client. Le serveur reste la seule
	source de vérité : changer ce fichier côté client (triche) ne change rien
	aux gains réels.
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
-- Combo : cliquer vite remplit une jauge (0 à 100) qui multiplie les clics
----------------------------------------------------------------------
Config.Combo = {
	GainPerClick = 5, -- points de jauge gagnés par clic
	DecayPerSecond = 25, -- points perdus par seconde (il faut > 5 clics/s pour monter)
	MaxMultiplier = 3, -- multiplicateur quand la jauge est pleine
}

----------------------------------------------------------------------
-- Améliorations de la boutique
--   Category : "Click" (+X par clic), "Passive" (+X par seconde),
--              "Multiplier" (multiplie TOUS les gains par Value^niveau)
--   Coût du niveau N = BaseCost * CostGrowth^N
--   MaxLevel : optionnel (nil = infini)
----------------------------------------------------------------------
Config.Upgrades = {
	-- Améliorations de clic
	{ Id = "Finger", Category = "Click", Name = "Doigt agile", Icon = "👆", Value = 1, BaseCost = 15, CostGrowth = 1.15 },
	{ Id = "Mouse", Category = "Click", Name = "Souris gaming", Icon = "🖱️", Value = 5, BaseCost = 250, CostGrowth = 1.15 },
	{ Id = "Keyboard", Category = "Click", Name = "Clavier RGB", Icon = "⌨️", Value = 25, BaseCost = 3500, CostGrowth = 1.15 },
	{ Id = "BionicHand", Category = "Click", Name = "Main bionique", Icon = "🦾", Value = 100, BaseCost = 45000, CostGrowth = 1.16 },
	{ Id = "QuantumClick", Category = "Click", Name = "Clic quantique", Icon = "⚛️", Value = 500, BaseCost = 700000, CostGrowth = 1.17 },
	{ Id = "GodFinger", Category = "Click", Name = "Doigt divin", Icon = "✨", Value = 2500, BaseCost = 1.2e7, CostGrowth = 1.18 },

	-- Générateurs passifs
	{ Id = "AutoClicker", Category = "Passive", Name = "Auto-clicker", Icon = "🤖", Value = 1, BaseCost = 50, CostGrowth = 1.15 },
	{ Id = "Brain", Category = "Passive", Name = "Cerveau", Icon = "🧠", Value = 8, BaseCost = 600, CostGrowth = 1.15 },
	{ Id = "NeuronLab", Category = "Passive", Name = "Labo de neurones", Icon = "🔬", Value = 47, BaseCost = 7000, CostGrowth = 1.15 },
	{ Id = "Factory", Category = "Passive", Name = "Usine à dopamine", Icon = "🏭", Value = 260, BaseCost = 80000, CostGrowth = 1.15 },
	{ Id = "SocialNetwork", Category = "Passive", Name = "Réseau social", Icon = "📱", Value = 1400, BaseCost = 1e6, CostGrowth = 1.15 },
	{ Id = "LikeSatellite", Category = "Passive", Name = "Satellite à likes", Icon = "🛰️", Value = 7800, BaseCost = 1.4e7, CostGrowth = 1.15 },
	{ Id = "GalacticDopamine", Category = "Passive", Name = "Dopamine galactique", Icon = "🌌", Value = 44000, BaseCost = 2e8, CostGrowth = 1.15 },

	-- Multiplicateurs globaux (achat unique)
	{ Id = "Coffee", Category = "Multiplier", Name = "Café serré", Icon = "☕", Value = 2, BaseCost = 25000, CostGrowth = 1, MaxLevel = 1 },
	{ Id = "Endorphins", Category = "Multiplier", Name = "Endorphines", Icon = "💊", Value = 5, BaseCost = 5e6, CostGrowth = 1, MaxLevel = 1 },
	{ Id = "MegaDose", Category = "Multiplier", Name = "Méga-dose", Icon = "💉", Value = 10, BaseCost = 1e9, CostGrowth = 1, MaxLevel = 1 },
	{ Id = "Singularity", Category = "Multiplier", Name = "Singularité", Icon = "🌀", Value = 25, BaseCost = 1e12, CostGrowth = 1, MaxLevel = 1 },
}

-- Onglets de la boutique (ordre d'affichage)
Config.ShopCategories = {
	{ Id = "Click", Name = "CLIC" },
	{ Id = "Passive", Name = "PASSIF" },
	{ Id = "Multiplier", Name = "MULTI" },
}

-- Nombre maximum de niveaux achetés en une fois avec le mode "MAX"
Config.MaxBulkBuy = 1000

----------------------------------------------------------------------
-- Rebirth (prestige)
----------------------------------------------------------------------
Config.Rebirth = {
	BaseCost = 1e6, -- Dopamine nécessaire pour le 1er rebirth
	CostGrowth = 8, -- chaque rebirth coûte x8 de plus
	MultiplierPerRebirth = 0.5, -- +50 % de gains permanents par rebirth
}

----------------------------------------------------------------------
-- Récompenses "à l'échelle" : beaucoup de récompenses valent
-- "X secondes de production" pour rester intéressantes à tous les stades.
-- Production estimée = Dopamine/s + (Dopamine/clic * EstimatedClicksPerSecond)
----------------------------------------------------------------------
Config.Rewards = {
	EstimatedClicksPerSecond = 3,
}

-- Chaque succès débloqué donne +X % de gains permanents
Config.AchievementBonus = 0.02

----------------------------------------------------------------------
-- Succès
--   Stat : nom de la statistique suivie (voir Data.Stats côté serveur)
--   Reward : Dopamine offerte au déblocage
----------------------------------------------------------------------
Config.Achievements = {
	{ Id = "Clicks100", Name = "Doigt chaud", Icon = "👆", Stat = "TotalClicks", Goal = 100, Reward = 200 },
	{ Id = "Clicks1K", Name = "Clic addict", Icon = "🔥", Stat = "TotalClicks", Goal = 1000, Reward = 5000 },
	{ Id = "Clicks10K", Name = "Tendinite", Icon = "🩹", Stat = "TotalClicks", Goal = 10000, Reward = 250000 },
	{ Id = "Clicks100K", Name = "Machine humaine", Icon = "🦿", Stat = "TotalClicks", Goal = 100000, Reward = 5e7 },
	{ Id = "Earn1K", Name = "Premier shoot", Icon = "💧", Stat = "LifetimeDopamine", Goal = 1000, Reward = 100 },
	{ Id = "Earn1M", Name = "Millionnaire du bonheur", Icon = "💰", Stat = "LifetimeDopamine", Goal = 1e6, Reward = 50000 },
	{ Id = "Earn1B", Name = "Milliardaire neuronal", Icon = "💎", Stat = "LifetimeDopamine", Goal = 1e9, Reward = 5e7 },
	{ Id = "Earn1T", Name = "Cerveau cosmique", Icon = "🪐", Stat = "LifetimeDopamine", Goal = 1e12, Reward = 5e10 },
	{ Id = "Buy10", Name = "Shopping", Icon = "🛒", Stat = "UpgradesBought", Goal = 10, Reward = 500 },
	{ Id = "Buy100", Name = "Accro aux achats", Icon = "🛍️", Stat = "UpgradesBought", Goal = 100, Reward = 100000 },
	{ Id = "Combo1", Name = "Combo max !", Icon = "⚡", Stat = "CombosMaxed", Goal = 1, Reward = 1000 },
	{ Id = "DVD1", Name = "Chasseur de logo", Icon = "📀", Stat = "DVDClicks", Goal = 1, Reward = 250 },
	{ Id = "Corner1", Name = "LE COIN !!!", Icon = "📐", Stat = "DVDCorners", Goal = 1, Reward = 100000 },
	{ Id = "Golden1", Name = "Main en or", Icon = "🌟", Stat = "GoldenClicks", Goal = 1, Reward = 1000 },
	{ Id = "Golden10", Name = "Chercheur d'or", Icon = "🏆", Stat = "GoldenClicks", Goal = 10, Reward = 500000 },
	{ Id = "Quests5", Name = "Aventurier", Icon = "📜", Stat = "QuestsCompleted", Goal = 5, Reward = 5000 },
	{ Id = "Daily3", Name = "Fidèle", Icon = "📅", Stat = "DailyClaims", Goal = 3, Reward = 10000 },
	{ Id = "Rebirth1", Name = "Renaissance", Icon = "♻️", Stat = "Rebirths", Goal = 1, Reward = 1000 },
	{ Id = "Rebirth5", Name = "Phénix", Icon = "🦅", Stat = "Rebirths", Goal = 5, Reward = 1e8 },
}

----------------------------------------------------------------------
-- Quêtes (3 actives en même temps, remplacées dès qu'elles sont finies)
--   Goals : objectifs possibles (tirés au hasard)
--   GoalSeconds : pour "Earn", l'objectif vaut X secondes de production
--   RewardSeconds : récompense en secondes de production (minimum MinReward)
--   Le "%s" de Text est remplacé par l'objectif.
----------------------------------------------------------------------
Config.Quests = {
	ActiveCount = 3,
	Pool = {
		{ Type = "Clicks", Text = "Fais %s clics", Goals = { 50, 150, 300, 500 }, RewardSeconds = 60, MinReward = 100 },
		{ Type = "Earn", Text = "Gagne %s Dopamine", GoalSeconds = { 60, 120, 300 }, MinGoal = 500, RewardSeconds = 90, MinReward = 150 },
		{ Type = "Buy", Text = "Achète %s améliorations", Goals = { 3, 5, 10 }, RewardSeconds = 60, MinReward = 100 },
		{ Type = "DVDClicks", Text = "Clique %s fois sur le logo DVD", Goals = { 1, 2, 3 }, RewardSeconds = 120, MinReward = 200 },
		{ Type = "Golden", Text = "Attrape %s objet(s) doré(s)", Goals = { 1, 2 }, RewardSeconds = 180, MinReward = 300 },
		{ Type = "Combo", Text = "Remplis la jauge de combo %s fois", Goals = { 1, 2, 3 }, RewardSeconds = 120, MinReward = 200 },
	},
}

----------------------------------------------------------------------
-- Récompense quotidienne (jour = jour UTC)
----------------------------------------------------------------------
Config.Daily = {
	BaseRewardSeconds = 120, -- récompense du jour 1 (en secondes de production)
	StreakBonusSeconds = 60, -- + X secondes par jour de série
	MaxStreakBonus = 7, -- la série plafonne au jour 7
	MinReward = 250, -- minimum (multiplié par le jour de série)
}

----------------------------------------------------------------------
-- Événements aléatoires
----------------------------------------------------------------------
Config.Events = {
	Rush = {
		Name = "DOPAMINE RUSH",
		Multiplier = 2,
		Duration = 30,
		MinInterval = 150, -- temps (s) minimum entre deux Rush
		MaxInterval = 300,
	},
	Golden = {
		MinInterval = 40, -- temps (s) entre deux objets dorés pour un joueur
		MaxInterval = 100,
		Lifetime = 6, -- durée d'affichage avant disparition
		RewardSeconds = 90,
		MinReward = 300,
		Image = "", -- mets un "rbxassetid://..." ou laisse vide (emoji 🌟)
	},
	-- En test dans Studio, les événements arrivent X fois plus vite
	StudioSpeedup = 5,
}

----------------------------------------------------------------------
-- Logo DVD rebondissant
--   Les positions sont "normalisées" (0 à 1 = largeur/hauteur de l'écran)
--   pour fonctionner à l'identique sur PC, mobile et tablette.
----------------------------------------------------------------------
Config.DVD = {
	Speed = 0.16, -- fraction de l'écran parcourue par seconde
	LogoSize = Vector2.new(170, 90), -- taille en pixels "design" (1280x720)
	LogoImage = "", -- "rbxassetid://..." (image BLANCHE, recolorée à chaque rebond) ou vide
	CornerTolerance = 0.006, -- marge pour considérer qu'un coin est touché (0.6 % de l'écran)
	ClickCooldown = 6, -- secondes entre deux clics récompensés sur le logo
	ClickRewardSeconds = 15,
	ClickMinReward = 25,
	JackpotRewardSeconds = 600,
	JackpotMinReward = 10000,
	Colors = {
		Color3.fromRGB(255, 46, 136),
		Color3.fromRGB(0, 240, 255),
		Color3.fromRGB(157, 78, 221),
		Color3.fromRGB(57, 255, 20),
		Color3.fromRGB(255, 229, 59),
		Color3.fromRGB(255, 120, 30),
	},
}

----------------------------------------------------------------------
-- Classement global
----------------------------------------------------------------------
Config.Leaderboard = {
	StoreName = "DopamineLeaderboard_v1",
	UpdateInterval = 60, -- secondes
	Size = 10,
}

----------------------------------------------------------------------
-- Sauvegarde
----------------------------------------------------------------------
Config.DataStore = {
	Name = "DopamineClickerData_v1", -- change le nom pour repartir de zéro
	AutoSaveInterval = 120, -- sauvegarde périodique (s)
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
	Bounce = { Id = "rbxasset://sounds/clickfast.wav", Volume = 0.15 },
	Bonus = { Id = "rbxasset://sounds/electronicpingshort.wav", Volume = 0.6 },
	Achievement = { Id = "rbxasset://sounds/electronicpingshort.wav", Volume = 0.8 },
	Jackpot = { Id = "rbxasset://sounds/electronicpingshort.wav", Volume = 1 },
	Golden = { Id = "rbxasset://sounds/swoosh.wav", Volume = 0.6 },
	Rush = { Id = "rbxasset://sounds/swoosh.wav", Volume = 0.8 },
	Rebirth = { Id = "rbxasset://sounds/swoosh.wav", Volume = 1 },
	Open = { Id = "rbxasset://sounds/swoosh.wav", Volume = 0.3 },
	Music = { Id = "", Volume = 0.3 }, -- musique de fond en boucle (mets ton ID)
}

----------------------------------------------------------------------
-- Index calculés automatiquement (ne pas modifier)
----------------------------------------------------------------------
Config.UpgradesById = {}
for index, upgrade in ipairs(Config.Upgrades) do
	upgrade.Order = index
	Config.UpgradesById[upgrade.Id] = upgrade
end

Config.AchievementsById = {}
for _, achievement in ipairs(Config.Achievements) do
	Config.AchievementsById[achievement.Id] = achievement
end

return Config
