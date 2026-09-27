--[[
	FriendMailService (ModuleScript)
	Emplacement : ServerScriptService > Services > FriendMailService

	Dopamail entre AMIS Roblox (vrais joueurs) : écrire à un ami, qu'il soit
	sur ce serveur, sur un autre serveur du jeu ou hors ligne, et lui répondre.
	Ces mails ne rapportent JAMAIS de Dopamine.

	Règles (toutes vérifiées ICI, jamais confiées au client) :
	  - le destinataire est un ami Roblox du joueur (liste GetFriendsAsync en
	    cache, sinon player:IsFriendsWithAsync) ;
	  - le joueur a le droit de discuter (TextChatService:CanUserChatAsync) et
	    la paire expéditeur -> destinataire aussi
	    (TextChatService:CanUsersDirectChatAsync, sinon CanUsersChatAsync) :
	    réglages de confidentialité, d'âge et contrôle parental respectés.
	    Réponse inconnue (panne) = refusé ; contrôle REFAIT à la livraison ;
	  - anti-spam persistant (data.FriendMail, sauvegardé : se reconnecter ne
	    remet rien à zéro) : 1 nouveau mail / 10 min, 1 réponse à un mail
	    d'ami reçu / 2 min (une seule réponse par mail reçu) ;
	  - longueurs : objet 60, texte 300 caractères (FriendMailRules).

	Filtrage (règle Roblox) :
	  - le texte BRUT n'est gardé que côté serveur (DataStore "FriendMail_v1",
	    une clé par destinataire) et n'est jamais envoyé à personne ;
	  - à la LIVRAISON, sur le serveur du destinataire (il y est donc présent) :
	    TextService:FilterStringAsync(brut, expéditeur, PrivateChat) puis
	    GetChatForUserAsync(destinataire). Pourquoi la variante "chat" : un
	    mail d'ami est un message privé d'un utilisateur à UN autre
	    utilisateur précis ; Roblox demande PrivateChat + GetChatForUserAsync
	    pour ces messages (le filtre s'adapte aux deux comptes : âge,
	    réglages). GetNonChatString* est prévu pour du texte "hors
	    conversation" (noms d'objets, panneaux...), ce qui n'est pas le cas ;
	  - filtre en échec = mail NON montré ; nouvel essai plus tard ;
	  - la copie "Envoyés" de l'expéditeur passe par le chemin habituel
	    (RemoteFunction "FilterText", purpose "Mail", côté client).

	Livraison :
	  - même serveur : immédiate ;
	  - autre serveur : MessagingService, sujet "FriendMail", petit message
	    { To = UserId, Id = id du mail } ; le serveur du destinataire relit sa
	    boîte (DataStore, sans cache) et livre ;
	  - hors ligne : la boîte (UpdateAsync, ajout, 30 mails max, rien de plus
	    de 30 jours) est lue à la prochaine connexion : mails non lus.
	  + relecture de secours toutes les 3 minutes (message perdu, filtre en
	    panne...). Tout est sous pcall avec nouvelles tentatives, budgets
	    DataStore vérifiés ; dans Studio sans accès aux API, rien ne casse :
	    le client affiche "indisponible dans Studio".

	Remotes :
	  RemoteFunction "FriendMail" (action, argument) -> (ok, résultat | message, état?)
	    "Status" -> état { Enabled, Reason, NewIn, ReplyIn, NewInterval, ReplyInterval }
	    "Friends" -> { Friends = { { Id, Name, Display } }, Status }
	    "Inbox" -> { Mails = { mail filtré }, Loaded, Status }
	    "Send" { To, Subject, Body, ReplyTo? } -> { Id, Where = "Server" | "Away", Status }
	    "Read" id | "Delete" id | "Report" id (cache + bloque l'expéditeur)
	    "Block" userId | "Unblock" userId -> { Blocked = { [userId] = true } }
	  RemoteEvent "FriendMailEvent" S -> C ("New", mail filtré)
	    mail filtré = { Id, From, Name, Display, Subject, Body, Time, Age, Read, Replied, IsReply }
]]

local DataStoreService = game:GetService("DataStoreService")
local HttpService = game:GetService("HttpService")
local MessagingService = game:GetService("MessagingService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TextChatService = game:GetService("TextChatService")
local TextService = game:GetService("TextService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared.Net)
local Rules = require(Shared.FriendMailRules)

local RateLimiter = require(script.Parent.RateLimiter)

local FriendMailService = {}

local STORE_NAME = "FriendMail_v1"
local TOPIC = "FriendMail"
local FRIENDS_TTL = 600 -- liste d'amis gardée 10 min
local FRIENDS_MAX = 250
local PAIR_TTL = 300 -- résultat d'un contrôle "peuvent discuter" gardé 5 min
local FLUSH_DELAY = 10 -- regroupe les changements (lu, supprimé...) avant d'écrire
local POLL_INTERVAL = 180 -- relecture de secours de la boîte
local RETRY_INTERVAL = 60 -- relecture plus tôt si un mail n'a pas pu être livré
local MAX_ATTEMPTS = 3

-- Délais anti-spam des appels (secondes), par action
local CALL_INTERVALS = {
	Status = 0.5,
	Friends = 2,
	Inbox = 1,
	Send = 1.5,
	Read = 0.1,
	Delete = 0.2,
	Report = 0.5,
	Block = 0.5,
	Unblock = 0.5,
}

local services = nil
local store: DataStore? = nil
-- "Unknown" (pas encore essayé) | "Ok" | "Studio" (API coupées dans Studio) | "Down"
local storeState = "Unknown"
local messagingReady = false
local sessions: { [Player]: any } = {}
local inflight = 0 -- écritures en cours (sortie d'un joueur, fermeture du serveur)

----------------------------------------------------------------------
-- Utilitaires
----------------------------------------------------------------------

local function T(player: Player, text: string, ...): string
	local game = services and services.GameService
	if game and game.T then
		return game:T(player, text, ...)
	end
	return string.format(text, ...)
end

local function getData(player: Player): any
	local dataService = services and services.DataService
	return dataService and dataService:GetData(player)
end

-- Données anti-spam / blocages du joueur (créées si absentes)
local function friendState(player: Player): any
	local data = getData(player)
	if not data then
		return nil
	end
	if type(data.FriendMail) ~= "table" then
		data.FriendMail = Rules.SanitizeData(nil, os.time())
	end
	if type(data.FriendMail.Blocked) ~= "table" then
		data.FriendMail.Blocked = {}
	end
	return data.FriendMail
end

-- Erreurs pour lesquelles réessayer ne sert à rien (Studio sans API, place non publiée)
local function isFatal(message: string): boolean
	return string.find(message, "StudioAccessToApisNotAllowed", 1, true) ~= nil
		or string.find(message, "publish", 1, true) ~= nil
		or string.find(message, "403", 1, true) ~= nil
end

local function markFatal()
	storeState = RunService:IsStudio() and "Studio" or "Down"
end

-- pcall + nouvelles tentatives avec attente croissante (1 s, 2 s...)
local function retry(description: string, callback: () -> any): (boolean, any)
	local lastError = nil
	for attempt = 1, MAX_ATTEMPTS do
		local ok, result = pcall(callback)
		if ok then
			return true, result
		end
		lastError = result
		if isFatal(tostring(result)) then
			markFatal()
			break
		end
		warn(string.format("[FriendMailService] %s : échec (tentative %d) : %s", description, attempt, tostring(result)))
		if attempt < MAX_ATTEMPTS then
			task.wait(2 ^ (attempt - 1))
		end
	end
	return false, lastError
end

-- Budget DataStore restant pour ce type de requête (inconnu = on tente)
local function hasBudget(requestType: Enum.DataStoreRequestType): boolean
	local ok, budget = pcall(function()
		return DataStoreService:GetRequestBudgetForRequestType(requestType)
	end)
	if not ok or type(budget) ~= "number" then
		return true
	end
	return budget >= 1
end

local function keyFor(userId: number): string
	return "Inbox_" .. tostring(userId)
end

-- Lecture SANS le cache de 4 s du DataStore (un mail vient d'arriver)
local function freshOptions(): any
	local ok, options = pcall(function()
		local value = Instance.new("DataStoreGetOptions")
		value.UseCache = false
		return value
	end)
	return ok and options or nil
end

local function unavailableReason(): string?
	if storeState == "Studio" or (store == nil and RunService:IsStudio()) then
		return "Studio"
	end
	if store == nil or storeState == "Down" then
		return "Down"
	end
	return nil
end

local function unavailableText(player: Player, reason: string): string
	if reason == "Studio" then
		return T(player, "Friend mail is unavailable in Studio")
	end
	return T(player, "Friend mail is unavailable right now")
end

local function statusFor(player: Player)
	local state = friendState(player)
	local now = os.time()
	local _, newIn = Rules.Check(state, now, false)
	local _, replyIn = Rules.Check(state, now, true)
	local reason = unavailableReason()
	return {
		Enabled = reason == nil,
		Reason = reason,
		NewIn = newIn,
		ReplyIn = replyIn,
		NewInterval = Rules.NewInterval,
		ReplyInterval = Rules.ReplyInterval,
	}
end

local function newSession(): any
	return {
		Inbox = {}, -- enregistrements BRUTS (jamais envoyés)
		Shown = {}, -- [id] = mail filtré déjà livré au client
		Ops = { Delete = {}, Read = {}, Replied = {} }, -- changements à écrire
		Pairs = {}, -- ["de>à"] = { Value, At } (peuvent discuter ?)
		Loaded = false,
		Dirty = false,
		Flushing = false,
		FlushQueued = false,
		RefreshQueued = false,
		Delivering = false,
		DeliverAgain = false,
		Failed = false,
		LastPoll = os.clock(),
		Friends = nil,
		FriendSet = nil,
		FriendsAt = 0,
		FriendsLoading = false,
		Sending = false,
	}
end

-- Changements à appliquer à la boîte stockée (+ expéditeurs bloqués)
local function opsFor(player: Player?, session): any
	local state = player and friendState(player)
	return {
		Delete = session.Ops.Delete,
		Read = session.Ops.Read,
		Replied = session.Ops.Replied,
		-- (joueur parti : copie de ses blocages faite à sa sortie)
		Blocked = (state and state.Blocked) or session.BlockedCopy or {},
	}
end

local function findRecord(session, id: any): any
	if type(id) ~= "string" then
		return nil
	end
	for _, record in ipairs(session.Inbox) do
		if record.Id == id then
			return record
		end
	end
	return nil
end

----------------------------------------------------------------------
-- Contrôles Roblox (amis, droit de discuter, filtre)
----------------------------------------------------------------------

-- Amis du joueur (paginé, en cache 10 min). nil si l'API a échoué.
local function fetchFriends(player: Player, session): { any }?
	if session.Friends and os.clock() - session.FriendsAt < FRIENDS_TTL then
		return session.Friends
	end
	local waited = 0
	while session.FriendsLoading and waited < 15 do
		waited += task.wait(0.2)
	end
	if session.Friends and os.clock() - session.FriendsAt < FRIENDS_TTL then
		return session.Friends
	end
	session.FriendsLoading = true
	local list: { any } = {}
	local ok = false
	for attempt = 1, 2 do
		list = {}
		ok = pcall(function()
			local pages = Players:GetFriendsAsync(player.UserId)
			while true do
				for _, item in ipairs(pages:GetCurrentPage()) do
					if type(item) == "table" and Rules.ValidUserId(item.Id) and #list < FRIENDS_MAX then
						local name = type(item.Username) == "string" and item.Username or ""
						local display = type(item.DisplayName) == "string" and item.DisplayName ~= "" and item.DisplayName or name
						table.insert(list, { Id = item.Id, Name = name, Display = display })
					end
				end
				if pages.IsFinished or #list >= FRIENDS_MAX then
					break
				end
				pages:AdvanceToNextPageAsync()
			end
		end)
		if ok or attempt == 2 then
			break
		end
		task.wait(1)
	end
	session.FriendsLoading = false
	if not ok then
		return nil
	end
	local set = {}
	for _, friend in ipairs(list) do
		set[friend.Id] = true
	end
	session.Friends = list
	session.FriendSet = set
	session.FriendsAt = os.clock()
	return list
end

local function isFriend(player: Player, session, userId: number): boolean?
	if session.FriendSet and session.FriendSet[userId] and os.clock() - session.FriendsAt < FRIENDS_TTL then
		return true
	end
	local ok, result = pcall(function()
		return player:IsFriendsWithAsync(userId)
	end)
	if ok and type(result) == "boolean" then
		return result
	end
	return nil
end

-- Le joueur a-t-il le droit de discuter (réglages du compte) ? nil = inconnu
local function canUserChat(userId: number): boolean?
	local ok, result = pcall(function()
		return TextChatService:CanUserChatAsync(userId)
	end)
	if ok and type(result) == "boolean" then
		return result
	end
	return nil
end

-- `fromId` peut-il écrire en privé à `toId` ? true / false / nil (inconnu).
-- CanUsersDirectChatAsync est fait pour les messages directs (1 à 1) ;
-- CanUsersChatAsync en secours si l'API précédente n'est pas disponible.
local function canUsersChat(fromId: number, toId: number): boolean?
	local ok, result = pcall(function()
		return TextChatService:CanUsersDirectChatAsync(fromId, { toId })
	end)
	if ok and type(result) == "table" then
		return table.find(result, toId) ~= nil
	end
	local okPair, allowed = pcall(function()
		return TextChatService:CanUsersChatAsync(fromId, toId)
	end)
	if okPair and type(allowed) == "boolean" then
		return allowed
	end
	return nil
end

-- Même contrôle, gardé 5 min dans la session (par sens : "de>à" ; seulement
-- les réponses sûres)
local function pairAllowed(session, fromId: number, toId: number): boolean?
	local key = tostring(fromId) .. ">" .. tostring(toId)
	local cached = session.Pairs[key]
	if cached and os.clock() - cached.At < PAIR_TTL then
		return cached.Value
	end
	local value = canUsersChat(fromId, toId)
	if value ~= nil then
		session.Pairs[key] = { Value = value, At = os.clock() }
	end
	return value
end

-- Texte brut -> texte filtré POUR le destinataire (nil = échec : pas montré)
local function filterFor(raw: string, fromId: number, toId: number): string?
	if raw == "" then
		return ""
	end
	local ok, text = pcall(function()
		local result = TextService:FilterStringAsync(raw, fromId, Enum.TextFilterContext.PrivateChat)
		return result:GetChatForUserAsync(toId)
	end)
	if ok and type(text) == "string" then
		return text
	end
	return nil
end

----------------------------------------------------------------------
-- Boîte de réception (DataStore) : lecture, écriture, livraison
----------------------------------------------------------------------

local function flushSession(userId: number, session, player: Player?)
	if not session.Dirty or session.Flushing or not store then
		return
	end
	if not hasBudget(Enum.DataStoreRequestType.UpdateAsync) then
		return
	end
	local dataStore = store :: DataStore
	session.Flushing = true
	session.Dirty = false
	local ops = opsFor(player, session)
	local ok = retry("Écriture de la boîte " .. tostring(userId), function()
		dataStore:UpdateAsync(keyFor(userId), function(old)
			return Rules.ApplyOps(old, ops, os.time())
		end)
	end)
	session.Flushing = false
	if not ok then
		session.Dirty = true -- nouvel essai au prochain passage
	end
end

-- Écriture comptée : la fermeture du serveur attend qu'elle finisse
local function trackedFlush(userId: number, session, player: Player?)
	inflight += 1
	pcall(flushSession, userId, session, player)
	inflight -= 1
end

local function markDirty(player: Player, session)
	session.Dirty = true
	if session.FlushQueued then
		return
	end
	session.FlushQueued = true
	task.delay(FLUSH_DELAY, function()
		session.FlushQueued = false
		if sessions[player] == session then
			flushSession(player.UserId, session, player)
		end
	end)
end

local function removeFromSession(session, predicate: (any) -> boolean): number
	local removed = 0
	for index = #session.Inbox, 1, -1 do
		local record = session.Inbox[index]
		if predicate(record) then
			table.remove(session.Inbox, index)
			session.Shown[record.Id] = nil
			removed += 1
		end
	end
	return removed
end

-- Copie envoyée au client : + Age (secondes depuis l'envoi, calculées ici :
-- l'heure du client n'entre pas en jeu)
local function withAge(mail): any
	local copy = table.clone(mail)
	copy.Age = math.max(0, os.time() - mail.Time)
	return copy
end

-- Filtre puis envoie UN mail au client (s'il ne l'a pas déjà)
local function deliver(player: Player, session, record): boolean
	if session.Shown[record.Id] then
		return true
	end
	local state = friendState(player)
	if state and state.Blocked[tostring(record.F)] then
		return true -- expéditeur bloqué : jamais montré
	end
	local allowed = pairAllowed(session, record.F, player.UserId)
	if allowed == false then
		-- Réglages de confidentialité / d'âge : jamais montré, retiré de la boîte
		session.Ops.Delete[record.Id] = true
		removeFromSession(session, function(other)
			return other.Id == record.Id
		end)
		markDirty(player, session)
		return true
	elseif allowed == nil then
		return false
	end
	local subject = filterFor(record.S, record.F, player.UserId)
	local body = subject ~= nil and filterFor(record.B, record.F, player.UserId) or nil
	if subject == nil or body == nil or not player.Parent or sessions[player] ~= session then
		return false -- filtre en échec : pas montré, nouvel essai plus tard
	end
	local out = {
		Id = record.Id,
		From = record.F,
		Name = type(record.N) == "string" and record.N or "",
		Display = type(record.D) == "string" and record.D or "",
		Subject = subject,
		Body = body,
		Time = record.T,
		Read = record.Rd == true or session.Ops.Read[record.Id] == true,
		Replied = record.Rp == true or session.Ops.Replied[record.Id] == true,
		IsReply = record.R ~= nil,
	}
	session.Shown[record.Id] = out
	Net.Event("FriendMailEvent"):FireClient(player, "New", withAge(out))
	return true
end

-- Livre tous les mails pas encore montrés (un seul passage à la fois)
local function deliverAll(player: Player)
	local session = sessions[player]
	if not session then
		return
	end
	if session.Delivering then
		session.DeliverAgain = true
		return
	end
	session.Delivering = true
	repeat
		session.DeliverAgain = false
		local failed = false
		local list = table.clone(session.Inbox)
		for _, record in ipairs(list) do
			if sessions[player] ~= session then
				break
			end
			if not deliver(player, session, record) then
				failed = true
			end
		end
		session.Failed = failed
	until not session.DeliverAgain or sessions[player] ~= session
	session.Delivering = false
end

-- (Re)lit la boîte du joueur ; `fresh` = sans cache (un mail vient d'arriver)
local function loadInbox(player: Player, fresh: boolean): boolean
	local session = sessions[player]
	if not session or not store or unavailableReason() == "Studio" then
		return false
	end
	if not hasBudget(Enum.DataStoreRequestType.GetAsync) then
		return false
	end
	local dataStore = store :: DataStore
	session.LastPoll = os.clock()
	local options = fresh and freshOptions() or nil
	local ok, value = retry("Lecture de la boîte de " .. player.Name, function()
		if options then
			return dataStore:GetAsync(keyFor(player.UserId), options)
		end
		return dataStore:GetAsync(keyFor(player.UserId))
	end)
	if not ok then
		return false
	end
	if storeState == "Unknown" then
		storeState = "Ok"
	end
	if sessions[player] ~= session then
		return false
	end
	session.Inbox = Rules.ApplyOps(value, opsFor(player, session), os.time())
	session.Loaded = true
	deliverAll(player)
	return true
end

local function queueRefresh(player: Player, delay: number)
	local session = sessions[player]
	if not session or session.RefreshQueued then
		return
	end
	session.RefreshQueued = true
	task.delay(delay, function()
		if sessions[player] == session then
			session.RefreshQueued = false
			loadInbox(player, true)
		end
	end)
end

-- Message d'un autre serveur : un mail attend un joueur d'ici
local function onMessage(message: any)
	local data = type(message) == "table" and message.Data or nil
	if type(data) ~= "table" or not Rules.ValidUserId(data.To) then
		return
	end
	local player = Players:GetPlayerByUserId(data.To)
	if player and sessions[player] then
		queueRefresh(player, 1.5)
	end
end

----------------------------------------------------------------------
-- Envoi
----------------------------------------------------------------------

local function doSend(player: Player, session, args): (boolean, any)
	local toId = args.To
	local subject = Rules.Clean(args.Subject, Rules.SubjectMax)
	local body = Rules.Clean(args.Body, Rules.BodyMax)
	if subject == "" and body == "" then
		return false, T(player, "Write something first ✍️")
	end

	-- Réponse : à un mail reçu de CE destinataire, une seule fois
	local original = nil
	if args.ReplyTo ~= nil then
		original = findRecord(session, args.ReplyTo)
		if not original or original.F ~= toId then
			return false, T(player, "This mail can't be answered anymore")
		end
		if original.Rp or session.Ops.Replied[original.Id] then
			return false, T(player, "You already answered this mail")
		end
	end
	local replying = original ~= nil

	local state = friendState(player)
	if not state then
		return false, T(player, "Message could not be sent, try again")
	end
	local allowedNow, remaining = Rules.Check(state, os.time(), replying)
	if not allowedNow then
		return false, T(player, "Next friend mail in %s", Rules.Countdown(remaining))
	end

	local friend = isFriend(player, session, toId)
	if friend == false then
		return false, T(player, "You can only mail your Roblox friends")
	elseif friend == nil then
		return false, T(player, "Friend mail is unavailable right now")
	end
	local canChat = canUserChat(player.UserId)
	if canChat == false then
		return false, T(player, "Your account settings don't allow private messages")
	elseif canChat == nil then
		return false, T(player, "Friend mail is unavailable right now")
	end
	local pair = pairAllowed(session, player.UserId, toId)
	if pair == false then
		return false, T(player, "This friend can't receive messages (privacy settings)")
	elseif pair == nil then
		return false, T(player, "Friend mail is unavailable right now")
	end

	if not store or not hasBudget(Enum.DataStoreRequestType.UpdateAsync) then
		return false, T(player, "Friend mail is busy, try again in a minute")
	end
	local dataStore = store :: DataStore
	local now = os.time()
	local record = {
		Id = HttpService:GenerateGUID(false),
		F = player.UserId,
		N = player.Name,
		D = player.DisplayName,
		S = subject,
		B = body,
		T = now,
		R = original and original.Id or nil,
	}
	local ok = retry("Envoi d'un mail à " .. tostring(toId), function()
		dataStore:UpdateAsync(keyFor(toId), function(old)
			return Rules.Append(old, record, os.time())
		end)
	end)
	if not ok then
		return false, T(player, "Message could not be sent, try again")
	end

	-- Envoyé : l'anti-spam compte (sauvegardé avec les données du joueur)
	if replying then
		state.LastReply = now
		original.Rp = true
		session.Ops.Replied[original.Id] = true
		local shown = session.Shown[original.Id]
		if shown then
			shown.Replied = true
		end
		markDirty(player, session)
	else
		state.LastNew = now
	end

	-- Livraison : tout de suite (même serveur) ou message aux autres serveurs
	local target = Players:GetPlayerByUserId(toId)
	local targetSession = target and sessions[target]
	if target and targetSession then
		targetSession.Inbox = Rules.Append(targetSession.Inbox, table.clone(record), os.time())
		task.spawn(deliverAll, target)
	elseif messagingReady then
		task.spawn(function()
			pcall(function()
				MessagingService:PublishAsync(TOPIC, { To = toId, Id = record.Id })
			end)
		end)
	end
	return true, { Id = record.Id, Where = targetSession and "Server" or "Away" }
end

----------------------------------------------------------------------
-- RemoteFunction "FriendMail"
----------------------------------------------------------------------

local function sortedShown(session): { any }
	local list = {}
	for _, mail in pairs(session.Shown) do
		table.insert(list, withAge(mail))
	end
	table.sort(list, function(a, b)
		return a.Time > b.Time
	end)
	return list
end

local function onInvoke(player: Player, action: any, arg: any)
	local session = sessions[player]
	local interval = type(action) == "string" and CALL_INTERVALS[action] or nil
	if not session or not interval then
		return false, T(player, "Invalid message")
	end
	if not RateLimiter.Check(player, "FriendMail_" .. action, interval) then
		return false, T(player, "Slow down a little!"), statusFor(player)
	end

	if action == "Status" then
		return true, statusFor(player)
	elseif action == "Inbox" then
		return true, { Mails = sortedShown(session), Loaded = session.Loaded, Status = statusFor(player) }
	elseif action == "Friends" then
		local reason = unavailableReason()
		local list = fetchFriends(player, session)
		if not list then
			return false, T(player, "Couldn't load your friends"), statusFor(player)
		end
		local state = friendState(player)
		return true, { Friends = list, Blocked = state and state.Blocked or {}, Status = statusFor(player), Reason = reason }
	elseif action == "Send" then
		local reason = unavailableReason()
		if reason then
			return false, unavailableText(player, reason), statusFor(player)
		end
		if type(arg) ~= "table" or not Rules.ValidUserId(arg.To) or arg.To == player.UserId then
			return false, T(player, "Invalid message"), statusFor(player)
		end
		if type(arg.Subject) ~= "string" or type(arg.Body) ~= "string" or (arg.ReplyTo ~= nil and type(arg.ReplyTo) ~= "string") then
			return false, T(player, "Invalid message"), statusFor(player)
		end
		if session.Sending then
			return false, T(player, "Slow down a little!"), statusFor(player)
		end
		session.Sending = true
		local okCall, ok, result = pcall(doSend, player, session, arg)
		session.Sending = false
		if not okCall then
			warn("[FriendMailService] Envoi : " .. tostring(ok))
			return false, T(player, "Message could not be sent, try again"), statusFor(player)
		end
		if ok then
			result.Status = statusFor(player)
			return true, result
		end
		return false, result, statusFor(player)
	elseif action == "Read" then
		local record = findRecord(session, arg)
		if record and not record.Rd then
			record.Rd = true
			session.Ops.Read[record.Id] = true
			local shown = session.Shown[record.Id]
			if shown then
				shown.Read = true
			end
			markDirty(player, session)
		end
		return true, true
	elseif action == "Delete" or action == "Report" then
		local record = findRecord(session, arg)
		if not record then
			return false, T(player, "This mail can't be answered anymore")
		end
		session.Ops.Delete[record.Id] = true
		removeFromSession(session, function(other)
			return other.Id == record.Id
		end)
		local state = friendState(player)
		if action == "Report" and state then
			-- Signaler : rien n'est envoyé ailleurs ; le mail est caché et
			-- l'expéditeur bloqué pour CE joueur
			state.Blocked[tostring(record.F)] = true
			removeFromSession(session, function(other)
				return other.F == record.F
			end)
		end
		markDirty(player, session)
		return true, { Blocked = state and state.Blocked or {} }
	elseif action == "Block" or action == "Unblock" then
		local state = friendState(player)
		if not state or not Rules.ValidUserId(arg) then
			return false, T(player, "Invalid message")
		end
		local key = tostring(arg)
		if action == "Block" then
			local count = 0
			for _ in pairs(state.Blocked) do
				count += 1
			end
			if count >= Rules.BlockMax and not state.Blocked[key] then
				return false, T(player, "Too many blocked players")
			end
			state.Blocked[key] = true
			removeFromSession(session, function(other)
				return other.F == arg
			end)
			markDirty(player, session)
		else
			state.Blocked[key] = nil
			queueRefresh(player, 1)
		end
		return true, { Blocked = state.Blocked }
	end
	return false, T(player, "Invalid message")
end

----------------------------------------------------------------------
-- Cycle de vie
----------------------------------------------------------------------

function FriendMailService:Init(allServices)
	services = allServices
end

function FriendMailService:Start()
	local ok, result = pcall(function()
		return DataStoreService:GetDataStore(STORE_NAME)
	end)
	if ok then
		store = result
	else
		warn("[FriendMailService] DataStore indisponible (place non publiée ?) :", result)
		markFatal()
	end

	Net.Function("FriendMail").OnServerInvoke = onInvoke

	-- Messages des autres serveurs (quelques essais, rien de grave sinon :
	-- la relecture de secours livre quand même)
	task.spawn(function()
		for attempt = 1, 3 do
			local subscribed, err = pcall(function()
				return MessagingService:SubscribeAsync(TOPIC, onMessage)
			end)
			if subscribed then
				messagingReady = true
				return
			end
			if isFatal(tostring(err)) then
				return
			end
			task.wait(5 * attempt)
		end
	end)

	-- Relecture de secours + écritures en retard
	task.spawn(function()
		while true do
			task.wait(20)
			local clock = os.clock()
			for player, session in pairs(sessions) do
				if session.Dirty and not session.FlushQueued and not session.Flushing then
					task.spawn(flushSession, player.UserId, session, player)
				end
				local wait = session.Failed and RETRY_INTERVAL or POLL_INTERVAL
				if clock - session.LastPoll >= wait and not session.RefreshQueued then
					queueRefresh(player, math.random() * 5)
				end
			end
		end
	end)

	-- Fermeture du serveur : on écrit ce qui reste
	game:BindToClose(function()
		for player, session in pairs(sessions) do
			if session.Dirty then
				task.spawn(trackedFlush, player.UserId, session, player)
			end
		end
		local start = os.clock()
		while inflight > 0 and os.clock() - start < 15 do
			task.wait(0.1)
		end
	end)
end

function FriendMailService:PlayerReady(player: Player, _data)
	local session = newSession()
	sessions[player] = session
	task.spawn(loadInbox, player, false)
end

function FriendMailService:PlayerRemoving(player: Player)
	local session = sessions[player]
	sessions[player] = nil
	if session and session.Dirty then
		-- (ses données sont encore là : DataService les libère après nous)
		session.BlockedCopy = table.clone(opsFor(player, session).Blocked)
		task.spawn(trackedFlush, player.UserId, session, nil)
	end
end

return FriendMailService
