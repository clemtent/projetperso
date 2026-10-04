--[[
	BankService (ModuleScript)
	Emplacement : ServerScriptService > Services > BankService

	🏦 Banque Dopamine + 💎 Diamants + boutique de luxe + casse de la banque
	(v11, BANK11). Tout est décidé ICI (le client DEMANDE) :
	  - 💎 en POCHE (Wallet) et au COFFRE (Vault) ; dépôt / retrait au
	    guichet, aux distributeurs ou à la salle des coffres (il faut être à
	    la banque) ; INTÉRÊTS du coffre une fois par jour (Diamonds.Interest) ;
	  - CHANGE 💎 -> Dopamine en secondes de production, plafonné par jour ;
	  - BOUTIQUE DE LUXE (Config.Bank.Luxury) : achat en 💎 (poche), objets
	    portés en ville (attributs "Lux<Slot>" du personnage, dessinés par
	    chaque client : LuxuryWear), titres, peintures de voiture
	    (OwnsLuxury, pour CarService / CarWorkshop) ;
	  - CASSE DE LA BANQUE : un casse HeistKit ouvert quand le coffre est
	    "plein" (toutes les Cooldown s ; FailCooldown après un échec) :
	    pirater le boîtier d'alarme -> percer la porte du coffre (alarme) ->
	    remplir les sacs -> porter le butin à la planque.
	  - API pour les autres services : GrantDiamonds / GetDiamonds /
	    SpendDiamonds / OwnsLuxury (voir plus bas).

	Données : data.Diamonds (Shared/Diamonds) et data.Heist.
	Remotes : RemoteFunction "Bank" (C -> S : action, arg -> ok, message, état)
	  actions : "state" | "deposit" n | "withdraw" n | "interest" | "exchange" n |
	            "buy" id | "equip" id | "unequip" slot
	RemoteEvent "BankEvent" (S -> C) : ("State", état) | ("Toast", texte) |
	  ("Heist", { NextAt, Id, State }) (prochain casse de la banque)
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Diamonds = require(ReplicatedStorage.Shared.Diamonds)
local BankLayout = require(ReplicatedStorage.Shared.BankLayout)
local WorldLayout = require(ReplicatedStorage.Shared.WorldLayout)
local NumberFormatter = require(ReplicatedStorage.Shared.NumberFormatter)
local RateLimiter = require(script.Parent.RateLimiter)
local HeistKit = require(script.Parent.HeistKit)

local BankService = {}
BankService.HeistKit = HeistKit

-- Sources de 💎 HORS plafond quotidien des casses
local UNCAPPED = { Ocean = true, Interest = true, Admin = true, Race = true } -- (Race : 1 💎 par médaille d'or, 7 au plus pour toujours)
local BANK_RANGE = 12 -- (studs) marge autour de la banque pour les opérations
local FIRST_HEIST_DELAY = 45 -- (s) après le démarrage du serveur

local services: any = nil
local bankHeist: any = nil
local nextHeistAt = 0
local charConns: { [Player]: RBXScriptConnection } = {}

----------------------------------------------------------------------
-- Outils
----------------------------------------------------------------------

local function now(): number
	local ok, t = pcall(function()
		return workspace:GetServerTimeNow()
	end)
	if ok and type(t) == "number" then
		return t
	end
	return os.clock()
end

local function T(player: Player, text: string, ...): string
	if services and services.GameService then
		return services.GameService:T(player, text, ...)
	end
	if select("#", ...) > 0 then
		return string.format(text, ...)
	end
	return text
end

local function remote(name: string, className: string): Instance?
	local folder = ReplicatedStorage:FindFirstChild("Remotes")
	if not folder then
		return nil
	end
	local r = folder:FindFirstChild(name)
	if not r then
		r = Instance.new(className)
		r.Name = name
		r.Parent = folder
	end
	return r
end

local function fire(player: Player, kind: string, payload: any)
	local r = remote("BankEvent", "RemoteEvent")
	if r then
		pcall(function()
			(r :: RemoteEvent):FireClient(player, kind, payload)
		end)
	end
end

local function plotCount(): number
	return WorldLayout.PlotCount(Players.MaxPlayers)
end

local function inTown(player: Player): boolean
	local world = services and services.WorldService
	if world and type(world.IsInTown) == "function" then
		local ok, result = pcall(world.IsInTown, world, player)
		return ok and result == true
	end
	return false
end

local function dataOf(player: Player): any
	return services and services.DataService and services.DataService:GetData(player) or nil
end

-- data.Diamonds / data.Heist propres (jour UTC remis à jour)
local function wallet(player: Player): (any?, any?)
	local data = dataOf(player)
	if type(data) ~= "table" then
		return nil, nil
	end
	local today = Diamonds.Today(os.time())
	data.Diamonds = Diamonds.Sanitize(data.Diamonds, today)
	data.Heist = Diamonds.SanitizeHeist(data.Heist, today)
	return data.Diamonds, data
end

local function statsOf(player: Player): any
	if services and services.GameService then
		local ok, s = pcall(services.GameService.GetStats, services.GameService, player)
		if ok then
			return s
		end
	end
	return nil
end

local function atBank(player: Player): boolean
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not root or not root:IsA("BasePart") then
		return false
	end
	return BankLayout.Inside(plotCount(), root.Position, BANK_RANGE)
end

local function markDirty(player: Player)
	if services and services.GameService then
		services.GameService:MarkDirty(player)
	end
end

----------------------------------------------------------------------
-- État envoyé au client
----------------------------------------------------------------------

local function stateOf(player: Player): any?
	local d, data = wallet(player)
	if not d or not data then
		return nil
	end
	local B = Config.Bank
	local hd = data.Heist
	local stats = statsOf(player)
	local today = Diamonds.Today(os.time())
	return {
		Wallet = d.Wallet,
		Vault = d.Vault,
		Earned = d.Earned,
		Spent = d.Spent,
		DayEarned = d.DayEarned,
		DailyCap = B.Diamonds.DailyCap,
		Exchanged = d.Exchanged,
		ExchangeLeft = Diamonds.ExchangeLeft(d),
		ExchangeRate = Diamonds.ExchangeValue(stats, 1),
		InterestDue = Diamonds.InterestDue(d, today),
		InterestRate = B.Vault.InterestRate,
		InterestTomorrow = Diamonds.Interest(d.Vault),
		History = d.History,
		Owned = d.Owned,
		Equipped = d.Equipped,
		Dopamine = tonumber(data.Dopamine) or 0,
		Heist = {
			Done = hd.Done,
			Success = hd.Success,
			Best = hd.Best,
			Bank = hd.Bank,
			Train = hd.Train,
			BankDaily = B.Heist.Kinds.Bank.Daily,
			TrainDaily = B.Heist.Kinds.Train.Daily,
		},
		NextHeistAt = nextHeistAt,
		HeistId = bankHeist and bankHeist.Id or nil,
	}
end

local function pushState(player: Player)
	local st = stateOf(player)
	if st then
		fire(player, "State", st)
	end
end

----------------------------------------------------------------------
-- Objets de luxe portés (attributs du personnage)
----------------------------------------------------------------------

local function applyWear(player: Player)
	local character = player.Character
	local d = wallet(player)
	if not character or not d then
		return
	end
	for _, slot in ipairs(Diamonds.SLOTS) do
		local id = d.Equipped[slot]
		local item = id and Config.BankLuxuryById[id]
		pcall(function()
			if slot == "Title" then
				character:SetAttribute("LuxTitle", item and item.Title or nil)
			else
				character:SetAttribute("Lux" .. slot, item and item.Id or nil)
			end
		end)
	end
end

----------------------------------------------------------------------
-- API des autres services
----------------------------------------------------------------------

-- 💎 gagnés -> 💎 réellement accordés (plafond du jour des casses sauf
-- sources UNCAPPED : "Ocean", "Interest"). Toast + état envoyés.
function BankService:GrantDiamonds(player: Player, amount: number, source: string?, quiet: boolean?): number
	local d = wallet(player)
	if not d then
		return 0
	end
	local src = type(source) == "string" and string.sub(source, 1, 20) or "Bonus"
	local n = Diamonds.Grantable(d, amount, not UNCAPPED[src])
	if n <= 0 then
		if not quiet then
			fire(player, "Toast", T(player, "💎 Daily diamond limit reached"))
		end
		return 0
	end
	d.Wallet += n
	d.Earned += n
	if not UNCAPPED[src] then
		d.DayEarned += n
	end
	Diamonds.Log(d, os.time(), src, n, "")
	if not quiet then
		fire(player, "Toast", T(player, "💎 +%d diamonds!", n))
	end
	pushState(player)
	markDirty(player)
	return n
end

-- (poche, coffre)
function BankService:GetDiamonds(player: Player): (number, number)
	local d = wallet(player)
	if not d then
		return 0, 0
	end
	return d.Wallet, d.Vault
end

-- Dépense depuis la POCHE (jamais négatif) -> ok
function BankService:SpendDiamonds(player: Player, amount: number, reason: string?): boolean
	local d = wallet(player)
	local n = Diamonds.Amount(amount)
	if not d or not n or d.Wallet < n then
		return false
	end
	d.Wallet -= n
	d.Spent += n
	Diamonds.Log(d, os.time(), "Spend", -n, type(reason) == "string" and reason or "")
	pushState(player)
	markDirty(player)
	return true
end

-- Objet de luxe possédé ? (ex. CarService : peinture "PaintGold")
function BankService:OwnsLuxury(player: Player, id: string): boolean
	local d = wallet(player)
	return d ~= nil and type(id) == "string" and d.Owned[id] == true
end

----------------------------------------------------------------------
-- Actions "Bank"
----------------------------------------------------------------------

local INTERVALS = { state = 0.5, deposit = 0.4, withdraw = 0.4, interest = 1, exchange = 0.6, buy = 0.6, equip = 0.3, unequip = 0.3 }

local function act(player: Player, action: string, arg: any): (boolean, string?)
	local d, data = wallet(player)
	if not d or not data then
		return false, T(player, "Loading...")
	end
	if action == "state" then
		return true, nil
	end
	local B = Config.Bank
	if action == "equip" or action == "unequip" then
		if action == "unequip" then
			if type(arg) ~= "string" or not table.find(Diamonds.SLOTS, arg) then
				return false, T(player, "Invalid request")
			end
			d.Equipped[arg] = nil
		else
			local item = type(arg) == "string" and Config.BankLuxuryById[arg]
			if not item or not d.Owned[item.Id] or not item.Slot then
				return false, T(player, "Invalid request")
			end
			if d.Equipped[item.Slot] == item.Id then
				d.Equipped[item.Slot] = nil
			else
				d.Equipped[item.Slot] = item.Id
			end
		end
		applyWear(player)
		markDirty(player)
		return true, nil
	end
	-- le reste se fait À la banque (guichet, distributeur, coffres, bijoutier)
	if not inTown(player) or not atBank(player) then
		return false, T(player, "Go to the bank 🏦")
	end
	if action == "deposit" or action == "withdraw" then
		local n = Diamonds.Amount(arg, B.Vault.MaxMove)
		if not n then
			return false, T(player, "Invalid request")
		end
		if action == "deposit" then
			if d.Wallet < n then
				return false, T(player, "Not enough diamonds")
			end
			d.Wallet -= n
			d.Vault += n
			Diamonds.Log(d, os.time(), "Deposit", n, "")
			markDirty(player)
			return true, T(player, "🔒 %d 💎 deposited in your vault", n)
		end
		if d.Vault < n then
			return false, T(player, "Not enough diamonds in your vault")
		end
		d.Vault -= n
		d.Wallet += n
		Diamonds.Log(d, os.time(), "Withdraw", -n, "")
		markDirty(player)
		return true, T(player, "💎 %d withdrawn", n)
	elseif action == "interest" then
		local today = Diamonds.Today(os.time())
		local due = Diamonds.InterestDue(d, today)
		if due <= 0 then
			if d.InterestDay >= today then
				return false, T(player, "Come back tomorrow for more interest")
			end
			return false, T(player, "Keep at least %d 💎 in your vault to earn interest", B.Vault.MinForInterest)
		end
		d.InterestDay = today
		local n = Diamonds.Grantable(d, due, false)
		d.Vault += n
		d.Earned += n
		Diamonds.Log(d, os.time(), "Interest", n, "")
		markDirty(player)
		return true, T(player, "📈 +%d 💎 interest added to your vault", n)
	elseif action == "exchange" then
		local n = Diamonds.Amount(arg, 1000)
		if not n then
			return false, T(player, "Invalid request")
		end
		if n > Diamonds.ExchangeLeft(d) then
			return false, T(player, "Daily exchange limit: %d 💎 left", Diamonds.ExchangeLeft(d))
		end
		if d.Wallet < n then
			return false, T(player, "Not enough diamonds")
		end
		local value = Diamonds.ExchangeValue(statsOf(player), n)
		if value <= 0 then
			return false, T(player, "Invalid request")
		end
		d.Wallet -= n
		d.Spent += n
		d.Exchanged += n
		Diamonds.Log(d, os.time(), "Exchange", -n, NumberFormatter.Format(value))
		if services and services.GameService then
			services.GameService:AddDopamine(player, value, false)
		end
		markDirty(player)
		return true, T(player, "💱 %d 💎 → +%s Dopamine", n, NumberFormatter.Format(value))
	elseif action == "buy" then
		local item = type(arg) == "string" and Config.BankLuxuryById[arg]
		if not item then
			return false, T(player, "Invalid request")
		end
		local ok, why = Diamonds.CanBuy(d, data.Heist, item)
		if not ok then
			if why == "Locked" then
				return false, T(player, "🔒 Needs %d successful heists", tonumber(item.NeedHeists) or 0)
			end
			return false, T(player, why or "Invalid request")
		end
		local price = math.floor(item.Price)
		d.Wallet -= price
		d.Spent += price
		d.Owned[item.Id] = true
		Diamonds.Log(d, os.time(), "Buy", -price, item.Id)
		-- porté tout de suite (même emplacement : remplace)
		if item.Slot then
			d.Equipped[item.Slot] = item.Id
			applyWear(player)
		end
		markDirty(player)
		task.spawn(function()
			if services and services.DataService and services.DataService.SaveAsync then
				pcall(services.DataService.SaveAsync, services.DataService, player, true)
			end
		end)
		return true, T(player, "%s %s is yours!", item.Icon, T(player, item.Name))
	end
	return false, T(player, "Invalid request")
end

local function onInvoke(player: Player, action: any, arg: any): (boolean, any, any)
	if type(action) ~= "string" or INTERVALS[action] == nil then
		return false, T(player, "Invalid request")
	end
	if not RateLimiter.Check(player, "bank:" .. action, INTERVALS[action]) then
		return false, T(player, "Slow down!")
	end
	local ok, success, message = pcall(act, player, action, arg)
	if not ok then
		warn("[BankService] " .. action .. " : " .. tostring(success))
		return false, T(player, "Invalid request"), stateOf(player)
	end
	return success, message, stateOf(player)
end

----------------------------------------------------------------------
-- Casse de la banque (HeistKit)
----------------------------------------------------------------------

local function broadcastHeist()
	local payload = { NextAt = nextHeistAt, Id = bankHeist and bankHeist.Id or nil, State = bankHeist and bankHeist.State or "Idle" }
	for _, p in ipairs(Players:GetPlayers()) do
		if inTown(p) then
			fire(p, "Heist", payload)
		end
	end
end

local function openBankHeist()
	local count = plotCount()
	local pts = BankLayout.Points(count)
	local K = Config.Bank.Heist.Kinds.Bank
	local drops = BankLayout.Drops(count)
	bankHeist = HeistKit.Create({
		Kind = "Bank",
		Name = K.Name,
		Icon = K.Icon,
		Lobby = { Position = pts.Lobby, Radius = 12 },
		MaxCrew = Config.Bank.Heist.MaxCrew,
		LobbySeconds = Config.Bank.Heist.LobbySeconds,
		Duration = K.Duration,
		Steps = {
			{ Id = "hack", Kind = "Hack", Label = "Hack the alarm box", Position = pts.Hack, Radius = 7 },
			{ Id = "drill", Kind = "Drill", Label = "Drill the vault door", Position = pts.Drill, Radius = 10, Alarm = true },
			{ Id = "grab", Kind = "Grab", Label = "Fill the loot bags", Spots = pts.Piles, Radius = 4 },
			{ Id = "escape", Kind = "Escape", Label = "Bring the loot to the hideout", Drops = drops, Radius = 14 },
		},
		OnEvent = function(heist: any, kind: string, payload: any)
			if kind == "Finished" then
				local K2 = Config.Bank.Heist.Kinds.Bank
				nextHeistAt = now() + (if payload and payload.Success then K2.Cooldown else K2.FailCooldown)
				for _, p in ipairs(heist.Order) do
					pushState(p)
				end
				task.delay(14, function()
					if bankHeist == heist then
						heist:Destroy()
						bankHeist = nil
						broadcastHeist()
					end
				end)
			end
			if kind == "Opened" or kind == "Finished" or kind == "Started" or kind == "Step" or kind == "Alarm" then
				broadcastHeist()
			end
		end,
	})
	bankHeist:Open("🏦 The bank vault is full of diamonds: plan a heist!")
end

local function heistLoop()
	while true do
		task.wait(1)
		local ok, err = pcall(function()
			if not bankHeist and now() >= nextHeistAt then
				-- seulement si quelqu'un est en ville (sinon on attend)
				for _, p in ipairs(Players:GetPlayers()) do
					if inTown(p) then
						openBankHeist()
						break
					end
				end
			end
		end)
		if not ok then
			warn("[BankService] casse : " .. tostring(err))
		end
	end
end

----------------------------------------------------------------------
-- Cycle de vie
----------------------------------------------------------------------

function BankService:Init(allServices)
	services = allServices
	HeistKit.Init(allServices)
end

function BankService:Start()
	remote("BankEvent", "RemoteEvent")
	local rf = remote("Bank", "RemoteFunction")
	if rf then
		(rf :: RemoteFunction).OnServerInvoke = onInvoke
	end
	HeistKit.Start()
	nextHeistAt = now() + FIRST_HEIST_DELAY
	task.spawn(heistLoop)
end

function BankService:PlayerReady(player: Player, _data)
	wallet(player)
	if charConns[player] then
		charConns[player]:Disconnect()
	end
	charConns[player] = player.CharacterAdded:Connect(function()
		task.defer(applyWear, player)
	end)
	if player.Character then
		applyWear(player)
	end
	pushState(player)
	fire(player, "Heist", { NextAt = nextHeistAt, Id = bankHeist and bankHeist.Id or nil, State = bankHeist and bankHeist.State or "Idle" })
end

function BankService:PlayerRemoving(player: Player)
	HeistKit.PlayerRemoving(player)
	local c = charConns[player]
	if c then
		c:Disconnect()
		charConns[player] = nil
	end
end

-- (tests / débogage)
BankService.Act = act
BankService.State = stateOf
function BankService:OpenHeistNow()
	if bankHeist then
		bankHeist:Destroy()
		bankHeist = nil
	end
	openBankHeist()
	return bankHeist
end
function BankService:GetHeist()
	return bankHeist
end

return BankService
