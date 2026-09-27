--[[
	MinigameService (ModuleScript)
	Emplacement : ServerScriptService > Services > MinigameService

	🕹️ Arcade (amélioration "Arcade", Feature "Minigames") : mini-jeux solo,
	🎟️ tickets, 🏆 trophées et duels entre joueurs du serveur. 100 % côté serveur.

	RemoteFunction "Arcade" (action, argument) -> (succès, résultat | message) :
	  - "solo:*"    : routé vers Services > Arcade > SoloGames.Handle(player, data,
	                  action, arg, api) (jeux solo, écrits à part ; chargé avec
	                  pcall : son absence ne casse jamais l'arcade) ;
	  - "lobby"     : joueurs du serveur qui ont l'arcade, invitations, duel en cours ;
	  - "invite"    : { Target = UserId, Game = Id, Stake = 🏆 trophées } ;
	  - "cancel" / "accept" / "decline" (Id d'invitation) ;
	  - "move"      : { Id = duel, Move = coup } ; "forfeit" (abandon) ;
	  - "buy"       : Id d'un objet de la boutique à tickets ; "badge" : équipe un badge.
	    Refus faute de tickets : (false, { Text, Missing = tickets manquants,
	    Currency = "Tickets" }) -> le client propose d'en acheter (NeedTickets).
	RemoteEvent "ArcadeEvent" (S -> C) : "invite", "inviteClosed", "duelStart",
	  "duelUpdate", "duelEnd" (payload = invitation ou état du duel VU par ce joueur).

	Deux monnaies (règles Roblox : on ne mise JAMAIS une monnaie achetable) :
	  - 🎟️ tickets (data.Tickets) : boutique à tickets. Gagnés en jouant
	    (plafond par jour) ou achetés en Robux (packs : MonetizationService
	    appelle GrantPurchasedTickets). Jamais misés ;
	  - 🏆 trophées (data.Trophies) : MISES des duels. Gagnés UNIQUEMENT en
	    jouant (victoires solo / duel récompensées, plafond par jour) + un
	    cadeau de bienvenue ; jamais achetables, jamais convertibles.

	Duels :
	  - invitation d'un joueur du serveur (pas soi-même), mise identique pour
	    les deux (en 🏆, vérifiée ici pour les DEUX joueurs), délai
	    d'expiration, refus, annulation ;
	  - à l'acceptation : les deux mises sont prises (séquestre), revérifiées ;
	  - état du jeu gardé ICI : coups validés (tour, case libre...), victoire
	    détectée ici (ArcadeConfig.Logic), temps par coup, durée max ;
	  - gagnant : les deux mises (x2, en 🏆) + Dopamine (secondes de
	    production) + tickets bonus + 1 🏆 bonus (le prix NE dépend PAS de la
	    mise) ; perdant : perd sa mise ; égalité : mises rendues ;
	  - déconnexion ou abandon : le joueur qui part perd ;
	  - anti-abus : limites de duels par jour contre le MÊME joueur (et
	    récompenses limitées), cadence des invitations, pas de duel contre soi.

	data.Arcade = { Day, DayTickets, DayTrophies, DayRewards = { [jeu] = n }, DayPairs = { [UserId] = n },
	  DayPairRewards = { [UserId] = n }, DayShop = { [objet] = n }, Best = { [jeu] = record },
	  Plays / Wins / Losses / Draws = { [jeu] = n }, Badges = { [id] = true }, Badge = id,
	  History = { dernier duel en premier ; K = "T" : mise en 🏆 }, TicketsEarned, TrophiesEarned,
	  TicketsBought, Welcomed, TrophyGift }
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Config = require(Shared.Config)
local Formulas = require(Shared.Formulas)
local Locale = require(Shared.Locale)
local NumberFormatter = require(Shared.NumberFormatter)
local Net = require(Shared.Net)
local ArcadeConfig = require(Shared.ArcadeConfig)
local RateLimiter = require(script.Parent.RateLimiter)

local MinigameService = {}

local services
local random = Random.new()
local Logic = ArcadeConfig.Logic
local DUELS = ArcadeConfig.Duels
local TICKETS = ArcadeConfig.Tickets
local TROPHIES = ArcadeConfig.Trophies
local SECONDS_PER_DAY = 86400
local HISTORY_SIZE = 8

local arcadeEvent: RemoteEvent? = nil

-- Joueurs dont les tickets / records ont changé pendant l'action en cours (état complet à renvoyer)
local changed: { [Player]: boolean } = {}

-- Invitations : [id] = { Id, From, To, Game, Stake, ExpiresAt }
local invites = {}
-- Duels en cours : [id] = duel ; [Player] = duel
local duels = {}
local duelOf: { [Player]: any } = {}
local lastInviteAt: { [Player]: number } = {}
local declinedAt: { [Player]: { [number]: number } } = {}
local nextId = 0

----------------------------------------------------------------------
-- Utilitaires
----------------------------------------------------------------------

local function isValidNumber(value): boolean
	return type(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge
end

local function T(player: Player, text: string, ...): string
	return services.GameService:T(player, text, ...)
end

local function newId(prefix: string): string
	nextId += 1
	return string.format("%s%d_%d", prefix, nextId, random:NextInteger(100, 999))
end

local function getData(player: Player)
	return services.DataService:GetData(player)
end

local function asTable(value)
	return type(value) == "table" and value or {}
end

-- Données d'arcade propres (sauvegarde abîmée corrigée) + remise à zéro des limites du jour
local function ensureArcade(data)
	local arcade = data.Arcade
	if type(arcade) ~= "table" then
		arcade = {}
		data.Arcade = arcade
	end
	if not isValidNumber(data.Tickets) or data.Tickets < 0 then
		data.Tickets = 0
	end
	data.Tickets = math.floor(math.min(data.Tickets, TICKETS.Max))
	if not isValidNumber(data.Trophies) or data.Trophies < 0 then
		data.Trophies = 0
	end
	data.Trophies = math.floor(math.min(data.Trophies, TROPHIES.Max))
	for _, key in ipairs({ "Best", "Plays", "Wins", "Losses", "Draws", "Badges", "History" }) do
		arcade[key] = asTable(arcade[key])
	end
	if type(arcade.Badge) ~= "string" or not arcade.Badges[arcade.Badge] or not ArcadeConfig.ShopById[arcade.Badge] then
		arcade.Badge = ""
	end
	for _, key in ipairs({ "TicketsEarned", "TrophiesEarned", "TicketsBought" }) do
		if not isValidNumber(arcade[key]) then
			arcade[key] = 0
		end
	end
	local day = math.floor(os.time() / SECONDS_PER_DAY)
	if arcade.Day ~= day then
		arcade.Day = day
		arcade.DayTickets = 0
		arcade.DayTrophies = 0
		arcade.DayRewards = {}
		arcade.DayPairs = {}
		arcade.DayPairRewards = {}
		arcade.DayShop = {}
	else
		arcade.DayTickets = isValidNumber(arcade.DayTickets) and arcade.DayTickets or 0
		arcade.DayTrophies = isValidNumber(arcade.DayTrophies) and arcade.DayTrophies or 0
		for _, key in ipairs({ "DayRewards", "DayPairs", "DayPairRewards", "DayShop" }) do
			arcade[key] = asTable(arcade[key])
		end
	end
	return arcade
end

local function hasArcade(player: Player): boolean
	local data = getData(player)
	return data ~= nil and services.GameService:IsReady(player) and Formulas.HasFeature(data, ArcadeConfig.Feature)
end

local function badgeIcon(data): string
	local arcade = data and data.Arcade
	local item = arcade and type(arcade.Badge) == "string" and ArcadeConfig.ShopById[arcade.Badge]
	return item and item.Icon or ""
end

local function playerInfo(player: Player)
	local data = getData(player)
	return {
		UserId = player.UserId,
		Name = player.DisplayName,
		User = player.Name,
		Badge = badgeIcon(data),
		Trophies = data and isValidNumber(data.Trophies) and math.floor(data.Trophies) or 0,
	}
end

local function fire(player: Player, kind: string, payload)
	if arcadeEvent and player.Parent == Players then
		arcadeEvent:FireClient(player, kind, payload)
	end
end

local function incr(map, key, amount: number?)
	map[key] = (tonumber(map[key]) or 0) + (amount or 1)
end

----------------------------------------------------------------------
-- Tickets, trophées, Dopamine, stats (aussi exposés aux jeux solo via `api`)
----------------------------------------------------------------------

-- Ajoute / retire des 🎟️ tickets SANS plafond du jour (achats en tickets, cadeau, packs Robux)
local function moveTickets(player: Player, amount: number): number
	local data = getData(player)
	if not data or not isValidNumber(amount) then
		return 0
	end
	ensureArcade(data)
	local before = data.Tickets
	data.Tickets = math.clamp(math.floor(before + amount), 0, TICKETS.Max)
	changed[player] = true
	return data.Tickets - before
end

-- Tickets GAGNÉS (récompenses) : plafonnés par jour. Renvoie le nombre vraiment donné.
local function grantTickets(player: Player, amount: number): number
	local data = getData(player)
	if not data then
		return 0
	end
	local arcade = ensureArcade(data)
	local granted = Logic.CappedGrant(amount, arcade.DayTickets, TICKETS.DailyCap)
	if granted <= 0 then
		return 0
	end
	granted = moveTickets(player, granted)
	arcade.DayTickets += granted
	arcade.TicketsEarned += granted
	return granted
end

-- Ajoute / retire des 🏆 trophées SANS plafond du jour (mises en séquestre, pots, remboursements, cadeau)
local function moveTrophies(player: Player, amount: number): number
	local data = getData(player)
	if not data or not isValidNumber(amount) then
		return 0
	end
	ensureArcade(data)
	local before = data.Trophies
	data.Trophies = math.clamp(math.floor(before + amount), 0, TROPHIES.Max)
	changed[player] = true
	return data.Trophies - before
end

-- Trophées GAGNÉS en jouant : plafonnés par jour. Renvoie le nombre vraiment donné.
local function grantTrophies(player: Player, amount: number): number
	local data = getData(player)
	if not data then
		return 0
	end
	local arcade = ensureArcade(data)
	local granted = Logic.CappedGrant(amount, arcade.DayTrophies, TROPHIES.DailyCap)
	if granted <= 0 then
		return 0
	end
	granted = moveTrophies(player, granted)
	arcade.DayTrophies += granted
	arcade.TrophiesEarned += granted
	return granted
end

-- Dopamine = `seconds` de production (comme les autres bonus du jeu)
local function grantDopamineSeconds(player: Player, seconds: number, countForQuests: boolean?): number
	if not isValidNumber(seconds) or seconds <= 0 or not getData(player) then
		return 0
	end
	local stats = services.GameService:GetStats(player)
	local amount = Formulas.ScaledReward(stats, math.min(seconds, 3600), ArcadeConfig.MinDopamineReward)
	if not isValidNumber(amount) or amount <= 0 then
		return 0
	end
	services.GameService:AddDopamine(player, amount, countForQuests ~= false)
	changed[player] = true
	return amount
end

local function addStat(player: Player, stat: string, amount: number?)
	local data = getData(player)
	if not data or type(stat) ~= "string" or type(data.Stats) ~= "table" then
		return
	end
	local value = amount or 1
	if not isValidNumber(value) then
		return
	end
	data.Stats[stat] = (tonumber(data.Stats[stat]) or 0) + value
	changed[player] = true
end

-- Record d'un jeu (game.Record "High" = plus grand, "Low" = plus petit) -> nouveau record ?
local function recordScore(player: Player, gameId: string, score: number): boolean
	local data = getData(player)
	local entry = ArcadeConfig.GamesById[gameId]
	if not data or not entry or not isValidNumber(score) then
		return false
	end
	local arcade = ensureArcade(data)
	local best = arcade.Best[gameId]
	local better = best == nil or (entry.Record == "Low" and score < best) or (entry.Record ~= "Low" and score > best)
	if better then
		arcade.Best[gameId] = score
		changed[player] = true
	end
	return better
end

-- Une partie récompensée de plus aujourd'hui pour ce jeu ? (consomme si oui)
local function takeDailyReward(player: Player, gameId: string): boolean
	local data = getData(player)
	local entry = ArcadeConfig.GamesById[gameId]
	if not data or not entry then
		return false
	end
	local arcade = ensureArcade(data)
	local used = tonumber(arcade.DayRewards[gameId]) or 0
	if used >= (entry.DailyRewarded or 10) then
		return false
	end
	arcade.DayRewards[gameId] = used + 1
	changed[player] = true
	return true
end

local function countPlay(player: Player, gameId: string)
	local data = getData(player)
	if not data or not ArcadeConfig.GamesById[gameId] then
		return
	end
	incr(ensureArcade(data).Plays, gameId)
	addStat(player, "MinigamesPlayed", 1)
end

-- Victoire en solo : récompense (si pas encore au plafond du jour), record, stats
local function rewardWin(player: Player, gameId: string, score: number?)
	local data = getData(player)
	local entry = ArcadeConfig.GamesById[gameId]
	local result = { Tickets = 0, Trophies = 0, Dopamine = 0, Record = false, Capped = false }
	if not data or not entry then
		return result
	end
	local arcade = ensureArcade(data)
	incr(arcade.Wins, gameId)
	if score ~= nil then
		result.Record = recordScore(player, gameId, score)
	end
	if takeDailyReward(player, gameId) then
		result.Tickets = grantTickets(player, entry.Tickets or 0)
		result.Trophies = grantTrophies(player, TROPHIES.PerSoloWin)
		result.Dopamine = grantDopamineSeconds(player, entry.RewardSeconds or 0, true)
		addStat(player, "MinigamesWon", 1)
	else
		result.Capped = true
	end
	changed[player] = true
	return result
end

-- API donnée aux jeux solo (Services > Arcade > SoloGames)
local soloApi = {
	GrantDopamineSeconds = function(player: Player, seconds: number): number
		return grantDopamineSeconds(player, seconds, true)
	end,
	GrantTickets = grantTickets,
	GrantTrophies = grantTrophies,
	AddStat = addStat,
	Notify = function(player: Player, payload)
		services.GameService:Notify(player, payload)
	end,
	T = function(player: Player, text: string, ...): string
		return T(player, text, ...)
	end,
	Now = function(): number
		return os.clock()
	end,
	Config = ArcadeConfig,
	CountPlay = countPlay,
	RecordScore = recordScore,
	TakeDailyReward = takeDailyReward,
	RewardWin = rewardWin,
}

----------------------------------------------------------------------
-- Jeux solo (module écrit à part, chargé prudemment)
----------------------------------------------------------------------

local soloModule = nil
local soloWarned = false

local function getSolo()
	if soloModule then
		return soloModule
	end
	local folder = script.Parent:FindFirstChild("Arcade")
	local moduleScript = folder and folder:FindFirstChild("SoloGames")
	if not moduleScript or not moduleScript:IsA("ModuleScript") then
		return nil
	end
	local ok, result = pcall(require, moduleScript)
	if ok and type(result) == "table" and type(result.Handle) == "function" then
		soloModule = result
		if type(result.Init) == "function" then
			pcall(result.Init, soloApi)
		end
		return result
	end
	if not soloWarned then
		soloWarned = true
		warn("[MinigameService] SoloGames indisponible :", result)
	end
	return nil
end

----------------------------------------------------------------------
-- Invitations
----------------------------------------------------------------------

local function inviteView(invite)
	return {
		Id = invite.Id,
		From = playerInfo(invite.From),
		To = playerInfo(invite.To),
		Game = invite.Game,
		Stake = invite.Stake,
		Seconds = math.max(0, math.floor(invite.ExpiresAt - os.clock() + 0.5)),
		Total = DUELS.InviteSeconds,
	}
end

local function closeInvite(invite, reason: string?)
	if invites[invite.Id] ~= invite then
		return
	end
	invites[invite.Id] = nil
	if reason then
		local payload = { Id = invite.Id, Reason = reason, From = invite.From.DisplayName, To = invite.To.DisplayName, Game = invite.Game }
		fire(invite.From, "inviteClosed", payload)
		fire(invite.To, "inviteClosed", payload)
	end
end

-- Ferme toutes les invitations d'un joueur (envoyées et reçues)
local function closeInvitesOf(player: Player, reason: string)
	for _, invite in pairs(invites) do
		if invite.From == player or invite.To == player then
			closeInvite(invite, reason)
		end
	end
end

local function outgoingOf(player: Player)
	for _, invite in pairs(invites) do
		if invite.From == player then
			return invite
		end
	end
	return nil
end

local function incomingOf(player: Player)
	local list = {}
	for _, invite in pairs(invites) do
		if invite.To == player then
			table.insert(list, invite)
		end
	end
	table.sort(list, function(a, b)
		return a.ExpiresAt < b.ExpiresAt
	end)
	return list
end

local function pairCount(data, other: Player, key: string): number
	return tonumber(ensureArcade(data)[key][tostring(other.UserId)]) or 0
end

----------------------------------------------------------------------
-- Duels : état, vue, fin
----------------------------------------------------------------------

local function gameOf(duel)
	return ArcadeConfig.GamesById[duel.Game]
end

-- État du duel vu par `viewer` (rien de secret : ni l'intrus avant la fin de manche, ni l'heure du GO)
local function snapshot(duel, viewer: Player?)
	local now = os.clock()
	local entry = gameOf(duel)
	local view = {
		Id = duel.Id,
		Game = duel.Game,
		Stake = duel.Stake,
		Pot = duel.Pot,
		You = viewer and duel.Seats[viewer] or 0,
		Players = duel.Infos,
		Turn = duel.Turn,
		TurnLeft = duel.TurnEndsAt and math.max(0, duel.TurnEndsAt - now) or nil,
		TurnSeconds = entry.TurnSeconds,
		Scores = { duel.Scores[1], duel.Scores[2] },
		WinScore = entry.WinScore,
		Round = duel.Round,
		Phase = duel.Phase,
		PhaseLeft = duel.PhaseEndsAt and math.max(0, duel.PhaseEndsAt - now) or nil,
		Moves = duel.Moves,
		Over = duel.Over,
		Winner = duel.Winner,
		Reason = duel.Reason,
	}
	if duel.Game == "TicTacToe" or duel.Game == "Connect4" then
		view.Board = duel.Board
		view.Last = duel.Last
		view.Line = duel.Line
	elseif duel.Game == "ReactionDuel" then
		view.RoundResult = duel.RoundResult
	elseif duel.Game == "SpotRace" then
		local grid = duel.Grid
		if grid then
			view.Grid = { Size = grid.Size, Cells = grid.Cells }
		end
		view.RoundResult = duel.RoundResult
		local seat = viewer and duel.Seats[viewer]
		local locked = seat and duel.Locked and duel.Locked[seat] or 0
		view.Locked = math.max(0, locked - now)
	end
	return view
end

local function broadcast(duel, kind: string)
	for _, player in ipairs(duel.Players) do
		fire(player, kind, snapshot(duel, player))
	end
end

local function pushHistory(data, entry)
	local history = ensureArcade(data).History
	table.insert(history, 1, entry)
	while #history > HISTORY_SIZE do
		table.remove(history)
	end
end

-- Fin du duel : winnerSeat = 1 | 2, ou 0 (égalité : mises rendues)
local function endDuel(duel, winnerSeat: number, reason: string)
	if duel.Over then
		return
	end
	duel.Over = true
	duel.Winner = winnerSeat
	duel.Reason = reason
	duel.Token += 1
	duel.TurnEndsAt = nil
	duel.PhaseEndsAt = nil
	duels[duel.Id] = nil
	for _, player in ipairs(duel.Players) do
		if duelOf[player] == duel then
			duelOf[player] = nil
		end
	end

	local entry = gameOf(duel)
	local results = {}
	-- Mises en 🏆 (déjà en séquestre) : gagnant x2, perdant rien, égalité rendue
	local payouts = Logic.StakePayouts(duel.Stake, winnerSeat)
	for seat, player in ipairs(duel.Players) do
		local data = getData(player)
		local other = duel.Players[3 - seat]
		-- Trophies = gain / perte de la mise ; Bonus = 🎟️ bonus ; TrophyBonus = 🏆 bonus
		local result = { Outcome = "Draw", Reason = reason, Trophies = 0, Bonus = 0, TrophyBonus = 0, Dopamine = 0, Rewarded = false }
		results[seat] = result
		if data then
			local arcade = ensureArcade(data)
			addStat(player, "MinigamesPlayed", 1)
			incr(arcade.Plays, duel.Game)
			if payouts[seat] > 0 then
				moveTrophies(player, payouts[seat])
			end
			if winnerSeat == 0 then
				incr(arcade.Draws, duel.Game)
			elseif winnerSeat == seat then
				result.Outcome = "Win"
				result.Trophies = payouts[seat] - duel.Stake
				incr(arcade.Wins, duel.Game)
				local key = tostring(other.UserId)
				local rewardedToday = tonumber(arcade.DayPairRewards[key]) or 0
				if rewardedToday < DUELS.PairRewardedPerDay and duel.Moves >= DUELS.MinMovesForReward then
					-- Prix de la victoire : identique quelle que soit la mise (même en duel amical)
					arcade.DayPairRewards[key] = rewardedToday + 1
					result.Rewarded = true
					result.Bonus = grantTickets(player, TICKETS.DuelWinBonus)
					result.TrophyBonus = grantTrophies(player, TROPHIES.PerDuelWin)
					result.Dopamine = grantDopamineSeconds(player, entry.RewardSeconds or 30, true)
					addStat(player, "MinigamesWon", 1)
					addStat(player, "DuelsWon", 1)
				end
			else
				result.Outcome = "Lose"
				result.Trophies = -duel.Stake
				incr(arcade.Losses, duel.Game)
			end
			pushHistory(data, {
				G = duel.Game,
				O = duel.Infos[3 - seat].Name,
				R = result.Outcome == "Win" and "W" or (result.Outcome == "Lose" and "L" or "D"),
				S = duel.Stake,
				K = "T", -- mise en 🏆 trophées (les anciens duels, sans K, étaient en tickets)
				T = os.time(),
			})
			changed[player] = true
		end
	end

	for seat, player in ipairs(duel.Players) do
		local view = snapshot(duel, player)
		view.Result = results[seat]
		fire(player, "duelEnd", view)
		if player.Parent == Players and services.GameService:IsReady(player) then
			changed[player] = nil
			services.GameService:SendState(player)
		end
	end

	-- Gros duel : tout le serveur est prévenu
	if winnerSeat ~= 0 and duel.Stake >= (DUELS.AnnounceStake or 5) then
		local winnerName = duel.Infos[winnerSeat].Name
		local loserName = duel.Infos[3 - winnerSeat].Name
		local pot = tostring(duel.Pot)
		local gameName = entry.Name
		services.GameService:NotifyAll(function(lang)
			return {
				Type = "Info",
				Text = Locale.TFor(lang, "⚔️ %s beat %s at %s and won %s 🏆!", winnerName, loserName, Locale.TFor(lang, gameName), pot),
			}
		end)
	end
end

-- Temps pour jouer (jeux au tour par tour) : trop lent = défaite
local function armTurn(duel)
	local entry = gameOf(duel)
	local seconds = entry.TurnSeconds or 20
	duel.Token += 1
	local token = duel.Token
	duel.TurnEndsAt = os.clock() + seconds
	task.delay(seconds + 0.35, function()
		if not duel.Over and duel.Token == token then
			endDuel(duel, 3 - duel.Turn, "timeout")
		end
	end)
end

----------------------------------------------------------------------
-- Jeux en manches (Reaction Duel, Spot Race)
----------------------------------------------------------------------

local nextRound -- (duel) déclaré plus bas

-- Fin d'une manche : points, puis manche suivante ou fin du duel
local function finishRound(duel)
	if duel.Over then
		return
	end
	local entry = gameOf(duel)
	duel.Phase = "result"
	duel.Token += 1
	local token = duel.Token
	local result = duel.RoundResult or { Winner = 0 }
	local winner = result.Winner or 0
	if winner > 0 then
		duel.Scores[winner] += 1
		duel.Moves += 1
	end
	duel.PhaseEndsAt = os.clock() + DUELS.ResultSeconds
	broadcast(duel, "duelUpdate")
	local champion = Logic.RoundsWinner(duel.Scores, entry.WinScore or 3)
	task.delay(champion > 0 and 1.4 or DUELS.ResultSeconds, function()
		if duel.Over or duel.Token ~= token then
			return
		end
		if champion > 0 then
			endDuel(duel, champion, "score")
		else
			nextRound(duel)
		end
	end)
end

-- (lecture de la phase hors du raffinement de type de l'analyseur : elle change entre deux délais)
local function phaseOf(duel): string
	return duel.Phase
end

local function maxRounds(duel): number
	return duel.Game == "ReactionDuel" and DUELS.Reaction.MaxRounds or DUELS.Spot.MaxRounds
end

-- Réaction : le premier appui valide est connu, on attend `Window` pour départager avec la latence
local function reactionResolve(duel, token: number)
	if duel.Over or duel.Token ~= token or duel.Phase ~= "go" then
		return
	end
	local t1, t2 = duel.Taps[1], duel.Taps[2]
	local winner = 0
	if t1 and (not t2 or t1 <= t2) then
		winner = 1
	elseif t2 then
		winner = 2
	end
	duel.RoundResult = { Winner = winner, Times = { t1 or -1, t2 or -1 } }
	finishRound(duel)
end

nextRound = function(duel: any)
	if duel.Over then
		return
	end
	if duel.Round >= maxRounds(duel) then
		-- Trop de manches : le meilleur score gagne, sinon égalité
		local s1, s2 = duel.Scores[1], duel.Scores[2]
		endDuel(duel, s1 > s2 and 1 or (s2 > s1 and 2 or 0), "rounds")
		return
	end
	duel.Round += 1
	duel.RoundResult = nil
	duel.Token += 1
	local token = duel.Token

	if duel.Game == "ReactionDuel" then
		local settings = DUELS.Reaction
		duel.Phase = "wait"
		duel.Taps = {}
		duel.PhaseEndsAt = nil
		broadcast(duel, "duelUpdate")
		task.delay(random:NextNumber(settings.MinDelay, settings.MaxDelay), function()
			if duel.Over or duel.Token ~= token or duel.Phase ~= "wait" then
				return
			end
			duel.Phase = "go"
			duel.GoAt = os.clock()
			broadcast(duel, "duelUpdate")
			task.delay(settings.RoundTimeout, function()
				if not duel.Over and duel.Token == token and phaseOf(duel) == "go" then
					duel.RoundResult = { Winner = 0, Void = true }
					finishRound(duel)
				end
			end)
		end)
	else
		local settings = DUELS.Spot
		duel.Grid = Logic.SpotMakeGrid(function(a: number, b: number): number
			return random:NextInteger(a, b)
		end, duel.Round)
		duel.Phase = "play"
		duel.GridAt = os.clock()
		duel.Locked = { 0, 0 }
		duel.PhaseEndsAt = os.clock() + settings.RoundTimeout
		broadcast(duel, "duelUpdate")
		task.delay(settings.RoundTimeout, function()
			if not duel.Over and duel.Token == token and duel.Phase == "play" then
				duel.RoundResult = { Winner = 0, Void = true, Odd = duel.Grid.Odd }
				finishRound(duel)
			end
		end)
	end
end

----------------------------------------------------------------------
-- Début d'un duel
----------------------------------------------------------------------

local INTRO_SECONDS = 3

local function startDuel(gameId: string, a: Player, b: Player, stake: number)
	-- Places tirées au hasard (la place 1 commence au morpion / puissance 4)
	local first, second = a, b
	if random:NextInteger(1, 2) == 2 then
		first, second = b, a
	end
	local duel = {
		Id = newId("D"),
		Game = gameId,
		Stake = stake,
		Pot = stake * 2,
		Players = { first, second },
		Seats = { [first] = 1, [second] = 2 },
		Infos = { playerInfo(first), playerInfo(second) },
		Turn = 1,
		Scores = { 0, 0 },
		Round = 0,
		Moves = 0,
		Token = 0,
		Over = false,
		Winner = 0,
		StartedAt = os.clock(),
	}
	duels[duel.Id] = duel
	duelOf[first] = duel
	duelOf[second] = duel

	-- Compteurs anti-farm (des deux côtés)
	for seat, player in ipairs(duel.Players) do
		local data = getData(player)
		if data then
			incr(ensureArcade(data).DayPairs, tostring(duel.Players[3 - seat].UserId))
		end
	end

	if gameId == "TicTacToe" then
		duel.Board = table.create(9, 0)
		duel.Phase = "play"
		armTurn(duel)
	elseif gameId == "Connect4" then
		duel.Board = table.create(Logic.C4Cols * Logic.C4Rows, 0)
		duel.Phase = "play"
		armTurn(duel)
	else
		duel.Phase = "intro"
		duel.PhaseEndsAt = os.clock() + INTRO_SECONDS
		local token = duel.Token
		task.delay(INTRO_SECONDS, function()
			if not duel.Over and duel.Token == token then
				nextRound(duel)
			end
		end)
	end

	broadcast(duel, "duelStart")

	-- Duel trop long : égalité, mises rendues
	task.delay(DUELS.MaxDuelSeconds, function()
		if not duel.Over then
			endDuel(duel, 0, "time")
		end
	end)
	return duel
end

----------------------------------------------------------------------
-- Coups
----------------------------------------------------------------------

local function pingOf(player: Player): number
	local ok, ping = pcall(function()
		return player:GetNetworkPing()
	end)
	if ok and isValidNumber(ping) then
		return math.clamp(ping, 0, DUELS.Reaction.MaxPingComp)
	end
	return 0
end

-- Coup d'un jeu au tour par tour (morpion, puissance 4)
local function playBoardMove(player: Player, duel, seat: number, move): (boolean, string?)
	if duel.Phase ~= "play" or duel.Turn ~= seat then
		return false, T(player, "Not your turn!")
	end
	local index
	if duel.Game == "TicTacToe" then
		if type(move) ~= "number" or move ~= math.floor(move) or move < 1 or move > 9 or duel.Board[move] ~= 0 then
			return false, T(player, "Invalid move")
		end
		index = move
	else
		index = Logic.C4Drop(duel.Board, move)
		if not index then
			return false, T(player, "This column is full")
		end
	end
	duel.Board[index] = seat
	duel.Last = index
	duel.Moves += 1

	local winner, line
	if duel.Game == "TicTacToe" then
		winner, line = Logic.TicTacToeWinner(duel.Board)
	else
		winner, line = Logic.C4Winner(duel.Board)
	end
	if winner ~= 0 then
		duel.Line = line
		endDuel(duel, winner, "line")
		return true, nil
	end
	if Logic.IsFull(duel.Board, #duel.Board) then
		endDuel(duel, 0, "draw")
		return true, nil
	end
	duel.Turn = 3 - seat
	armTurn(duel)
	broadcast(duel, "duelUpdate")
	return true, nil
end

local function playReactionTap(player: Player, duel, seat: number): (boolean, any)
	local settings = DUELS.Reaction
	if duel.Phase == "wait" then
		-- Faux départ : le point va à l'adversaire
		duel.RoundResult = { Winner = 3 - seat, FalseStart = seat }
		finishRound(duel)
		return true, { FalseStart = true }
	elseif duel.Phase == "go" then
		if duel.Taps[seat] then
			return true, nil
		end
		local reaction = os.clock() - duel.GoAt - pingOf(player)
		if reaction < settings.MinHuman then
			-- Impossible pour un humain : appui envoyé avant d'avoir vu le GO
			duel.RoundResult = { Winner = 3 - seat, FalseStart = seat }
			finishRound(duel)
			return true, { FalseStart = true }
		end
		duel.Taps[seat] = math.floor(reaction * 1000 + 0.5) / 1000
		local token = duel.Token
		if duel.Taps[3 - seat] then
			reactionResolve(duel, token)
		elseif not duel.WindowArmed or duel.WindowArmed ~= token then
			duel.WindowArmed = token
			task.delay(settings.Window, reactionResolve, duel, token)
		end
		return true, { Time = duel.Taps[seat] }
	end
	return false, nil
end

local function playSpot(player: Player, duel, seat: number, move): (boolean, any)
	local settings = DUELS.Spot
	local grid = duel.Grid
	if duel.Phase ~= "play" or not grid then
		return false, nil
	end
	if type(move) ~= "number" or move ~= math.floor(move) or move < 1 or move > #grid.Cells then
		return false, T(player, "Invalid move")
	end
	local now = os.clock()
	if now < (duel.Locked[seat] or 0) then
		return false, { Locked = duel.Locked[seat] - now }
	end
	if now - duel.GridAt < settings.MinFind then
		return false, nil -- trop rapide pour un humain (la grille vient d'arriver)
	end
	if move == grid.Odd then
		duel.RoundResult = { Winner = seat, Odd = grid.Odd, Time = math.floor((now - duel.GridAt) * 100 + 0.5) / 100 }
		finishRound(duel)
		return true, { Found = true }
	end
	duel.Locked[seat] = now + settings.WrongLock
	return true, { Wrong = true, Locked = settings.WrongLock }
end

----------------------------------------------------------------------
-- Actions
----------------------------------------------------------------------

local ACTIONS = {}

function ACTIONS.lobby(player: Player, _data, _arg)
	local list = {}
	local outgoing = outgoingOf(player)
	local myData = getData(player)
	for _, other in ipairs(Players:GetPlayers()) do
		if other ~= player and other.UserId ~= player.UserId and hasArcade(other) then
			local info = playerInfo(other)
			info.Busy = duelOf[other] ~= nil
			info.Invited = outgoing ~= nil and outgoing.To == other
			info.PairLeft = math.max(0, DUELS.PairDailyLimit - pairCount(myData, other, "DayPairs"))
			table.insert(list, info)
		end
	end
	table.sort(list, function(a, b)
		return string.lower(a.Name) < string.lower(b.Name)
	end)
	local incoming = {}
	for _, invite in ipairs(incomingOf(player)) do
		table.insert(incoming, inviteView(invite))
	end
	local duel = duelOf[player]
	return true, {
		Players = list,
		Incoming = incoming,
		Outgoing = outgoing and inviteView(outgoing) or nil,
		Duel = duel and snapshot(duel, player) or nil,
	}
end

function ACTIONS.invite(player: Player, data, arg)
	if type(arg) ~= "table" then
		return false, T(player, "Invalid request")
	end
	local gameId, stake, targetId = arg.Game, arg.Stake, arg.Target
	local entry = type(gameId) == "string" and ArcadeConfig.GamesById[gameId]
	if not entry or entry.Kind ~= "Duel" then
		return false, T(player, "Unknown game")
	end
	if type(stake) ~= "number" or not ArcadeConfig.StakesSet[stake] then
		return false, T(player, "Invalid stake")
	end
	if type(targetId) ~= "number" then
		return false, T(player, "Invalid request")
	end
	local target = Players:GetPlayerByUserId(targetId)
	if not target or target == player or target.UserId == player.UserId then
		return false, T(player, "You can't duel yourself!")
	end
	if not hasArcade(target) then
		return false, T(player, "%s doesn't have the arcade yet", target.DisplayName)
	end
	if duelOf[player] then
		return false, T(player, "Finish your current duel first")
	end
	if duelOf[target] then
		return false, T(player, "%s is already in a duel", target.DisplayName)
	end
	local now = os.clock()
	if now - (lastInviteAt[player] or -math.huge) < DUELS.InviteCooldown then
		return false, T(player, "Slow down!")
	end
	local declined = declinedAt[player] and declinedAt[player][target.UserId]
	if declined and now - declined < DUELS.DeclineCooldown then
		return false, T(player, "%s just said no. Try again in a moment", target.DisplayName)
	end
	local targetData = getData(target)
	if not targetData then
		return false, T(player, "This player has left")
	end
	if pairCount(data, target, "DayPairs") >= DUELS.PairDailyLimit or pairCount(targetData, player, "DayPairs") >= DUELS.PairDailyLimit then
		return false, T(player, "You've dueled %s a lot today. Come back tomorrow!", target.DisplayName)
	end
	-- Mise en 🏆 trophées (jamais en tickets : ils s'achètent en Robux)
	ensureArcade(targetData)
	local stakeOk, why = Logic.CheckStake(stake, data.Trophies, targetData.Trophies)
	if not stakeOk then
		if why == "self" then
			return false, T(player, "Not enough trophies: win arcade games to earn some!")
		elseif why == "other" then
			return false, T(player, "%s doesn't have enough trophies for this stake", target.DisplayName)
		end
		return false, T(player, "Invalid stake")
	end
	local previous = outgoingOf(player)
	if previous then
		closeInvite(previous, "cancelled")
	end
	if #incomingOf(target) >= DUELS.MaxIncoming then
		return false, T(player, "%s already has too many invitations", target.DisplayName)
	end
	-- Invitation croisée déjà en attente : on l'accepte directement ? Non : chacun choisit, on garde les deux.
	lastInviteAt[player] = now
	local invite = {
		Id = newId("I"),
		From = player,
		To = target,
		Game = entry.Id,
		Stake = stake,
		ExpiresAt = now + DUELS.InviteSeconds,
	}
	invites[invite.Id] = invite
	task.delay(DUELS.InviteSeconds, function()
		if invites[invite.Id] == invite then
			closeInvite(invite, "expired")
		end
	end)
	fire(target, "invite", inviteView(invite))
	return true, { Invite = inviteView(invite), Text = T(player, "Invitation sent to %s", target.DisplayName) }
end

function ACTIONS.cancel(player: Player, _data, _arg)
	local invite = outgoingOf(player)
	if invite then
		closeInvite(invite, "cancelled")
	end
	return true, nil
end

function ACTIONS.decline(player: Player, _data, id)
	local invite = type(id) == "string" and invites[id]
	if not invite or invite.To ~= player then
		return false, T(player, "This invitation has expired")
	end
	declinedAt[invite.From] = declinedAt[invite.From] or {}
	declinedAt[invite.From][player.UserId] = os.clock()
	closeInvite(invite, "declined")
	return true, nil
end

function ACTIONS.accept(player: Player, data, id)
	local invite = type(id) == "string" and invites[id]
	if not invite or invite.To ~= player then
		return false, T(player, "This invitation has expired")
	end
	local from = invite.From
	local fromData = getData(from)
	if from.Parent ~= Players or not fromData or not hasArcade(from) then
		closeInvite(invite, "left")
		return false, T(player, "This player has left")
	end
	if duelOf[player] then
		return false, T(player, "Finish your current duel first")
	end
	if duelOf[from] then
		closeInvite(invite, "busy")
		return false, T(player, "%s is already in a duel", from.DisplayName)
	end
	if pairCount(data, from, "DayPairs") >= DUELS.PairDailyLimit or pairCount(fromData, player, "DayPairs") >= DUELS.PairDailyLimit then
		closeInvite(invite, "limit")
		return false, T(player, "You've dueled %s a lot today. Come back tomorrow!", from.DisplayName)
	end
	-- Mise revérifiée au moment d'accepter (les soldes ont pu changer)
	local stake = invite.Stake
	ensureArcade(fromData)
	local stakeOk, why = Logic.CheckStake(stake, data.Trophies, fromData.Trophies)
	if not stakeOk then
		if why == "self" then
			return false, T(player, "Not enough trophies: win arcade games to earn some!")
		end
		closeInvite(invite, "trophies")
		return false, T(player, "%s doesn't have enough trophies anymore", from.DisplayName)
	end
	closeInvite(invite, "accepted")
	-- Les deux joueurs ne sont plus disponibles : leurs autres invitations tombent
	closeInvitesOf(player, "busy")
	closeInvitesOf(from, "busy")
	-- Séquestre : les deux mises (🏆) sont prises maintenant
	if stake > 0 then
		moveTrophies(player, -stake)
		moveTrophies(from, -stake)
	end
	local duel = startDuel(invite.Game, from, player, stake)
	if changed[from] then
		changed[from] = nil
		services.GameService:SendState(from)
	end
	return true, snapshot(duel, player)
end

function ACTIONS.move(player: Player, _data, arg)
	local duel = duelOf[player]
	if type(arg) ~= "table" or not duel or arg.Id ~= duel.Id or duel.Over then
		return false, T(player, "This duel is over")
	end
	local seat = duel.Seats[player]
	if not seat then
		return false, T(player, "Invalid request")
	end
	if duel.Game == "TicTacToe" or duel.Game == "Connect4" then
		return playBoardMove(player, duel, seat, arg.Move)
	elseif duel.Game == "ReactionDuel" then
		return playReactionTap(player, duel, seat)
	elseif duel.Game == "SpotRace" then
		return playSpot(player, duel, seat, arg.Move)
	end
	return false, T(player, "Invalid request")
end

function ACTIONS.forfeit(player: Player, _data, id)
	local duel = duelOf[player]
	if not duel or (id ~= nil and id ~= duel.Id) then
		return false, T(player, "This duel is over")
	end
	endDuel(duel, 3 - duel.Seats[player], "forfeit")
	return true, nil
end

function ACTIONS.buy(player: Player, data, itemId)
	local item = type(itemId) == "string" and ArcadeConfig.ShopById[itemId]
	if not item then
		return false, T(player, "Unknown item")
	end
	if not RateLimiter.Check(player, "ArcadeBuy", 0.3) then
		return false, T(player, "Slow down!")
	end
	local arcade = ensureArcade(data)
	if item.Kind == "Badge" and arcade.Badges[item.Id] then
		return false, T(player, "You already own this item")
	end
	if item.MaxPerDay and (tonumber(arcade.DayShop[item.Id]) or 0) >= item.MaxPerDay then
		return false, T(player, "Sold out for today. Come back tomorrow!")
	end
	if data.Tickets < item.Price then
		-- Le client propose alors d'en acheter (fenêtre NeedTickets)
		return false, { Text = T(player, "Not enough tickets"), Missing = item.Price - data.Tickets, Currency = "Tickets" }
	end
	local name = T(player, item.Name)
	local text
	if item.Kind == "Boost" then
		local monetization = services.MonetizationService
		local current, remaining = monetization:GetBoost(data)
		-- Un autre boost (ex. acheté avec des Robux) est actif : on ne l'écrase pas
		if remaining > 0 and math.abs(current - item.Multiplier) > 1e-6 then
			return false, T(player, "Another boost is already running")
		end
		moveTickets(player, -item.Price)
		monetization:AddBoost(data, item.Multiplier, item.Duration)
		text = T(player, "%s %s activated!", item.Icon, name)
	elseif item.Kind == "Dopamine" then
		moveTickets(player, -item.Price)
		local amount = grantDopamineSeconds(player, item.Seconds, false)
		text = T(player, "%s +%s %s", item.Icon, NumberFormatter.Format(amount), Config.Game.CurrencyName)
	elseif item.Kind == "Badge" then
		moveTickets(player, -item.Price)
		arcade.Badges[item.Id] = true
		arcade.Badge = item.Id -- équipé tout de suite
		text = T(player, "%s %s bought and equipped!", item.Icon, name)
	else
		return false, T(player, "Invalid item")
	end
	incr(arcade.DayShop, item.Id)
	changed[player] = true
	return true, { Text = text, Tickets = data.Tickets }
end

function ACTIONS.badge(player: Player, data, badgeId)
	local arcade = ensureArcade(data)
	if badgeId == "" or badgeId == nil then
		arcade.Badge = ""
		changed[player] = true
		return true, T(player, "Badge removed")
	end
	local item = type(badgeId) == "string" and ArcadeConfig.ShopById[badgeId]
	if not item or item.Kind ~= "Badge" or not arcade.Badges[badgeId] then
		return false, T(player, "You don't own this item")
	end
	arcade.Badge = badgeId
	changed[player] = true
	return true, T(player, "%s %s equipped", item.Icon, T(player, item.Name))
end

----------------------------------------------------------------------
-- Point d'entrée (RemoteFunction "Arcade")
----------------------------------------------------------------------

local function onArcade(player: Player, action: any, arg: any)
	if type(action) ~= "string" or #action > 48 then
		return false, T(player, "Invalid request")
	end
	-- ~30 appels / s max (les jeux de rapidité cliquent vite)
	if not RateLimiter.Check(player, "Arcade", 0.03) then
		return false, T(player, "Slow down!")
	end
	local data = getData(player)
	if not data or not services.GameService:IsReady(player) then
		return false, T(player, "Loading...")
	end
	if not Formulas.HasFeature(data, ArcadeConfig.Feature) then
		return false, T(player, "The arcade isn't unlocked yet")
	end
	local arcade = ensureArcade(data)
	-- Cadeaux de bienvenue (une seule fois chacun ; les trophées sont aussi
	-- offerts aux joueurs qui avaient déjà l'arcade avant leur arrivée)
	if not arcade.Welcomed then
		arcade.Welcomed = true
		moveTickets(player, TICKETS.StartTickets)
	end
	if not arcade.TrophyGift then
		arcade.TrophyGift = true
		moveTrophies(player, TROPHIES.WelcomeGift)
	end

	local okCall, ok, result
	if string.sub(action, 1, 5) == "solo:" then
		local solo = getSolo()
		if not solo then
			return false, T(player, "This game is coming soon!")
		end
		okCall, ok, result = pcall(solo.Handle, player, data, action, arg, soloApi)
	else
		local handler = ACTIONS[action]
		if not handler then
			return false, T(player, "Invalid request")
		end
		okCall, ok, result = pcall(handler, player, data, arg)
	end
	if not okCall then
		warn("[MinigameService] Erreur dans l'action " .. action .. " :", ok)
		ok, result = false, T(player, "Something went wrong")
	end
	if changed[player] then
		changed[player] = nil
		services.GameService:SendState(player)
	end
	return ok == true, result
end

----------------------------------------------------------------------
-- Cycle de vie
----------------------------------------------------------------------

function MinigameService:Init(allServices)
	services = allServices
end

-- Champs ajoutés à l'état envoyé au client (GameService:BuildState)
function MinigameService:GetClientState(player: Player, data)
	local arcade = ensureArcade(data)
	return {
		Tickets = data.Tickets,
		Trophies = data.Trophies,
		Arcade = {
			Badge = arcade.Badge,
			Badges = arcade.Badges,
			Best = arcade.Best,
			Plays = arcade.Plays,
			Wins = arcade.Wins,
			Losses = arcade.Losses,
			Draws = arcade.Draws,
			History = arcade.History,
			TicketsEarned = arcade.TicketsEarned,
			TrophiesEarned = arcade.TrophiesEarned,
			DayTickets = arcade.DayTickets,
			DailyCap = TICKETS.DailyCap,
			DayTrophies = arcade.DayTrophies,
			TrophyCap = TROPHIES.DailyCap,
			DayRewards = arcade.DayRewards,
			DayShop = arcade.DayShop,
			InDuel = duelOf[player] ~= nil,
		},
	}
end

-- 🎟️ Tickets achetés en Robux (appelé par MonetizationService dans
-- ProcessReceipt, APRÈS la vérification de l'achat) : ajoutés au même solde
-- que les tickets gagnés, sans plafond du jour. -> (ajoutés, nouveau solde)
function MinigameService:GrantPurchasedTickets(player: Player, amount: number): (number, number)
	local data = getData(player)
	if not data or not isValidNumber(amount) or amount <= 0 or amount ~= math.floor(amount) then
		error("montant de tickets invalide : " .. tostring(amount))
	end
	local arcade = ensureArcade(data)
	local added = moveTickets(player, amount)
	arcade.TicketsBought += added
	changed[player] = nil -- (MonetizationService renvoie l'état complet lui-même)
	return added, data.Tickets
end

function MinigameService:PlayerReady(_player: Player, data)
	ensureArcade(data)
end

function MinigameService:PlayerRemoving(player: Player)
	-- Le joueur qui part perd son duel
	local duel = duelOf[player]
	if duel and not duel.Over then
		local seat = duel.Seats[player]
		if seat then
			endDuel(duel, 3 - seat, "left")
		end
	end
	closeInvitesOf(player, "left")
	duelOf[player] = nil
	changed[player] = nil
	lastInviteAt[player] = nil
	declinedAt[player] = nil
	local solo = soloModule
	if solo then
		for _, name in ipairs({ "PlayerRemoving", "Cleanup" }) do
			if type(solo[name]) == "function" then
				pcall(solo[name], player)
			end
		end
	end
end

function MinigameService:Start()
	arcadeEvent = Net.Event("ArcadeEvent")
	Net.Function("Arcade").OnServerInvoke = onArcade
	-- Préchargement des jeux solo (sans bloquer : une erreur est seulement signalée)
	task.defer(getSolo)
	-- Fermeture du serveur : duels en cours annulés, mises rendues (avant la sauvegarde)
	game:BindToClose(function()
		for _, duel in pairs(duels) do
			pcall(endDuel, duel, 0, "shutdown")
		end
	end)
end

-- (tests / debug) logique interne accessible sans passer par le réseau
MinigameService._Internal = {
	Snapshot = snapshot,
	EndDuel = endDuel,
	RewardWin = rewardWin,
}

return MinigameService
