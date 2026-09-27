--[[
	SoloGames (ModuleScript)
	Emplacement : ServerScriptService > Services > Arcade > SoloGames

	🕹️ Mini-jeux SOLO de l'arcade, côté serveur (anti-triche) :
	  💣 Minesweeper, 🃏 Memory, 🎵 Simon, 🔨 WhackAMole, 🐍 Snake, 🔢 Game2048.

	Appelé par MinigameService pour toute action "solo:..." :
	  SoloGames.Handle(player, data, action, arg, api) -> (ok, résultat | message)

	Principe : une seule partie en cours par joueur (session en mémoire,
	jamais sauvegardée). Chaque partie a un jeton (Token) à renvoyer.
	  - Démineur, Memory, Simon : le SERVEUR garde le plateau / le paquet /
	    la séquence et répond coup par coup (le client ne voit jamais les
	    mines ni les cartes cachées).
	  - Tape-taupe, Snake, 2048 : le serveur donne une graine (Seed), le
	    client joue avec la même simulation (Client > Minigames > Solo_Logic)
	    et envoie à la fin le journal de la partie ; le serveur la REJOUE et
	    vérifie les durées (impossible d'annoncer un faux score).

	Protocole (arg = table ; toute valeur invalide est refusée sans erreur) :
	  solo:info   nil                                  -> { Best = { ["Id:Diff"] = n } }
	  solo:start  { Game, Difficulty }                 -> { Token, Game, Difficulty, Best, ... (selon le jeu) }
	  solo:move   { Token, ... }                       -> selon le jeu (Démineur, Memory, Simon)
	  solo:finish { Token, ... }                       -> { Done = true, Won, Stars, Score, Tickets, Trophies, Dopamine, ... }
	  (voir le détail en bas de chaque section)

	Récompenses : une victoire (>= 1 étoile) appelle api.RewardWin (base
	ArcadeConfig : tickets, 🏆 trophée, Dopamine, stat MinigamesWon, parties
	récompensées par jour, record), puis ajoute un bonus selon la difficulté et les étoiles
	(Solo_Logic.Multiplier) tant que le quota du jour n'est pas atteint.
	Records par difficulté : data.Arcade.Solo.Best["Id:Diff"] (nettoyé ici).
	L'onglet Records de l'arcade (data.Arcade.Best) reçoit le score du mode
	RECORD_DIFFICULTY ("Normal") pour que les records restent comparables.
]]

local SoloGames = {}

local RECORD_DIFFICULTY = "Normal"
local MAX_BEST_ENTRIES = 64

----------------------------------------------------------------------
-- Dépendances (résolues sans jamais bloquer ; injectables pour les tests)
----------------------------------------------------------------------

local Logic = nil
local ArcadeConfig = nil

local function resolveModules()
	if Logic then
		return
	end
	local ok, err = pcall(function()
		local ReplicatedStorage = game:GetService("ReplicatedStorage")
		local folder = ReplicatedStorage:WaitForChild("Client", 10):WaitForChild("Minigames", 10)
		Logic = require(folder:WaitForChild("Solo_Logic", 10))
		local shared = ReplicatedStorage:FindFirstChild("Shared")
		local config = shared and shared:FindFirstChild("ArcadeConfig")
		if config then
			ArcadeConfig = require(config)
		end
	end)
	if not ok then
		warn("[SoloGames] Solo_Logic introuvable : " .. tostring(err))
	end
end

-- Tests hors Roblox : SoloGames._Inject(logicModule, arcadeConfig)
function SoloGames._Inject(logicModule, arcadeConfig)
	Logic = logicModule
	ArcadeConfig = arcadeConfig
end

-- Hasard du serveur (plateaux secrets : Démineur, Memory, Simon, graines)
local serverRandom = nil
local function randomInt(a: number, b: number): number
	if b <= a then
		return a
	end
	if serverRandom == nil then
		local ok, rng = pcall(function()
			return Random.new()
		end)
		serverRandom = ok and rng or false
	end
	if serverRandom then
		return serverRandom:NextInteger(a, b)
	end
	return math.random(a, b)
end

----------------------------------------------------------------------
-- Sessions (une partie en cours par joueur, en mémoire seulement)
----------------------------------------------------------------------

local sessions = {}
local tokenCounter = 0

pcall(function()
	game:GetService("Players").PlayerRemoving:Connect(function(player)
		sessions[player] = nil
	end)
end)

function SoloGames.Cleanup(player)
	sessions[player] = nil
end

-- Tests : session en cours d'un joueur (lecture seule)
function SoloGames._GetSession(player)
	return sessions[player]
end

local function now(api): number
	if type(api.Now) == "function" then
		local ok, value = pcall(api.Now)
		if ok and type(value) == "number" and value == value then
			return value
		end
	end
	return os.clock()
end

local function T(api, player, text: string, ...): string
	if type(api.T) == "function" then
		local ok, result = pcall(api.T, player, text, ...)
		if ok and type(result) == "string" then
			return result
		end
	end
	if select("#", ...) > 0 then
		local ok, result = pcall(string.format, text, ...)
		if ok then
			return result
		end
	end
	return text
end

-- Entier valide dans [lo, hi] (sinon nil) : protège contre NaN, 1e999, "1"...
local function int(value: any, lo: number, hi: number): number?
	if type(value) ~= "number" or value ~= value or value % 1 ~= 0 or value < lo or value > hi then
		return nil
	end
	return value
end

----------------------------------------------------------------------
-- Données : records par difficulté (data.Arcade.Solo)
----------------------------------------------------------------------

local function soloData(data)
	if type(data.Arcade) ~= "table" then
		data.Arcade = {}
	end
	local solo = data.Arcade.Solo
	if type(solo) ~= "table" then
		solo = {}
		data.Arcade.Solo = solo
	end
	if type(solo.Best) ~= "table" then
		solo.Best = {}
	end
	-- Nettoyage : seulement "Jeu:Difficulté" connus, nombres finis >= 0
	local count = 0
	for key, value in pairs(solo.Best) do
		local valid = false
		if type(key) == "string" and type(value) == "number" and value == value and value >= 0 and value < 1e12 then
			local gameId, difficulty = string.match(key, "^(%w+):(%w+)$")
			valid = gameId ~= nil and Logic.GetRules(gameId, difficulty) ~= nil
		end
		if valid then
			count += 1
		end
		if not valid or count > MAX_BEST_ENTRIES then
			solo.Best[key] = nil
		end
	end
	for key in pairs(solo) do
		if key ~= "Best" then
			solo[key] = nil
		end
	end
	return solo
end

local function bestKey(session): string
	return session.Game .. ":" .. session.Difficulty
end

-- Met à jour le record perso ; renvoie (record, nouveau record ?)
local function updateBest(data, session, value: number?, lower: boolean): (number?, boolean)
	local solo = soloData(data)
	local key = bestKey(session)
	local old = solo.Best[key]
	if type(value) ~= "number" or value ~= value or value < 0 then
		return old, false
	end
	local better = old == nil or (lower and value < old) or (not lower and value > old)
	if better and (lower or value > 0) then
		solo.Best[key] = value
		return value, true
	end
	return old, false
end

----------------------------------------------------------------------
-- Fin de partie : stats, récompenses, records
----------------------------------------------------------------------

local function arcadeEntry(api, gameId: string)
	local config = (type(api.Config) == "table" and api.Config) or ArcadeConfig
	local byId = config and config.GamesById
	return type(byId) == "table" and byId[gameId] or nil
end

local function callApi(api, name: string, ...)
	local fn = api[name]
	if type(fn) ~= "function" then
		return false, nil
	end
	local ok, result = pcall(fn, ...)
	if not ok then
		warn("[SoloGames] api." .. name .. " : " .. tostring(result))
		return false, nil
	end
	return true, result
end

-- metrics : { Score (affiché), Record (valeur de record, optionnelle), Stars,
-- Lower (record "plus petit = mieux"), Rejected (message anti-triche) }
local function conclude(player, data, api, session, metrics)
	session.Done = true
	if sessions[player] == session then
		sessions[player] = nil
	end
	local stars = math.clamp(math.floor(metrics.Stars or 0), 0, 3)
	local elapsed = now(api) - (session.FirstMove or session.Started)
	local result = {
		Done = true,
		Game = session.Game,
		Difficulty = session.Difficulty,
		Won = stars >= 1,
		Stars = stars,
		Score = metrics.Score or 0,
		Time = math.floor(elapsed * 10) / 10,
		Tickets = 0,
		Trophies = 0,
		Dopamine = 0,
		Capped = false,
		Record = false,
		NewBest = false,
	}
	-- Une partie compte si le joueur a vraiment joué
	if session.Moves > 0 or metrics.Played then
		callApi(api, "CountPlay", player, session.Game)
	end
	if metrics.Rejected then
		result.Won = false
		result.Stars = 0
		result.Rejected = metrics.Rejected
		result.Best = soloData(data).Best[bestKey(session)]
		return result
	end
	if stars >= 1 then
		local recordValue = session.Difficulty == RECORD_DIFFICULTY and (metrics.Record or metrics.Score) or nil
		local entry = arcadeEntry(api, session.Game)
		local baseTickets = entry and tonumber(entry.Tickets) or 0
		local baseSeconds = entry and tonumber(entry.RewardSeconds) or 0
		local okReward, reward = callApi(api, "RewardWin", player, session.Game, recordValue)
		if okReward and type(reward) == "table" then
			result.Tickets = tonumber(reward.Tickets) or 0
			result.Trophies = tonumber(reward.Trophies) or 0 -- 🏆 (mises des duels, jamais achetables)
			result.Dopamine = tonumber(reward.Dopamine) or 0
			result.Capped = reward.Capped == true
			result.Record = reward.Record == true
		elseif type(api.RewardWin) ~= "function" then
			-- Ancien contrat : récompense de base à la main
			local _, granted = callApi(api, "GrantTickets", player, baseTickets)
			local _, amount = callApi(api, "GrantDopamineSeconds", player, baseSeconds)
			callApi(api, "AddStat", player, "MinigamesWon", 1)
			result.Tickets = tonumber(granted) or 0
			result.Dopamine = tonumber(amount) or 0
		end
		-- Bonus de difficulté / étoiles (pas de bonus si le quota du jour est atteint)
		if not result.Capped then
			local totalTickets, totalSeconds = Logic.Reward(baseTickets, baseSeconds, session.Difficulty, stars)
			local bonusTickets = math.max(0, totalTickets - baseTickets)
			local bonusSeconds = math.max(0, totalSeconds - baseSeconds)
			if bonusTickets > 0 then
				local _, granted = callApi(api, "GrantTickets", player, bonusTickets)
				result.Tickets += tonumber(granted) or 0
			end
			if bonusSeconds > 0 then
				local _, amount = callApi(api, "GrantDopamineSeconds", player, bonusSeconds)
				result.Dopamine += tonumber(amount) or 0
			end
		end
	end
	-- Record perso de cette difficulté (temps : seulement les victoires)
	local bestValue = metrics.Record or metrics.Score
	if metrics.Lower and stars < 1 then
		bestValue = nil
	end
	result.Best, result.NewBest = updateBest(data, session, bestValue, metrics.Lower == true)
	return result
end

local function newSession(player, gameId: string, difficulty: string, gameRules, rules, api)
	tokenCounter += 1
	local session = {
		Game = gameId,
		Difficulty = difficulty,
		GameRules = gameRules,
		Rules = rules,
		Token = tokenCounter * 1000 + randomInt(0, 999),
		Started = now(api),
		Moves = 0,
		Done = false,
	}
	sessions[player] = session
	return session
end

----------------------------------------------------------------------
-- 💣 Démineur
--   start  -> { Cols, Rows, Mines }
--   move   { Token, Cell = i } ou { Token, Cells = { i, ... } (<= 9, "accord") }
--          -> { Cells = { i... }, Numbers = { n... } }  (+ Boom, Cell, Mines = { i... }, Done, Result en fin)
--   finish { Token } -> abandon (défaite)
----------------------------------------------------------------------

local Minesweeper = {}

function Minesweeper.Start(session, reply)
	local rules = session.Rules
	session.Board = Logic.MineBoard(rules.Cols, rules.Rows, rules.Mines)
	reply.Cols = rules.Cols
	reply.Rows = rules.Rows
	reply.Mines = rules.Mines
end

local function allMines(board): { number }
	local list = {}
	for index in pairs(board.Mines or {}) do
		table.insert(list, index)
	end
	table.sort(list)
	return list
end

-- Chrono à partir du premier coup (comme le démineur classique)
local function playTime(session, api): number
	return math.floor((now(api) - (session.FirstMove or session.Started)) * 10) / 10
end

local function mineMetrics(session, api, won: boolean)
	local board = session.Board
	local elapsed = playTime(session, api)
	local stars = Logic.Stars("Minesweeper", session.Rules, {
		Won = won,
		Time = elapsed,
		Progress = board.SafeTotal > 0 and board.RevealedCount / board.SafeTotal or 0,
	})
	local metrics = { Stars = stars, Score = elapsed, Record = elapsed, Lower = true }
	if won and elapsed < (session.Rules.MinSeconds or 0) then
		metrics.Rejected = "Too fast! This run can't be rewarded."
	end
	return metrics
end

function Minesweeper.Move(player, data, api, session, arg)
	local board = session.Board
	local total = board.Cols * board.Rows
	local list = {}
	if type(arg.Cells) == "table" then
		for k = 1, 9 do
			local cell = int(arg.Cells[k], 1, total)
			if cell then
				table.insert(list, cell)
			end
		end
	else
		local cell = int(arg.Cell, 1, total)
		if cell then
			table.insert(list, cell)
		end
	end
	if #list == 0 then
		return false, T(api, player, "Invalid move")
	end
	if not board.Mines then
		Logic.MinePlace(board, list[1], randomInt)
		session.FirstMove = now(api)
	end
	session.Moves += 1
	local reply = { Cells = {}, Numbers = {} }
	for _, cell in ipairs(list) do
		local opened, boom = Logic.MineReveal(board, cell)
		if boom then
			reply.Boom = true
			reply.Cell = cell
			reply.Mines = allMines(board)
			reply.Done = true
			local metrics = mineMetrics(session, api, false)
			if metrics.Rejected then
				metrics.Rejected = nil
			end
			reply.Result = conclude(player, data, api, session, metrics)
			return true, reply
		end
		for _, index in ipairs(opened) do
			table.insert(reply.Cells, index)
			table.insert(reply.Numbers, board.Counts[index])
		end
	end
	if Logic.MineWon(board) then
		reply.Won = true
		reply.Mines = allMines(board)
		reply.Done = true
		reply.Result = conclude(player, data, api, session, mineMetrics(session, api, true))
	end
	return true, reply
end

function Minesweeper.Finish(player, data, api, session, _arg)
	return true, conclude(player, data, api, session, { Stars = 0, Score = 0, Lower = true })
end

----------------------------------------------------------------------
-- 🃏 Memory
--   start  -> { Cols, Rows, Pairs }
--   move   { Token, Cell = i } -> { Cell, Symbol } (1re carte) ou
--          { Cell, Symbol, Other, Match, Pairs, Moves } (2e carte) (+ Done, Result à la fin)
--          { Ignored = true } si la carte est déjà ouverte / trouvée
--   finish { Token } -> abandon
----------------------------------------------------------------------

local Memory = {}

function Memory.Start(session, reply)
	local rules = session.Rules
	session.Deck = Logic.MemoryDeck(rules.Pairs, randomInt)
	session.Matched = {}
	session.Found = 0
	session.Turns = 0
	session.Open = nil
	reply.Cols = rules.Cols
	reply.Rows = rules.Rows
	reply.Pairs = rules.Pairs
end

function Memory.Move(player, data, api, session, arg)
	local cell = int(arg.Cell, 1, #session.Deck)
	if not cell then
		return false, T(api, player, "Invalid move")
	end
	if session.Matched[cell] or session.Open == cell then
		return true, { Ignored = true, Cell = cell }
	end
	session.Moves += 1
	session.FirstMove = session.FirstMove or now(api)
	local symbol = session.Deck[cell]
	if not session.Open then
		session.Open = cell
		return true, { Cell = cell, Symbol = symbol }
	end
	local other = session.Open
	session.Open = nil
	session.Turns += 1
	local match = session.Deck[other] == symbol
	if match then
		session.Matched[cell] = true
		session.Matched[other] = true
		session.Found += 1
	end
	local reply = { Cell = cell, Symbol = symbol, Other = other, Match = match, Pairs = session.Found, Moves = session.Turns }
	if session.Found >= session.Rules.Pairs then
		local elapsed = playTime(session, api)
		local stars = Logic.Stars("Memory", session.Rules, { Won = true, Moves = session.Turns })
		local metrics = { Stars = stars, Score = session.Turns, Record = elapsed, Lower = true }
		if elapsed < (session.Rules.MinSeconds or 0) then
			metrics.Rejected = "Too fast! This run can't be rewarded."
		end
		reply.Done = true
		reply.Result = conclude(player, data, api, session, metrics)
	end
	return true, reply
end

function Memory.Finish(player, data, api, session, _arg)
	return true, conclude(player, data, api, session, { Stars = 0, Score = session.Turns or 0, Lower = true })
end

----------------------------------------------------------------------
-- 🎵 Simon
--   start  -> { Pads, Step, MaxRounds, Sequence = { pad } }
--   move   { Token, Inputs = { pad, ... } } (la manche entière, ou jusqu'à l'erreur)
--          -> { Round, Sequence } (manche réussie : séquence complète suivante)
--          -> { Wrong = true, Expected, Done, Result } (erreur = fin)
--   finish { Token } -> arrêt (score = manches réussies)
----------------------------------------------------------------------

local Simon = {}

function Simon.Start(session, reply, api)
	local rules = session.Rules
	session.Sequence = { randomInt(1, rules.Pads) }
	session.SentAt = now(api)
	session.Rounds = 0
	reply.Pads = rules.Pads
	reply.Step = rules.Step
	reply.MaxRounds = session.GameRules.MaxRounds
	reply.Sequence = table.clone(session.Sequence)
end

local function simonEnd(player, data, api, session)
	local score = session.Rounds
	local stars = Logic.Stars("Simon", session.Rules, { Score = score })
	return conclude(player, data, api, session, { Stars = stars, Score = score })
end

function Simon.Move(player, data, api, session, arg)
	local inputs = arg.Inputs
	local sequence = session.Sequence
	if type(inputs) ~= "table" then
		return false, T(api, player, "Invalid move")
	end
	local count = 0
	for k = 1, #sequence do
		local value = inputs[k]
		if value == nil then
			break
		end
		count = k
		local pad = int(value, 1, session.Rules.Pads)
		if pad ~= sequence[k] then
			session.Moves += 1
			local reply = { Wrong = true, Expected = sequence[k], Index = k, Done = true }
			reply.Result = simonEnd(player, data, api, session)
			return true, reply
		end
	end
	if count < #sequence then
		return false, T(api, player, "Invalid move")
	end
	-- Anti-robot : il faut au moins le temps de voir la séquence et de la rejouer
	local elapsed = now(api) - session.SentAt
	local minimum = #sequence * session.Rules.Step * 0.85 + #sequence * 0.07
	if elapsed < minimum then
		return false, T(api, player, "Too fast!")
	end
	session.Moves += 1
	session.Rounds = #sequence
	if session.Rounds >= session.GameRules.MaxRounds then
		return true, { Round = session.Rounds, Done = true, Result = simonEnd(player, data, api, session) }
	end
	table.insert(sequence, randomInt(1, session.Rules.Pads))
	session.SentAt = now(api)
	return true, { Round = session.Rounds, Sequence = table.clone(sequence) }
end

function Simon.Finish(player, data, api, session, _arg)
	return true, simonEnd(player, data, api, session)
end

----------------------------------------------------------------------
-- 🔨 Tape-taupe (programme des taupes = Solo_Logic.WhackSchedule(Seed))
--   start  -> { Seed, Holes, Duration }
--   finish { Token, Hits = { index dans le programme, ... } } (après Duration s)
----------------------------------------------------------------------

local Whack = {}

function Whack.Start(session, reply)
	local gameRules = session.GameRules
	session.Seed = randomInt(1, 2147483646)
	reply.Seed = session.Seed
	reply.Holes = gameRules.Holes
	reply.Duration = gameRules.Duration
end

function Whack.Finish(player, data, api, session, arg)
	local gameRules = session.GameRules
	local elapsed = now(api) - session.Started
	local schedule, maxScore = Logic.WhackSchedule(session.Seed, session.Rules, gameRules.Holes, gameRules.Duration)
	local hits = type(arg.Hits) == "table" and arg.Hits or {}
	local score, counted = Logic.WhackScore(schedule, hits, elapsed)
	session.Moves += counted
	if elapsed < gameRules.Duration - 1.5 then
		-- partie arrêtée avant la fin : pas de victoire
		return true, conclude(player, data, api, session, { Stars = 0, Score = score, Played = counted > 0 })
	end
	local stars = Logic.Stars("WhackAMole", session.Rules, { Score = score, Max = maxScore })
	return true, conclude(player, data, api, session, { Stars = stars, Score = score, Played = true })
end

----------------------------------------------------------------------
-- 🐍 Snake (rejoué avec Solo_Logic.SnakeReplay)
--   start  -> { Seed, Cols, Rows, Tick, Wrap }
--   finish { Token, Turns = { tick1, dir1, tick2, dir2, ... }, Ticks = pas joués }
----------------------------------------------------------------------

local Snake = {}

function Snake.Start(session, reply)
	local rules = session.Rules
	session.Seed = randomInt(1, 2147483646)
	reply.Seed = session.Seed
	reply.Cols = rules.Cols
	reply.Rows = rules.Rows
	reply.Tick = rules.Tick
	reply.Wrap = rules.Wrap
end

function Snake.Finish(player, data, api, session, arg)
	local gameRules = session.GameRules
	local maxTicks = gameRules.MaxTicks
	local turns = {}
	if type(arg.Turns) == "table" then
		local last = 0
		for k = 1, math.min(#arg.Turns, 12000), 2 do
			local tick = int(arg.Turns[k], 1, maxTicks)
			local dir = int(arg.Turns[k + 1], 1, 4)
			if not tick or not dir or tick <= last then
				break -- journal abîmé : on garde le début
			end
			last = tick
			table.insert(turns, tick)
			table.insert(turns, dir)
		end
	end
	local ticks = int(arg.Ticks, 0, maxTicks) or 0
	local score, played, minDuration = Logic.SnakeReplay(session.Seed, session.Rules, turns, ticks, maxTicks)
	session.Moves += played
	local elapsed = now(api) - session.Started
	local stars = Logic.Stars("Snake", session.Rules, { Score = score })
	local metrics = { Stars = stars, Score = score, Played = played > 0 }
	if elapsed < minDuration * 0.8 - 1 then
		metrics.Rejected = "Too fast! This run can't be rewarded."
	end
	return true, conclude(player, data, api, session, metrics)
end

----------------------------------------------------------------------
-- 🔢 2048 (rejoué avec Solo_Logic.G2048Replay)
--   start  -> { Seed, Size, Target }
--   finish { Token, Moves = "URDL..." (coups qui ont bougé) }
----------------------------------------------------------------------

local G2048 = {}

function G2048.Start(session, reply)
	session.Seed = randomInt(1, 2147483646)
	reply.Seed = session.Seed
	reply.Size = session.GameRules.Size
	reply.Target = session.Rules.Target
end

function G2048.Finish(player, data, api, session, arg)
	local gameRules = session.GameRules
	local moves = arg.Moves
	if type(moves) ~= "string" or #moves > gameRules.MaxMoves + 16 then
		moves = ""
	end
	local state, played = Logic.G2048Replay(session.Seed, session.Rules, gameRules.Size, moves, gameRules.MaxMoves)
	session.Moves += played
	local elapsed = now(api) - session.Started
	local stars = Logic.Stars("Game2048", session.Rules, { MaxTile = state.MaxTile })
	local metrics = { Stars = stars, Score = state.Score, Played = played > 0 }
	if elapsed + 1 < played * gameRules.MinMoveSeconds then
		metrics.Rejected = "Too fast! This run can't be rewarded."
	end
	local result = conclude(player, data, api, session, metrics)
	result.MaxTile = state.MaxTile
	return true, result
end

----------------------------------------------------------------------
-- Routage
----------------------------------------------------------------------

local HANDLERS = {
	Minesweeper = Minesweeper,
	Memory = Memory,
	Simon = Simon,
	WhackAMole = Whack,
	Snake = Snake,
	Game2048 = G2048,
}

-- Abandon silencieux de la partie en cours (nouvelle partie lancée)
local function dropSession(player, data, api)
	local session = sessions[player]
	if session and not session.Done then
		conclude(player, data, api, session, { Stars = 0, Score = 0, Lower = true })
	end
	sessions[player] = nil
end

local function activeSession(player, api, arg)
	local session = sessions[player]
	if not session or type(arg) ~= "table" or arg.Token ~= session.Token then
		return nil, T(api, player, "This game is over. Start a new one!")
	end
	if now(api) - session.Started > Logic.SessionTimeout then
		sessions[player] = nil
		return nil, T(api, player, "This game is over. Start a new one!")
	end
	return session, nil
end

local function dispatch(player, data, action: string, arg, api)
	if action == "solo:info" then
		local best = table.clone(soloData(data).Best)
		return true, { Best = best }
	end

	if action == "solo:start" then
		if type(arg) ~= "table" then
			return false, T(api, player, "Invalid request")
		end
		local gameRules, rules = Logic.GetRules(arg.Game, arg.Difficulty)
		local handler = HANDLERS[arg.Game]
		if not gameRules or not handler then
			return false, T(api, player, "Unknown game")
		end
		dropSession(player, data, api)
		local session = newSession(player, arg.Game, arg.Difficulty, gameRules, rules, api)
		local reply = { Token = session.Token, Game = session.Game, Difficulty = session.Difficulty }
		handler.Start(session, reply, api)
		reply.Best = soloData(data).Best[bestKey(session)]
		return true, reply
	end

	if action == "solo:move" then
		local session, message = activeSession(player, api, arg)
		if not session then
			return false, message
		end
		local handler = HANDLERS[session.Game]
		if not handler.Move then
			return false, T(api, player, "Invalid move")
		end
		return handler.Move(player, data, api, session, arg)
	end

	if action == "solo:finish" then
		local session, message = activeSession(player, api, arg)
		if not session then
			return false, message
		end
		return HANDLERS[session.Game].Finish(player, data, api, session, arg)
	end

	return false, T(api, player, "Invalid request")
end

function SoloGames.Handle(player, data, action, arg, api)
	if type(api) ~= "table" then
		return false, "Invalid request"
	end
	if type(action) ~= "string" or type(data) ~= "table" or player == nil then
		return false, T(api, player, "Invalid request")
	end
	resolveModules()
	if not Logic then
		return false, T(api, player, "Arcade unavailable, try again later")
	end
	local ok, success, result = pcall(dispatch, player, data, action, arg, api)
	if not ok then
		warn("[SoloGames] " .. tostring(action) .. " : " .. tostring(success))
		return false, T(api, player, "Something went wrong")
	end
	return success, result
end

return SoloGames
