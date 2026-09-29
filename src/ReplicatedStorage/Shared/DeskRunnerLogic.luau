--[[
	DeskRunnerLogic (ModuleScript)
	Emplacement : ReplicatedStorage > Shared > DeskRunnerLogic

	v9.8 🎮 Logique PURE du "Desk Runner", le jeu de course façon Subway
	jouable sur l'écran du bureau gamer (Client > World > DeskGames). Aucune
	instance, aucun service : la MÊME simulation tourne sur le client (le
	jeu) et sur le serveur (Services > Arcade > SoloGames : rejeu de la
	partie, anti-triche comme le Snake de l'arcade).

	Monde (unités = "mètres" du jeu) :
	  - 3 voies (-1, 0, 1) ; le coureur est à la distance D de la piste ;
	  - obstacles posés à une position absolue P de la piste :
	      "Train"  : bloque la voie (on change de voie) ;
	      "Low"    : barrière basse (on saute) ;
	      "High"   : portique haut (on roule dessous) ;
	      "Coin"   : pièce (ramassée si on passe dans la voie) ;
	  - pas fixe de TICK secondes ; la vitesse augmente avec le temps.
	Entrées (une par pas au plus) : 1 = gauche, 2 = droite, 3 = saut, 4 = roulade.
	Score = distance + 10 x pièces.

	API :
	  DeskRunnerLogic.New(seed) -> State
	  DeskRunnerLogic.Input(state, action) -> boolean   (appliquée au pas suivant)
	  DeskRunnerLogic.Step(state) -> string?            ("crash", "coin" ou nil)
	  DeskRunnerLogic.Height(state) -> number           (hauteur du saut)
	  DeskRunnerLogic.Replay(seed, inputs, ticks) -> (score, coins, distance, played, minDuration)
	  DeskRunnerLogic.Stars(score) -> (stars, progress)
	  DeskRunnerLogic.Rules / GameRules                 (règles "arcade" : difficulté Normal)
]]

local DeskRunnerLogic = {}

local TICK = 1 / 30
local BASE_SPEED = 11 -- m/s au départ
local MAX_SPEED = 24
local SPEED_RAMP = 0.12 -- m/s gagnés par seconde
local JUMP_TICKS = 19 -- ~0,63 s en l'air
local JUMP_HEIGHT = 1.6
local CLEAR_HEIGHT = 0.75 -- hauteur pour passer une barrière basse
local ROLL_TICKS = 18 -- ~0,6 s au ras du sol
local HALF_BODY = 0.4 -- demi-profondeur du coureur
local AHEAD = 95 -- génération jusqu'à D + AHEAD
local BEHIND = 12 -- nettoyage derrière le coureur
local TRAIN_LEN = 9
local BAR_LEN = 0.6
local COIN_POINTS = 10
local MAX_TICKS = 18000 -- 10 minutes

DeskRunnerLogic.TICK = TICK
DeskRunnerLogic.MAX_TICKS = MAX_TICKS
DeskRunnerLogic.JUMP_HEIGHT = JUMP_HEIGHT
DeskRunnerLogic.TRAIN_LEN = TRAIN_LEN
DeskRunnerLogic.COIN_POINTS = COIN_POINTS
DeskRunnerLogic.Actions = { Left = 1, Right = 2, Jump = 3, Roll = 4 }

-- Règles au format de l'arcade (Solo_Logic.Games / SoloGames)
DeskRunnerLogic.GameRules = {
	Name = "Desk Runner",
	Icon = "🏃",
	MaxTicks = MAX_TICKS,
	Hidden = true, -- jamais listé dans le panneau Arcade (joué au bureau gamer)
	Difficulties = {
		Normal = { Thresholds = { 400, 1000, 2000 } },
	},
}
DeskRunnerLogic.Rules = DeskRunnerLogic.GameRules.Difficulties.Normal

----------------------------------------------------------------------
-- Hasard déterministe (xorshift32, identique client / serveur)
----------------------------------------------------------------------

type Rng = { State: number }

local function newRng(seed: number): Rng
	local state = math.floor(tonumber(seed) or 1) % 4294967296
	if state ~= state or state <= 0 then
		state = 2463534242
	end
	local rng = { State = state }
	for _ = 1, 6 do
		local s = rng.State
		s = bit32.bxor(s, bit32.lshift(s, 13))
		s = bit32.bxor(s, bit32.rshift(s, 17))
		s = bit32.bxor(s, bit32.lshift(s, 5))
		rng.State = s
	end
	return rng
end

local function nextFloat(rng: Rng): number
	local s = rng.State
	s = bit32.bxor(s, bit32.lshift(s, 13))
	s = bit32.bxor(s, bit32.rshift(s, 17))
	s = bit32.bxor(s, bit32.lshift(s, 5))
	rng.State = s
	return s / 4294967296
end

local function nextInt(rng: Rng, a: number, b: number): number
	if b <= a then
		return a
	end
	return a + math.floor(nextFloat(rng) * (b - a + 1))
end

----------------------------------------------------------------------
-- État
----------------------------------------------------------------------

export type Obstacle = { Id: number, Kind: string, Lane: number, P: number, Len: number, Taken: boolean, Y: number }

export type State = {
	Rng: Rng,
	Tick: number,
	Distance: number,
	Speed: number,
	Lane: number,
	JumpTick: number, -- pas écoulés depuis le début du saut (-1 = au sol)
	RollTick: number, -- pas restants de roulade (0 = debout)
	Coins: number,
	Score: number,
	Alive: boolean,
	Pending: number?, -- entrée à appliquer au prochain pas
	Obstacles: { Obstacle },
	NextRow: number, -- position de la prochaine rangée d'obstacles
	NextId: number,
	Crash: string?, -- cause du choc ("Train" | "Low" | "High")
	Row: number, -- rangées générées
}

function DeskRunnerLogic.New(seed: number): State
	return {
		Rng = newRng(seed),
		Tick = 0,
		Distance = 0,
		Speed = BASE_SPEED,
		Lane = 0,
		JumpTick = -1,
		RollTick = 0,
		Coins = 0,
		Score = 0,
		Alive = true,
		Pending = nil,
		Obstacles = {},
		NextRow = 34, -- quelques mètres tranquilles au départ
		NextId = 0,
		Crash = nil,
		Row = 0,
	}
end

local function add(s: State, kind: string, lane: number, p: number, len: number, y: number?)
	s.NextId += 1
	table.insert(s.Obstacles, { Id = s.NextId, Kind = kind, Lane = lane, P = p, Len = len, Taken = false, Y = y or 0 })
end

-- Une rangée : au moins une voie praticable ; trains, barrières, pièces
local function generateRow(s: State)
	local rng = s.Rng
	local p = s.NextRow
	s.Row += 1
	local early = s.Row <= 3
	local kinds = { "Free", "Free", "Free" }
	-- trains (jamais sur les 3 voies ; pas dans les 3 premières rangées)
	local trains = 0
	if not early then
		local roll = nextFloat(rng)
		trains = roll < 0.3 and 0 or (roll < 0.78 and 1 or 2)
	end
	local lanes = { -1, 0, 1 }
	for _ = 1, trains do
		local index = nextInt(rng, 1, #lanes)
		local lane = table.remove(lanes, index)
		kinds[lane + 2] = "Train"
	end
	-- barrières sur les voies restantes (une voie reste toujours libre de tout)
	local freeLane = lanes[nextInt(rng, 1, #lanes)]
	for _, lane in ipairs(lanes) do
		if lane ~= freeLane then
			local roll = nextFloat(rng)
			if roll < 0.42 then
				kinds[lane + 2] = "Low"
			elseif roll < 0.68 then
				kinds[lane + 2] = "High"
			end
		end
	end
	-- parfois la voie libre a aussi une barrière (il faut sauter / rouler)
	if not early and nextFloat(rng) < 0.35 then
		kinds[freeLane + 2] = nextFloat(rng) < 0.55 and "Low" or "High"
	end
	for index, kind in ipairs(kinds) do
		local lane = index - 2
		if kind == "Train" then
			add(s, "Train", lane, p, TRAIN_LEN)
		elseif kind == "Low" or kind == "High" then
			add(s, kind, lane, p, BAR_LEN)
		end
	end
	-- pièces : une file dans une voie sans train (en arc au-dessus d'une barrière basse)
	local coinLanes = {}
	for index, kind in ipairs(kinds) do
		if kind ~= "Train" then
			table.insert(coinLanes, index - 2)
		end
	end
	if #coinLanes > 0 and nextFloat(rng) < 0.8 then
		local lane = coinLanes[nextInt(rng, 1, #coinLanes)]
		local count = nextInt(rng, 3, 6)
		local overBar = kinds[lane + 2] == "Low"
		for k = 1, count do
			local cp = p - (count - k) * 1.8 + (overBar and (count / 2) * 1.8 or -2)
			local y = 0
			if overBar then
				local t = (k - 0.5) / count
				y = 4 * t * (1 - t) * 1.2
			end
			add(s, "Coin", lane, cp, 0, y)
		end
	end
	-- écart jusqu'à la rangée suivante : plus on va vite, plus il est grand
	s.NextRow = p + 15 + s.Speed * 0.42 + nextFloat(rng) * 6
end

function DeskRunnerLogic.Height(s: State): number
	if s.JumpTick < 0 then
		return 0
	end
	local t = math.clamp(s.JumpTick / JUMP_TICKS, 0, 1)
	return 4 * JUMP_HEIGHT * t * (1 - t)
end

function DeskRunnerLogic.Input(s: State, action: any): boolean
	if not s.Alive or type(action) ~= "number" or action < 1 or action > 4 or action % 1 ~= 0 then
		return false
	end
	s.Pending = action
	return true
end

local function apply(s: State, action: number)
	if action == 1 then
		s.Lane = math.max(-1, s.Lane - 1)
	elseif action == 2 then
		s.Lane = math.min(1, s.Lane + 1)
	elseif action == 3 then
		if s.JumpTick < 0 then
			s.JumpTick = 0
			s.RollTick = 0
		end
	elseif action == 4 then
		-- roulade (en l'air : on redescend tout de suite)
		s.JumpTick = -1
		s.RollTick = ROLL_TICKS
	end
end

-- Un pas de simulation ; renvoie "crash", "coin" ou nil
function DeskRunnerLogic.Step(s: State): string?
	if not s.Alive then
		return "crash"
	end
	s.Tick += 1
	local pending = s.Pending
	if pending then
		s.Pending = nil
		apply(s, pending)
	end
	local seconds = s.Tick * TICK
	s.Speed = math.min(MAX_SPEED, BASE_SPEED + SPEED_RAMP * seconds)
	s.Distance += s.Speed * TICK
	if s.JumpTick >= 0 then
		s.JumpTick += 1
		if s.JumpTick >= JUMP_TICKS then
			s.JumpTick = -1
		end
	end
	if s.RollTick > 0 then
		s.RollTick -= 1
	end
	while s.NextRow < s.Distance + AHEAD do
		generateRow(s)
	end
	local height = DeskRunnerLogic.Height(s)
	local event: string? = nil
	local d = s.Distance
	local swept = s.Speed * TICK -- (balayage : rien ne passe "entre" deux pas)
	for index = #s.Obstacles, 1, -1 do
		local o = s.Obstacles[index]
		local rel = o.P - d
		if rel + o.Len < -BEHIND then
			table.remove(s.Obstacles, index)
		elseif o.Lane == s.Lane and rel < HALF_BODY and rel + o.Len + swept > -HALF_BODY then
			if o.Kind == "Coin" then
				if not o.Taken and math.abs(height - o.Y) < 1.1 then
					o.Taken = true
					s.Coins += 1
					event = event or "coin"
				end
			elseif o.Kind == "Train" or (o.Kind == "Low" and height < CLEAR_HEIGHT) or (o.Kind == "High" and s.RollTick <= 0) then
				s.Alive = false
				s.Crash = o.Kind
				event = "crash"
				break
			end
		end
	end
	s.Score = math.floor(s.Distance) + s.Coins * COIN_POINTS
	return event
end

-- Rejoue une partie : inputs = { tick1, action1, tick2, action2, ... } (ticks croissants)
function DeskRunnerLogic.Replay(seed: number, inputs: { number }, ticks: number): (number, number, number, number, number)
	local s = DeskRunnerLogic.New(seed)
	local limit = math.clamp(math.floor(tonumber(ticks) or 0), 0, MAX_TICKS)
	local k = 1
	local count = type(inputs) == "table" and #inputs or 0
	while s.Alive and s.Tick < limit do
		local nextTick = s.Tick + 1
		while k + 1 <= count and inputs[k] == nextTick do
			DeskRunnerLogic.Input(s, inputs[k + 1])
			k += 2
		end
		-- (entrée d'un pas déjà passé : journal abîmé, on l'ignore)
		while k + 1 <= count and inputs[k] < nextTick do
			k += 2
		end
		DeskRunnerLogic.Step(s)
	end
	return s.Score, s.Coins, s.Distance, s.Tick, s.Tick * TICK
end

function DeskRunnerLogic.Stars(score: number): (number, number)
	local thresholds = DeskRunnerLogic.Rules.Thresholds
	local stars = 0
	for index, threshold in ipairs(thresholds) do
		if score >= threshold then
			stars = index
		end
	end
	local progress = stars == 0 and math.clamp(score / thresholds[1], 0, 1) or 1
	return stars, progress
end

return DeskRunnerLogic
