--[[
	StockService (ModuleScript)
	Emplacement : ServerScriptService > Services > StockService

	Bourse (débloquée par l'amélioration "Bourse") :
	  - un cours COMMUN à tout le serveur, qui suit une marche aléatoire :
	      prix *= exp(N(0, Volatility) - Volatility² / 2) ; prix += (StartPrice - prix) * MeanReversion
	    puis borné entre MinPrice et MaxPrice ;
	  - envoyé à tous les joueurs toutes les UpdateInterval secondes (StockUpdate) ;
	  - achat / vente validés par le serveur (RemoteFunction StockTrade),
	    avec des frais (Fee) à l'achat et à la vente ;
	  - seul le bénéfice NET cumulé de la session (au-dessus de son record)
	    compte dans LifetimeDopamine : acheter/vendre en boucle ne gonfle rien.
	Uniquement avec la Dopamine du jeu.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Formulas = require(ReplicatedStorage.Shared.Formulas)
local NumberFormatter = require(ReplicatedStorage.Shared.NumberFormatter)
local Net = require(ReplicatedStorage.Shared.Net)
local RateLimiter = require(script.Parent.RateLimiter)

local StockService = {}

local services
local random = Random.new()
local settings = Config.Stocks

local price = settings.StartPrice
local history = { price } -- du plus ancien au plus récent

-- Bénéfice net cumulé (pertes comprises) et son record, par joueur (session)
local tradeNet = {}
local tradePeak = {}

function StockService:Init(allServices)
	services = allServices
end

function StockService:GetPrice(): number
	return price
end

local function payload()
	return {
		Symbol = settings.Symbol,
		Price = price,
		History = table.clone(history),
	}
end

function StockService:SendTo(player: Player)
	Net.Event("StockUpdate"):FireClient(player, payload())
end

-- Tirage selon une loi normale N(0, 1) (méthode de Box-Muller)
local function gaussian(): number
	local u1 = math.max(random:NextNumber(), 1e-12)
	local u2 = random:NextNumber()
	return math.sqrt(-2 * math.log(u1)) * math.cos(2 * math.pi * u2)
end

local function step()
	-- Le terme -Volatility²/2 enlève la dérive à la hausse de exp(N(0, σ))
	price *= math.exp(gaussian() * settings.Volatility - settings.Volatility ^ 2 / 2)
	price += (settings.StartPrice - price) * settings.MeanReversion
	if price ~= price then
		price = settings.StartPrice
	end
	price = math.clamp(price, settings.MinPrice, settings.MaxPrice)

	table.insert(history, price)
	while #history > settings.HistoryLength do
		table.remove(history, 1)
	end
end

local function isAllowedFraction(fraction: any): boolean
	if type(fraction) ~= "number" or fraction ~= fraction then
		return false
	end
	for _, allowed in ipairs(settings.Fractions) do
		if math.abs(allowed - fraction) < 1e-9 then
			return true
		end
	end
	return false
end

local function onTrade(player: Player, action: any, fraction: any)
	-- Petite marge pour la latence réseau (le client attend TradeCooldown entre deux clics)
	if not RateLimiter.Check(player, "StockTrade", math.max(0, settings.TradeCooldown - 0.1)) then
		return false, "Doucement !"
	end
	local data = services.DataService:GetData(player)
	if not data or not services.GameService:IsReady(player) then
		return false, "Chargement en cours..."
	end
	if not Formulas.HasFeature(data, settings.Feature) then
		return false, "La bourse n'est pas encore débloquée"
	end
	if (action ~= "buy" and action ~= "sell") or not isAllowedFraction(fraction) then
		return false, "Requête invalide"
	end

	local stock = data.Stock
	local maxValue = Config.Game.MaxDopamine
	local fee = settings.Fee or 0

	if action == "buy" then
		local spend = data.Dopamine * fraction
		if not (spend >= 1) then
			return false, "Pas assez de " .. Config.Game.CurrencyName
		end
		local shares = spend * (1 - fee) / price
		data.Dopamine -= spend
		stock.Shares += shares
		stock.CostBasis += spend
		data.Stats.StockTrades += 1
		services.GameService:SendState(player)
		return true, string.format("📈 %s action(s) %s achetée(s)", NumberFormatter.Format(shares), settings.Symbol)
	end

	-- Vente
	if not (stock.Shares > 0) then
		return false, "Tu n'as aucune action"
	end
	local shares = stock.Shares * fraction
	local costPart = stock.CostBasis * fraction
	if fraction >= 1 then
		shares = stock.Shares
		costPart = stock.CostBasis
	end
	local proceeds = shares * price * (1 - fee)
	local profit = proceeds - costPart

	stock.Shares = math.max(0, stock.Shares - shares)
	stock.CostBasis = math.max(0, stock.CostBasis - costPart)
	if stock.Shares < 1e-9 then
		stock.Shares = 0
		stock.CostBasis = 0
	end
	data.Dopamine = math.min(maxValue, data.Dopamine + proceeds)
	-- Seul le bénéfice net qui dépasse le record précédent compte (les pertes sont déduites)
	local net = (tradeNet[player] or 0) + profit
	tradeNet[player] = net
	local peak = tradePeak[player] or 0
	if net > peak then
		data.Stats.LifetimeDopamine = math.min(maxValue, data.Stats.LifetimeDopamine + (net - peak))
		tradePeak[player] = net
	end
	data.Stats.StockTrades += 1
	services.GameService:SendState(player)

	local result = profit >= 0 and ("bénéfice +" .. NumberFormatter.Format(profit))
		or ("perte -" .. NumberFormatter.Format(-profit))
	return true, string.format("💰 Vendu pour %s (%s)", NumberFormatter.Format(proceeds), result)
end

function StockService:PlayerRemoving(player: Player)
	tradeNet[player] = nil
	tradePeak[player] = nil
end

function StockService:Start()
	Net.Function("StockTrade").OnServerInvoke = onTrade

	task.spawn(function()
		while true do
			task.wait(settings.UpdateInterval)
			step()
			if #Players:GetPlayers() > 0 then
				Net.Event("StockUpdate"):FireAllClients(payload())
			end
		end
	end)
end

return StockService
