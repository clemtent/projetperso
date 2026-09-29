--[[
	Solo_Logic (ModuleScript)
	Emplacement : ReplicatedStorage > Client > Minigames > Solo_Logic

	🕹️ Logique PURE des mini-jeux solo de l'arcade (aucune instance Roblox,
	aucun service) : partagée par le serveur (Services > Arcade > SoloGames :
	validation, rejeu des parties) et par les modules clients Solo_* (même
	simulation des deux côtés => mêmes résultats, aucune désynchronisation).

	Contenu :
	  - Logic.Rng(seed)          : générateur pseudo-aléatoire déterministe (xorshift32)
	  - Logic.Games              : règles, difficultés, récompenses, plafonds du jour
	  - Logic.Stars / Reward     : étoiles (0 à 3) et récompenses d'une partie
	  - Démineur                 : génération (1er clic sûr), révélation en cascade
	  - Memory                   : paquet de paires
	  - Tape-taupe               : programme des taupes (graine)
	  - Snake                    : simulation pas à pas (graine)
	  - 2048                     : simulation des coups (graine)

	Les récompenses sont des 🎟️ tickets, un 🏆 trophée (jamais achetable) et
	des SECONDES de production de Dopamine (aucune mise, aucun hasard payant :
	jeux d'adresse).
]]

local Logic = {}

----------------------------------------------------------------------
-- Générateur pseudo-aléatoire déterministe (identique client / serveur)
----------------------------------------------------------------------

export type Rng = {
	Next: () -> number,
	Int: (a: number, b: number) -> number,
}

function Logic.Rng(seed: number?): Rng
	local state = math.floor(tonumber(seed) or 1) % 4294967296
	if state ~= state or state <= 0 then
		state = 2654435769
	end
	local function step(): number
		state = bit32.bxor(state, bit32.lshift(state, 13))
		state = bit32.bxor(state, bit32.rshift(state, 17))
		state = bit32.bxor(state, bit32.lshift(state, 5))
		return state
	end
	-- Quelques tours à vide : deux graines proches donnent des suites différentes
	for _ = 1, 6 do
		step()
	end
	local rng = {}
	function rng.Next(): number
		return step() / 4294967296
	end
	function rng.Int(a: number, b: number): number
		if b <= a then
			return a
		end
		return a + math.floor(rng.Next() * (b - a + 1))
	end
	return rng
end

----------------------------------------------------------------------
-- Règles des jeux (paramètres de chaque difficulté)
--   Les récompenses de BASE (Tickets, RewardSeconds, DailyRewarded) sont
--   dans Shared > ArcadeConfig (GamesById[Id]) : une victoire donne la base
--   (api.RewardWin), puis un bonus selon la difficulté et les étoiles
--   (Logic.Multiplier, jamais plus de parties récompensées par jour).
--   MinSeconds : durée minimale d'une victoire récompensée (anti-triche).
----------------------------------------------------------------------

Logic.DifficultyOrder = { "Easy", "Normal", "Hard" }
Logic.DifficultyInfo = {
	Easy = { Name = "Easy", Icon = "🌱", Color = Color3.fromRGB(96, 206, 140) },
	Normal = { Name = "Normal", Icon = "⭐", Color = Color3.fromRGB(255, 170, 60) },
	Hard = { Name = "Hard", Icon = "🔥", Color = Color3.fromRGB(240, 84, 120) },
}
Logic.SessionTimeout = 1800 -- une partie abandonnée expire après 30 min
Logic.GameOrder = { "Minesweeper", "Memory", "Simon", "WhackAMole", "Snake", "Game2048" }

Logic.Games = {
	Minesweeper = {
		Name = "Minesweeper",
		Icon = "💣",
		BestLower = true, -- record = meilleur temps (en secondes)
		Difficulties = {
			Easy = { Cols = 8, Rows = 8, Mines = 10, Fast = 45, Ok = 100, MinSeconds = 2 },
			Normal = { Cols = 12, Rows = 10, Mines = 20, Fast = 110, Ok = 240, MinSeconds = 5 },
			Hard = { Cols = 16, Rows = 12, Mines = 38, Fast = 240, Ok = 480, MinSeconds = 10 },
		},
	},
	Memory = {
		Name = "Memory",
		Icon = "🃏",
		BestLower = true, -- record = moins de coups
		Difficulties = {
			Easy = { Cols = 4, Rows = 3, Pairs = 6, MinSeconds = 4 },
			Normal = { Cols = 4, Rows = 4, Pairs = 8, MinSeconds = 6 },
			Hard = { Cols = 6, Rows = 4, Pairs = 12, MinSeconds = 10 },
		},
	},
	Simon = {
		Name = "Simon",
		Icon = "🎵",
		MaxRounds = 30,
		Difficulties = {
			Easy = { Pads = 4, Step = 0.6, Thresholds = { 3, 6, 9 } },
			Normal = { Pads = 4, Step = 0.45, Thresholds = { 4, 8, 12 } },
			Hard = { Pads = 6, Step = 0.38, Thresholds = { 5, 9, 13 } },
		},
	},
	WhackAMole = {
		Name = "Whack-a-Mole",
		Icon = "🔨",
		Holes = 9,
		Duration = 30,
		Difficulties = {
			Easy = { Every = 0.95, Up = 1.35, Gold = 0.08, Bomb = 0.08, Fractions = { 0.35, 0.55, 0.75 } },
			Normal = { Every = 0.72, Up = 1.05, Gold = 0.1, Bomb = 0.12, Fractions = { 0.35, 0.55, 0.75 } },
			Hard = { Every = 0.52, Up = 0.8, Gold = 0.12, Bomb = 0.15, Fractions = { 0.35, 0.55, 0.75 } },
		},
	},
	Snake = {
		Name = "Snake",
		Icon = "🐍",
		MaxTicks = 30000,
		Difficulties = {
			Easy = { Cols = 14, Rows = 10, Tick = 0.16, Wrap = true, Thresholds = { 5, 12, 20 } },
			Normal = { Cols = 16, Rows = 11, Tick = 0.125, Wrap = false, Thresholds = { 6, 14, 24 } },
			Hard = { Cols = 18, Rows = 12, Tick = 0.095, Wrap = false, Thresholds = { 8, 16, 28 } },
		},
	},
	Game2048 = {
		Name = "2048",
		Icon = "🔢",
		Size = 4,
		MaxMoves = 8000,
		MinMoveSeconds = 0.05, -- 20 coups / s maximum
		Difficulties = {
			Easy = { Target = 256, Thresholds = { 64, 128, 256 } },
			Normal = { Target = 512, Thresholds = { 128, 256, 512 } },
			Hard = { Target = 2048, Thresholds = { 512, 1024, 2048 } },
		},
	},
}

-- v9.8 (DESK98) 🏃 "Desk Runner" (bureau gamer, simulation : Shared >
-- DeskRunnerLogic ; rejoué par SoloGames). Pas dans GameOrder : jamais
-- listé dans le panneau Arcade. Mêmes seuils que DeskRunnerLogic.Rules.
Logic.Games.DeskRunner = {
	Name = "Desk Runner",
	Icon = "🏃",
	MaxTicks = 18000,
	Hidden = true,
	Difficulties = {
		Normal = { Thresholds = { 400, 1000, 2000 } },
	},
}

-- Règles d'une difficulté (nil si inconnue : arguments "poubelle")
function Logic.GetRules(gameId: any, difficulty: any): (any, any)
	if type(gameId) ~= "string" or type(difficulty) ~= "string" then
		return nil, nil
	end
	local game = Logic.Games[gameId]
	if not game then
		return nil, nil
	end
	local rules = game.Difficulties[difficulty]
	if not rules then
		return nil, nil
	end
	return game, rules
end

-- Étoiles d'un score "plus grand = mieux" (seuils croissants)
local function starsFromThresholds(value: number, thresholds: { number }): (number, number)
	local stars = 0
	for index, threshold in ipairs(thresholds) do
		if value >= threshold then
			stars = index
		end
	end
	local progress = 0
	if stars == 0 and thresholds[1] and thresholds[1] > 0 then
		progress = math.clamp(value / thresholds[1], 0, 1)
	end
	return stars, progress
end
Logic.StarsFromThresholds = starsFromThresholds

-- Étoiles d'une partie : metrics dépend du jeu (voir chaque jeu plus bas)
function Logic.Stars(gameId: string, rules: any, metrics: any): (number, number)
	if gameId == "Minesweeper" then
		if metrics.Won then
			local t = metrics.Time or math.huge
			return (t <= rules.Fast and 3) or (t <= rules.Ok and 2) or 1, 1
		end
		return 0, math.clamp(metrics.Progress or 0, 0, 1)
	elseif gameId == "Memory" then
		if metrics.Won then
			local moves = metrics.Moves or math.huge
			if moves <= math.ceil(rules.Pairs * 1.5) then
				return 3, 1
			elseif moves <= math.ceil(rules.Pairs * 2.25) then
				return 2, 1
			end
			return 1, 1
		end
		return 0, math.clamp(metrics.Progress or 0, 0, 1)
	elseif gameId == "Simon" or gameId == "Snake" or gameId == "DeskRunner" then
		return starsFromThresholds(metrics.Score or 0, rules.Thresholds)
	elseif gameId == "WhackAMole" then
		local max = math.max(1, metrics.Max or 1)
		local fractions = rules.Fractions
		local thresholds = {}
		for index, fraction in ipairs(fractions) do
			thresholds[index] = math.max(1, math.floor(max * fraction + 0.5))
		end
		return starsFromThresholds(metrics.Score or 0, thresholds)
	elseif gameId == "Game2048" then
		return starsFromThresholds(metrics.MaxTile or 0, rules.Thresholds)
	end
	return 0, 0
end

-- Multiplicateur de la récompense de base [difficulté][étoiles]
Logic.Multiplier = {
	Easy = { 1, 1, 1.25 },
	Normal = { 1, 1.25, 1.5 },
	Hard = { 1.25, 1.75, 2.25 },
}

-- Récompense totale d'une victoire : (tickets, secondes) à partir de la base
-- ArcadeConfig (baseTickets, baseSeconds). 0 étoile = rien.
function Logic.Reward(baseTickets: number, baseSeconds: number, difficulty: string, stars: number): (number, number)
	local row = Logic.Multiplier[difficulty]
	if not row or not stars or stars < 1 then
		return 0, 0
	end
	local factor = row[math.clamp(math.floor(stars), 1, 3)]
	return math.floor((baseTickets or 0) * factor + 0.5), math.floor((baseSeconds or 0) * factor + 0.5)
end

----------------------------------------------------------------------
-- 💣 Démineur (généré et révélé par le SERVEUR uniquement)
----------------------------------------------------------------------

-- Voisins (8 directions) d'une case (index 1..cols*rows, ligne par ligne)
function Logic.Neighbors(cols: number, rows: number, index: number): { number }
	local list = {}
	local x = (index - 1) % cols
	local y = (index - 1) // cols
	for dy = -1, 1 do
		for dx = -1, 1 do
			if dx ~= 0 or dy ~= 0 then
				local nx, ny = x + dx, y + dy
				if nx >= 0 and nx < cols and ny >= 0 and ny < rows then
					table.insert(list, ny * cols + nx + 1)
				end
			end
		end
	end
	return list
end

-- Plateau vide (les mines sont posées au premier clic)
function Logic.MineBoard(cols: number, rows: number, mines: number)
	return {
		Cols = cols,
		Rows = rows,
		MineCount = mines,
		Mines = nil :: { [number]: boolean }?,
		Counts = {} :: { [number]: number },
		Revealed = {} :: { [number]: boolean },
		RevealedCount = 0,
		SafeTotal = cols * rows - mines,
	}
end

-- Pose les mines en évitant la case cliquée et ses voisines (1er clic sûr,
-- et toujours une petite zone qui s'ouvre). randomInt(a, b) : entier aléatoire.
function Logic.MinePlace(board, safeIndex: number, randomInt: (number, number) -> number)
	local cols, rows = board.Cols, board.Rows
	local total = cols * rows
	local excluded = { [safeIndex] = true }
	for _, n in ipairs(Logic.Neighbors(cols, rows, safeIndex)) do
		excluded[n] = true
	end
	local candidates = {}
	for index = 1, total do
		if not excluded[index] then
			table.insert(candidates, index)
		end
	end
	if #candidates < board.MineCount then
		-- plateau trop petit : on n'exclut que la case cliquée
		candidates = {}
		for index = 1, total do
			if index ~= safeIndex then
				table.insert(candidates, index)
			end
		end
	end
	local mines = {}
	local count = math.min(board.MineCount, #candidates)
	-- Mélange partiel (Fisher-Yates) : les `count` premières cases = mines
	for k = 1, count do
		local j = randomInt(k, #candidates)
		candidates[k], candidates[j] = candidates[j], candidates[k]
		mines[candidates[k]] = true
	end
	board.Mines = mines
	board.MineCount = count
	board.SafeTotal = total - count
	for index = 1, total do
		local n = 0
		for _, neighbor in ipairs(Logic.Neighbors(cols, rows, index)) do
			if mines[neighbor] then
				n += 1
			end
		end
		board.Counts[index] = n
	end
end

-- Révèle une case (cascade sur les zéros). Renvoie (liste des cases
-- nouvellement révélées, boom: boolean).
function Logic.MineReveal(board, index: number): ({ number }, boolean)
	local mines = board.Mines
	if not mines or board.Revealed[index] then
		return {}, false
	end
	if mines[index] then
		return { index }, true
	end
	local opened = {}
	local stack = { index }
	board.Revealed[index] = true
	while #stack > 0 do
		local current = table.remove(stack)
		table.insert(opened, current)
		board.RevealedCount += 1
		if board.Counts[current] == 0 then
			for _, neighbor in ipairs(Logic.Neighbors(board.Cols, board.Rows, current)) do
				if not board.Revealed[neighbor] and not mines[neighbor] then
					board.Revealed[neighbor] = true
					table.insert(stack, neighbor)
				end
			end
		end
	end
	return opened, false
end

function Logic.MineWon(board): boolean
	return board.Mines ~= nil and board.RevealedCount >= board.SafeTotal
end

----------------------------------------------------------------------
-- 🃏 Memory (paquet gardé par le SERVEUR, cartes révélées une à une)
----------------------------------------------------------------------

Logic.MemorySymbols = {
	{ "🍓", Color3.fromRGB(255, 120, 140) },
	{ "🐱", Color3.fromRGB(255, 190, 110) },
	{ "🌈", Color3.fromRGB(140, 170, 255) },
	{ "🍩", Color3.fromRGB(255, 150, 200) },
	{ "🦄", Color3.fromRGB(200, 150, 255) },
	{ "🌸", Color3.fromRGB(255, 170, 205) },
	{ "🐸", Color3.fromRGB(120, 210, 130) },
	{ "🍉", Color3.fromRGB(255, 110, 120) },
	{ "⭐", Color3.fromRGB(255, 205, 70) },
	{ "🐼", Color3.fromRGB(160, 160, 175) },
	{ "🍭", Color3.fromRGB(255, 130, 220) },
	{ "🎀", Color3.fromRGB(255, 105, 160) },
	{ "🐙", Color3.fromRGB(250, 130, 110) },
	{ "🍒", Color3.fromRGB(230, 70, 90) },
	{ "🌙", Color3.fromRGB(120, 130, 220) },
	{ "🧁", Color3.fromRGB(240, 160, 190) },
}

-- Paquet mélangé : liste de pairs*2 index de symboles
function Logic.MemoryDeck(pairs: number, randomInt: (number, number) -> number): { number }
	local pool = {}
	for index = 1, #Logic.MemorySymbols do
		pool[index] = index
	end
	for k = 1, math.min(pairs, #pool) do
		local j = randomInt(k, #pool)
		pool[k], pool[j] = pool[j], pool[k]
	end
	local deck = {}
	for k = 1, math.min(pairs, #pool) do
		table.insert(deck, pool[k])
		table.insert(deck, pool[k])
	end
	for k = #deck, 2, -1 do
		local j = randomInt(1, k)
		deck[k], deck[j] = deck[j], deck[k]
	end
	return deck
end

----------------------------------------------------------------------
-- 🔨 Tape-taupe : programme déterministe des apparitions (graine)
--   Kind : 1 = taupe (+1), 2 = taupe dorée (+3), 3 = bombe (-2)
----------------------------------------------------------------------

Logic.WhackValues = { 1, 3, -2 }

function Logic.WhackSchedule(seed: number, rules: any, holes: number, duration: number)
	local rng = Logic.Rng(seed)
	local schedule = {}
	local busyUntil = {}
	for hole = 1, holes do
		busyUntil[hole] = -1
	end
	local maxScore = 0
	local t = 0.7
	while t < duration - 0.5 and #schedule < 400 do
		local free = {}
		for hole = 1, holes do
			if busyUntil[hole] < t - 0.12 then
				table.insert(free, hole)
			end
		end
		if #free > 0 then
			local hole = free[rng.Int(1, #free)]
			-- Plus rapide vers la fin de la partie
			local rush = 1 - 0.28 * (t / duration)
			local up = math.min(rules.Up * rush * (0.85 + 0.3 * rng.Next()), duration - t)
			local roll = rng.Next()
			local kind = 1
			if roll < rules.Bomb then
				kind = 3
			elseif roll < rules.Bomb + rules.Gold then
				kind = 2
				up *= 0.8 -- les dorées filent plus vite
			end
			table.insert(schedule, { T = t, Hole = hole, Up = up, Kind = kind })
			busyUntil[hole] = t + up
			if Logic.WhackValues[kind] > 0 then
				maxScore += Logic.WhackValues[kind]
			end
		end
		local rush = 1 - 0.3 * (t / duration)
		t += rules.Every * rush * (0.7 + 0.6 * rng.Next())
	end
	return schedule, maxScore
end

-- Score d'une liste de coups (index dans le programme). Ignore les doublons
-- et les index invalides. elapsed (optionnel) : taupes pas encore sorties refusées.
function Logic.WhackScore(schedule, hits: any, elapsed: number?): (number, number)
	local score = 0
	local counted = 0
	local seen = {}
	if type(hits) ~= "table" then
		return 0, 0
	end
	for _, index in ipairs(hits) do
		if type(index) == "number" and index == index and index % 1 == 0 and not seen[index] then
			local mole = schedule[index]
			if mole and (elapsed == nil or mole.T <= elapsed + 0.5) then
				seen[index] = true
				counted += 1
				score += Logic.WhackValues[mole.Kind] or 0
			end
		end
		if counted >= #schedule then
			break
		end
	end
	return math.max(0, score), counted
end

----------------------------------------------------------------------
-- 🐍 Snake : simulation pas à pas (graine pour les fruits)
--   Directions : 1 = haut, 2 = droite, 3 = bas, 4 = gauche
----------------------------------------------------------------------

Logic.Directions = { { 0, -1 }, { 1, 0 }, { 0, 1 }, { -1, 0 } }

local function snakePlaceFood(s)
	local total = s.Cols * s.Rows
	local free = total - #s.Body
	if free <= 0 then
		s.Food = nil
		s.Full = true
		return
	end
	local k = s.Rng.Int(1, free)
	for index = 1, total do
		if not s.Occupied[index] then
			k -= 1
			if k == 0 then
				s.Food = index
				return
			end
		end
	end
end

function Logic.SnakeNew(seed: number, rules: any)
	local cols, rows = rules.Cols, rules.Rows
	local y = rows // 2
	local s = {
		Cols = cols,
		Rows = rows,
		Wrap = rules.Wrap == true,
		Rng = Logic.Rng(seed),
		Body = {} :: { number },
		Occupied = {} :: { [number]: number },
		Dir = 2,
		Tick = 0,
		Score = 0,
		Alive = true,
		Full = false,
		Food = nil :: number?,
	}
	for x = 4, 2, -1 do
		local index = y * cols + x
		table.insert(s.Body, index)
		s.Occupied[index] = (s.Occupied[index] or 0) + 1
	end
	snakePlaceFood(s)
	return s
end

-- Change de direction (refusé : même direction ou demi-tour). true si pris en compte.
function Logic.SnakeTurn(s, dir: any): boolean
	if type(dir) ~= "number" or not Logic.Directions[dir] then
		return false
	end
	if dir == s.Dir or (dir - s.Dir) % 4 == 2 then
		return false
	end
	s.Dir = dir
	return true
end

-- Avance d'une case. Renvoie "eat", "dead" ou nil.
function Logic.SnakeStep(s): string?
	if not s.Alive then
		return "dead"
	end
	s.Tick += 1
	local head = s.Body[1]
	local x = (head - 1) % s.Cols
	local y = (head - 1) // s.Cols
	local d = Logic.Directions[s.Dir]
	local nx, ny = x + d[1], y + d[2]
	if s.Wrap then
		nx %= s.Cols
		ny %= s.Rows
	elseif nx < 0 or nx >= s.Cols or ny < 0 or ny >= s.Rows then
		s.Alive = false
		return "dead"
	end
	local nextIndex = ny * s.Cols + nx + 1
	local eating = nextIndex == s.Food
	if not eating then
		-- la queue avance d'abord (on peut suivre sa propre queue)
		local tail = table.remove(s.Body)
		local left = (s.Occupied[tail] or 1) - 1
		s.Occupied[tail] = left > 0 and left or nil
	end
	if s.Occupied[nextIndex] then
		s.Alive = false
		return "dead"
	end
	table.insert(s.Body, 1, nextIndex)
	s.Occupied[nextIndex] = (s.Occupied[nextIndex] or 0) + 1
	if eating then
		s.Score += 1
		snakePlaceFood(s)
		if s.Full then
			s.Alive = false
			return "dead"
		end
		return "eat"
	end
	return nil
end

-- Durée d'un pas (le serpent accélère un peu à chaque fruit)
function Logic.SnakeInterval(rules: any, score: number): number
	return rules.Tick * math.max(0.62, 1 - 0.012 * score)
end

-- Rejoue une partie : turns = { tick1, dir1, tick2, dir2, ... } (tick
-- croissants), ticks = nombre de pas joués. Renvoie (score, pas simulés,
-- durée minimale théorique en secondes).
function Logic.SnakeReplay(seed: number, rules: any, turns: any, ticks: number, maxTicks: number)
	local s = Logic.SnakeNew(seed, rules)
	local list = type(turns) == "table" and turns or {}
	local cursor = 1
	local minDuration = 0
	local limit = math.clamp(math.floor(tonumber(ticks) or 0), 0, maxTicks)
	while s.Alive and s.Tick < limit do
		local nextTick = s.Tick + 1
		-- saute les virages "dans le passé" (liste mal triée = ignorée)
		while type(list[cursor]) == "number" and list[cursor] < nextTick do
			cursor += 2
		end
		if list[cursor] == nextTick then
			Logic.SnakeTurn(s, list[cursor + 1])
			cursor += 2
		end
		minDuration += Logic.SnakeInterval(rules, s.Score)
		Logic.SnakeStep(s)
	end
	return s.Score, s.Tick, minDuration, s
end

----------------------------------------------------------------------
-- 🔢 2048 : simulation (graine pour les nouvelles tuiles)
--   Directions : 1 = haut, 2 = droite, 3 = bas, 4 = gauche
----------------------------------------------------------------------

local function spawnTile(s)
	local free = {}
	for index = 1, s.Size * s.Size do
		if s.Cells[index] == 0 then
			table.insert(free, index)
		end
	end
	if #free == 0 then
		return nil, nil
	end
	local index = free[s.Rng.Int(1, #free)]
	local value = s.Rng.Next() < 0.9 and 2 or 4
	s.Cells[index] = value
	s.MaxTile = math.max(s.MaxTile, value)
	return index, value
end

function Logic.G2048New(seed: number, size: number?)
	local n = size or 4
	local s = { Size = n, Cells = {} :: { number }, Score = 0, MaxTile = 0, Moves = 0, Rng = Logic.Rng(seed) }
	for index = 1, n * n do
		s.Cells[index] = 0
	end
	local a, av = spawnTile(s)
	local b, bv = spawnTile(s)
	s.Initial = { { a, av }, { b, bv } }
	return s
end

-- Index des cases d'une ligne, dans le sens du mouvement
local function lineCells(size: number, dir: number, line: number): { number }
	local cells = {}
	for k = 1, size do
		local row, col
		if dir == 4 then -- gauche
			row, col = line, k
		elseif dir == 2 then -- droite
			row, col = line, size - k + 1
		elseif dir == 1 then -- haut
			row, col = k, line
		else -- bas
			row, col = size - k + 1, line
		end
		cells[k] = (row - 1) * size + col
	end
	return cells
end

-- Joue un coup. Renvoie (a bougé, infos d'animation) ; infos =
-- { Slides = { {from, to, value, merged} }, Spawn = {index, value}, Gain }
function Logic.G2048Move(s, dir: any)
	if type(dir) ~= "number" or dir < 1 or dir > 4 or dir % 1 ~= 0 then
		return false, nil
	end
	local size = s.Size
	local new = table.create(size * size, 0)
	local slides = {}
	local gain = 0
	for line = 1, size do
		local cells = lineCells(size, dir, line)
		local target = 1
		local lastValue, lastMerged = 0, true
		for k = 1, size do
			local from = cells[k]
			local value = s.Cells[from]
			if value ~= 0 then
				if value == lastValue and not lastMerged then
					local to = cells[target - 1]
					new[to] = value * 2
					gain += value * 2
					lastMerged = true
					table.insert(slides, { from, to, value, true })
				else
					local to = cells[target]
					new[to] = value
					lastValue = value
					lastMerged = false
					target += 1
					table.insert(slides, { from, to, value, false })
				end
			end
		end
	end
	local moved = false
	for index = 1, size * size do
		if new[index] ~= s.Cells[index] then
			moved = true
			break
		end
	end
	if not moved then
		return false, nil
	end
	s.Cells = new
	s.Score += gain
	s.Moves += 1
	for index = 1, size * size do
		if new[index] > s.MaxTile then
			s.MaxTile = new[index]
		end
	end
	local spawnIndex, spawnValue = spawnTile(s)
	return true, { Slides = slides, Spawn = spawnIndex and { spawnIndex, spawnValue } or nil, Gain = gain }
end

function Logic.G2048CanMove(s): boolean
	local size = s.Size
	for index = 1, size * size do
		local value = s.Cells[index]
		if value == 0 then
			return true
		end
		local col = (index - 1) % size
		if col < size - 1 and s.Cells[index + 1] == value then
			return true
		end
		if index + size <= size * size and s.Cells[index + size] == value then
			return true
		end
	end
	return false
end

Logic.G2048Letters = { U = 1, R = 2, D = 3, L = 4 }
Logic.G2048Chars = { "U", "R", "D", "L" }

-- Rejoue une suite de coups ("URDL..."). S'arrête à l'objectif ou au blocage.
function Logic.G2048Replay(seed: number, rules: any, size: number, moves: any, maxMoves: number)
	local s = Logic.G2048New(seed, size)
	local text = type(moves) == "string" and moves or ""
	local played = 0
	for k = 1, math.min(#text, maxMoves) do
		if s.MaxTile >= rules.Target then
			break
		end
		local dir = Logic.G2048Letters[string.sub(text, k, k)]
		if dir then
			local moved = Logic.G2048Move(s, dir)
			if moved then
				played += 1
			end
		end
	end
	return s, played
end

return Logic
