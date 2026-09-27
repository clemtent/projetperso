--[[
	FriendMailRules (ModuleScript)
	Emplacement : ReplicatedStorage > Shared > FriendMailRules

	Règles PURES (sans service Roblox) des mails entre amis Roblox
	(FriendMailService côté serveur, Dopamail côté client) : limites,
	anti-spam, nettoyage du texte, tri et élagage de la boîte de réception
	stockée (DataStore "FriendMail_v1"). Testées par tests/run_tests.py.

	Enregistrement stocké (côté serveur UNIQUEMENT, jamais envoyé tel quel) :
	  { Id = "guid", F = expéditeur (UserId), N = pseudo, D = nom affiché,
	    S = objet BRUT, B = texte BRUT, T = os.time() d'envoi,
	    BS / BB = objet / texte filtrés "pour tout le monde" à l'envoi
	    (GetNonChatStringForBroadcastAsync, le plus strict : secours si le
	    filtre par destinataire échoue à la livraison),
	    R = Id du mail auquel il répond (ou nil), Rd = lu, Rp = déjà répondu }
]]

local FriendMailRules = {}

FriendMailRules.NewInterval = 600 -- 1 nouveau mail toutes les 10 minutes
FriendMailRules.ReplyInterval = 120 -- 1 réponse (à un mail d'ami reçu) toutes les 2 minutes
FriendMailRules.SubjectMax = 60
FriendMailRules.BodyMax = 300
FriendMailRules.InboxMax = 30 -- mails gardés par destinataire
FriendMailRules.MaxAge = 30 * 86400 -- plus vieux que 30 jours : oubliés
FriendMailRules.BlockMax = 200 -- expéditeurs bloqués gardés
FriendMailRules.ClockSkew = 300 -- tolérance d'horloge entre serveurs (secondes)

local function isNumber(value): boolean
	return type(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge
end

-- Secondes à attendre avant de pouvoir envoyer (0 = tout de suite).
-- `last` abîmé (pas un nombre, négatif) = jamais envoyé ; `last` dans le
-- futur (horloge d'un autre serveur en avance) = compté comme "maintenant".
function FriendMailRules.Remaining(last: any, interval: number, now: number): number
	if not isNumber(last) or last <= 0 then
		return 0
	end
	local from = math.min(last, now)
	return math.max(0, math.ceil(from + interval - now))
end

-- Anti-spam : (autorisé, secondes restantes). `state` = data.FriendMail
function FriendMailRules.Check(state: any, now: number, isReply: boolean): (boolean, number)
	local last = type(state) == "table" and (isReply and state.LastReply or state.LastNew) or 0
	local interval = isReply and FriendMailRules.ReplyInterval or FriendMailRules.NewInterval
	local remaining = FriendMailRules.Remaining(last, interval, now)
	return remaining <= 0, remaining
end

-- "7:32" / "1:02:03" (compte à rebours affiché au joueur)
function FriendMailRules.Countdown(seconds: number): string
	local total = math.max(0, math.ceil(isNumber(seconds) and seconds or 0))
	local hours = math.floor(total / 3600)
	local minutes = math.floor((total % 3600) / 60)
	local secs = total % 60
	if hours > 0 then
		return string.format("%s:%02d:%02d", tostring(hours), minutes, secs)
	end
	return string.format("%s:%02d", tostring(minutes), secs)
end

-- Nettoie un texte tapé : caractères de contrôle -> espace, espaces réduits,
-- coupé à `maxChars` caractères (UTF-8). UTF-8 invalide -> "".
function FriendMailRules.Clean(text: any, maxChars: number): string
	if type(text) ~= "string" then
		return ""
	end
	if #text > maxChars * 8 then
		text = string.sub(text, 1, maxChars * 8)
	end
	text = string.gsub(text, "%c", " ")
	text = string.gsub(text, "%s+", " ")
	text = string.gsub(text, "^%s+", "")
	text = string.gsub(text, "%s+$", "")
	local length = utf8.len(text)
	if length == nil then
		-- (une coupe brute a pu casser un caractère : on retire la fin abîmée)
		for cut = #text, math.max(1, #text - 3), -1 do
			local candidate = string.sub(text, 1, cut - 1)
			if utf8.len(candidate) ~= nil then
				text = candidate
				length = utf8.len(candidate)
				break
			end
		end
		if length == nil then
			return ""
		end
	end
	if (length :: number) > maxChars then
		local cut = utf8.offset(text, maxChars + 1)
		if cut then
			text = string.gsub(string.sub(text, 1, cut - 1), "%s+$", "")
		end
	end
	return text
end

-- UserId valide (entier > 0)
function FriendMailRules.ValidUserId(value: any): boolean
	return isNumber(value) and value > 0 and value == math.floor(value) and value < 2 ^ 53
end

-- Un enregistrement de boîte de réception bien formé ?
function FriendMailRules.ValidRecord(record: any): boolean
	return type(record) == "table"
		and type(record.Id) == "string" and #record.Id > 0 and #record.Id <= 64
		and FriendMailRules.ValidUserId(record.F)
		and type(record.S) == "string" and type(record.B) == "string"
		and isNumber(record.T)
end

-- Texte à montrer au destinataire : filtré POUR lui si possible, sinon la
-- version filtrée "pour tout le monde" faite à l'envoi ; sinon rien (nil =
-- pas montré). JAMAIS le texte brut.
function FriendMailRules.ShownText(forRecipient: any, broadcast: any): string?
	if type(forRecipient) == "string" then
		return forRecipient
	end
	if type(broadcast) == "string" then
		return broadcast
	end
	return nil
end

-- Lecture prudente d'un ami (FriendPages, GetFriendsOnlineAsync) : les noms
-- de champs varient selon l'API -> (UserId, pseudo, nom affiché) ou nil
function FriendMailRules.ReadFriend(item: any): (number?, string, string)
	if type(item) ~= "table" then
		return nil, "", ""
	end
	local id = nil
	for _, key in ipairs({ "VisitorId", "Id", "UserId" }) do
		local value = tonumber(item[key])
		if value and FriendMailRules.ValidUserId(value) then
			id = value
			break
		end
	end
	local name = ""
	for _, key in ipairs({ "Username", "UserName", "Name" }) do
		if type(item[key]) == "string" and item[key] ~= "" then
			name = item[key]
			break
		end
	end
	local display = (type(item.DisplayName) == "string" and item.DisplayName ~= "") and item.DisplayName or name
	if name == "" then
		name = display
	end
	return id, name, display
end

-- Boîte stockée -> liste propre : enregistrements invalides, doublons et
-- mails de plus de 30 jours retirés, du plus récent au plus ancien, 30 max.
function FriendMailRules.TrimInbox(list: any, now: number): { any }
	local kept = {}
	if type(list) ~= "table" then
		return kept
	end
	local seen = {}
	for _, record in ipairs(list) do
		if FriendMailRules.ValidRecord(record) and not seen[record.Id] then
			local age = now - record.T
			if age <= FriendMailRules.MaxAge and age >= -FriendMailRules.ClockSkew then
				seen[record.Id] = true
				table.insert(kept, record)
			end
		end
	end
	table.sort(kept, function(a, b)
		if a.T ~= b.T then
			return a.T > b.T
		end
		return a.Id < b.Id
	end)
	for index = #kept, FriendMailRules.InboxMax + 1, -1 do
		kept[index] = nil
	end
	return kept
end

-- Ajoute un mail (sans doublon) puis élague
function FriendMailRules.Append(list: any, record: any, now: number): { any }
	local merged = {}
	if type(list) == "table" then
		for _, existing in ipairs(list) do
			table.insert(merged, existing)
		end
	end
	table.insert(merged, record)
	return FriendMailRules.TrimInbox(merged, now)
end

-- Applique les changements du destinataire (en attente d'écriture) :
-- ops = { Delete = { [id] = true }, Read = { [id] = true },
--   Replied = { [id] = true }, Blocked = { ["userId"] = true } }
function FriendMailRules.ApplyOps(list: any, ops: any, now: number): { any }
	local result = {}
	local delete = type(ops) == "table" and ops.Delete or {}
	local read = type(ops) == "table" and ops.Read or {}
	local replied = type(ops) == "table" and ops.Replied or {}
	local blocked = type(ops) == "table" and ops.Blocked or {}
	for _, record in ipairs(FriendMailRules.TrimInbox(list, now)) do
		if not delete[record.Id] and not blocked[tostring(record.F)] then
			if read[record.Id] then
				record.Rd = true
			end
			if replied[record.Id] then
				record.Rp = true
			end
			table.insert(result, record)
		end
	end
	return result
end

-- Répare data.FriendMail (sauvegarde abîmée) : horodatages valides et pas
-- dans le futur, liste de blocage = { ["UserId"] = true } (200 max)
function FriendMailRules.SanitizeData(state: any, now: number): { [string]: any }
	local clean = { LastNew = 0, LastReply = 0, Blocked = {} }
	if type(state) ~= "table" then
		return clean
	end
	for _, key in ipairs({ "LastNew", "LastReply" }) do
		local value = state[key]
		if isNumber(value) and value > 0 then
			clean[key] = math.floor(math.min(value, now))
		end
	end
	local count = 0
	if type(state.Blocked) == "table" then
		for key, value in pairs(state.Blocked) do
			local id = tonumber(key)
			if value == true and id and FriendMailRules.ValidUserId(id) and count < FriendMailRules.BlockMax then
				clean.Blocked[tostring(id)] = true
				count += 1
			end
		end
	end
	return clean
end

return FriendMailRules
