--[[
	RobuxShop (ModuleScript) — "💎 Boutique Robux"
	Emplacement : ReplicatedStorage > Client > Components > Panels > RobuxShop

	Deux sections construites depuis Config.Monetization :
	  - "Game Passes" (achat unique, pour toujours) : x10, x2, Auto-clic, VIP...
	  - "Packs & Boosts" (Developer Products, rachetables) : doses de
	    Dopamine, boosts temporaires, Rush pour tout le serveur.
	Les offres dont l'ID vaut 0 sont cachées. Si TOUT est à 0 : message
	"Bientôt disponible" (et, dans Studio, l'aide pour le propriétaire du jeu).

	Le vrai prix vient de MarketplaceService:GetProductInfo (dans un thread
	séparé, protégé par pcall, mis en cache) ; en attendant ou en cas
	d'erreur, on affiche Config PriceHint.
	L'achat ouvre la fenêtre Roblox (PromptGamePassPurchase /
	PromptProductPurchase). Le SERVEUR vérifie et donne l'achat, puis
	envoie Notify { Type = "Purchase" } (fête gérée par Notifications).
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

local RobuxShop = {
	Title = "💎 Boutique Robux",
	Subtitle = "Merci de soutenir le jeu 💖",
	Color = Theme.Colors.Robux,
	Size = Vector2.new(760, 540),
}

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

local PENDING_TIMEOUT = 20 -- secondes d'attente max de l'activation d'un pass acheté
local PROMPT_COOLDOWN = 1
local RETRY_DELAY = 30 -- nouvel essai de GetProductInfo après une erreur

type Offer = {
	Def: any,
	IsPass: boolean,
	Id: number,
	Card: Frame,
	Stroke: UIStroke,
	Button: TextButton,
	Extra: TextLabel?,
}

local player = Players.LocalPlayer
local offers: { Offer } = {}
local priceCache: { [string]: { Price: number?, ForSale: boolean } } = {}
local fetching: { [string]: boolean } = {}
local lastFailure: { [string]: number } = {}
local pendingPasses: { [number]: number } = {} -- [GamePassId] = os.clock() de l'achat
local lastPrompt = 0
local visible = false

local statusLabel: TextLabel
local bonusChip: Frame
local statusBar: Frame

----------------------------------------------------------------------
-- Prix (MarketplaceService, jamais sur le thread de rendu)
----------------------------------------------------------------------

local function cacheKey(isPass: boolean, id: number): string
	return (isPass and "Pass:" or "Product:") .. tostring(id)
end

local refreshOffer: (offer: Offer) -> () -- défini plus bas

local function fetchPrice(offer: Offer)
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

local function priceText(offer: Offer): (string, boolean)
	local cached = priceCache[cacheKey(offer.IsPass, offer.Id)]
	if cached then
		if not cached.ForSale or not cached.Price then
			return "Indisponible", false
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
	if offer.IsPass and ClientState.HasPass(offer.Def.Id) then
		SoundManager.Play("Error", 0.8)
		return
	end
	local _, forSale = priceText(offer)
	if not forSale then
		SoundManager.Play("Error", 0.7)
		UIUtil.Shake(offer.Button)
		Notifications.Toast("Cette offre n'est pas en vente pour le moment.", Theme.Colors.Red)
		return
	end
	SoundManager.Play("Click", 1.2)
	local ok, err = pcall(function()
		if offer.IsPass then
			MarketplaceService:PromptGamePassPurchase(player, offer.Id)
		else
			MarketplaceService:PromptProductPurchase(player, offer.Id)
		end
	end)
	if not ok then
		warn("[RobuxShop] Impossible d'ouvrir l'achat : " .. tostring(err))
		Notifications.Toast("Achat impossible pour le moment, réessaie.", Theme.Colors.Red)
	end
end

----------------------------------------------------------------------
-- Affichage d'une offre
----------------------------------------------------------------------

local function styleButton(button: TextButton, text: string, background: Color3, textColor: Color3, enabled: boolean)
	button.Text = text
	button:SetAttribute("BaseColor", background)
	button.BackgroundColor3 = background
	button.TextColor3 = textColor
	button.TextTransparency = 0
	button:SetAttribute("Enabled", enabled)
end

function refreshOffer(offer: Offer)
	local def = offer.Def
	if offer.IsPass then
		local owned = ClientState.HasPass(def.Id)
		local pendingSince = pendingPasses[offer.Id]
		if owned then
			pendingPasses[offer.Id] = nil
			styleButton(offer.Button, "✔ Acheté", Color3.fromRGB(222, 247, 232), Theme.Colors.RobuxDark, false)
			offer.Stroke.Color = Theme.Colors.Robux
			offer.Stroke.Thickness = 2
			offer.Stroke.Transparency = 0
			return
		elseif pendingSince and os.clock() - pendingSince < PENDING_TIMEOUT then
			styleButton(offer.Button, "⏳ Activation…", Theme.Colors.PanelLight, Theme.Colors.TextDim, false)
			return
		end
	end
	offer.Stroke.Color = Theme.Colors.CardBorder
	offer.Stroke.Thickness = 1.5
	offer.Stroke.Transparency = 0.15
	local text, forSale = priceText(offer)
	if forSale then
		styleButton(offer.Button, text, Theme.Colors.Robux, Theme.Colors.TextLight, true)
	else
		styleButton(offer.Button, text, Theme.Colors.Disabled, Theme.Colors.TextDim, false)
	end
end

-- Ligne "extra" des produits : estimation du gain / boost actif
local function refreshExtra(offer: Offer, data)
	local extra = offer.Extra
	if not extra then
		return
	end
	local def = offer.Def
	if def.Kind == "Dopamine" then
		local stats = { PerSecond = tonumber(data and data.PerSecond) or 0, ClickValue = tonumber(data and data.ClickValue) or 0 }
		local amount = Formulas.ScaledReward(stats, tonumber(def.Seconds) or 0, tonumber(def.Minimum) or 0)
		extra.Text = "≈ +" .. NumberFormatter.Format(amount) .. " Dopamine"
		extra.TextColor3 = Theme.Colors.Blue
	elseif def.Kind == "Boost" then
		local multiplier, remaining = ClientState.GetBoost()
		if remaining > 0 then
			extra.Text = string.format("⏱️ Actif : x%s • %s", tostring(multiplier), UIUtil.FormatClock(remaining))
			extra.TextColor3 = Theme.Colors.Boost
		else
			extra.Text = "Durée : " .. NumberFormatter.Time(tonumber(def.Duration) or 0)
			extra.TextColor3 = Theme.Colors.TextDim
		end
	elseif def.Kind == "ServerRush" then
		extra.Text = "Tout le serveur en profite 🎉"
		extra.TextColor3 = Theme.Colors.Pink
	else
		extra.Text = ""
	end
end

----------------------------------------------------------------------
-- Construction des cartes
----------------------------------------------------------------------

-- Tuile colorée avec l'emoji de l'offre
local function iconTile(parent: GuiObject, icon: string, color: Color3, size: number, position: UDim2, anchor: Vector2?)
	local tile = UIUtil.Create("Frame", {
		Name = "Icon",
		Size = UDim2.fromOffset(size, size),
		Position = position,
		AnchorPoint = anchor or Vector2.zero,
		BackgroundColor3 = color,
		ZIndex = 3,
		Parent = parent,
	})
	UIUtil.Corner(tile, math.floor(size * 0.26))
	UIUtil.Stroke(tile, Theme.Colors.Border, 1.5, 0.25)
	UIUtil.Gradient(tile, ColorSequence.new(Color3.new(1, 1, 1), Color3.fromRGB(200, 200, 200)), 90)
	UIUtil.Label({
		Text = icon,
		Size = UDim2.new(1, -8, 1, -8),
		Position = UDim2.fromOffset(4, 4),
		MaxTextSize = math.floor(size * 0.62),
		ZIndex = 4,
		Parent = tile,
	})
	return tile
end

-- Carte "support" dans une grille : un cadre transparent (cellule) qui porte
-- la carte blanche et son ombre
local function cardShell(grid: Frame, order: number): (Frame, Frame, UIStroke)
	local cell = UIUtil.Create("Frame", {
		BackgroundTransparency = 1,
		LayoutOrder = order,
		Parent = grid,
	})
	local card = UIUtil.Create("Frame", {
		Name = "Card",
		Size = UDim2.new(1, 0, 1, -6),
		BackgroundColor3 = Theme.Colors.Card,
		ZIndex = 2,
		Parent = cell,
	})
	UIUtil.Corner(card, Theme.Radius.L)
	local stroke = UIUtil.Stroke(card, Theme.Colors.CardBorder, 1.5, 0.15)
	UIUtil.Shadow(card, 3, 0.86)
	UIUtil.Create("UIScale", { Name = "PopScale", Parent = card })
	return cell, card, stroke
end

local function priceButton(card: Frame, size: UDim2, position: UDim2, anchor: Vector2): TextButton
	return UIUtil.NeonButton({
		Name = "Price",
		Text = "",
		Color = Theme.Colors.Robux,
		TextColor3 = Theme.Colors.TextLight,
		Size = size,
		Position = position,
		AnchorPoint = anchor,
		CornerRadius = 17,
		MaxTextSize = 17,
		ZIndex = 4,
		Parent = card,
	})
end

local function buildPassCard(grid: Frame, def, order: number)
	local _, card, stroke = cardShell(grid, order)
	local color = PASS_COLORS[def.Id] or Theme.Colors.Purple
	iconTile(card, def.Icon or "🎟️", color, 64, UDim2.new(0, 12, 0.5, 0), Vector2.new(0, 0.5))

	UIUtil.Label({
		Text = tostring(def.Name),
		Font = Theme.Fonts.Title,
		TextXAlignment = Enum.TextXAlignment.Left,
		Size = UDim2.new(1, -100, 0, 22),
		Position = UDim2.fromOffset(88, 10),
		MaxTextSize = Theme.TextSize.Heading,
		ZIndex = 3,
		Parent = card,
	})
	local desc = UIUtil.Create("TextLabel", {
		Text = tostring(def.Description or ""),
		Font = Theme.Fonts.Body,
		TextSize = 14,
		TextColor3 = Theme.Colors.TextDim,
		TextWrapped = true,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top,
		BackgroundTransparency = 1,
		Size = UDim2.new(1, -100, 0, 34),
		Position = UDim2.fromOffset(88, 34),
		ZIndex = 3,
		Parent = card,
	})
	desc.TextTruncate = Enum.TextTruncate.AtEnd

	-- Petite étiquette de l'avantage principal
	local perk = ""
	if def.Multiplier then
		perk = NumberFormatter.Multiplier(def.Multiplier)
	elseif def.AutoClicksPerSecond then
		perk = tostring(def.AutoClicksPerSecond) .. " clics/s"
	end
	if def.UnlockPremiumThemes then
		perk = (perk ~= "" and (perk .. " • ") or "") .. "Thèmes Premium"
	end
	if perk ~= "" then
		local chip = UIUtil.Chip({
			Text = perk,
			Color = color:Lerp(Color3.new(1, 1, 1), 0.75),
			TextColor3 = Theme.Colors.TextDark,
			Height = 22,
			TextSize = 13,
			ZIndex = 3,
			Parent = card,
		})
		chip.AnchorPoint = Vector2.new(0, 1)
		chip.Position = UDim2.new(0, 88, 1, -12)
	end

	local button = priceButton(card, UDim2.fromOffset(118, 32), UDim2.new(1, -12, 1, -10), Vector2.new(1, 1))
	local offer: Offer = {
		Def = def,
		IsPass = true,
		Id = def.GamePassId,
		Card = card,
		Stroke = stroke,
		Button = button,
		Extra = nil,
	}
	button.Activated:Connect(function()
		prompt(offer)
	end)
	table.insert(offers, offer)
	refreshOffer(offer)
end

local function buildProductCard(grid: Frame, def, order: number)
	local _, card, stroke = cardShell(grid, order)
	local color = PRODUCT_COLORS[def.Kind] or Theme.Colors.Cyan
	iconTile(card, def.Icon or "💧", color, 56, UDim2.new(0.5, 0, 0, 12), Vector2.new(0.5, 0))

	UIUtil.Label({
		Text = tostring(def.Name),
		Font = Theme.Fonts.Title,
		Size = UDim2.new(1, -16, 0, 22),
		Position = UDim2.fromOffset(8, 74),
		MaxTextSize = 18,
		ZIndex = 3,
		Parent = card,
	})
	local desc = UIUtil.Create("TextLabel", {
		Text = tostring(def.Description or ""),
		Font = Theme.Fonts.Body,
		TextSize = 14,
		TextColor3 = Theme.Colors.TextDim,
		TextWrapped = true,
		BackgroundTransparency = 1,
		Size = UDim2.new(1, -20, 0, 32),
		Position = UDim2.fromOffset(10, 97),
		ZIndex = 3,
		Parent = card,
	})
	desc.TextTruncate = Enum.TextTruncate.AtEnd
	local extra = UIUtil.Label({
		Text = "",
		Font = Theme.Fonts.Title,
		TextColor3 = Theme.Colors.TextDim,
		Size = UDim2.new(1, -16, 0, 16),
		Position = UDim2.fromOffset(8, 130),
		MaxTextSize = 13,
		ZIndex = 3,
		Parent = card,
	})

	local button = priceButton(card, UDim2.new(1, -24, 0, 34), UDim2.new(0.5, 0, 1, -10), Vector2.new(0.5, 1))
	local offer: Offer = {
		Def = def,
		IsPass = false,
		Id = def.ProductId,
		Card = card,
		Stroke = stroke,
		Button = button,
		Extra = extra,
	}
	button.Activated:Connect(function()
		prompt(offer)
	end)
	table.insert(offers, offer)
	refreshOffer(offer)
	refreshExtra(offer, ClientState.Data)
end

----------------------------------------------------------------------
-- Barre d'état (boost / VIP / bonus)
----------------------------------------------------------------------

local function refreshStatus(data)
	if not statusLabel then
		return
	end
	local multiplier, remaining = ClientState.GetBoost()
	if remaining > 0 then
		statusLabel.Text = string.format("🔥 Boost x%s actif • encore %s", tostring(multiplier), UIUtil.FormatClock(remaining))
		statusLabel.TextColor3 = Theme.Colors.Boost
	elseif ClientState.IsVIP() then
		statusLabel.Text = "👑 Tu es VIP — merci pour ton soutien !"
		statusLabel.TextColor3 = Theme.Colors.Text
	else
		statusLabel.Text = "Les achats sont liés à ton compte et gardés pour toujours."
		statusLabel.TextColor3 = Theme.Colors.TextDim
	end

	local bonus = tonumber(data and data.BonusMultiplier) or 1
	local label = bonusChip:FindFirstChild("Label") :: TextLabel?
	bonusChip.Visible = bonus > 1.001
	if label and bonusChip.Visible then
		label.Text = "💎 Bonus Robux " .. NumberFormatter.Multiplier(bonus)
	end
end

----------------------------------------------------------------------
-- API du panneau
----------------------------------------------------------------------

function RobuxShop.Build(content: Frame)
	-- Barre d'état
	statusBar = UIUtil.Create("Frame", {
		Name = "Status",
		Size = UDim2.new(1, 0, 0, 38),
		BackgroundColor3 = Theme.Colors.Surface,
		Parent = content,
	})
	UIUtil.Corner(statusBar, Theme.Radius.M)
	UIUtil.Stroke(statusBar, Theme.Colors.Divider, 1)
	statusLabel = UIUtil.Label({
		Text = "",
		Font = Theme.Fonts.Title,
		TextXAlignment = Enum.TextXAlignment.Left,
		Size = UDim2.new(1, -220, 1, -10),
		Position = UDim2.fromOffset(14, 5),
		MaxTextSize = 15,
		Parent = statusBar,
	})
	bonusChip = UIUtil.Chip({
		Name = "Bonus",
		Text = "",
		Color = Theme.Colors.Robux,
		TextColor3 = Theme.Colors.TextLight,
		Height = 26,
		TextSize = 14,
		Visible = false,
		Parent = statusBar,
	})
	bonusChip.AnchorPoint = Vector2.new(1, 0.5)
	bonusChip.Position = UDim2.new(1, -8, 0.5, 0)

	local list = UIUtil.Create("ScrollingFrame", {
		Name = "Offers",
		Size = UDim2.new(1, 0, 1, -48),
		Position = UDim2.fromOffset(0, 48),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 6,
		ScrollBarImageColor3 = Theme.Colors.Robux,
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollingDirection = Enum.ScrollingDirection.Y,
		Parent = content,
	})
	UIUtil.Create("UIPadding", {
		PaddingTop = UDim.new(0, 2),
		PaddingLeft = UDim.new(0, 4),
		PaddingRight = UDim.new(0, 14),
		PaddingBottom = UDim.new(0, 8),
		Parent = list,
	})
	UIUtil.Create("UIListLayout", {
		Padding = UDim.new(0, 10),
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = list,
	})

	local function grid(order: number, cellSize: UDim2): Frame
		local frame = UIUtil.Create("Frame", {
			Size = UDim2.fromScale(1, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			BackgroundTransparency = 1,
			LayoutOrder = order,
			Parent = list,
		})
		UIUtil.Create("UIGridLayout", {
			CellSize = cellSize,
			CellPadding = UDim2.fromOffset(12, 10),
			SortOrder = Enum.SortOrder.LayoutOrder,
			Parent = frame,
		})
		return frame
	end

	local function caption(section: Frame, text: string)
		UIUtil.Label({
			Text = text,
			TextColor3 = Theme.Colors.TextDim,
			TextXAlignment = Enum.TextXAlignment.Right,
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.new(1, 0, 0.5, 0),
			Size = UDim2.new(0.5, 0, 0, 18),
			MaxTextSize = 14,
			Parent = section,
		})
	end

	-- Offres configurées (ID ~= 0) et cachées (ID = 0)
	local passes, products = {}, {}
	local hidden = 0
	for _, pass in ipairs(Config.Monetization.GamePasses) do
		if (tonumber(pass.GamePassId) or 0) ~= 0 then
			table.insert(passes, pass)
		else
			hidden += 1
		end
	end
	for _, product in ipairs(Config.Monetization.Products) do
		if (tonumber(product.ProductId) or 0) ~= 0 then
			table.insert(products, product)
		else
			hidden += 1
		end
	end

	if #passes > 0 then
		local section = UIUtil.SectionHeader(list, "🎟️ Game Passes", 1, Theme.Colors.Purple)
		caption(section, "Achat unique • pour toujours")
		local passGrid = grid(2, UDim2.new(0.5, -6, 0, 114))
		for index, pass in ipairs(passes) do
			buildPassCard(passGrid, pass, index)
		end
	end
	if #products > 0 then
		local section = UIUtil.SectionHeader(list, "📦 Packs & Boosts", 3, Theme.Colors.Boost)
		caption(section, "Rachetables à volonté")
		local productGrid = grid(4, UDim2.new(1 / 3, -8, 0, 202))
		for index, product in ipairs(products) do
			buildProductCard(productGrid, product, index)
		end
	end

	-- Rien à vendre : état vide propre
	if #passes == 0 and #products == 0 then
		local studio = RunService:IsStudio()
		local empty = UIUtil.Create("Frame", {
			Name = "Empty",
			Size = UDim2.new(1, 0, 0, 300),
			BackgroundTransparency = 1,
			LayoutOrder = 5,
			Parent = list,
		})
		local bubble = UIUtil.Create("Frame", {
			Size = UDim2.fromOffset(110, 110),
			AnchorPoint = Vector2.new(0.5, 0),
			Position = UDim2.new(0.5, 0, 0, 20),
			BackgroundColor3 = Theme.Colors.Surface,
			Parent = empty,
		})
		UIUtil.Corner(bubble, UDim.new(1, 0))
		UIUtil.Stroke(bubble, Theme.Colors.Divider, 2)
		UIUtil.Label({
			Text = studio and "🛠️" or "💎",
			Size = UDim2.new(1, -24, 1, -24),
			Position = UDim2.fromOffset(12, 12),
			MaxTextSize = 60,
			Parent = bubble,
		})
		UIUtil.Label({
			Text = studio and "Ajoute tes IDs dans Config.Monetization" or "Bientôt disponible",
			Font = Theme.Fonts.Title,
			Size = UDim2.new(1, -40, 0, 30),
			Position = UDim2.fromOffset(20, 146),
			MaxTextSize = 24,
			Parent = empty,
		})
		local body = UIUtil.Create("TextLabel", {
			Text = studio
					and "Crée tes Game Passes et Developer Products sur create.roblox.com (ton expérience > Monétisation), puis colle leurs IDs dans ReplicatedStorage > Shared > Config (Config.Monetization). Les offres à 0 restent cachées.\n(Ce message n'apparaît que dans Studio.)"
				or "La boutique ouvre très bientôt. Reviens nous voir ! 💖",
			Font = Theme.Fonts.Body,
			TextSize = 16,
			TextColor3 = Theme.Colors.TextDim,
			TextWrapped = true,
			BackgroundTransparency = 1,
			Size = UDim2.new(1, -80, 0, 90),
			Position = UDim2.fromOffset(40, 182),
			Parent = empty,
		})
		body.TextYAlignment = Enum.TextYAlignment.Top
	elseif hidden > 0 and RunService:IsStudio() then
		UIUtil.Label({
			Text = string.format("🛠️ Studio : %d offre(s) cachée(s) (ID = 0 dans Config.Monetization)", hidden),
			TextColor3 = Theme.Colors.TextDim,
			Size = UDim2.new(1, 0, 0, 20),
			LayoutOrder = 6,
			MaxTextSize = 14,
			Parent = list,
		})
	end

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

	-- Comptes à rebours (boost, activation) : 2 fois par seconde, seulement si ouvert
	task.spawn(function()
		while content.Parent do
			if visible then
				local data = ClientState.Data
				refreshStatus(data)
				for _, offer in ipairs(offers) do
					if offer.Extra and offer.Def.Kind == "Boost" then
						refreshExtra(offer, data)
					end
					if offer.IsPass and pendingPasses[offer.Id] then
						refreshOffer(offer)
					end
				end
			end
			task.wait(0.5)
		end
	end)

	refreshStatus(ClientState.Data)
end

function RobuxShop.OnOpen()
	visible = true
	-- Vrais prix (threads séparés : ne bloque jamais l'interface)
	for _, offer in ipairs(offers) do
		fetchPrice(offer)
	end
end

function RobuxShop.OnClose()
	visible = false
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

return RobuxShop
