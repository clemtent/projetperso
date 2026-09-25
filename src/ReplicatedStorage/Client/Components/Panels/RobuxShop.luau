--[[
	RobuxShop (ModuleScript) — "💎 Boutique Robux"
	Emplacement : ReplicatedStorage > Client > Components > Panels > RobuxShop

	Présentation "premium" construite depuis Config.Monetization :
	  - bannière violette animée (diamant, rayons, étincelles) avec ton état :
	    VIP, bonus des Game Passes, boost en cours (compte à rebours) ;
	  - onglets Tout / Passes / Dopamine / Boosts ;
	  - grandes cartes illustrées : vitrine au dégradé de l'offre, rayons,
	    rubans ("MEILLEURE OFFRE", "POPULAIRE"...), avantages en pastilles,
	    bouton prix R$ (vrai prix Roblox), "✔ Acheté" pour les passes possédés.
	Les offres dont l'ID vaut 0 sont cachées dans le jeu publié. Dans Studio,
	elles restent visibles en APERÇU (bouton "ID à configurer") pour que le
	propriétaire voie la boutique ; s'il n'y a rien à vendre dans le jeu
	publié : "Bientôt disponible".

	Le vrai prix vient de MarketplaceService:GetProductInfo (dans un thread
	séparé, protégé par pcall, mis en cache) ; en attendant ou en cas
	d'erreur, on affiche Config PriceHint.
	L'achat ouvre la fenêtre Roblox (PromptGamePassPurchase /
	PromptProductPurchase). Le SERVEUR vérifie et donne l'achat, puis
	envoie Notify { Type = "Purchase" } (fête + confettis gérés par Notifications).
]]

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Client = script.Parent.Parent.Parent
local Theme = require(Client.Theme)
local UIUtil = require(Client.UIUtil)
local ClientState = require(Client.ClientState)
local SoundManager = require(Client.SoundManager)
local Notifications = require(script.Parent.Parent.Notifications)
local Config = require(ReplicatedStorage.Shared.Config)
local Formulas = require(ReplicatedStorage.Shared.Formulas)
local NumberFormatter = require(ReplicatedStorage.Shared.NumberFormatter)
local Locale = require(ReplicatedStorage.Shared.Locale)

-- Title / Subtitle en anglais : traduits par PanelManager
local RobuxShop = {
	Title = "💎 Robux Shop",
	Subtitle = "Thanks for supporting the game 💖",
	Color = Theme.Colors.Robux,
	Size = Vector2.new(800, 600),
}

local WHITE = Color3.new(1, 1, 1)
local HERO_TOP = Color3.fromRGB(64, 28, 140)
local HERO_BOTTOM = Color3.fromRGB(200, 50, 160)

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
-- Rubans de mise en avant (Id de l'offre -> texte anglais, traduit à l'affichage)
local HIGHLIGHTS = {
	X10 = "🔥 BEST DEAL",
	VIP = "⭐ POPULAR",
	PackL = "💰 BEST VALUE",
	Boost5 = "⚡ POWERFUL",
}

local PENDING_TIMEOUT = 20 -- secondes d'attente max de l'activation d'un pass acheté
local PROMPT_COOLDOWN = 1
local RETRY_DELAY = 30 -- nouvel essai de GetProductInfo après une erreur

type Offer = {
	Def: any,
	IsPass: boolean,
	Id: number,
	Category: string, -- "Passes" | "Dopamine" | "Boosts"
	Color: Color3,
	Cell: Frame,
	Card: Frame,
	Stroke: UIStroke,
	Button: TextButton,
	Extra: TextLabel?,
	Owned: Frame?,
	Kind: Frame?, -- pastille "Pour toujours" / "Rachetable"
	Rays: Frame,
	Hovered: boolean,
}

local player = Players.LocalPlayer
local offers: { Offer } = {}
local priceCache: { [string]: { Price: number?, ForSale: boolean } } = {}
local fetching: { [string]: boolean } = {}
local lastFailure: { [string]: number } = {}
local pendingPasses: { [number]: number } = {} -- [GamePassId] = os.clock() de l'achat
local lastPrompt = 0
local visible = false
local filter = "All"
local filterTabs: UIUtil.Tabs? = nil
local animation: RBXScriptConnection? = nil
local refreshClock = 0

local heroStatus: TextLabel
local heroChips: { VIP: Frame, Bonus: Frame, Boost: Frame } = {} :: any
local heroDiamond: TextLabel
local heroRays: Frame
local sparkles: { TextLabel } = {}
local filterEmpty: TextLabel

----------------------------------------------------------------------
-- Prix (MarketplaceService, jamais sur le thread de rendu)
----------------------------------------------------------------------

local function cacheKey(isPass: boolean, id: number): string
	return (isPass and "Pass:" or "Product:") .. tostring(id)
end

local refreshOffer: (offer: Offer) -> () -- défini plus bas

local function fetchPrice(offer: Offer)
	if offer.Id == 0 then
		return
	end
	local key = cacheKey(offer.IsPass, offer.Id)
	if priceCache[key] or fetching[key] then
		return
	end
	if lastFailure[key] and os.clock() - lastFailure[key] < RETRY_DELAY then
		return
	end
	fetching[key] = true
	task.spawn(function()
		local infoType = offer.IsPass and Enum.InfoType.GamePass or Enum.InfoType.Product
		local ok, info = pcall(function()
			return MarketplaceService:GetProductInfo(offer.Id, infoType)
		end)
		fetching[key] = nil
		if ok and type(info) == "table" then
			local price = tonumber(info.PriceInRobux)
			local forSale = info.IsForSale ~= false and price ~= nil
			if not offer.IsPass then
				-- Les Developer Products n'ont pas toujours IsForSale : le prix suffit
				forSale = price ~= nil
			end
			priceCache[key] = { Price = price, ForSale = forSale }
		else
			lastFailure[key] = os.clock()
			warn("[RobuxShop] Prix introuvable pour " .. key .. " : " .. tostring(info))
		end
		if offer.Card.Parent then
			refreshOffer(offer)
		end
	end)
end

-- (texte du prix, en vente ?)
local function priceText(offer: Offer): (string, boolean)
	if offer.Id == 0 then
		return "R$ " .. NumberFormatter.WithSpaces(tonumber(offer.Def.PriceHint) or 0), false
	end
	local cached = priceCache[cacheKey(offer.IsPass, offer.Id)]
	if cached then
		if not cached.ForSale or not cached.Price then
			return Locale.T("Unavailable"), false
		end
		return "R$ " .. NumberFormatter.WithSpaces(cached.Price), true
	end
	return "R$ " .. NumberFormatter.WithSpaces(tonumber(offer.Def.PriceHint) or 0), true
end

----------------------------------------------------------------------
-- Achat
----------------------------------------------------------------------

local function prompt(offer: Offer)
	if os.clock() - lastPrompt < PROMPT_COOLDOWN then
		return
	end
	lastPrompt = os.clock()
	if offer.Id == 0 then
		SoundManager.Play("Error", 0.8)
		UIUtil.Shake(offer.Button)
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
	if offer.IsPass and ClientState.HasPass(offer.Def.Id) then
		SoundManager.Play("Error", 0.8)
		return
	end
	local _, forSale = priceText(offer)
	if not forSale then
		SoundManager.Play("Error", 0.7)
		UIUtil.Shake(offer.Button)
		Notifications.Toast(Locale.T("This offer isn't on sale right now."), Theme.Colors.Red)
		return
	end
	SoundManager.Play("Click", 1.2)
	UIUtil.Pop(offer.Card, 1.05, 0.3)
	local ok, err = pcall(function()
		if offer.IsPass then
			MarketplaceService:PromptGamePassPurchase(player, offer.Id)
		else
			MarketplaceService:PromptProductPurchase(player, offer.Id)
		end
	end)
	if not ok then
		warn("[RobuxShop] Impossible d'ouvrir l'achat : " .. tostring(err))
		Notifications.Toast(Locale.T("Can't buy right now, try again."), Theme.Colors.Red)
	end
end

----------------------------------------------------------------------
-- Affichage d'une offre
----------------------------------------------------------------------

local function styleButton(button: TextButton, text: string, background: Color3, textColor: Color3, enabled: boolean)
	if button.Text ~= text then
		button.Text = text
	end
	button:SetAttribute("BaseColor", background)
	button.BackgroundColor3 = background
	button.TextColor3 = textColor
	button.TextTransparency = 0
	button:SetAttribute("Enabled", enabled)
end

function refreshOffer(offer: Offer)
	local def = offer.Def
	local owned = offer.IsPass and ClientState.HasPass(def.Id)
	if offer.Owned then
		offer.Owned.Visible = owned
		-- (le tampon "✔ ACHETÉ" prend la place de la pastille "Pour toujours")
		if offer.Kind then
			offer.Kind.Visible = not owned
		end
	end
	if owned then
		pendingPasses[offer.Id] = nil
		styleButton(offer.Button, Locale.T("✔ Purchased"), Color3.fromRGB(222, 247, 232), Theme.Colors.RobuxDark, false)
		offer.Stroke.Color = Theme.Colors.Robux
		offer.Stroke.Thickness = 2
		offer.Stroke.Transparency = 0
		return
	end
	offer.Stroke.Color = offer.Color:Lerp(Color3.new(0, 0, 0), 0.2)
	offer.Stroke.Thickness = offer.Hovered and 2 or 1.5
	offer.Stroke.Transparency = offer.Hovered and 0 or 0.35
	local pendingSince = offer.IsPass and pendingPasses[offer.Id]
	if pendingSince and os.clock() - pendingSince < PENDING_TIMEOUT then
		styleButton(offer.Button, Locale.T("⏳ Activating…"), Theme.Colors.PanelLight, Theme.Colors.TextDim, false)
		return
	end
	if offer.Id == 0 then
		styleButton(offer.Button, Locale.T("🛠️ ID to set up"), Theme.Colors.PanelLight, Theme.Colors.TextDim, false)
		return
	end
	local text, forSale = priceText(offer)
	if forSale then
		styleButton(offer.Button, text, Theme.Colors.Robux, Theme.Colors.TextLight, true)
	else
		styleButton(offer.Button, text, Theme.Colors.Disabled, Theme.Colors.TextDim, false)
	end
end

-- Ligne "extra" : estimation du gain / boost actif / effet
local function refreshExtra(offer: Offer, data)
	local extra = offer.Extra
	if not extra then
		return
	end
	local def = offer.Def
	local text = ""
	local color = Theme.Colors.TextDim
	if offer.IsPass then
		if def.Multiplier then
			text = Locale.T("📈 Gains %s forever", NumberFormatter.Multiplier(def.Multiplier))
			color = offer.Color:Lerp(Color3.new(0, 0, 0), 0.35)
		elseif def.AutoClicksPerSecond then
			text = Locale.T("🤖 %s clicks / second", tostring(def.AutoClicksPerSecond))
			color = offer.Color:Lerp(Color3.new(0, 0, 0), 0.35)
		end
		if def.UnlockPremiumThemes then
			text = (text ~= "" and (text .. " • ") or "") .. Locale.T("🎨 Premium themes")
		end
	elseif def.Kind == "Dopamine" then
		local stats = { PerSecond = tonumber(data and data.PerSecond) or 0, ClickValue = tonumber(data and data.ClickValue) or 0 }
		local amount = Formulas.ScaledReward(stats, tonumber(def.Seconds) or 0, tonumber(def.Minimum) or 0)
		text = "≈ +" .. NumberFormatter.Format(amount) .. " Dopamine"
		color = Theme.Colors.Blue
	elseif def.Kind == "Boost" then
		local multiplier, remaining = ClientState.GetBoost()
		if remaining > 0 then
			text = Locale.T("⏱️ Active: %s • %s", NumberFormatter.Multiplier(multiplier), UIUtil.FormatClock(remaining))
			color = Theme.Colors.Boost
		else
			text = Locale.T("⏱️ Duration: %s", NumberFormatter.Time(tonumber(def.Duration) or 0))
		end
	elseif def.Kind == "ServerRush" then
		text = Locale.T("🎉 The whole server benefits")
		color = Theme.Colors.Pink
	end
	if extra.Text ~= text then
		extra.Text = text
	end
	extra.TextColor3 = color
end

----------------------------------------------------------------------
-- Bannière
----------------------------------------------------------------------

local function setChip(chip: Frame, show: boolean, text: string?)
	if chip.Visible ~= show then
		chip.Visible = show
		if show then
			UIUtil.Pop(chip, 0.4, 0.35)
		end
	end
	if show and text then
		local label = chip:FindFirstChild("Label") :: TextLabel?
		if label and label.Text ~= text then
			label.Text = text
		end
	end
end

local function refreshStatus(data)
	if not heroStatus then
		return
	end
	local multiplier, remaining = ClientState.GetBoost()
	local vip = ClientState.IsVIP()
	if remaining > 0 then
		heroStatus.Text = Locale.T("🔥 Your boost is active: enjoy it!")
	elseif vip then
		heroStatus.Text = Locale.T("👑 You're VIP — thanks for your support!")
	else
		heroStatus.Text = Locale.T("Purchases are tied to your account and kept forever.")
	end
	local bonus = tonumber(data and data.BonusMultiplier) or ClientState.GetPassMultiplier()
	setChip(heroChips.VIP, vip, "👑 VIP")
	setChip(heroChips.Bonus, bonus > 1.001, "💎 Bonus " .. NumberFormatter.Multiplier(bonus))
	setChip(heroChips.Boost, remaining > 0, string.format("⏱️ %s • %s", NumberFormatter.Multiplier(multiplier), UIUtil.FormatClock(remaining)))
end

local function buildHero(content: Frame)
	local hero = UIUtil.Create("Frame", {
		Name = "Hero",
		Size = UDim2.new(1, 0, 0, 110),
		BackgroundColor3 = WHITE,
		ClipsDescendants = true,
		Parent = content,
	})
	UIUtil.Corner(hero, Theme.Radius.L)
	UIUtil.Stroke(hero, HERO_TOP, 1.5, 0.3)
	UIUtil.Gradient(hero, ColorSequence.new(HERO_TOP, HERO_BOTTOM), 15)

	-- Étincelles
	local random = Random.new(42)
	for index = 1, 12 do
		local star = UIUtil.Label({
			Name = "Sparkle" .. index,
			Text = index % 3 == 0 and "✦" or "•",
			TextColor3 = WHITE,
			Size = UDim2.fromOffset(14, 14),
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(random:NextNumber(0.35, 0.98), random:NextNumber(0.08, 0.92)),
			MaxTextSize = index % 3 == 0 and 14 or 10,
			ZIndex = 2,
			Parent = hero,
		})
		star:SetAttribute("Phase", random:NextNumber(0, math.pi * 2))
		table.insert(sparkles, star)
	end

	-- Gros diamant à droite, devant des rayons
	heroRays = UIUtil.Rays(hero, WHITE, 8, 220, UDim2.new(1, -80, 0.5, 0), 2)
	local halo = UIUtil.Create("Frame", {
		Name = "Halo",
		Size = UDim2.fromOffset(92, 92),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(1, -80, 0.5, 0),
		BackgroundColor3 = WHITE,
		BackgroundTransparency = 0.8,
		ZIndex = 2,
		Parent = hero,
	})
	UIUtil.Corner(halo, UDim.new(1, 0))
	heroDiamond = UIUtil.Label({
		Name = "Diamond",
		Text = "💎",
		Size = UDim2.fromOffset(76, 76),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(1, -80, 0.5, 0),
		MaxTextSize = 64,
		ZIndex = 3,
		Parent = hero,
	})

	local title = UIUtil.Label({
		Name = "HeroTitle",
		Text = Locale.T("Robux Shop"),
		Font = Theme.Fonts.Title,
		TextColor3 = WHITE,
		TextXAlignment = Enum.TextXAlignment.Left,
		Size = UDim2.new(1, -200, 0, 30),
		Position = UDim2.fromOffset(18, 12),
		MaxTextSize = 26,
		ZIndex = 3,
		Parent = hero,
	})
	local stroke = UIUtil.Stroke(title, Color3.fromRGB(40, 10, 80), 1.5, 0.4)
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
	heroStatus = UIUtil.Label({
		Name = "Status",
		Text = "",
		TextColor3 = WHITE,
		TextXAlignment = Enum.TextXAlignment.Left,
		Size = UDim2.new(1, -200, 0, 18),
		Position = UDim2.fromOffset(18, 44),
		MaxTextSize = 15,
		ZIndex = 3,
		Parent = hero,
	})

	local chips = UIUtil.Create("Frame", {
		Name = "Chips",
		Size = UDim2.new(1, -200, 0, 26),
		Position = UDim2.fromOffset(18, 72),
		BackgroundTransparency = 1,
		ZIndex = 3,
		Parent = hero,
	})
	UIUtil.Create("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		Padding = UDim.new(0, 8),
		SortOrder = Enum.SortOrder.LayoutOrder,
		VerticalAlignment = Enum.VerticalAlignment.Center,
		Parent = chips,
	})
	local function chip(order: number, color: Color3, textColor: Color3): Frame
		return UIUtil.Chip({
			Text = "",
			Color = color,
			TextColor3 = textColor,
			Height = 24,
			TextSize = 13,
			LayoutOrder = order,
			ZIndex = 4,
			StrokeColor = WHITE,
			Visible = false,
			Parent = chips,
		})
	end
	heroChips = {
		VIP = chip(1, Theme.Colors.Premium, Theme.Colors.TextDark),
		Bonus = chip(2, WHITE, HERO_TOP),
		Boost = chip(3, Theme.Colors.Boost, Theme.Colors.TextLight),
	}
	-- Toujours visible : rappel "achat sécurisé"
	local safe = chip(4, WHITE, Theme.Colors.RobuxDark)
	safe.Visible = true
	setChip(safe, true, Locale.T("🔒 Secure Roblox payment"))
end

----------------------------------------------------------------------
-- Construction des cartes
----------------------------------------------------------------------

local function buildCard(grid: ScrollingFrame, def, isPass: boolean, order: number)
	local color: Color3 = isPass and (PASS_COLORS[def.Id] or Theme.Colors.Purple)
		or (PRODUCT_COLORS[def.Kind] or Theme.Colors.Cyan)
	local category = isPass and "Passes" or (def.Kind == "Dopamine" and "Dopamine" or "Boosts")

	local cell = UIUtil.Create("Frame", {
		Name = tostring(def.Id),
		BackgroundTransparency = 1,
		LayoutOrder = order,
		Parent = grid,
	})
	local card = UIUtil.Create("Frame", {
		Name = "Card",
		Size = UDim2.new(1, 0, 1, -6),
		Position = UDim2.fromOffset(0, 5),
		BackgroundColor3 = Theme.Colors.Card,
		ZIndex = 2,
		Parent = cell,
	})
	UIUtil.Corner(card, Theme.Radius.L)
	local stroke = UIUtil.Stroke(card, color:Lerp(Color3.new(0, 0, 0), 0.2), 1.5, 0.35)
	UIUtil.Shadow(card, 3, 0.86, 2)

	-- Vitrine
	local showcase = UIUtil.Create("Frame", {
		Name = "Showcase",
		Size = UDim2.new(1, -10, 0, 104),
		Position = UDim2.fromOffset(5, 5),
		BackgroundColor3 = WHITE,
		ClipsDescendants = true,
		ZIndex = 3,
		Parent = card,
	})
	UIUtil.Corner(showcase, Theme.Radius.M)
	UIUtil.SoftGradient(showcase, color, 90)
	local rays = UIUtil.Rays(showcase, WHITE, 6, 190, UDim2.fromScale(0.5, 0.55), 3)
	local glow = UIUtil.Create("Frame", {
		Name = "Glow",
		Size = UDim2.fromOffset(74, 74),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.55),
		BackgroundColor3 = WHITE,
		BackgroundTransparency = 0.55,
		ZIndex = 3,
		Parent = showcase,
	})
	UIUtil.Corner(glow, UDim.new(1, 0))
	UIUtil.Label({
		Name = "Icon",
		Text = tostring(def.Icon or (isPass and "🎟️" or "💧")),
		Size = UDim2.fromOffset(64, 64),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.56),
		MaxTextSize = 54,
		ZIndex = 4,
		Parent = showcase,
	})

	-- "Pour toujours" / "Rachetable"
	local kindChip = UIUtil.Chip({
		Name = "Kind",
		Text = isPass and Locale.T("♾️ FOREVER") or Locale.T("🔁 REBUYABLE"),
		Color = WHITE,
		TextColor3 = color:Lerp(Color3.new(0, 0, 0), 0.45),
		Height = 18,
		TextSize = 10,
		ZIndex = 5,
		StrokeColor = WHITE,
		Parent = showcase,
	})
	kindChip.Position = UDim2.fromOffset(6, 6)

	-- Ruban de mise en avant
	local highlight = HIGHLIGHTS[def.Id]
	if highlight then
		-- Deux pastilles ne tiennent pas sur une ligne : "Pour toujours" se
		-- réduit à son icône (la ligne "Extra" le redit en toutes lettres)
		local kindLabel = kindChip:FindFirstChild("Label") :: TextLabel?
		if kindLabel then
			kindLabel.Text = isPass and "♾️" or "🔁"
		end
		local ribbon = UIUtil.Chip({
			Name = "Highlight",
			Text = Locale.T(highlight),
			Color = Theme.Colors.Premium,
			TextColor3 = Theme.Colors.TextDark,
			Height = 18,
			TextSize = 10,
			ZIndex = 5,
			Parent = showcase,
		})
		ribbon.AnchorPoint = Vector2.new(1, 0)
		ribbon.Position = UDim2.new(1, -6, 0, 6)
	end

	-- Ruban "✔ ACHETÉ" (passes possédés)
	local owned: Frame? = nil
	if isPass then
		-- En haut à gauche, à la place de "Pour toujours" : ne cache pas l'icône
		local ownedChip = UIUtil.Chip({
			Name = "Owned",
			Text = Locale.T("✔ PURCHASED"),
			Color = Theme.Colors.Robux,
			TextColor3 = WHITE,
			Height = 18,
			TextSize = 10,
			ZIndex = 6,
			Visible = false,
			StrokeColor = WHITE,
			Parent = showcase,
		})
		ownedChip.Position = UDim2.fromOffset(6, 6)
		owned = ownedChip
	end

	UIUtil.Label({
		Name = "OfferName",
		Text = Locale.T(tostring(def.Name)),
		Font = Theme.Fonts.Title,
		Size = UDim2.new(1, -16, 0, 22),
		Position = UDim2.fromOffset(8, 114),
		MaxTextSize = 18,
		ZIndex = 3,
		Parent = card,
	})
	local desc = UIUtil.Create("TextLabel", {
		Name = "Description",
		Text = Locale.T(tostring(def.Description or "")),
		Font = Theme.Fonts.Body,
		TextSize = 14,
		TextColor3 = Theme.Colors.TextDim,
		TextWrapped = true,
		BackgroundTransparency = 1,
		Size = UDim2.new(1, -20, 0, 32),
		Position = UDim2.fromOffset(10, 137),
		ZIndex = 3,
		Parent = card,
	})
	desc.TextTruncate = Enum.TextTruncate.AtEnd
	local extra = UIUtil.Label({
		Name = "Extra",
		Text = "",
		Font = Theme.Fonts.Title,
		TextColor3 = Theme.Colors.TextDim,
		Size = UDim2.new(1, -16, 0, 16),
		Position = UDim2.fromOffset(8, 171),
		MaxTextSize = 13,
		ZIndex = 3,
		Parent = card,
	})

	local button = UIUtil.NeonButton({
		Name = "Price",
		Text = "",
		Color = Theme.Colors.Robux,
		TextColor3 = Theme.Colors.TextLight,
		Size = UDim2.new(1, -20, 0, 36),
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -9),
		CornerRadius = 18,
		MaxTextSize = 17,
		ZIndex = 4,
		Parent = card,
	})

	local offer: Offer = {
		Def = def,
		IsPass = isPass,
		Id = tonumber(isPass and def.GamePassId or def.ProductId) or 0,
		Category = category,
		Color = color,
		Cell = cell,
		Card = card,
		Stroke = stroke,
		Button = button,
		Extra = extra,
		Owned = owned,
		Kind = kindChip,
		Rays = rays,
		Hovered = false,
	}
	button.Activated:Connect(function()
		prompt(offer)
	end)
	local function hover(on: boolean)
		offer.Hovered = on
		UIUtil.Tween(card, 0.18, { Position = UDim2.fromOffset(0, on and 0 or 5) }, Enum.EasingStyle.Quad)
		refreshOffer(offer)
	end
	card.MouseEnter:Connect(function()
		hover(true)
	end)
	card.MouseLeave:Connect(function()
		hover(false)
	end)
	table.insert(offers, offer)
	refreshOffer(offer)
	refreshExtra(offer, ClientState.Data)
end

local function applyFilter()
	local shown = 0
	for _, offer in ipairs(offers) do
		local show = filter == "All" or offer.Category == filter
		offer.Cell.Visible = show
		if show then
			shown += 1
		end
	end
	if filterEmpty then
		filterEmpty.Visible = shown == 0 and #offers > 0
	end
end

----------------------------------------------------------------------
-- API du panneau
----------------------------------------------------------------------

function RobuxShop.Build(content: Frame)
	local studio = RunService:IsStudio()
	buildHero(content)

	filterTabs = UIUtil.Tabs({
		Parent = content,
		Tabs = {
			{ Id = "All", Text = Locale.T("⭐ All") },
			{ Id = "Passes", Text = "🎟️ Passes" },
			{ Id = "Dopamine", Text = "💧 Dopamine" },
			{ Id = "Boosts", Text = "⚡ Boosts" },
		},
		Color = Theme.Colors.Purple,
		Size = UDim2.new(1, 0, 0, 36),
		Position = UDim2.fromOffset(0, 118),
		Selected = filter,
		OnSelect = function(id: string)
			filter = id
			applyFilter()
			SoundManager.Play("Click", 1.3)
		end,
	})

	-- Offres affichées : configurées (ID ~= 0) ; dans Studio, aussi les autres (aperçu)
	local passes, products = {}, {}
	local hidden = 0
	for _, pass in ipairs(Config.Monetization.GamePasses) do
		if (tonumber(pass.GamePassId) or 0) ~= 0 or studio then
			table.insert(passes, pass)
		end
		if (tonumber(pass.GamePassId) or 0) == 0 then
			hidden += 1
		end
	end
	for _, product in ipairs(Config.Monetization.Products) do
		if (tonumber(product.ProductId) or 0) ~= 0 or studio then
			table.insert(products, product)
		end
		if (tonumber(product.ProductId) or 0) == 0 then
			hidden += 1
		end
	end

	local top = 162
	if studio and hidden > 0 then
		-- Bandeau d'aide pour le propriétaire (Studio uniquement)
		local notice = UIUtil.Create("Frame", {
			Name = "StudioNotice",
			Size = UDim2.new(1, 0, 0, 26),
			Position = UDim2.fromOffset(0, top),
			BackgroundColor3 = Color3.fromRGB(255, 244, 220),
			Parent = content,
		})
		UIUtil.Corner(notice, Theme.Radius.S)
		UIUtil.Stroke(notice, Theme.Colors.Orange, 1, 0.5)
		UIUtil.Label({
			Text = Locale.T(
				"🛠️ Studio preview: %d offer(s) without an ID (0) — hidden in the published game. Paste your IDs in Config.Monetization.",
				hidden
			),
			TextColor3 = Color3.fromRGB(150, 80, 0),
			Size = UDim2.new(1, -16, 1, -8),
			Position = UDim2.fromOffset(8, 4),
			MaxTextSize = 13,
			Parent = notice,
		})
		top += 32
	end

	local grid = UIUtil.Create("ScrollingFrame", {
		Name = "Offers",
		Size = UDim2.new(1, 0, 1, -top),
		Position = UDim2.fromOffset(0, top),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 5,
		ScrollBarImageColor3 = Theme.Colors.Purple,
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollingDirection = Enum.ScrollingDirection.Y,
		Parent = content,
	})
	UIUtil.Create("UIPadding", {
		PaddingTop = UDim.new(0, 2),
		PaddingLeft = UDim.new(0, 4),
		PaddingRight = UDim.new(0, 12),
		PaddingBottom = UDim.new(0, 10),
		Parent = grid,
	})
	UIUtil.Create("UIGridLayout", {
		CellSize = UDim2.new(1 / 3, -10, 0, 246), -- (8 px d'air entre la ligne "Extra" et le bouton)
		CellPadding = UDim2.fromOffset(10, 6),
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = grid,
	})

	local order = 0
	for _, pass in ipairs(passes) do
		order += 1
		buildCard(grid, pass, true, order)
	end
	for _, product in ipairs(products) do
		order += 1
		buildCard(grid, product, false, order)
	end

	filterEmpty = UIUtil.Label({
		Name = "FilterEmpty",
		Text = Locale.T("Nothing in this category for now."),
		TextColor3 = Theme.Colors.TextDim,
		Size = UDim2.new(1, 0, 0, 30),
		Position = UDim2.fromOffset(0, top + 40),
		MaxTextSize = 16,
		Visible = false,
		Parent = content,
	})

	-- Rien à vendre (jeu publié) : état vide propre
	if #offers == 0 then
		local empty = UIUtil.Create("Frame", {
			Name = "Empty",
			Size = UDim2.new(1, 0, 1, -top),
			Position = UDim2.fromOffset(0, top),
			BackgroundTransparency = 1,
			Parent = content,
		})
		local bubble = UIUtil.Create("Frame", {
			Size = UDim2.fromOffset(110, 110),
			AnchorPoint = Vector2.new(0.5, 0),
			Position = UDim2.new(0.5, 0, 0, 30),
			BackgroundColor3 = Theme.Colors.Surface,
			Parent = empty,
		})
		UIUtil.Corner(bubble, UDim.new(1, 0))
		UIUtil.Stroke(bubble, Theme.Colors.Divider, 2)
		UIUtil.Label({
			Text = "💎",
			Size = UDim2.new(1, -24, 1, -24),
			Position = UDim2.fromOffset(12, 12),
			MaxTextSize = 60,
			Parent = bubble,
		})
		UIUtil.Label({
			Text = Locale.T("Coming soon"),
			Font = Theme.Fonts.Title,
			Size = UDim2.new(1, -40, 0, 30),
			Position = UDim2.fromOffset(20, 156),
			MaxTextSize = 24,
			Parent = empty,
		})
		UIUtil.Label({
			Text = Locale.T("The shop opens very soon. Come back and see us! 💖"),
			TextColor3 = Theme.Colors.TextDim,
			Size = UDim2.new(1, -80, 0, 22),
			Position = UDim2.fromOffset(40, 192),
			MaxTextSize = 16,
			Parent = empty,
		})
	end
	applyFilter()

	-- Pass acheté : "⏳ Activation…" jusqu'à la confirmation du serveur
	MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(who: Player, passId: number, purchased: boolean)
		if who ~= player or not purchased then
			return
		end
		pendingPasses[passId] = os.clock()
		for _, offer in ipairs(offers) do
			if offer.IsPass and offer.Id == passId then
				refreshOffer(offer)
			end
		end
	end)

	refreshStatus(ClientState.Data)
end

-- Ouvre directement un onglet ("Dopamine" quand il en manque pour un achat)
function RobuxShop.ShowTab(id: string)
	filter = id
	local tabs = filterTabs
	if tabs then
		tabs.Select(id, true)
	end
	applyFilter()
end

function RobuxShop.OnOpen()
	visible = true
	-- Vrais prix (threads séparés : ne bloque jamais l'interface)
	for _, offer in ipairs(offers) do
		fetchPrice(offer)
	end
	refreshStatus(ClientState.Data)

	-- Animations (seulement fenêtre ouverte) : rayons, diamant, étincelles,
	-- et comptes à rebours (boost, activation) 2 fois par seconde
	if animation then
		animation:Disconnect()
	end
	local started = os.clock()
	animation = RunService.RenderStepped:Connect(function(dt: number)
		local t = os.clock() - started
		heroRays.Rotation = (heroRays.Rotation + dt * 14) % 360
		heroDiamond.Position = UDim2.new(1, -80, 0.5, math.sin(t * 2) * 4)
		heroDiamond.Rotation = math.sin(t * 1.3) * 6
		for _, star in ipairs(sparkles) do
			local phase = star:GetAttribute("Phase") or 0
			star.TextTransparency = 0.2 + 0.6 * (0.5 + 0.5 * math.sin(t * 2.5 + phase))
		end
		for _, offer in ipairs(offers) do
			if offer.Cell.Visible then
				offer.Rays.Rotation = (offer.Rays.Rotation + dt * (offer.Hovered and 60 or 12)) % 360
			end
		end
		refreshClock += dt
		if refreshClock >= 0.5 then
			refreshClock = 0
			local data = ClientState.Data
			refreshStatus(data)
			for _, offer in ipairs(offers) do
				if offer.Def.Kind == "Boost" then
					refreshExtra(offer, data)
				end
				if offer.IsPass and pendingPasses[offer.Id] then
					refreshOffer(offer)
				end
			end
		end
	end)
end

function RobuxShop.OnClose()
	visible = false
	local connection = animation
	if connection then
		connection:Disconnect()
		animation = nil
	end
end

function RobuxShop.Update(data)
	for _, offer in ipairs(offers) do
		refreshOffer(offer)
		refreshExtra(offer, data)
	end
	refreshStatus(data)
end

-- Vrai si au moins une offre Robux est configurée (utilisé par la colonne centrale)
function RobuxShop.HasOffers(): boolean
	return Config.IsSellingForRobux == true
end

-- Vrai si la boutique est ouverte
function RobuxShop.IsOpen(): boolean
	return visible
end

return RobuxShop
