--[[
	OfferPopup (ModuleScript)
	Emplacement : ReplicatedStorage > Client > Components > OfferPopup

	Petite fenêtre "offre" Robux, discrète et HONNÊTE, construite sur
	Config.Monetization.Offers :
	  - au plus MaxPerSession offres par session, au moins Interval secondes
	    entre deux, la première après FirstDelay secondes de jeu ;
	  - jamais par-dessus une fenêtre (PanelManager), "Bon retour !",
	    "Pas assez de Dopamine", un succès ou l'écran de chargement ;
	    si une fenêtre s'ouvre pendant l'offre, l'offre se ferme ;
	  - toujours fermable (✕, "Non merci", clic à côté) ;
	  - prix clair (vrai prix Roblox, sinon Config PriceHint), pas de faux
	    compte à rebours ni de fausse rareté ; une offre déjà montrée n'est
	    pas reproposée dans la session, un pass possédé jamais.
	Offre choisie selon le moment :
	  - fin d'un Dopamine Rush ou d'un boost -> Boost (x2 15 min...) ;
	  - un peu après un refus de "Pas assez de Dopamine" -> pack de Dopamine
	    (le plus petit qui couvrait le manque) ;
	  - nouveau joueur (aucune visite à l'océan) -> pass x2 ;
	  - gros cliqueur -> pass Auto-clic ; joueur avancé -> pass x10 ;
	  - sinon, la liste Offers.Products dans l'ordre.
	Achat : MarketplaceService:PromptProductPurchase / PromptGamePassPurchase
	(comme la boutique Robux) ; le SERVEUR vérifie et donne l'achat.
	La fenêtre vit dans le calque Toasts.
	API : Build(calque), IsVisible(), Close(), Preview(genre) (Studio / tests :
	"Boost" | "Pass" | "Dopamine", sans les règles de fréquence).
]]

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Client = script.Parent.Parent
local Theme = require(Client.Theme)
local UIUtil = require(Client.UIUtil)
local Interface = require(Client.Interface)
local ClientState = require(Client.ClientState)
local SoundManager = require(Client.SoundManager)
local PanelManager = require(script.Parent.PanelManager)
local NeedDopamine = require(script.Parent.NeedDopamine)
local OfflinePopup = require(script.Parent.OfflinePopup)
local AchievementPopup = require(script.Parent.AchievementPopup)
local Notifications = require(script.Parent.Notifications)
local LoadingScreen = require(script.Parent.LoadingScreen)
local Config = require(ReplicatedStorage.Shared.Config)
local Formulas = require(ReplicatedStorage.Shared.Formulas)
local NumberFormatter = require(ReplicatedStorage.Shared.NumberFormatter)
local Locale = require(ReplicatedStorage.Shared.Locale)

local OfferPopup = {}

local CARD_SIZE = Vector2.new(440, 318)
local SHOWCASE_HEIGHT = 112
local CHECK_EVERY = 2 -- (s) surveillance (fin de boost, conditions)
local PERIODIC_EVERY = 15 -- (s) essai d'une offre "normale"
local AFTER_EVENT_DELAY = 3 -- (s) après la fin d'un rush / boost (le temps de lire le message)
local REFUSAL_COOLDOWN = 150 -- (s) après un "Plus tard" de NeedDopamine avant de proposer un pack
local INTENT_TTL = 90 -- (s) une occasion (fin de rush...) n'est plus valable après
local DETOX_QUIET = 25 -- (s) pas d'offre pendant / juste après la cinématique de l'océan
local CLICKER_CLICKS = 1500 -- clics avant de proposer l'auto-clic
local WHITE = Color3.new(1, 1, 1)
local BLACK = Color3.new(0, 0, 0)

local PASS_COLORS = {
	X10 = Theme.Colors.Purple,
	X2 = Theme.Colors.Blue,
	AutoClick = Theme.Colors.Cyan,
	VIP = Theme.Colors.Premium,
}
local PRODUCT_COLORS = {
	Dopamine = Theme.Colors.Cyan,
	Boost = Theme.Colors.Boost,
	ServerRush = Theme.Colors.Pink,
}

type Offer = {
	Def: any,
	IsPass: boolean,
	Id: number,
	Reason: string, -- phrase (anglais) qui dit POURQUOI on la propose maintenant
}
type Intent = { Kind: string, At: number, Missing: number? }

local player = Players.LocalPlayer
local layer: Frame? = nil
local current: Frame? = nil
local currentOffer: Offer? = nil
local animation: RBXScriptConnection? = nil
local sessionStart = os.clock()
local lastShown = -math.huge
local shownCount = 0
local shownIds: { [string]: boolean } = {}
local intent: Intent? = nil
local quietUntil = 0
local priceCache: { [string]: number } = {}
local fetching: { [string]: boolean } = {}

----------------------------------------------------------------------
-- Offres disponibles
----------------------------------------------------------------------

local function settings()
	return (Config.Monetization and Config.Monetization.Offers) or {}
end

local function selling(): boolean
	return Config.IsSellingForRobux == true or RunService:IsStudio()
end

-- Offre construite depuis Config (nil si elle n'est pas en vente ou déjà possédée)
local function makeOffer(id: string, isPass: boolean, reason: string): Offer?
	local def = isPass and Config.GamePassesById[id] or Config.ProductsById[id]
	if not def then
		return nil
	end
	local robloxId = tonumber(isPass and def.GamePassId or def.ProductId) or 0
	if robloxId == 0 and not RunService:IsStudio() then
		return nil
	end
	if isPass and ClientState.HasPass(def.Id) then
		return nil
	end
	return { Def = def, IsPass = isPass, Id = robloxId, Reason = reason }
end

local function listed(list: { string }?, id: string): boolean
	return type(list) == "table" and table.find(list, id) ~= nil
end

-- Pack de Dopamine le plus petit qui couvre `missing` (liste Offers.Products)
local function packFor(missing: number?): string?
	local data = ClientState.Data
	local stats = { PerSecond = tonumber(data and data.PerSecond) or 0, ClickValue = tonumber(data and data.ClickValue) or 0 }
	local best, bestAmount, fallback = nil, math.huge, nil
	for _, id in ipairs(settings().Products or {}) do
		local def = Config.ProductsById[id]
		if def and def.Kind == "Dopamine" and not shownIds[id] then
			fallback = fallback or id
			local amount = Formulas.ScaledReward(stats, tonumber(def.Seconds) or 0, tonumber(def.Minimum) or 0)
			if amount >= (missing or 0) and amount < bestAmount then
				best, bestAmount = id, amount
			end
		end
	end
	return best or fallback
end

-- Premier boost de la liste pas encore montré
local function boostOffer(reason: string): Offer?
	for _, id in ipairs(settings().Products or {}) do
		local def = Config.ProductsById[id]
		if def and def.Kind == "Boost" and not shownIds[id] then
			local offer = makeOffer(id, false, reason)
			if offer then
				return offer
			end
		end
	end
	return nil
end

-- Offre selon le moment (occasion en attente, profil du joueur, liste)
local function chooseOffer(): Offer?
	local offers = settings()
	local now = os.clock()
	local pending = intent
	if pending and now - pending.At <= INTENT_TTL + (pending.Kind == "Refused" and REFUSAL_COOLDOWN or 0) then
		if pending.Kind == "RushEnded" then
			local offer = boostOffer("The Dopamine Rush is over. Want to keep that pace a little longer?")
			if offer then
				return offer
			end
		elseif pending.Kind == "BoostEnded" then
			local offer = boostOffer("Your boost just ended.")
			if offer then
				return offer
			end
		elseif pending.Kind == "Refused" and now - pending.At >= REFUSAL_COOLDOWN then
			local id = packFor(pending.Missing)
			local offer = id and makeOffer(id, false, "Short on Dopamine earlier? A pack gets you there right away.")
			if offer then
				return offer
			end
		end
	end

	local data = ClientState.Data
	local rebirths = tonumber(data and data.Rebirths) or 0
	local clicks = tonumber(data and data.Stats and data.Stats.TotalClicks) or 0
	local passes = offers.GamePasses
	local candidates: { { string } } = {}
	if rebirths == 0 and not ClientState.HasPass("X10") then
		table.insert(candidates, { "X2", "New here? Double all your gains, forever." })
	end
	if clicks >= CLICKER_CLICKS then
		table.insert(candidates, { "AutoClick", "You click a lot! Let a little robot help your finger." })
	end
	if rebirths >= 1 then
		table.insert(candidates, { "X10", "For long runs: all your gains x10, forever." })
	end
	for _, candidate in ipairs(candidates) do
		local id = candidate[1]
		if listed(passes, id) and not shownIds[id] then
			local offer = makeOffer(id, true, candidate[2])
			if offer then
				return offer
			end
		end
	end
	for _, id in ipairs(offers.Products or {}) do
		if not shownIds[id] then
			local def = Config.ProductsById[id]
			local reason = def and def.Kind == "Dopamine" and "A little extra Dopamine, right now." or "A short boost for your session."
			local offer = makeOffer(id, false, reason)
			if offer then
				return offer
			end
		end
	end
	return nil
end

----------------------------------------------------------------------
-- Règles (fréquence, rien d'ouvert)
----------------------------------------------------------------------

local function somethingOpen(): boolean
	if PanelManager.IsOpen() or NeedDopamine.IsVisible() or OfflinePopup.IsVisible() then
		return true
	end
	if type(AchievementPopup.IsShowing) == "function" and AchievementPopup.IsShowing() then
		return true
	end
	return LoadingScreen.IsVisible()
end

local function allowed(): boolean
	local offers = settings()
	local now = os.clock()
	if current or not selling() or not ClientState.Data then
		return false
	end
	if shownCount >= (tonumber(offers.MaxPerSession) or 0) then
		return false
	end
	if now - sessionStart < (tonumber(offers.FirstDelay) or 300) then
		return false
	end
	if now - lastShown < (tonumber(offers.Interval) or 720) then
		return false
	end
	if now < quietUntil then
		return false
	end
	return not somethingOpen()
end

----------------------------------------------------------------------
-- Prix (MarketplaceService, jamais sur le thread de rendu)
----------------------------------------------------------------------

local function cacheKey(offer: Offer): string
	return (offer.IsPass and "Pass:" or "Product:") .. tostring(offer.Id)
end

local function priceOf(offer: Offer): number
	return priceCache[cacheKey(offer)] or tonumber(offer.Def.PriceHint) or 0
end

local function fetchPrice(offer: Offer, onReady: () -> ())
	local key = cacheKey(offer)
	if offer.Id == 0 or priceCache[key] or fetching[key] then
		return
	end
	fetching[key] = true
	task.spawn(function()
		local ok, info = pcall(function()
			return MarketplaceService:GetProductInfo(offer.Id, offer.IsPass and Enum.InfoType.GamePass or Enum.InfoType.Product)
		end)
		fetching[key] = nil
		local price = ok and type(info) == "table" and tonumber(info.PriceInRobux) or nil
		if price then
			priceCache[key] = price
			onReady()
		end
	end)
end

----------------------------------------------------------------------
-- Fenêtre
----------------------------------------------------------------------

local function close()
	local window = current
	if not window then
		return
	end
	current = nil
	currentOffer = nil
	if animation then
		animation:Disconnect()
		animation = nil
	end
	local card = window:FindFirstChild("Card") :: Frame?
	local dimmer = window:FindFirstChild("Dimmer") :: GuiObject?
	if dimmer then
		UIUtil.Tween(dimmer, 0.2, { BackgroundTransparency = 1 })
	end
	if card then
		local scale = card:FindFirstChildOfClass("UIScale")
		if scale then
			UIUtil.Tween(scale, 0.2, { Scale = 0.88 }, Enum.EasingStyle.Back, Enum.EasingDirection.In)
		end
	end
	task.delay(0.22, function()
		window:Destroy()
	end)
end

local function buyOffer(offer: Offer, buyButton: TextButton)
	if offer.Id == 0 then
		SoundManager.Play("Error", 0.8)
		UIUtil.Shake(buyButton)
		Notifications.Toast(
			Locale.T("Paste the ID of “%s” in Config.Monetization to sell it.", Locale.T(tostring(offer.Def.Name))),
			Theme.Colors.Orange,
			5,
			Locale.T("Studio preview"),
			false,
			"🛠️"
		)
		return
	end
	SoundManager.Play("Click", 1.2)
	close()
	local ok, err = pcall(function()
		if offer.IsPass then
			MarketplaceService:PromptGamePassPurchase(player, offer.Id)
		else
			MarketplaceService:PromptProductPurchase(player, offer.Id)
		end
	end)
	if not ok then
		warn("[OfferPopup] Impossible d'ouvrir l'achat : " .. tostring(err))
		Notifications.Toast(Locale.T("Can't buy right now, try again."), Theme.Colors.Red)
	end
end

-- Ligne "ce que tu obtiens" (concrète, chiffrée)
local function benefitText(offer: Offer): string
	local def = offer.Def
	if offer.IsPass then
		if def.Multiplier then
			return Locale.T("📈 Gains %s forever", NumberFormatter.Multiplier(def.Multiplier))
		elseif def.AutoClicksPerSecond then
			return Locale.T("🤖 %s clicks / second", tostring(def.AutoClicksPerSecond))
		end
		return Locale.T(tostring(def.Description or ""))
	end
	if def.Kind == "Dopamine" then
		local data = ClientState.Data
		local stats = { PerSecond = tonumber(data and data.PerSecond) or 0, ClickValue = tonumber(data and data.ClickValue) or 0 }
		local amount = Formulas.ScaledReward(stats, tonumber(def.Seconds) or 0, tonumber(def.Minimum) or 0)
		return "💧 ≈ +" .. NumberFormatter.Format(amount) .. " Dopamine"
	elseif def.Kind == "Boost" then
		local seconds = tonumber(def.Duration) or 0
		local duration = seconds % 60 == 0 and string.format("%d min", seconds // 60) or NumberFormatter.Time(seconds)
		return Locale.T("⏱️ Gains %s for %s", NumberFormatter.Multiplier(tonumber(def.Multiplier) or 2), duration)
	end
	return Locale.T(tostring(def.Description or ""))
end

local function pillButton(parent: Instance, name: string, text: string, color: Color3, textColor: Color3, position: UDim2, width: number): TextButton
	local node = UIUtil.Create("TextButton", {
		Name = name,
		AnchorPoint = Vector2.new(0.5, 1),
		Position = position,
		Size = UDim2.fromOffset(width, 48),
		BackgroundColor3 = color,
		AutoButtonColor = false,
		Font = Theme.Fonts.Title,
		Text = text,
		TextColor3 = textColor,
		TextSize = 20,
		TextScaled = true,
		ZIndex = 6,
		Parent = parent,
	})
	UIUtil.Create("UITextSizeConstraint", { MaxTextSize = 20, MinTextSize = 12, Parent = node })
	UIUtil.Create("UIPadding", {
		PaddingLeft = UDim.new(0, 14),
		PaddingRight = UDim.new(0, 14),
		PaddingTop = UDim.new(0, 11),
		PaddingBottom = UDim.new(0, 11),
		Parent = node,
	})
	UIUtil.Corner(node, UDim.new(1, 0))
	UIUtil.Stroke(node, color:Lerp(BLACK, 0.3), 2, 0)
	UIUtil.Gradient(node, ColorSequence.new(WHITE, Color3.fromRGB(212, 212, 212)), 90)
	UIUtil.AnimateButton(node, 1.05, 0.93)
	return node
end

local function show(offer: Offer)
	local parent = layer
	if not parent then
		return
	end
	if current then
		current:Destroy()
		current = nil
	end
	local def = offer.Def
	local color: Color3 = offer.IsPass and (PASS_COLORS[def.Id] or Theme.Colors.Purple) or (PRODUCT_COLORS[def.Kind] or Theme.Colors.Cyan)

	local window = UIUtil.Create("Frame", {
		Name = "OfferPopup",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		ZIndex = 44,
		Parent = parent,
	})
	current = window
	currentOffer = offer

	-- Fond légèrement assombri : un clic à côté ferme
	local dimmer = UIUtil.Create("TextButton", {
		Name = "Dimmer",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.fromRGB(12, 10, 30),
		BackgroundTransparency = 1,
		AutoButtonColor = false,
		Text = "",
		ZIndex = 1,
		Parent = window,
	})
	UIUtil.Tween(dimmer, 0.25, { BackgroundTransparency = 0.55 })
	dimmer.Activated:Connect(close)

	local card = UIUtil.Create("Frame", {
		Name = "Card",
		Size = UDim2.fromOffset(CARD_SIZE.X, CARD_SIZE.Y),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		BackgroundColor3 = WHITE,
		Active = true,
		ZIndex = 2,
		Parent = window,
	})
	UIUtil.Corner(card, Theme.Radius.XL)
	UIUtil.Stroke(card, color:Lerp(BLACK, 0.25), 2, 0.25)
	UIUtil.Shadow(card, 6, 0.75, 4)
	local fitScale = math.min(1, (Interface.CanvasSize.X - 24) / CARD_SIZE.X, (Interface.CanvasSize.Y - 24) / CARD_SIZE.Y)
	local scale = UIUtil.Create("UIScale", { Scale = 0.85 * fitScale, Parent = card })
	UIUtil.Tween(scale, 0.35, { Scale = fitScale }, Enum.EasingStyle.Back)

	-- Vitrine (dégradé de l'offre, rayons, icône)
	local showcase = UIUtil.Create("Frame", {
		Name = "Showcase",
		Size = UDim2.new(1, -12, 0, SHOWCASE_HEIGHT),
		Position = UDim2.fromOffset(6, 6),
		BackgroundColor3 = WHITE,
		ClipsDescendants = true,
		ZIndex = 3,
		Parent = card,
	})
	UIUtil.Corner(showcase, Theme.Radius.L)
	UIUtil.SoftGradient(showcase, color, 90)
	local rays = UIUtil.Rays(showcase, WHITE, 8, 260, UDim2.fromScale(0.5, 0.55), 3)
	local glow = UIUtil.Create("Frame", {
		Name = "Glow",
		Size = UDim2.fromOffset(84, 84),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.55),
		BackgroundColor3 = WHITE,
		BackgroundTransparency = 0.5,
		ZIndex = 3,
		Parent = showcase,
	})
	UIUtil.Corner(glow, UDim.new(1, 0))
	local icon = UIUtil.Create("TextLabel", {
		Name = "Icon",
		Size = UDim2.fromOffset(76, 76),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.56),
		BackgroundTransparency = 1,
		Font = Theme.Fonts.Body,
		Text = tostring(def.Icon or "💎"),
		TextSize = 56,
		ZIndex = 4,
		Parent = showcase,
	})
	local kindChip = UIUtil.Chip({
		Name = "Kind",
		Text = offer.IsPass and Locale.T("♾️ FOREVER") or Locale.T("🔁 REBUYABLE"),
		Color = WHITE,
		TextColor3 = color:Lerp(BLACK, 0.45),
		Height = 22,
		TextSize = 12,
		ZIndex = 5,
		StrokeColor = WHITE,
		Parent = showcase,
	})
	kindChip.Position = UDim2.fromOffset(10, 10)

	-- ✕ (toujours visible, zone tactile de 44 px)
	local closeButton = UIUtil.Create("TextButton", {
		Name = "Close",
		Size = UDim2.fromOffset(36, 36),
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -8, 0, 8),
		BackgroundColor3 = WHITE,
		BackgroundTransparency = 0.1,
		AutoButtonColor = false,
		Font = Theme.Fonts.Title,
		Text = "✕",
		TextSize = 18,
		TextColor3 = Theme.Colors.Text,
		ZIndex = 7,
		Parent = card,
	})
	UIUtil.Corner(closeButton, UDim.new(1, 0))
	UIUtil.Stroke(closeButton, Theme.Colors.Border, 1.5, 0.5)
	local closeHitbox = UIUtil.Create("TextButton", {
		Name = "CloseHitbox",
		Size = UDim2.fromOffset(52, 52),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		BackgroundTransparency = 1,
		Text = "",
		ZIndex = 6,
		Parent = closeButton,
	})
	closeButton.Activated:Connect(close)
	closeHitbox.Activated:Connect(close)

	-- Textes
	local top = SHOWCASE_HEIGHT + 14
	UIUtil.Label({
		Name = "OfferName",
		Text = Locale.T(tostring(def.Name)),
		Font = Theme.Fonts.Title,
		Size = UDim2.new(1, -40, 0, 28),
		Position = UDim2.fromOffset(20, top),
		MaxTextSize = 26,
		ZIndex = 4,
		Parent = card,
	})
	local reason = UIUtil.Create("TextLabel", {
		Name = "Reason",
		Text = Locale.T(offer.Reason),
		Font = Theme.Fonts.Body,
		TextSize = 16,
		TextColor3 = Theme.Colors.TextDim,
		TextWrapped = true,
		TextScaled = true,
		BackgroundTransparency = 1,
		Size = UDim2.new(1, -48, 0, 38),
		Position = UDim2.fromOffset(24, top + 30),
		ZIndex = 4,
		Parent = card,
	})
	UIUtil.Create("UITextSizeConstraint", { MaxTextSize = 16, MinTextSize = 10, Parent = reason })
	local benefit = UIUtil.Chip({
		Name = "Benefit",
		Text = benefitText(offer),
		Color = color:Lerp(WHITE, 0.82),
		TextColor3 = color:Lerp(BLACK, 0.55),
		Height = 28,
		TextSize = 15,
		ZIndex = 4,
		StrokeColor = color,
		Parent = card,
	})
	benefit.AnchorPoint = Vector2.new(0.5, 0)
	benefit.Position = UDim2.new(0.5, 0, 0, top + 72)

	-- Boutons : "Non merci" + prix (R$)
	local margin, gap = 22, 12
	local noWidth = math.floor((CARD_SIZE.X - margin * 2 - gap) * 0.4)
	local buyWidth = CARD_SIZE.X - margin * 2 - gap - noWidth
	local no = pillButton(card, "NoThanks", Locale.T("No thanks"), Color3.fromRGB(238, 236, 244), Theme.Colors.TextDim, UDim2.new(0, margin + noWidth / 2, 1, -30), noWidth)
	local buyButton = pillButton(
		card,
		"Buy",
		"",
		Theme.Colors.Robux,
		Theme.Colors.TextLight,
		UDim2.new(1, -(margin + buyWidth / 2), 1, -30),
		buyWidth
	)
	local function paintPrice()
		if buyButton.Parent then
			buyButton.Text = Locale.T("Buy • R$ %s", NumberFormatter.WithSpaces(priceOf(offer)))
		end
	end
	paintPrice()
	fetchPrice(offer, paintPrice)
	no.Activated:Connect(function()
		SoundManager.Play("Click", 1.05)
		close()
	end)
	buyButton.Activated:Connect(function()
		buyOffer(offer, buyButton)
	end)
	UIUtil.Label({
		Name = "Footer",
		Text = Locale.T("🔒 Secure Roblox payment"),
		TextColor3 = Theme.Colors.TextDim,
		Size = UDim2.new(1, -40, 0, 14),
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -8),
		MaxTextSize = 12,
		ZIndex = 4,
		Parent = card,
	})

	-- Animation douce (seulement fenêtre ouverte) : rayons + icône qui flotte
	local started = os.clock()
	animation = RunService.RenderStepped:Connect(function(dt: number)
		local t = os.clock() - started
		rays.Rotation = (rays.Rotation + dt * 16) % 360
		icon.Position = UDim2.new(0.5, 0, 0.56, math.sin(t * 2) * 3)
		icon.Rotation = math.sin(t * 1.3) * 5
	end)
	SoundManager.Play("Open", 1.1)
end

-- Montre une offre si les règles le permettent
local function tryShow(): boolean
	if not allowed() then
		return false
	end
	local offer = chooseOffer()
	if not offer then
		return false
	end
	shownCount += 1
	lastShown = os.clock()
	shownIds[offer.Def.Id] = true
	intent = nil
	show(offer)
	return true
end

----------------------------------------------------------------------
-- API
----------------------------------------------------------------------

function OfferPopup.Build(parent: Frame)
	layer = parent
	sessionStart = os.clock()

	-- Une fenêtre s'ouvre (ou "Pas assez de Dopamine") : l'offre s'efface
	PanelManager.Opened:Connect(close)
	NeedDopamine.Shown:Connect(close)
	NeedDopamine.Refused:Connect(function(missing: number)
		intent = { Kind = "Refused", At = os.clock(), Missing = missing }
	end)
	ClientState.NotifyReceived:Connect(function(payload)
		if type(payload) == "table" and payload.Type == "Detox" then
			quietUntil = os.clock() + DETOX_QUIET
			close()
		end
	end)

	-- Surveillance légère : fin de rush / de boost, puis essai périodique
	task.spawn(function()
		local rushWasActive = false
		local boostWasActive = false
		local periodic = 0
		while layer do
			task.wait(CHECK_EVERY)
			local rush = ClientState.Rush
			local rushActive = rush ~= nil and rush.Active == true and (tonumber(rush.EndsAt) or 0) > workspace:GetServerTimeNow()
			if rushWasActive and not rushActive then
				intent = { Kind = "RushEnded", At = os.clock() }
				task.delay(AFTER_EVENT_DELAY, tryShow)
			end
			rushWasActive = rushActive
			local _, remaining = ClientState.GetBoost()
			local boostActive = remaining > 0
			if boostWasActive and not boostActive then
				intent = { Kind = "BoostEnded", At = os.clock() }
				task.delay(AFTER_EVENT_DELAY, tryShow)
			end
			boostWasActive = boostActive
			periodic += CHECK_EVERY
			if periodic >= PERIODIC_EVERY then
				periodic = 0
				tryShow()
			end
		end
	end)
end

function OfferPopup.IsVisible(): boolean
	return current ~= nil
end

function OfferPopup.Close()
	close()
end

-- Aperçu (Studio / tests) : montre une offre du genre demandé SANS les règles
-- de fréquence ; "Boost" | "Pass" | "Dopamine"
function OfferPopup.Preview(kind: string?)
	local offer: Offer?
	if kind == "Pass" then
		offer = makeOffer("X2", true, "New here? Double all your gains, forever.")
	elseif kind == "Dopamine" then
		offer = makeOffer(packFor(0) or "PackM", false, "Short on Dopamine earlier? A pack gets you there right away.")
	else
		offer = makeOffer("Boost2", false, "The Dopamine Rush is over. Want to keep that pace a little longer?")
	end
	if offer then
		show(offer)
	end
end

-- Offre affichée (nil si aucune) — pour les tests
function OfferPopup.GetCurrent(): any
	return currentOffer and currentOffer.Def or nil
end

return OfferPopup
