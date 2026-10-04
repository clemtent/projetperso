--[[
	Diamonds (ModuleScript)
	Emplacement : ReplicatedStorage > Shared > Diamonds

	💎 Règles PURES de la monnaie "Diamants" (v11, BANK11). Utilisé par le
	serveur (BankService, qui décide TOUT), le client (BankUI : afficher les
	prix, les intérêts, le change) et les tests (tests/run_tests.py, sans Roblox).

	Données du joueur : data.Diamonds = {
	  Wallet,       -- 💎 en poche (dépensables à la boutique de luxe)
	  Vault,        -- 💎 au coffre de la banque (rapportent des intérêts)
	  Earned,       -- total gagné depuis toujours
	  Spent,        -- total dépensé
	  Day,          -- jour UTC des compteurs du jour
	  DayEarned,    -- 💎 gagnés aujourd'hui aux casses (plafond DailyCap)
	  Exchanged,    -- 💎 échangés aujourd'hui contre de la Dopamine
	  InterestDay,  -- dernier jour où les intérêts ont été réclamés
	  History,      -- { { T = os.time, K = genre, A = montant signé, N = détail } } (récent en 1er)
	  Owned,        -- { [luxuryId] = true }
	  Equipped,     -- { [slot] = luxuryId }
	}
	data.Heist = { Day, Bank, Train (payés aujourd'hui), Done, Success, Best }
	Les 💎 ne sont JAMAIS touchés par l'océan (détox).
]]

local Config = require(script.Parent.Config)

local Diamonds = {}

Diamonds.SLOTS = { "Head", "Face", "Neck", "Wrist", "Back", "Aura", "Title" }
local SLOT_SET = {}
for _, s in ipairs(Diamonds.SLOTS) do
	SLOT_SET[s] = true
end

local function finite(v: any, default: number): number
	if type(v) ~= "number" or v ~= v or v == math.huge or v == -math.huge then
		return default
	end
	return v
end
Diamonds.Finite = finite

local function count(v: any): number
	return math.max(0, math.floor(finite(v, 0)))
end

local function cfg(): any
	return Config.Bank or {}
end

-- Jour UTC (plafonds quotidiens)
function Diamonds.Today(now: number): number
	return math.floor(finite(now, 0) / 86400)
end

-- Nombre entier de 💎 valide (> 0) ou nil (refus des valeurs bizarres du client)
function Diamonds.Amount(v: any, max: number?): number?
	if type(v) ~= "number" or v ~= v or v == math.huge or v == -math.huge then
		return nil
	end
	local n = math.floor(v)
	if n < 1 or n ~= v then
		return nil
	end
	if max and n > max then
		return nil
	end
	return n
end

----------------------------------------------------------------------
-- Données propres
----------------------------------------------------------------------

-- Recopie `clean` DANS `raw` (même table : les références gardées par les
-- services restent valides) ; raw absent / pas une table -> clean
function Diamonds.Into(raw: any, clean: { [string]: any }): any
	if type(raw) ~= "table" then
		return clean
	end
	table.clear(raw)
	for k, v in pairs(clean) do
		raw[k] = v
	end
	return raw
end

function Diamonds.Sanitize(raw: any, today: number): any
	local src = if type(raw) == "table" then raw else {}
	local maxBalance = (cfg().Diamonds and cfg().Diamonds.MaxBalance) or 1e6
	local historySize = (cfg().Diamonds and cfg().Diamonds.HistorySize) or 30
	local owned = {}
	if type(src.Owned) == "table" then
		for id, v in pairs(src.Owned) do
			if v == true and type(id) == "string" and Config.BankLuxuryById and Config.BankLuxuryById[id] then
				owned[id] = true
			end
		end
	end
	local equipped = {}
	if type(src.Equipped) == "table" then
		for slot, id in pairs(src.Equipped) do
			local item = type(id) == "string" and Config.BankLuxuryById and Config.BankLuxuryById[id]
			if SLOT_SET[slot] and item and owned[id] and item.Slot == slot then
				equipped[slot] = id
			end
		end
	end
	local history = {}
	if type(src.History) == "table" then
		for _, h in ipairs(src.History) do
			if #history >= historySize then
				break
			end
			if type(h) == "table" and type(h.K) == "string" and #h.K <= 24 then
				table.insert(history, {
					T = count(h.T),
					K = h.K,
					A = math.floor(finite(h.A, 0)),
					N = if type(h.N) == "string" then string.sub(h.N, 1, 60) else "",
				})
			end
		end
	end
	local day = count(src.Day)
	local dayEarned, exchanged = count(src.DayEarned), count(src.Exchanged)
	if day ~= today then
		day, dayEarned, exchanged = today, 0, 0
	end
	return Diamonds.Into(raw, {
		Wallet = math.min(count(src.Wallet), maxBalance),
		Vault = math.min(count(src.Vault), maxBalance),
		Earned = count(src.Earned),
		Spent = count(src.Spent),
		Day = day,
		DayEarned = dayEarned,
		Exchanged = exchanged,
		InterestDay = count(src.InterestDay),
		History = history,
		Owned = owned,
		Equipped = equipped,
	})
end

function Diamonds.SanitizeHeist(raw: any, today: number): any
	local src = if type(raw) == "table" then raw else {}
	local day = count(src.Day)
	local bank, train = count(src.Bank), count(src.Train)
	if day ~= today then
		day, bank, train = today, 0, 0
	end
	return Diamonds.Into(raw, {
		Day = day,
		Bank = bank,
		Train = train,
		Done = count(src.Done),
		Success = count(src.Success),
		Best = count(src.Best),
	})
end

-- Ajoute une ligne d'historique (en tête) ; garde HistorySize lignes
function Diamonds.Log(d: any, now: number, kind: string, amount: number, note: string?)
	local size = (cfg().Diamonds and cfg().Diamonds.HistorySize) or 30
	table.insert(d.History, 1, { T = count(now), K = kind, A = math.floor(finite(amount, 0)), N = note or "" })
	while #d.History > size do
		table.remove(d.History)
	end
end

----------------------------------------------------------------------
-- Gains (plafond du jour)
----------------------------------------------------------------------

-- 💎 réellement accordés (plafond quotidien des casses, plafond de solde)
function Diamonds.Grantable(d: any, amount: number, capped: boolean): number
	local n = count(amount)
	if n <= 0 then
		return 0
	end
	local maxBalance = (cfg().Diamonds and cfg().Diamonds.MaxBalance) or 1e6
	n = math.min(n, math.max(0, maxBalance - (d.Wallet + d.Vault)))
	if capped then
		local cap = (cfg().Diamonds and cfg().Diamonds.DailyCap) or 80
		n = math.min(n, math.max(0, cap - d.DayEarned))
	end
	return n
end

----------------------------------------------------------------------
-- Coffre : intérêts
----------------------------------------------------------------------

-- Intérêts du jour pour un coffre de `vault` 💎 (0 si trop peu)
function Diamonds.Interest(vault: number): number
	local V = cfg().Vault or {}
	local v = count(vault)
	if v < (V.MinForInterest or 10) then
		return 0
	end
	return math.clamp(math.floor(v * (V.InterestRate or 0.02)), 1, V.InterestMax or 10)
end

-- Intérêts réclamables aujourd'hui ? -> montant (0 = déjà réclamés / rien)
function Diamonds.InterestDue(d: any, today: number): number
	if count(d.InterestDay) >= today then
		return 0
	end
	return Diamonds.Interest(d.Vault)
end

----------------------------------------------------------------------
-- Change 💎 -> Dopamine
----------------------------------------------------------------------

-- Production "estimée" (Dopamine/s + clics) depuis les stats du serveur
function Diamonds.Production(stats: any): number
	local perSecond = finite(stats and stats.PerSecond, 0)
	local click = finite(stats and stats.ClickValue, 0)
	local cps = (Config.Rewards and Config.Rewards.EstimatedClicksPerSecond) or 3
	return math.max(0, perSecond + click * cps)
end

-- Dopamine donnée pour `n` 💎
function Diamonds.ExchangeValue(stats: any, n: number): number
	local E = cfg().Exchange or {}
	local per = math.max(E.MinPerDiamond or 500, Diamonds.Production(stats) * (E.SecondsPerDiamond or 30))
	return math.floor(per * count(n))
end

-- 💎 encore échangeables aujourd'hui
function Diamonds.ExchangeLeft(d: any): number
	local E = cfg().Exchange or {}
	return math.max(0, (E.DailyMax or 15) - count(d.Exchanged))
end

----------------------------------------------------------------------
-- Boutique de luxe
----------------------------------------------------------------------

-- Peut-on acheter cet objet ? -> (ok, raison anglaise si non)
function Diamonds.CanBuy(d: any, heist: any, item: any): (boolean, string?)
	if type(item) ~= "table" then
		return false, "Invalid request"
	end
	if d.Owned[item.Id] then
		return false, "Already owned"
	end
	local need = count(item.NeedHeists)
	if need > 0 and count(heist and heist.Success) < need then
		return false, "Locked"
	end
	if d.Wallet < count(item.Price) then
		return false, "Not enough diamonds"
	end
	return true, nil
end

-- Somme des prix de la boutique (tests : objectif à long terme)
function Diamonds.CatalogueTotal(): number
	local total = 0
	for _, item in ipairs(cfg().Luxury or {}) do
		total += count(item.Price)
	end
	return total
end

return Diamonds
