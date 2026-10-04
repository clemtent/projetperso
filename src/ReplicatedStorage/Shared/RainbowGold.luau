--[[
	RainbowGold (ModuleScript)
	Emplacement : ReplicatedStorage > Shared > RainbowGold

	v11 (REALISM11) 🌈 Règles PURES de l'arc-en-ciel et du 🍀 pot d'or.
	Aucune Instance, aucun service : seulement Config et WorldLayout.
	Partagé par le serveur (RainbowService : où est le pot, qui l'a atteint,
	récompense), le client (Weather3D : l'arc ; PotOfGold : le pot, les
	pièces) et les tests (tests/rainbow_tests.py).

	1) Horloge de la météo (déplacée ici depuis Weather3D pour que le
	   SERVEUR et tous les clients aient EXACTEMENT les mêmes épisodes) :
	   le temps (heure du serveur, workspace:GetServerTimeNow()) est découpé
	   en épisodes de 10 min tirés au sort (hachage entier 32 bits exact) :
	   Clear 30 % · Cloudy 22 % · Showers 22 % · Rain 16 % · Storm 10 %
	   (jamais deux orages de suite). Weather3D.KindOf / .Hash délèguent ici.
	2) L'arc-en-ciel : à la fin des averses / de la pluie / de l'orage
	   (éclaircie). RainbowGold.Amount(kind, phase) = intensité 0..1 (montée
	   douce, plateau, fondu) ; RainbowGold.Event(t) = l'arc-en-ciel en cours
	   (Id = n° de l'épisode, StartAt / EndAt, Open = le pot peut être
	   atteint). Environ 3 arcs-en-ciel par heure, ~2 à 4 min chacun.
	3) Le pot d'or : le PIED de l'arc touche le sol en ville, à un endroit
	   accessible : sur un TROTTOIR (avenues, ceinture, centre, rues des
	   quartiers ; jamais dans un bâtiment) :
	   RainbowGold.Candidates(count) = liste de places (repère ville),
	   RainbowGold.Order(id, n) = ordre d'essai (le serveur prend la 1re
	   place libre : sol plat au bon niveau, pas d'eau, pas de toit).
	4) Récompense (serveur) : les MaxWinners premiers joueurs qui restent
	   Dwell s au pied de l'arc (rayon ClaimRadius) gagnent des SECONDES de
	   production (1er 240 s, 2e 150 s, 3e 100 s ; minimum MinReward),
	   DailyRewarded pots payés par jour au plus, un seul gain par
	   arc-en-ciel, refus après un "saut" (téléportation) récent.
	   RainbowGold.MaxNetMultiplier(h) = gain net maximal (test d'économie).

	API (pure) :
	  RainbowGold.EPISODE, .KINDS, .CONFIG
	  RainbowGold.Hash(n) -> [0, 1)
	  RainbowGold.KindOf(index) -> "Clear" | "Cloudy" | "Showers" | "Rain" | "Storm"
	  RainbowGold.Amount(kind, phase) -> 0..1
	  RainbowGold.Event(t) -> Event?          { Id, Kind, StartAt, EndAt, Amount, Open }
	  RainbowGold.NextEvent(t) -> Event?      (prochain arc-en-ciel, au plus 6 h plus tard)
	  RainbowGold.Candidates(count) -> { Spot } { X, Z, Y, Zone }  (repère ville, cache)
	  RainbowGold.Order(id, n) -> { number }  (indices distincts, ≤ CONFIG.Tries)
	  RainbowGold.Side(id) -> 1 | -1          (côté où part l'arc depuis le pot)
	  RainbowGold.InReach(dx, dy, dz) -> boolean
	  RainbowGold.IsJump(distance, dt) -> boolean
	  RainbowGold.Production(stats) -> number
	  RainbowGold.Reward(stats, place, rewardedToday) -> (montant, secondes, plafonné?)
	  RainbowGold.MaxNetMultiplier(heuresParJour?) -> number
	  RainbowGold.Today(now) ; RainbowGold.SanitizeData(raw, today)
]]

local Config = require(script.Parent.Config)
local WorldLayout = require(script.Parent.WorldLayout)

local RainbowGold = {}

local EPISODE = 600 -- (s) un épisode de météo (identique à Weather3D)
RainbowGold.EPISODE = EPISODE
local KINDS = { "Clear", "Cloudy", "Showers", "Rain", "Storm" }
local WEIGHTS = { 0.30, 0.22, 0.22, 0.16, 0.10 }
RainbowGold.KINDS = KINDS
RainbowGold.WEIGHTS = WEIGHTS

RainbowGold.CONFIG = {
	OpenAmount = 0.12, -- le pot peut être atteint dès que l'arc est à 12 %
	ClaimRadius = 11, -- (studs, à plat) autour du pot
	ClaimHeight = 14, -- (studs) écart vertical toléré
	Dwell = 0.8, -- (s) rester au pied de l'arc
	MaxWinners = 3,
	Seconds = { 240, 150, 100 }, -- secondes de production selon l'ordre d'arrivée
	MinReward = 500,
	DailyRewarded = 6, -- pots payés par jour (UTC)
	JumpSpeed = 320, -- (studs / s) au-delà : saut / téléportation (voitures ≤ 90)
	JumpHold = 4, -- (s) pas de gain juste après un saut
	Tries = 30, -- places essayées par arc-en-ciel
	Spacing = 70, -- (studs) entre deux places candidates le long d'un trottoir
	ArcRadius = 300, -- (studs) rayon de l'arc (rendu client)
}
local CFG = RainbowGold.CONFIG

----------------------------------------------------------------------
-- Hasard déterministe (entiers 32 bits exacts : pas de math.sin / random)
----------------------------------------------------------------------

local TWO32 = 4294967296

-- (a * b) mod 2^32, exact en double (moitiés de 16 bits)
local function mul32(a: number, b: number): number
	local aHi = math.floor(a / 65536)
	local aLo = a % 65536
	return ((aHi * b % 65536) * 65536 + aLo * b) % TWO32
end

-- Hachage d'un entier (peut être négatif ou grand) -> [0, 1)
local function hash01(n: number): number
	local h = math.floor(n) % TWO32
	h = bit32.bxor(h, bit32.rshift(h, 16))
	h = mul32(h, 0x45D9F3B)
	h = bit32.bxor(h, bit32.rshift(h, 16))
	h = mul32(h, 0x45D9F3B)
	h = bit32.bxor(h, bit32.rshift(h, 16))
	return h / TWO32
end
RainbowGold.Hash = hash01

-- Tirage brut d'un épisode (sans la règle "pas deux orages")
local function rawKind(index: number): string
	local r = hash01(index * 7 + 1013)
	local acc = 0
	for i, w in ipairs(WEIGHTS) do
		acc += w
		if r < acc then
			return KINDS[i]
		end
	end
	return KINDS[1]
end

function RainbowGold.KindOf(index: number): string
	local kind = rawKind(index)
	if kind == "Storm" and rawKind(index - 1) == "Storm" then
		return "Rain"
	end
	return kind
end

----------------------------------------------------------------------
-- Intensité de l'arc-en-ciel (éclaircie de fin d'épisode)
----------------------------------------------------------------------

local function clamp01(x: number): number
	return math.clamp(x, 0, 1)
end

local function smooth(x: number): number
	x = clamp01(x)
	return x * x * (3 - 2 * x)
end

-- (montée a0 -> a1, plateau, fondu b0 -> b1 ; phase de l'épisode 0..1)
-- Fondu fini AVANT la fin de l'épisode : l'épisode suivant part de 0.
local WINDOWS: { [string]: { number } } = {
	Showers = { 0.60, 0.66, 0.93, 0.99 },
	Rain = { 0.70, 0.76, 0.93, 0.99 },
	Storm = { 0.74, 0.80, 0.93, 0.99 },
}
RainbowGold.WINDOWS = WINDOWS

function RainbowGold.Amount(kind: string, phase: number): number
	local w = WINDOWS[kind]
	if not w then
		return 0
	end
	local up = smooth((phase - w[1]) / (w[2] - w[1]))
	local down = 1 - smooth((phase - w[3]) / (w[4] - w[3]))
	return clamp01(up * down)
end

export type Event = {
	Id: number,
	Kind: string,
	StartAt: number,
	EndAt: number,
	Amount: number,
	Open: boolean,
}

local function eventOf(index: number, t: number): Event?
	local kind = RainbowGold.KindOf(index)
	local w = WINDOWS[kind]
	if not w then
		return nil
	end
	local base = index * EPISODE
	local phase = (t - base) / EPISODE
	local amount = RainbowGold.Amount(kind, phase)
	return {
		Id = index,
		Kind = kind,
		StartAt = base + w[1] * EPISODE,
		EndAt = base + w[4] * EPISODE,
		Amount = amount,
		Open = amount >= CFG.OpenAmount,
	}
end

-- L'arc-en-ciel de l'épisode en cours (nil : pas d'éclaircie dans cet épisode,
-- ou pas encore / plus : Amount = 0)
function RainbowGold.Event(t: number): Event?
	if type(t) ~= "number" or t ~= t then
		return nil
	end
	local index = math.floor(t / EPISODE)
	local e = eventOf(index, t)
	if e and t >= e.StartAt and t <= e.EndAt then
		return e
	end
	return nil
end

-- Prochain arc-en-ciel (début après t ; au plus 36 épisodes = 6 h)
function RainbowGold.NextEvent(t: number): Event?
	local index = math.floor(t / EPISODE)
	for k = 0, 36 do
		local e = eventOf(index + k, t)
		if e and e.StartAt > t then
			return e
		end
	end
	return nil
end

----------------------------------------------------------------------
-- Places du pot (repère ville : x, z depuis le centre de la place)
----------------------------------------------------------------------

export type Spot = { X: number, Z: number, Y: number, Zone: string }

local spotCache: { [number]: { Spot } } = {}

--[[
	Places candidates : sur les TROTTOIRS de toute la ville (avenues, ceinture,
	boulevard du centre, rues des quartiers ; pas l'autoroute, ni les
	bretelles, ni les ponts) : toujours accessibles à pied, jamais dans un
	bâtiment (les bâtiments du client ne sont pas connus du serveur, le
	trottoir est le seul sol garanti libre). Tous les Spacing studs, des
	deux côtés, loin des carrefours (passages piétons), hors des lieux
	bâtis du centre (mairie, scène, fête foraine...).
]]
function RainbowGold.Candidates(count: number?): { Spot }
	local n = WorldLayout.PlotCount(count or 8)
	local cached = spotCache[n]
	if cached then
		return cached
	end
	local list: { Spot } = {}
	local step = CFG.Spacing
	local graph = WorldLayout.RoadGraph(n)
	local zones = WorldLayout.Facilities(n)
	local function busy(x: number, z: number): boolean
		for _, zone in ipairs(zones) do
			local blocked = zone.Kind == "Facility" or (zone.Kind == "Downtown" and zone.Id ~= "Downtown" and zone.Id ~= "Plaza")
			if blocked and WorldLayout.InZone(zone, x, z, 4) then
				return true
			end
		end
		return math.sqrt(x * x + z * z) < WorldLayout.PLAZA_R + 6
	end
	local function onCarriageway(x: number, z: number): boolean
		for _, e in ipairs(graph.Edges) do
			if WorldLayout.EdgeDistance(e, x, z) < e.Width / 2 + 1 then
				return true
			end
		end
		return false
	end
	local function nearNode(x: number, z: number): boolean
		for _, node in ipairs(graph.NodeList) do
			local dx, dz = node.X - x, node.Z - z
			if dx * dx + dz * dz < 30 * 30 then
				return true
			end
		end
		return false
	end
	for _, e in ipairs(graph.Edges) do
		if (e.Sidewalk or 0) >= 3 and not e.Highway and not e.Ramp and not e.Bridge and #e.Points >= 2 then
			local length = e.Length or 0
			local half = e.Width / 2 + e.Sidewalk / 2
			local s0 = 30
			while s0 <= length - 30 do
				local x, y, z, dx, dz = WorldLayout.PointAlong(e.Points, s0)
				local m = math.sqrt(dx * dx + dz * dz)
				if m > 1e-6 then
					local nx, nz = -dz / m, dx / m
					for _, side in ipairs({ 1, -1 }) do
						local px, pz = x + nx * half * side, z + nz * half * side
						if not onCarriageway(px, pz) and not WorldLayout.OnPlot(n, px, pz, 0) and not busy(px, pz) and not nearNode(px, pz)
							and math.max(math.abs(px), math.abs(pz)) < WorldLayout.TownRadius(n) - 30 then
							table.insert(list, { X = px, Z = pz, Y = y, Zone = e.Kind })
						end
					end
				end
				s0 += step
			end
		end
	end
	spotCache[n] = list
	return list
end

-- Ordre d'essai des places pour l'arc-en-ciel `id` (indices distincts)
function RainbowGold.Order(id: number, n: number): { number }
	local out: { number } = {}
	if n <= 0 then
		return out
	end
	local used: { [number]: boolean } = {}
	local want = math.min(n, CFG.Tries)
	local k = 0
	while #out < want and k < want * 8 do
		local index = math.floor(hash01(id * 131 + k * 17 + 29) * n) + 1
		if not used[index] then
			used[index] = true
			table.insert(out, index)
		end
		k += 1
	end
	-- (complété dans l'ordre si le hasard tourne en rond)
	local i = 1
	while #out < want and i <= n do
		if not used[i] then
			used[i] = true
			table.insert(out, i)
		end
		i += 1
	end
	return out
end

function RainbowGold.Side(id: number): number
	return hash01(id * 3 + 7) < 0.5 and -1 or 1
end

----------------------------------------------------------------------
-- Atteindre le pot (serveur)
----------------------------------------------------------------------

function RainbowGold.InReach(dx: number, dy: number, dz: number): boolean
	if dx ~= dx or dy ~= dy or dz ~= dz then
		return false
	end
	return dx * dx + dz * dz <= CFG.ClaimRadius * CFG.ClaimRadius and math.abs(dy) <= CFG.ClaimHeight
end

-- Déplacement trop rapide entre deux relevés = saut / téléportation
function RainbowGold.IsJump(distance: number, dt: number): boolean
	if distance ~= distance or distance == math.huge then
		return true
	end
	if dt <= 0 then
		return distance > 4
	end
	return distance > 6 and distance / dt > CFG.JumpSpeed
end

----------------------------------------------------------------------
-- Récompense
----------------------------------------------------------------------

local function finite(v: any, default: number): number
	if type(v) ~= "number" or v ~= v or v == math.huge or v == -math.huge then
		return default
	end
	return v
end
RainbowGold.Finite = finite

-- Production estimée (Dopamine / s), comme les courses
function RainbowGold.Production(stats: any): number
	local perSecond = finite(stats and stats.PerSecond, 0)
	local click = finite(stats and stats.ClickValue, 0)
	local cps = (Config.Rewards and Config.Rewards.EstimatedClicksPerSecond) or 3
	return math.max(0, perSecond + click * cps)
end

-- place = ordre d'arrivée (1 = le premier) ; rewardedToday = pots déjà payés aujourd'hui
function RainbowGold.Reward(stats: any, place: number, rewardedToday: number?): (number, number, boolean)
	local p = math.floor(finite(place, 0))
	local seconds = CFG.Seconds[p]
	if not seconds then
		return 0, 0, false
	end
	if finite(rewardedToday, 0) >= CFG.DailyRewarded then
		return 0, 0, true
	end
	local amount = math.floor(math.max(CFG.MinReward, RainbowGold.Production(stats) * seconds))
	local maxValue = (Config.Game and Config.Game.MaxDopamine) or 1e300
	return math.min(amount, maxValue), seconds, false
end

-- Gain net maximal d'un joueur qui arrive PREMIER à tous les pots payés
-- d'une journée de `sessionHours` h de jeu (défaut 2 h) : multiplicateur
-- moyen de la production (borne du test d'économie)
function RainbowGold.MaxNetMultiplier(sessionHours: number?): number
	local perDay = CFG.Seconds[1] * CFG.DailyRewarded
	local hours = math.max(1, finite(sessionHours, 2))
	return 1 + perDay / (hours * 3600)
end

function RainbowGold.Today(now: number): number
	return math.floor(finite(now, 0) / 86400)
end

-- data.Rainbow propre : { Day, Rewarded, Pots, Firsts, LastId }
function RainbowGold.SanitizeData(raw: any, today: number): any
	local src = if type(raw) == "table" then raw else {}
	local function count(v: any): number
		return math.max(0, math.floor(finite(v, 0)))
	end
	local day = count(src.Day)
	local rewarded = count(src.Rewarded)
	if day ~= today then
		day, rewarded = today, 0
	end
	return {
		Day = day,
		Rewarded = math.min(rewarded, CFG.DailyRewarded),
		Pots = count(src.Pots),
		Firsts = count(src.Firsts),
		LastId = math.floor(finite(src.LastId, -1)),
	}
end

return RainbowGold
