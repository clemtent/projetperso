--[[
	MonetizationService (ModuleScript)
	Emplacement : ServerScriptService > Services > MonetizationService

	💎 Boutique Robux (offres dans Config.Monetization) :
	  - Game Passes : possession vérifiée par le SERVEUR à l'arrivée du joueur
	    (UserOwnsGamePassAsync, 1 nouvel essai si Roblox ne répond pas) puis
	    après chaque achat (PromptGamePassPurchaseFinished). Multiplicateurs
	    (x2, x10, VIP), auto-clic, thèmes Premium (VIP) et thèmes vendus en
	    Game Pass (Config.Themes[].GamePassId) ;
	  - Developer Products : ProcessReceipt (défini UNE seule fois ici).
	    Chaque achat n'est accordé qu'une fois : son PurchaseId est gardé dans
	    data.Purchases et sauvegardé AVANT de répondre "PurchaseGranted" à Roblox ;
	  - Boost temporaire (data.Boost, conservé si le joueur revient avant la fin).
	Le client ne fait qu'OUVRIR la fenêtre d'achat Roblox : il ne peut rien
	s'accorder lui-même.
]]

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage.Shared.Config)
local Formulas = require(ReplicatedStorage.Shared.Formulas)
local NumberFormatter = require(ReplicatedStorage.Shared.NumberFormatter)

local MonetizationService = {}

local services

local MAX_PURCHASES_KEPT = 50 -- nombre de PurchaseId gardés (anti-doublon)
local MAX_BOOST_MULTIPLIER = 1000 -- sécurité contre une sauvegarde abîmée

--[[
	Possession par joueur (session, jamais sauvegardée : Roblox fait foi) :
	[Player] = {
		Passes = { [passId de Config.Monetization.GamePasses] = true },
		Themes = { [themeId] = true }, -- thèmes vendus en Game Pass
		Debug = { [passId] = true | false }, -- commande de test /pass (Studio)
		AutoClickCarry = number, -- fraction de clic automatique en attente
		PendingChecks = number, -- vérifications Roblox encore en cours (arrivée)
	}
]]
local owners = {}

-- PurchaseId en cours de traitement (évite deux traitements simultanés)
local processing = {}

-- Index : ID Roblox du Game Pass -> offres / thèmes concernés
local passesByGamePassId = {}
local themesByGamePassId = {}
for _, pass in ipairs(Config.Monetization.GamePasses) do
	if type(pass.GamePassId) == "number" and pass.GamePassId ~= 0 then
		passesByGamePassId[pass.GamePassId] = passesByGamePassId[pass.GamePassId] or {}
		table.insert(passesByGamePassId[pass.GamePassId], pass)
	end
end
for _, theme in ipairs(Config.Themes) do
	if type(theme.GamePassId) == "number" and theme.GamePassId ~= 0 then
		themesByGamePassId[theme.GamePassId] = themesByGamePassId[theme.GamePassId] or {}
		table.insert(themesByGamePassId[theme.GamePassId], theme)
	end
end

local function isValidNumber(value): boolean
	return type(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge
end

function MonetizationService:Init(allServices)
	services = allServices
end

----------------------------------------------------------------------
-- Casino (règle Roblox : pas de jeu de hasard si on vend de la Dopamine)
----------------------------------------------------------------------

function MonetizationService:IsCasinoEnabled(): boolean
	return Config.Casino.Enabled == true
		and not (Config.IsSellingForRobux and Config.Monetization.DisableCasinoWhenSelling)
end

----------------------------------------------------------------------
-- Game Passes
----------------------------------------------------------------------

-- Vérifie auprès de Roblox (pcall + 1 nouvel essai). Renvoie nil si Roblox
-- n'a pas répondu (on ne change alors rien).
local function checkOwnership(player: Player, gamePassId: number): boolean?
	for attempt = 1, 2 do
		local ok, result = pcall(function()
			return MarketplaceService:UserOwnsGamePassAsync(player.UserId, gamePassId)
		end)
		if ok then
			return result == true
		end
		warn(string.format("[MonetizationService] Vérification du Game Pass %d pour %s impossible (essai %d) : %s",
			gamePassId, player.Name, attempt, tostring(result)))
		if attempt == 1 then
			task.wait(2)
		end
	end
	return nil
end

-- Le joueur possède-t-il l'offre `passId` (Config.Monetization.GamePasses) ?
function MonetizationService:OwnsPass(player: Player, passId: string): boolean
	local owner = owners[player]
	if not owner then
		return false
	end
	local override = owner.Debug[passId]
	if override ~= nil then
		return override
	end
	return owner.Passes[passId] == true
end

-- { [passId] = true } des Game Passes possédés (copie envoyée au client)
function MonetizationService:GetOwnedPasses(player: Player): { [string]: boolean }
	local result = {}
	for _, pass in ipairs(Config.Monetization.GamePasses) do
		if self:OwnsPass(player, pass.Id) then
			result[pass.Id] = true
		end
	end
	return result
end

-- VIP = possède un pass qui débloque les thèmes Premium (le pass "VIP")
function MonetizationService:IsVIP(player: Player): boolean
	for _, pass in ipairs(Config.Monetization.GamePasses) do
		if (pass.UnlockPremiumThemes or pass.Id == "VIP") and self:OwnsPass(player, pass.Id) then
			return true
		end
	end
	return false
end

-- Le joueur possède-t-il le Game Pass propre à ce thème ?
function MonetizationService:OwnsThemePass(player: Player, themeId: string): boolean
	local owner = owners[player]
	return owner ~= nil and owner.Themes[themeId] == true
end

-- Clics automatiques par seconde (pass "Auto-clic")
function MonetizationService:GetAutoClicksPerSecond(player: Player): number
	local total = 0
	for _, pass in ipairs(Config.Monetization.GamePasses) do
		local rate = pass.AutoClicksPerSecond
		if isValidNumber(rate) and rate > 0 and self:OwnsPass(player, pass.Id) then
			total += rate
		end
	end
	return total
end

-- Nombre de clics automatiques à faire pendant `elapsed` secondes (garde la fraction restante)
function MonetizationService:TakeAutoClicks(player: Player, elapsed: number): number
	local owner = owners[player]
	local rate = self:GetAutoClicksPerSecond(player)
	if not owner or rate <= 0 or not isValidNumber(elapsed) or elapsed <= 0 then
		if owner then
			owner.AutoClickCarry = 0
		end
		return 0
	end
	local carry = owner.AutoClickCarry + rate * elapsed
	local clicks = math.floor(carry)
	owner.AutoClickCarry = carry - clicks
	return clicks
end

----------------------------------------------------------------------
-- Boost temporaire et multiplicateur bonus
----------------------------------------------------------------------

-- Boost actif : (multiplicateur, secondes restantes). (1, 0) si aucun.
function MonetizationService:GetBoost(data): (number, number)
	local boost = data and data.Boost
	if type(boost) ~= "table" or not isValidNumber(boost.Multiplier) or not isValidNumber(boost.EndsAt) then
		return 1, 0
	end
	local remaining = boost.EndsAt - os.time()
	if remaining <= 0 or boost.Multiplier <= 1 then
		return 1, 0
	end
	return boost.Multiplier, remaining
end

-- Produit des multiplicateurs des Game Passes possédés (sans le boost :
-- sert aussi au gain hors-ligne, un boost ne dure pas pendant l'absence)
function MonetizationService:GetPassMultiplier(player: Player): number
	local multiplier = 1
	for _, pass in ipairs(Config.Monetization.GamePasses) do
		if isValidNumber(pass.Multiplier) and pass.Multiplier > 0 and self:OwnsPass(player, pass.Id) then
			multiplier *= pass.Multiplier
		end
	end
	return multiplier
end

-- Produit des multiplicateurs des Game Passes possédés x boost actif
function MonetizationService:GetBonusMultiplier(player: Player): number
	local data = services.DataService:GetData(player)
	local boostMultiplier = self:GetBoost(data)
	return self:GetPassMultiplier(player) * boostMultiplier
end

-- Ajoute un boost : si un boost au moins aussi fort est actif, on le
-- prolonge ; sinon le nouveau boost remplace l'ancien.
function MonetizationService:AddBoost(data, multiplier: number, duration: number)
	local now = os.time()
	local currentMultiplier, remaining = self:GetBoost(data)
	if remaining > 0 and currentMultiplier >= multiplier then
		data.Boost.EndsAt = now + remaining + duration
	else
		data.Boost = { Multiplier = multiplier, EndsAt = now + duration }
	end
end

-- Accorde un Game Pass (après vérification serveur ou achat confirmé par Roblox)
local function grantGamePass(player: Player, gamePassId: number, purchased: boolean)
	local owner = owners[player]
	if not owner then
		return
	end
	local names = {}
	for _, pass in ipairs(passesByGamePassId[gamePassId] or {}) do
		if not owner.Passes[pass.Id] then
			owner.Passes[pass.Id] = true
			table.insert(names, pass.Icon .. " " .. pass.Name)
		end
	end
	for _, theme in ipairs(themesByGamePassId[gamePassId] or {}) do
		if not owner.Themes[theme.Id] then
			owner.Themes[theme.Id] = true
			table.insert(names, theme.Icon .. " Thème " .. theme.Name)
		end
	end
	if #names == 0 then
		return
	end

	local data = services.DataService:GetData(player)
	if purchased and data then
		data.Stats.RobuxPurchases += 1
		-- Un thème acheté en Game Pass est équipé tout de suite
		local themes = themesByGamePassId[gamePassId]
		if themes and themes[1] and type(data.Themes) == "table" then
			data.Themes.Equipped = themes[1].Id
		end
	end
	if purchased then
		services.GameService:Notify(player, {
			Type = "Purchase",
			Kind = "Pass",
			Id = (passesByGamePassId[gamePassId] and passesByGamePassId[gamePassId][1].Id) or nil,
			Text = "💎 Merci ! " .. table.concat(names, ", ") .. " débloqué !",
		})
	end
	services.GameService:MarkDirty(player)
end

-- Vérifie tous les Game Passes configurés (en parallèle) pour ce joueur
local function checkAllPasses(player: Player)
	local ids = {}
	for gamePassId in pairs(passesByGamePassId) do
		ids[gamePassId] = true
	end
	for gamePassId in pairs(themesByGamePassId) do
		ids[gamePassId] = true
	end
	local owner = owners[player]
	for gamePassId in pairs(ids) do
		if owner then
			owner.PendingChecks += 1
		end
		task.spawn(function()
			local ok, owned = pcall(checkOwnership, player, gamePassId)
			if ok and owned and owners[player] then
				grantGamePass(player, gamePassId, false)
			end
			if owner then
				owner.PendingChecks -= 1
			end
		end)
	end
end

-- Attend (au plus `timeout` secondes) la fin des vérifications des Game
-- Passes lancées à l'arrivée du joueur (utilisé avant le gain hors-ligne)
function MonetizationService:WaitForPassChecks(player: Player, timeout: number)
	local start = os.clock()
	while os.clock() - start < timeout do
		local owner = owners[player]
		if not owner or owner.PendingChecks <= 0 then
			return
		end
		task.wait(0.1)
	end
end

local function onGamePassPurchaseFinished(player: Player, gamePassId: number, wasPurchased: boolean)
	if typeof(player) ~= "Instance" or not player:IsA("Player") or type(gamePassId) ~= "number" then
		return
	end
	if not passesByGamePassId[gamePassId] and not themesByGamePassId[gamePassId] then
		return -- pas une offre de ce jeu
	end
	if not owners[player] then
		return
	end
	-- On revérifie auprès de Roblox (jamais de confiance aveugle) :
	--  - possédé -> accordé ;
	--  - Roblox ne répond pas mais achat annoncé -> accordé pour cette session
	--    (rien n'est sauvegardé : tout est revérifié à la prochaine connexion) ;
	--  - "pas possédé" juste après un achat -> on réessaie (cache Roblox) ;
	--    dans Studio les achats sont simulés : on se fie à l'événement.
	local purchased = wasPurchased == true
	local owned = checkOwnership(player, gamePassId)
	if owned == false and purchased then
		for _ = 1, 2 do
			task.wait(3)
			if not owners[player] then
				return
			end
			owned = checkOwnership(player, gamePassId)
			if owned ~= false then
				break
			end
		end
	end
	if owned == true or (owned == nil and purchased) or (purchased and RunService:IsStudio()) then
		grantGamePass(player, gamePassId, purchased)
	end
end

----------------------------------------------------------------------
-- Developer Products (ProcessReceipt)
----------------------------------------------------------------------

local function hasProcessed(data, purchaseId: string): boolean
	for _, id in ipairs(data.Purchases) do
		if id == purchaseId then
			return true
		end
	end
	return false
end

local function recordPurchase(data, purchaseId: string)
	table.insert(data.Purchases, purchaseId)
	while #data.Purchases > MAX_PURCHASES_KEPT do
		table.remove(data.Purchases, 1)
	end
	data.Stats.RobuxPurchases += 1
end

-- Accorde le contenu d'un produit. Renvoie le texte de remerciement.
-- Tout est calculé AVANT de modifier les données (pas d'accord à moitié).
local function grantProduct(player: Player, data, product): string
	local kind = product.Kind
	if kind == "Dopamine" then
		local stats = services.GameService:GetStats(player)
		local amount = Formulas.ScaledReward(stats, product.Seconds or 0, product.Minimum or 0)
		if not isValidNumber(amount) or amount <= 0 then
			error("montant invalide pour " .. tostring(product.Id))
		end
		-- Compté comme gagné (classement), mais ne fait pas avancer les quêtes
		services.GameService:AddDopamine(player, amount, false)
		return string.format("💎 Merci ! %s %s : +%s %s", product.Icon, product.Name,
			NumberFormatter.Format(amount), Config.Game.CurrencyName)
	elseif kind == "Boost" then
		local multiplier, duration = product.Multiplier, product.Duration
		if not isValidNumber(multiplier) or multiplier <= 1 or not isValidNumber(duration) or duration <= 0 then
			error("boost mal configuré : " .. tostring(product.Id))
		end
		MonetizationService:AddBoost(data, multiplier, duration)
		local _, remaining = MonetizationService:GetBoost(data)
		return string.format("💎 Merci ! %s %s actif (%d min restantes)", product.Icon, product.Name,
			math.ceil(remaining / 60))
	elseif kind == "ServerRush" then
		services.EventService:StartRush(true)
		services.GameService:NotifyAll({
			Type = "Info",
			Text = "🎉 " .. player.DisplayName .. " offre un Dopamine Rush à tout le serveur !",
		}, player)
		return "💎 Merci ! " .. product.Icon .. " Rush lancé pour tout le serveur !"
	end
	error("type de produit inconnu : " .. tostring(kind))
end

local function processReceipt(receiptInfo)
	local purchaseId = tostring(receiptInfo.PurchaseId)
	local product = Config.ProductsByProductId[receiptInfo.ProductId]
	if not product then
		warn("[MonetizationService] Produit inconnu (ProductId " .. tostring(receiptInfo.ProductId) .. ") : ajoute-le dans Config.Monetization.Products")
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end

	local player = Players:GetPlayerByUserId(receiptInfo.PlayerId)
	local data = player and services.DataService:GetData(player)
	if not player or not data or not services.GameService:IsReady(player) then
		-- Joueur absent ou pas encore chargé : Roblox réessaiera plus tard
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end

	-- Déjà accordé (et sauvegardé avec l'achat) : on confirme sans rien redonner
	if hasProcessed(data, purchaseId) then
		if processing[purchaseId] then
			return Enum.ProductPurchaseDecision.NotProcessedYet -- sauvegarde encore en cours
		end
		return Enum.ProductPurchaseDecision.PurchaseGranted
	end
	if processing[purchaseId] then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end

	-- Sans sauvegarde possible (chargement raté), on n'accorde rien en jeu
	-- publié : Roblox redemandera à la prochaine connexion. Dans Studio
	-- (DataStore souvent indisponible), on accorde quand même pour tester.
	local canSave = services.DataService:CanSave(player)
	if not canSave and not RunService:IsStudio() then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end

	-- Accord + enregistrement du PurchaseId, sans aucune attente entre les deux
	local ok, result = pcall(grantProduct, player, data, product)
	if not ok then
		warn("[MonetizationService] Erreur en accordant " .. tostring(product.Id) .. " :", result)
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	recordPurchase(data, purchaseId)

	services.GameService:Notify(player, {
		Type = "Purchase",
		Kind = "Product",
		Id = product.Id,
		Text = result,
	})
	services.GameService:SendState(player)

	if not canSave then
		return Enum.ProductPurchaseDecision.PurchaseGranted -- Studio sans DataStore
	end

	-- On ne confirme à Roblox qu'une fois l'achat sauvegardé. En cas d'échec,
	-- Roblox réessaiera : le PurchaseId est déjà enregistré, on ne redonnera
	-- rien (et si la sauvegarde n'a jamais eu lieu, l'achat sera réaccordé).
	processing[purchaseId] = true
	local saved = false
	local saveOk, saveResult = pcall(function()
		return services.DataService:SaveAsync(player, true)
	end)
	saved = saveOk and saveResult == true
	processing[purchaseId] = nil
	if not saved then
		warn("[MonetizationService] Sauvegarde après l'achat " .. purchaseId .. " impossible : Roblox réessaiera")
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	return Enum.ProductPurchaseDecision.PurchaseGranted
end

----------------------------------------------------------------------
-- Données sauvegardées (Boost, Purchases)
----------------------------------------------------------------------

local function sanitizeData(data)
	local boost = data.Boost
	if not isValidNumber(boost.Multiplier) or not isValidNumber(boost.EndsAt)
		or boost.Multiplier < 1 or boost.Multiplier > MAX_BOOST_MULTIPLIER or boost.EndsAt <= os.time() then
		data.Boost = { Multiplier = 1, EndsAt = 0 }
	end

	local purchases = {}
	for _, id in ipairs(data.Purchases) do
		if type(id) == "string" then
			table.insert(purchases, id)
		end
	end
	while #purchases > MAX_PURCHASES_KEPT do
		table.remove(purchases, 1)
	end
	data.Purchases = purchases
end

----------------------------------------------------------------------
-- Commande de test /pass (Studio uniquement, appelée par DebugService)
----------------------------------------------------------------------

function MonetizationService:DebugTogglePass(player: Player, passId: string): boolean?
	local owner = owners[player]
	if not owner or not Config.GamePassesById[passId] then
		return nil
	end
	local owned = not self:OwnsPass(player, passId)
	owner.Debug[passId] = owned
	services.GameService:MarkDirty(player)
	return owned
end

----------------------------------------------------------------------
-- Cycle de vie
----------------------------------------------------------------------

function MonetizationService:PlayerReady(player: Player, data)
	owners[player] = { Passes = {}, Themes = {}, Debug = {}, AutoClickCarry = 0, PendingChecks = 0 }
	sanitizeData(data)
	checkAllPasses(player)
end

function MonetizationService:PlayerRemoving(player: Player)
	owners[player] = nil
end

function MonetizationService:Start()
	MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(player, gamePassId, wasPurchased)
		local ok, err = pcall(onGamePassPurchaseFinished, player, gamePassId, wasPurchased)
		if not ok then
			warn("[MonetizationService] Erreur après l'achat d'un Game Pass :", err)
		end
	end)

	MarketplaceService.ProcessReceipt = function(receiptInfo)
		local ok, decision = pcall(processReceipt, receiptInfo)
		if ok and decision then
			return decision
		end
		warn("[MonetizationService] Erreur ProcessReceipt :", decision)
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end

	if Config.IsSellingForRobux and Config.Monetization.DisableCasinoWhenSelling and Config.Casino.Enabled then
		print("[Dopamine Clicker] Offres Robux actives : la machine à sous est désactivée (règles Roblox).")
	end
end

return MonetizationService
