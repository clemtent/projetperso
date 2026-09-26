--[[
	ArcadeConfig (ModuleScript)
	Emplacement : ReplicatedStorage > Shared > ArcadeConfig

	🕹️ Réglages de l'Arcade (amélioration "Arcade", Feature "Minigames") :
	  - Games      : liste des mini-jeux (Kind = "Solo" | "Duel"). Le client
	                 charge le module Client > Minigames > "<Kind>_<Id>"
	                 (ex. Solo_Minesweeper, Duel_TicTacToe) ;
	  - Tickets    : 🎟️ tickets d'arcade. Gagnés UNIQUEMENT en jouant,
	                 JAMAIS achetables avec des Robux, sans valeur Robux
	                 (règles Roblox : pas de mise de Dopamine, achetable) ;
	  - Duels      : mises en tickets, délais, limites anti-abus ;
	  - Shop       : boutique à tickets (petits boosts, Dopamine, badges).
	  - Logic      : règles PURES des duels (victoire au morpion, puissance 4,
	                 grilles de "Trouve l'intrus"), partagées par le serveur
	                 (qui décide) et le client (qui affiche la ligne gagnante).

	Tous les textes (Name, Description...) sont en ANGLAIS : traduits avec
	Locale (dictionnaire Shared > Lang > FR_V8_Arcade).
]]

local ArcadeConfig = {}

ArcadeConfig.Feature = "Minigames" -- Feature débloquée par l'amélioration "Arcade"

----------------------------------------------------------------------
-- 🎮 Jeux
----------------------------------------------------------------------
-- Champs communs : Id, Kind ("Solo" | "Duel"), Name, Icon, Description,
--   Color (couleur de la carte), Accent (2e couleur du dégradé), Tagline.
-- Solo (utilisés par Services > Arcade > SoloGames) :
--   Tickets         : 🎟️ gagnés par partie gagnée (plafonnés par Tickets.DailyCap)
--   RewardSeconds   : Dopamine gagnée (secondes de production) par victoire
--   DailyRewarded   : nombre de parties RÉCOMPENSÉES par jour pour ce jeu
--   Record          : "High" (plus grand = mieux) | "Low" (plus petit = mieux, ex. un temps)
--   RecordFormat    : "Score" | "Time" (affichage du record dans l'onglet Records)
-- Duel :
--   RewardSeconds   : Dopamine du gagnant (secondes de production), en plus du pot
--   TurnSeconds     : temps pour jouer un coup (jeux au tour par tour)
--   WinScore        : points pour gagner (jeux en manches)
ArcadeConfig.Games = {
	-- Jeux solo (modules écrits par ARCADESOLO : Client > Minigames > Solo_<Id>)
	{ Id = "Minesweeper", Kind = "Solo", Name = "Minesweeper", Icon = "💣", Tagline = "Classic",
		Description = "Clear the board without waking a single mine",
		Color = Color3.fromRGB(255, 92, 170), Accent = Color3.fromRGB(140, 70, 255),
		Tickets = 4, RewardSeconds = 45, DailyRewarded = 12, Record = "Low", RecordFormat = "Time" },
	{ Id = "Memory", Kind = "Solo", Name = "Memory", Icon = "🃏", Tagline = "Brain",
		Description = "Flip the cards and find every pair",
		Color = Color3.fromRGB(120, 110, 255), Accent = Color3.fromRGB(60, 200, 255),
		Tickets = 3, RewardSeconds = 30, DailyRewarded = 15, Record = "Low", RecordFormat = "Time" },
	{ Id = "Simon", Kind = "Solo", Name = "Simon Says", Icon = "🎵", Tagline = "Rhythm",
		Description = "Repeat the glowing sequence, longer every round",
		Color = Color3.fromRGB(255, 190, 40), Accent = Color3.fromRGB(255, 90, 120),
		Tickets = 3, RewardSeconds = 30, DailyRewarded = 15, Record = "High", RecordFormat = "Score" },
	{ Id = "WhackAMole", Kind = "Solo", Name = "Whack-a-Mole", Icon = "🔨", Tagline = "Reflex",
		Description = "Bonk the moles before they hide again",
		Color = Color3.fromRGB(90, 210, 120), Accent = Color3.fromRGB(20, 170, 190),
		Tickets = 3, RewardSeconds = 30, DailyRewarded = 15, Record = "High", RecordFormat = "Score" },
	{ Id = "Snake", Kind = "Solo", Name = "Snake", Icon = "🐍", Tagline = "Retro",
		Description = "Eat the snacks, grow longer, don't bite your tail",
		Color = Color3.fromRGB(60, 220, 170), Accent = Color3.fromRGB(40, 120, 255),
		Tickets = 3, RewardSeconds = 30, DailyRewarded = 15, Record = "High", RecordFormat = "Score" },
	{ Id = "Game2048", Kind = "Solo", Name = "2048", Icon = "🔢", Tagline = "Puzzle",
		Description = "Slide and merge the tiles up to 2048",
		Color = Color3.fromRGB(255, 140, 60), Accent = Color3.fromRGB(255, 70, 140),
		Tickets = 4, RewardSeconds = 45, DailyRewarded = 10, Record = "High", RecordFormat = "Score" },

	-- Duels contre un joueur du serveur (Client > Minigames > Duel_<Id>)
	{ Id = "TicTacToe", Kind = "Duel", Name = "Tic-Tac-Toe", Icon = "⭕", Tagline = "Strategy",
		Description = "Three in a row wins. Quick and sneaky!",
		Color = Color3.fromRGB(255, 70, 160), Accent = Color3.fromRGB(0, 210, 255),
		RewardSeconds = 45, TurnSeconds = 15 },
	{ Id = "Connect4", Kind = "Duel", Name = "Connect 4", Icon = "🔴", Tagline = "Strategy",
		Description = "Drop your discs and line up four",
		Color = Color3.fromRGB(80, 100, 255), Accent = Color3.fromRGB(255, 200, 40),
		RewardSeconds = 75, TurnSeconds = 20 },
	{ Id = "ReactionDuel", Kind = "Duel", Name = "Reaction Duel", Icon = "⚡", Tagline = "Reflex",
		Description = "Wait for GO... then tap faster than your rival",
		Color = Color3.fromRGB(255, 200, 30), Accent = Color3.fromRGB(255, 80, 60),
		RewardSeconds = 45, WinScore = 3 },
	{ Id = "SpotRace", Kind = "Duel", Name = "Spot Race", Icon = "🔎", Tagline = "Race",
		Description = "Race to find the odd emoji out, grid after grid",
		Color = Color3.fromRGB(40, 210, 160), Accent = Color3.fromRGB(150, 80, 255),
		RewardSeconds = 60, WinScore = 4 },
}

----------------------------------------------------------------------
-- 🎟️ Tickets
----------------------------------------------------------------------
ArcadeConfig.Tickets = {
	Icon = "🎟️",
	Max = 99999, -- solde maximum
	DailyCap = 150, -- tickets GAGNÉS par jour (récompenses : solo + victoires de duel ; les mises gagnées ne comptent pas)
	DuelWinBonus = 3, -- tickets bonus du gagnant d'un duel récompensé (en plus du pot)
	StartTickets = 10, -- petit cadeau de bienvenue à l'ouverture de l'arcade
}

-- Récompense minimale en Dopamine (quand la production est encore petite)
ArcadeConfig.MinDopamineReward = 200

----------------------------------------------------------------------
-- ⚔️ Duels
----------------------------------------------------------------------
ArcadeConfig.Duels = {
	Stakes = { 0, 5, 10, 25, 50 }, -- mises possibles (tickets, chaque joueur)
	InviteSeconds = 30, -- une invitation expire après ce délai
	InviteCooldown = 2, -- (s) entre deux invitations envoyées
	DeclineCooldown = 20, -- (s) avant de réinviter quelqu'un qui a refusé
	MaxIncoming = 3, -- invitations en attente max pour un joueur
	MaxDuelSeconds = 300, -- un duel trop long se termine en égalité (mises rendues)
	PairDailyLimit = 10, -- duels par jour contre le MÊME joueur (anti-farm)
	PairRewardedPerDay = 4, -- duels par jour contre le même joueur qui donnent Dopamine + tickets bonus + stats
	MinMovesForReward = 2, -- abandon / déconnexion avant ce nombre de coups : pas de Dopamine (mais le pot est gagné)
	ResultSeconds = 2.5, -- pause entre deux manches (jeux en manches)
	Reaction = {
		MinDelay = 1.6, -- délai aléatoire avant le "GO!"
		MaxDelay = 4.2,
		RoundTimeout = 3, -- personne n'a tapé : manche rejouée
		Window = 0.12, -- (s) attente après le 1er appui pour départager avec la latence
		MinHuman = 0.08, -- temps de réaction impossible (après compensation) = faux départ
		MaxPingComp = 0.2, -- compensation de latence max (s)
		MaxRounds = 9,
	},
	Spot = {
		MaxRounds = 9,
		RoundTimeout = 20, -- personne n'a trouvé : nouvelle grille
		WrongLock = 1.2, -- (s) bloqué après une erreur
		MinFind = 0.25, -- (s) plus rapide = pas humain (clic refusé)
	},
}

----------------------------------------------------------------------
-- 🛍️ Boutique à tickets
----------------------------------------------------------------------
-- Kind :
--   "Dopamine" : Seconds de production tout de suite
--   "Boost"    : boost de gains Multiplier pendant Duration secondes (système de boost existant ;
--                refusé si un boost DIFFÉRENT est déjà actif, pour ne rien écraser)
--   "Badge"    : badge d'arcade (emblème affiché à côté de ton nom dans les duels) — exclusif à l'arcade
-- MaxPerDay : achats maximum par jour (optionnel)
ArcadeConfig.Shop = {
	{ Id = "Snack", Kind = "Dopamine", Name = "Dopamine Snack", Icon = "🍬", Price = 20, Seconds = 90,
		Description = "90 seconds of production, right now", MaxPerDay = 10 },
	{ Id = "Feast", Kind = "Dopamine", Name = "Dopamine Feast", Icon = "🍱", Price = 90, Seconds = 480,
		Description = "8 minutes of production, right now", MaxPerDay = 5 },
	{ Id = "MiniBoost", Kind = "Boost", Name = "Mini Boost x2", Icon = "⏱️", Price = 60, Multiplier = 2, Duration = 180,
		Description = "Earnings x2 for 3 minutes", MaxPerDay = 3 },
	{ Id = "Joystick", Kind = "Badge", Name = "Joystick", Icon = "🕹️", Price = 30, Description = "A badge for true arcade fans" },
	{ Id = "Invader", Kind = "Badge", Name = "Space Invader", Icon = "👾", Price = 75, Description = "Beep boop. Pew pew." },
	{ Id = "NeonKitty", Kind = "Badge", Name = "Neon Kitty", Icon = "😺", Price = 120, Description = "Cute, fast and a little bit smug" },
	{ Id = "Rainbow", Kind = "Badge", Name = "Rainbow Star", Icon = "🌈", Price = 200, Description = "Shine on the duel board" },
	{ Id = "Dragon", Kind = "Badge", Name = "Pixel Dragon", Icon = "🐉", Price = 400, Description = "Legendary duelist aura" },
	{ Id = "Crown", Kind = "Badge", Name = "Arcade Crown", Icon = "👑", Price = 800, Description = "Only for the kings and queens of the arcade" },
}

----------------------------------------------------------------------
-- Index
----------------------------------------------------------------------
ArcadeConfig.GamesById = {}
ArcadeConfig.SoloGames = {}
ArcadeConfig.DuelGames = {}
for index, entry in ipairs(ArcadeConfig.Games) do
	entry.Order = index
	ArcadeConfig.GamesById[entry.Id] = entry
	if entry.Kind == "Solo" then
		table.insert(ArcadeConfig.SoloGames, entry)
	else
		table.insert(ArcadeConfig.DuelGames, entry)
	end
end
ArcadeConfig.ShopById = {}
for index, item in ipairs(ArcadeConfig.Shop) do
	item.Order = index
	ArcadeConfig.ShopById[item.Id] = item
end
ArcadeConfig.StakesSet = {}
for _, stake in ipairs(ArcadeConfig.Duels.Stakes) do
	ArcadeConfig.StakesSet[stake] = true
end

-- Nom du module client d'un jeu : "Solo_Minesweeper", "Duel_TicTacToe"
function ArcadeConfig.ModuleName(entry): string
	return tostring(entry.Kind) .. "_" .. tostring(entry.Id)
end

----------------------------------------------------------------------
-- Logic : règles pures des duels (aucune API Roblox : testables hors jeu)
----------------------------------------------------------------------
local Logic = {}
ArcadeConfig.Logic = Logic

-- Morpion : plateau = 9 cases (0 = vide, 1 / 2 = joueur), index 1..9 ligne par ligne
Logic.TicTacToeLines = {
	{ 1, 2, 3 }, { 4, 5, 6 }, { 7, 8, 9 },
	{ 1, 4, 7 }, { 2, 5, 8 }, { 3, 6, 9 },
	{ 1, 5, 9 }, { 3, 5, 7 },
}

-- -> (gagnant 0 | 1 | 2, ligne gagnante { a, b, c } ?)
function Logic.TicTacToeWinner(board: { number }): (number, { number }?)
	for _, line in ipairs(Logic.TicTacToeLines) do
		local a = board[line[1]]
		if a ~= 0 and a ~= nil and a == board[line[2]] and a == board[line[3]] then
			return a, line
		end
	end
	return 0, nil
end

function Logic.IsFull(board: { number }, size: number): boolean
	for index = 1, size do
		if board[index] == 0 or board[index] == nil then
			return false
		end
	end
	return true
end

-- Puissance 4 : 7 colonnes x 6 lignes, index = (ligne - 1) * 7 + colonne, ligne 1 = EN HAUT
Logic.C4Cols = 7
Logic.C4Rows = 6

function Logic.C4Index(row: number, col: number): number
	return (row - 1) * Logic.C4Cols + col
end

-- Case où tombe un jeton lâché dans `col` (la plus basse libre) ; nil si colonne pleine / invalide
function Logic.C4Drop(board: { number }, col: number): number?
	if type(col) ~= "number" or col ~= math.floor(col) or col < 1 or col > Logic.C4Cols then
		return nil
	end
	for row = Logic.C4Rows, 1, -1 do
		local index = Logic.C4Index(row, col)
		if board[index] == 0 then
			return index
		end
	end
	return nil
end

-- -> (gagnant 0 | 1 | 2, cases gagnantes { index... } ?)
function Logic.C4Winner(board: { number }): (number, { number }?)
	local cols, rows = Logic.C4Cols, Logic.C4Rows
	local directions = { { 0, 1 }, { 1, 0 }, { 1, 1 }, { 1, -1 } }
	for row = 1, rows do
		for col = 1, cols do
			local seat = board[Logic.C4Index(row, col)]
			if seat ~= 0 then
				for _, dir in ipairs(directions) do
					local cells = { Logic.C4Index(row, col) }
					for step = 1, 3 do
						local r, c = row + dir[1] * step, col + dir[2] * step
						if r < 1 or r > rows or c < 1 or c > cols or board[Logic.C4Index(r, c)] ~= seat then
							break
						end
						table.insert(cells, Logic.C4Index(r, c))
					end
					if #cells == 4 then
						return seat, cells
					end
				end
			end
		end
	end
	return 0, nil
end

-- Trouve l'intrus : paires d'emojis presque identiques (base, intrus)
Logic.SpotPairs = {
	{ "😺", "😸" }, { "🍎", "🍏" }, { "🌕", "🌖" }, { "💙", "💜" }, { "🐶", "🐱" },
	{ "⭐", "🌟" }, { "🍩", "🍪" }, { "🐸", "🐢" }, { "🌸", "🌺" }, { "🍓", "🍒" },
	{ "🐧", "🐦" }, { "🎈", "🎀" }, { "🧁", "🍰" }, { "🐻", "🐼" }, { "🍋", "🍊" },
}

-- Taille de la grille selon la manche (4x4 -> 5x5 -> 6x6)
function Logic.SpotGridSize(round: number): number
	if round <= 2 then
		return 4
	elseif round <= 4 then
		return 5
	end
	return 6
end

-- Nouvelle grille : rng(a, b) -> entier dans [a, b]
-- -> { Size, Cells = { emoji... }, Odd = index de l'intrus }
function Logic.SpotMakeGrid(rng: (number, number) -> number, round: number)
	local size = Logic.SpotGridSize(round)
	local pair = Logic.SpotPairs[rng(1, #Logic.SpotPairs)]
	local swap = rng(1, 2) == 2
	local base, odd = pair[swap and 2 or 1], pair[swap and 1 or 2]
	local count = size * size
	local oddIndex = rng(1, count)
	local cells = table.create(count, base)
	cells[oddIndex] = odd
	return { Size = size, Cells = cells, Odd = oddIndex }
end

-- Le duel en manches est-il fini ? -> gagnant 0 | 1 | 2
function Logic.RoundsWinner(scores: { number }, winScore: number): number
	if (scores[1] or 0) >= winScore then
		return 1
	elseif (scores[2] or 0) >= winScore then
		return 2
	end
	return 0
end

return ArcadeConfig
