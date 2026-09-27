--[[
	NeedTickets (ModuleScript)
	Emplacement : ReplicatedStorage > Client > Components > NeedTickets

	Fenêtre "Pas assez de tickets !" (🕹️ Arcade : boutique à tickets et tout
	ce qui coûte des 🎟️ tickets) :
	  - bandeau doré animé (rayons qui tournent, gros ticket qui tremble) ;
	  - combien il manque + jauge "tu as / il faut" ;
	  - le plus petit pack de tickets de la boutique Robux qui suffit ;
	  - rappel honnête : les tickets se gagnent aussi en jouant (gratuit) ;
	  - "🎟️ Buy tickets" : ouvre la boutique Robux sur l'onglet 🎟️ Tickets
	    (le pack conseillé est mis en avant) ;
	  - "Later" ou clic à côté : ferme. Un clic DANS la carte ne ferme rien
	    (UIUtil.SinkClicks).
	Elle s'affiche À CHAQUE refus faute de tickets (aucune pause). S'il n'y a
	aucun pack de tickets à vendre (IDs à 0 hors Studio), options.Fallback
	est appelé à la place (bulle habituelle).
	Les 🏆 trophées (mises des duels) ne s'achètent JAMAIS : cette fenêtre ne
	concerne que les tickets.
	Calque Toasts (au-dessus des fenêtres), trouvé tout seul (Interface.Layers).

	API :
	  NeedTickets.Offer(missing, options?) -> boolean (true = fenêtre ouverte)
	    options = { Have = solde (sinon ClientState), Item = "nom affiché",
	                Fallback = function() ... end }
	  NeedTickets.IsVisible(), NeedTickets.Close()
	  NeedTickets.Shown (Signal), NeedTickets.Refused (Signal : manque)
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Client = script.Parent.Parent
local Theme = require(Client.Theme)
local UIUtil = require(Client.UIUtil)
local Interface = require(Client.Interface)
local SoundManager = require(Client.SoundManager)
local ClientState = require(Client.ClientState)
local Config = require(ReplicatedStorage.Shared.Config)
local ArcadeConfig = require(ReplicatedStorage.Shared.ArcadeConfig)
local NumberFormatter = require(ReplicatedStorage.Shared.NumberFormatter)
local Signal = require(ReplicatedStorage.Shared.Signal)
local Locale = require(ReplicatedStorage.Shared.Locale)

local NeedTickets = {}

NeedTickets.Shown = Signal.new() -- () : la fenêtre vient de s'ouvrir
NeedTickets.Refused = Signal.new() -- (manque) : "Later" ou clic à côté

local CARD_SIZE = Vector2.new(440, 330)
local HEADER_HEIGHT = 92
local TICKET = ArcadeConfig.Tickets.Icon
local WHITE = Color3.new(1, 1, 1)
local GOLD = Color3.fromRGB(255, 196, 40)
local ORANGE = Color3.fromRGB(255, 128, 48)
local PINK = Color3.fromRGB(255, 84, 160)
local INK = Color3.fromRGB(92, 52, 16) -- texte chaud sur fond doré

local current: Frame? = nil
local spin: Tween? = nil

----------------------------------------------------------------------
-- Packs de tickets (Config.Monetization.Products, Kind "Tickets")
----------------------------------------------------------------------

local function packOnSale(product): boolean
	return product.Kind == "Tickets"
		and product.ComingSoon ~= true
		and ((tonumber(product.ProductId) or 0) ~= 0 or RunService:IsStudio())
end

-- Packs en vente (dans l'ordre de la config)
function NeedTickets.GetPacks(): { any }
	local packs = {}
	for _, product in ipairs(Config.Monetization.Products) do
		if packOnSale(product) then
			table.insert(packs, product)
		end
	end
	return packs
end

----------------------------------------------------------------------
-- Fenêtre
----------------------------------------------------------------------

local function layer(): Frame?
	local layers = Interface.Layers
	return layers and layers.Toasts or nil
end

local function stopSpin()
	local tween = spin
	spin = nil
	if tween then
		tween:Cancel()
	end
end

local function close()
	local window = current
	if not window then
		return
	end
	current = nil
	stopSpin()
	local card = window:FindFirstChild("Card") :: Frame?
	local dimmer = window:FindFirstChild("Dimmer") :: GuiObject?
	if dimmer then
		UIUtil.Tween(dimmer, 0.2, { BackgroundTransparency = 1 })
	end
	if card then
		local scale = card:FindFirstChildOfClass("UIScale")
		if scale then
			UIUtil.Tween(scale, 0.2, { Scale = 0.85 * (Interface.IsPhone() and 0.92 or 1) }, Enum.EasingStyle.Back, Enum.EasingDirection.In)
		end
	end
	task.delay(0.22, function()
		window:Destroy()
	end)
end

local function refuse(missing: number)
	close()
	NeedTickets.Refused:Fire(missing)
end

-- Ouvre la boutique Robux sur l'onglet 🎟️ Tickets (pack conseillé mis en avant)
local function openShop(packId: string?)
	close()
	-- Chargés à la demande (évite les require circulaires au démarrage)
	local components = script.Parent
	local PanelManager = require(components:WaitForChild("PanelManager")) :: any
	if not PanelManager.IsRegistered("RobuxShop") then
		return
	end
	PanelManager.Open("RobuxShop")
	local ok, shop = pcall(require, components:WaitForChild("Panels"):WaitForChild("RobuxShop"))
	if ok and type(shop) == "table" then
		local api = shop :: any
		if type(api.ShowTab) == "function" then
			api.ShowTab("Tickets")
		end
		if packId and type(api.Spotlight) == "function" then
			api.Spotlight(packId)
		end
	end
end

local function button(parent: Instance, name: string, text: string, color: Color3, position: UDim2, width: number): TextButton
	local node = UIUtil.Create("TextButton", {
		Name = name,
		AnchorPoint = Vector2.new(0.5, 1),
		Position = position,
		Size = UDim2.fromOffset(width, 50),
		BackgroundColor3 = color,
		AutoButtonColor = false,
		Font = Theme.Fonts.Title,
		Text = text,
		TextColor3 = Theme.ContrastText(color),
		TextSize = 20,
		TextScaled = true, -- (texte traduit plus long : il rétrécit au lieu de déborder)
		ZIndex = 6,
		Parent = parent,
	})
	UIUtil.Create("UITextSizeConstraint", { MaxTextSize = 20, MinTextSize = 12, Parent = node })
	UIUtil.Create("UIPadding", {
		PaddingLeft = UDim.new(0, 14),
		PaddingRight = UDim.new(0, 14),
		PaddingTop = UDim.new(0, 12),
		PaddingBottom = UDim.new(0, 12),
		Parent = node,
	})
	UIUtil.Corner(node, UDim.new(1, 0))
	UIUtil.Stroke(node, color:Lerp(Color3.new(0, 0, 0), 0.25), 2, 0)
	UIUtil.Gradient(node, ColorSequence.new(WHITE, Color3.fromRGB(215, 215, 215)), 90)
	UIUtil.AnimateButton(node, 1.05, 0.93)
	return node
end

-- Bandeau doré : dégradé, rayons (rotation par Tween en boucle : aucun code
-- par image), gros ticket qui tremble, petites étincelles
local function buildHeader(card: Frame)
	local header = UIUtil.Create("Frame", {
		Name = "Header",
		Size = UDim2.new(1, -12, 0, HEADER_HEIGHT),
		Position = UDim2.fromOffset(6, 6),
		BackgroundColor3 = WHITE,
		ClipsDescendants = true,
		ZIndex = 3,
		Parent = card,
	})
	UIUtil.Corner(header, Theme.Radius.L)
	UIUtil.Gradient(header, ColorSequence.new({
		ColorSequenceKeypoint.new(0, GOLD),
		ColorSequenceKeypoint.new(0.55, ORANGE),
		ColorSequenceKeypoint.new(1, PINK),
	}), 20)
	local rays = UIUtil.Rays(header, WHITE, 8, 300, UDim2.fromScale(0.5, 0.62), 3)
	spin = TweenService:Create(rays, TweenInfo.new(24, Enum.EasingStyle.Linear, Enum.EasingDirection.InOut, -1), { Rotation = 360 })
	local tween = spin
	if tween then
		tween:Play()
	end
	-- Halo + gros ticket
	local halo = UIUtil.Create("Frame", {
		Name = "Halo",
		Size = UDim2.fromOffset(78, 78),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.52),
		BackgroundColor3 = WHITE,
		BackgroundTransparency = 0.72,
		ZIndex = 4,
		Parent = header,
	})
	UIUtil.Corner(halo, UDim.new(1, 0))
	UIUtil.Stroke(halo, WHITE, 2, 0.45)
	local icon = UIUtil.Create("TextLabel", {
		Name = "Icon",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.52),
		Size = UDim2.fromOffset(72, 64),
		BackgroundTransparency = 1,
		Font = Theme.Fonts.Body,
		Text = TICKET,
		TextSize = 50,
		ZIndex = 5,
		Parent = header,
	})
	-- Le ticket "tremble" : il en manque !
	task.spawn(function()
		for index = 1, 6 do
			if not icon.Parent then
				return
			end
			UIUtil.Tween(icon, 0.07, { Rotation = index % 2 == 0 and -12 or 12 })
			task.wait(0.07)
		end
		UIUtil.Tween(icon, 0.12, { Rotation = -6 })
	end)
	local sparkles = { { 0.2, 0.3, 16 }, { 0.8, 0.26, 13 }, { 0.3, 0.76, 11 }, { 0.72, 0.74, 15 }, { 0.1, 0.62, 9 }, { 0.9, 0.58, 10 } }
	for index, spec in ipairs(sparkles) do
		local star = UIUtil.Create("TextLabel", {
			Name = "Sparkle" .. index,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(spec[1], spec[2]),
			Size = UDim2.fromOffset(20, 20),
			BackgroundTransparency = 1,
			Font = Theme.Fonts.Title,
			Text = index % 2 == 0 and "✦" or "✧",
			TextColor3 = WHITE,
			TextSize = spec[3],
			TextTransparency = 0.15,
			ZIndex = 4,
			Parent = header,
		})
		UIUtil.Tween(star, 0.9 + index * 0.15, { TextTransparency = 0.7 }, Enum.EasingStyle.Sine)
	end
	return header
end

local function build(missing: number, have: number, item: string?)
	local parent = layer()
	if not parent then
		return false
	end
	if current then
		stopSpin()
		current:Destroy()
		current = nil
	end
	local need = have + missing

	local window = UIUtil.Create("Frame", {
		Name = "NeedTickets",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		ZIndex = 46,
		Parent = parent,
	})
	current = window

	-- Fond sombre : un clic dehors ferme
	local dimmer = UIUtil.Create("TextButton", {
		Name = "Dimmer",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.fromRGB(20, 10, 30),
		BackgroundTransparency = 1,
		AutoButtonColor = false,
		Text = "",
		ZIndex = 1,
		Parent = window,
	})
	UIUtil.Tween(dimmer, 0.25, { BackgroundTransparency = 0.45 })
	dimmer.Activated:Connect(function()
		refuse(missing)
	end)

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
	UIUtil.SinkClicks(card) -- clic dans la carte : ne ferme pas
	UIUtil.Stroke(card, ORANGE, 2.5, 0.15)
	UIUtil.Gradient(card, ColorSequence.new(WHITE, Color3.fromRGB(255, 244, 226)), 90)
	UIUtil.Shadow(card, 6, 0.75, 4)
	local base = Interface.IsPhone() and 0.92 or 1
	local scale = UIUtil.Create("UIScale", { Scale = 0.8 * base, Parent = card })
	UIUtil.Tween(scale, 0.3, { Scale = base }, Enum.EasingStyle.Back)

	buildHeader(card)

	-- Pastille "-N 🎟️" sur le bandeau
	local chip = UIUtil.Chip({
		Name = "Missing",
		Text = "−" .. NumberFormatter.Format(missing) .. " " .. TICKET,
		Color = WHITE,
		TextColor3 = Color3.fromRGB(200, 50, 60),
		Height = 24,
		TextSize = 14,
		ZIndex = 8,
		StrokeColor = WHITE,
		Parent = card,
	})
	chip.AnchorPoint = Vector2.new(1, 0)
	chip.Position = UDim2.new(1, -16, 0, 16)

	local top = HEADER_HEIGHT + 12
	UIUtil.Create("TextLabel", {
		Name = "Title",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, top),
		Size = UDim2.new(1, -40, 0, 28),
		BackgroundTransparency = 1,
		Font = Theme.Fonts.Title,
		Text = Locale.T("Not enough tickets!"),
		TextColor3 = Theme.Colors.Text,
		TextScaled = true,
		ZIndex = 4,
		Parent = card,
	})
	local message = item and item ~= "" and Locale.T("You need %s more tickets for %s.", NumberFormatter.Format(missing), item)
		or Locale.T("You need %s more tickets.", NumberFormatter.Format(missing))
	local text = UIUtil.Create("TextLabel", {
		Name = "Text",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, top + 30),
		Size = UDim2.new(1, -48, 0, 20),
		BackgroundTransparency = 1,
		Font = Theme.Fonts.Body,
		Text = message,
		TextColor3 = Theme.Colors.TextDim,
		TextSize = 16,
		TextScaled = true,
		ZIndex = 4,
		Parent = card,
	})
	UIUtil.Create("UITextSizeConstraint", { MaxTextSize = 16, MinTextSize = 11, Parent = text })

	-- Jauge "tu as / il faut"
	local track = UIUtil.Create("Frame", {
		Name = "Progress",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, top + 58),
		Size = UDim2.new(1, -60, 0, 22),
		BackgroundColor3 = Color3.fromRGB(250, 234, 206),
		ClipsDescendants = true,
		ZIndex = 4,
		Parent = card,
	})
	UIUtil.Corner(track, UDim.new(1, 0))
	UIUtil.Stroke(track, ORANGE, 1, 0.55)
	local ratio = need > 0 and math.clamp(have / need, 0, 1) or 0
	local fill = UIUtil.Create("Frame", {
		Name = "Fill",
		Size = UDim2.fromScale(0, 1),
		BackgroundColor3 = WHITE,
		BorderSizePixel = 0,
		ZIndex = 5,
		Parent = track,
	})
	UIUtil.Corner(fill, UDim.new(1, 0))
	UIUtil.Gradient(fill, ColorSequence.new(GOLD, ORANGE), 0)
	UIUtil.Tween(fill, 0.6, { Size = UDim2.fromScale(ratio, 1) }, Enum.EasingStyle.Quint)
	local amounts = UIUtil.Create("TextLabel", {
		Name = "Amounts",
		Size = UDim2.new(1, -16, 1, 0),
		Position = UDim2.fromOffset(8, 0),
		BackgroundTransparency = 1,
		Font = Theme.Fonts.Number,
		Text = string.format("%s %s / %s", TICKET, NumberFormatter.Format(have), NumberFormatter.Format(need)),
		TextColor3 = INK,
		TextSize = 14,
		ZIndex = 6,
		Parent = track,
	})
	local amountsStroke = UIUtil.Stroke(amounts, WHITE, 1.5, 0.2)
	amountsStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual

	-- Pack conseillé : le plus petit qui suffit (sinon le plus gros)
	local pack = ArcadeConfig.Logic.PickTicketPack(missing, NeedTickets.GetPacks())
	local tip = UIUtil.Create("Frame", {
		Name = "Tip",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, top + 90),
		Size = UDim2.new(1, -48, 0, 40),
		BackgroundColor3 = Color3.fromRGB(255, 248, 232),
		ZIndex = 4,
		Parent = card,
	})
	UIUtil.Corner(tip, Theme.Radius.M)
	UIUtil.Stroke(tip, GOLD, 1.5, 0.35)
	UIUtil.Create("TextLabel", {
		Name = "PackIcon",
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 8, 0.5, 0),
		Size = UDim2.fromOffset(30, 30),
		BackgroundTransparency = 1,
		Font = Theme.Fonts.Body,
		Text = pack and tostring(pack.Icon) or "💡",
		TextSize = 24,
		ZIndex = 5,
		Parent = tip,
	})
	local tipText = pack
			and Locale.T("Best fit: %s • +%s tickets", Locale.T(tostring(pack.Name)), NumberFormatter.Format(tonumber(pack.Tickets) or 0))
		or Locale.T("🕹️ Win arcade games to earn tickets!")
	local tipLabel = UIUtil.Create("TextLabel", {
		Name = "PackText",
		Position = UDim2.fromOffset(44, 0),
		Size = UDim2.new(1, -52, 1, 0),
		BackgroundTransparency = 1,
		Font = Theme.Fonts.Title,
		Text = tipText,
		TextColor3 = INK,
		TextSize = 15,
		TextScaled = true,
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = 5,
		Parent = tip,
	})
	UIUtil.Create("UITextSizeConstraint", { MaxTextSize = 15, MinTextSize = 10, Parent = tipLabel })

	-- Rappel honnête : les tickets se gagnent aussi gratuitement
	local free = UIUtil.Create("TextLabel", {
		Name = "Free",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, top + 136),
		Size = UDim2.new(1, -48, 0, 18),
		BackgroundTransparency = 1,
		Font = Theme.Fonts.Body,
		Text = Locale.T("🕹️ Or win arcade games: tickets are free to earn."),
		TextColor3 = Theme.Colors.TextDim,
		TextSize = 14,
		TextScaled = true,
		ZIndex = 4,
		Parent = card,
	})
	UIUtil.Create("UITextSizeConstraint", { MaxTextSize = 14, MinTextSize = 10, Parent = free })

	-- Deux boutons côte à côte, 12 px d'écart, 24 px des bords de la carte
	local margin, gap = 24, 12
	local laterWidth = math.floor((CARD_SIZE.X - margin * 2 - gap) * 0.36)
	local buyWidth = CARD_SIZE.X - margin * 2 - gap - laterWidth
	local later = button(card, "Later", Locale.T("Later"), Color3.fromRGB(240, 234, 226), UDim2.new(0, margin + laterWidth / 2, 1, -20), laterWidth)
	later.TextColor3 = Theme.Colors.TextDim
	local buy = button(card, "BuyTickets", Locale.T("🎟️ Buy tickets"), GOLD, UDim2.new(1, -(margin + buyWidth / 2), 1, -20), buyWidth)
	buy.TextColor3 = INK
	later.Activated:Connect(function()
		SoundManager.Play("Click", 1.1)
		refuse(missing)
	end)
	buy.Activated:Connect(function()
		SoundManager.Play("Click", 1.3)
		openShop(pack and pack.Id or nil)
	end)
	NeedTickets.Shown:Fire()
	return true
end

--[[
	À appeler À CHAQUE fois qu'une dépense en tickets est refusée (contrôle du
	client ou refus du serveur). missing = tickets manquants.
	Renvoie true si la fenêtre s'est ouverte (sinon options.Fallback est appelé).
]]
function NeedTickets.Offer(missing: number, options: { [string]: any }?): boolean
	local opts = options or {}
	local count = math.max(1, math.ceil(tonumber(missing) or 1))
	local fallback = opts.Fallback
	if #NeedTickets.GetPacks() == 0 or not layer() then
		if type(fallback) == "function" then
			fallback()
		end
		return false
	end
	local data = ClientState.Data
	local have = tonumber(opts.Have) or tonumber(data and data.Tickets) or 0
	SoundManager.Play("Error", 0.7)
	return build(count, math.max(0, math.floor(have)), type(opts.Item) == "string" and opts.Item or nil)
end

function NeedTickets.IsVisible(): boolean
	return current ~= nil
end

-- Ferme la fenêtre (sans compter comme un refus)
function NeedTickets.Close()
	close()
end

return NeedTickets
