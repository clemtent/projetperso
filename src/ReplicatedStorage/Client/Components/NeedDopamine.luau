--[[
	NeedDopamine (ModuleScript)
	Emplacement : ReplicatedStorage > Client > Components > NeedDopamine

	Petite fenêtre "Pas assez de Dopamine !" quand un achat est trop cher
	(améliorations, maison 🏠, thèmes, boutique d'objets) :
	  - combien il manque + jauge "tu as / il faut" ;
	  - conseil honnête : le plus petit pack de Dopamine qui suffit (selon ta
	    production actuelle), ou "reviens dans ~X" si ta production y arrive
	    vite toute seule ;
	  - bouton "💎 Get Dopamine" : ouvre la boutique Robux directement sur
	    l'onglet "💧 Dopamine" (packs de Dopamine) ;
	  - bouton "Later" (ou clic à côté) : ferme.
	Elle s'affiche À CHAQUE achat refusé faute de Dopamine (plus de pause
	après "Later"). S'il n'y a aucun pack de Dopamine à vendre (IDs à 0 hors
	Studio), on affiche juste la bulle.
	La fenêtre vit dans le calque Toasts (au-dessus des panneaux).
	Signaux (v8, utilisés par OfferPopup) : Shown (fenêtre ouverte),
	Refused(manque) ("Later" / clic à côté).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Client = script.Parent.Parent
local Theme = require(Client.Theme)
local UIUtil = require(Client.UIUtil)
local SoundManager = require(Client.SoundManager)
local ClientState = require(Client.ClientState)
local Config = require(ReplicatedStorage.Shared.Config)
local Formulas = require(ReplicatedStorage.Shared.Formulas)
local NumberFormatter = require(ReplicatedStorage.Shared.NumberFormatter)
local Signal = require(ReplicatedStorage.Shared.Signal)
local Locale = require(ReplicatedStorage.Shared.Locale)

local NeedDopamine = {}

NeedDopamine.Shown = Signal.new() -- () : la fenêtre vient de s'ouvrir
NeedDopamine.Refused = Signal.new() -- (manque) : "Later" ou clic à côté

local CARD_SIZE = Vector2.new(420, 284)
local WAIT_HINT = 45 -- (s) si la production comble le manque avant : on le dit

local layer: Frame? = nil
local current: Frame? = nil

function NeedDopamine.Build(parent: Frame)
	layer = parent
end

-- Pack de Dopamine achetable ?
local function packOnSale(product): boolean
	return product.Kind == "Dopamine" and ((tonumber(product.ProductId) or 0) ~= 0 or RunService:IsStudio())
end

-- Au moins un pack de Dopamine achetable ?
local function hasDopaminePacks(): boolean
	for _, product in ipairs(Config.Monetization.Products) do
		if packOnSale(product) then
			return true
		end
	end
	return false
end

-- Production actuelle (pour estimer les packs et le temps d'attente)
local function currentStats(): { PerSecond: number, ClickValue: number }
	local data = ClientState.Data
	return {
		PerSecond = tonumber(data and data.PerSecond) or 0,
		ClickValue = tonumber(data and data.ClickValue) or 0,
	}
end

-- Le plus petit pack qui couvre `missing` : (pack, montant) ; sinon le plus gros
local function suggestPack(missing: number): (any?, number)
	local stats = currentStats()
	local best, bestAmount, biggest, biggestAmount = nil, 0, nil, 0
	for _, product in ipairs(Config.Monetization.Products) do
		if packOnSale(product) then
			local amount = Formulas.ScaledReward(stats, tonumber(product.Seconds) or 0, tonumber(product.Minimum) or 0)
			if amount >= missing and (best == nil or amount < bestAmount) then
				best, bestAmount = product, amount
			end
			if amount > biggestAmount then
				biggest, biggestAmount = product, amount
			end
		end
	end
	if best then
		return best, bestAmount
	end
	return biggest, biggestAmount
end

local function close()
	local window = current
	if not window then
		return
	end
	current = nil
	local card = window:FindFirstChild("Card") :: Frame?
	local dimmer = window:FindFirstChild("Dimmer") :: GuiObject?
	if dimmer then
		UIUtil.Tween(dimmer, 0.2, { BackgroundTransparency = 1 })
	end
	if card then
		local scale = card:FindFirstChildOfClass("UIScale")
		if scale then
			UIUtil.Tween(scale, 0.2, { Scale = 0.85 }, Enum.EasingStyle.Back, Enum.EasingDirection.In)
		end
	end
	task.delay(0.22, function()
		window:Destroy()
	end)
end

local function refuse(missing: number)
	close()
	NeedDopamine.Refused:Fire(missing)
end

local function openShop()
	close()
	-- Chargés à la demande (évite les require circulaires au démarrage)
	local components = script.Parent
	local PanelManager = require(components:WaitForChild("PanelManager")) :: any
	if not PanelManager.IsRegistered("RobuxShop") then
		return
	end
	PanelManager.Open("RobuxShop")
	local ok, shop = pcall(require, components:WaitForChild("Panels"):WaitForChild("RobuxShop"))
	if ok and type(shop) == "table" and type((shop :: any).ShowTab) == "function" then
		(shop :: any).ShowTab("Dopamine")
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
		ZIndex = 5,
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
	UIUtil.Gradient(node, ColorSequence.new(Color3.new(1, 1, 1), Color3.fromRGB(215, 215, 215)), 90)
	UIUtil.AnimateButton(node, 1.05, 0.93)
	return node
end

local function build(missing: number)
	local parent = layer
	if not parent then
		return
	end
	if current then
		current:Destroy()
		current = nil
	end
	local have = math.max(0, ClientState.GetConfirmedDopamine())
	local need = have + missing

	local window = UIUtil.Create("Frame", {
		Name = "NeedDopamine",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		ZIndex = 45,
		Parent = parent,
	})
	current = window

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
	UIUtil.Tween(dimmer, 0.25, { BackgroundTransparency = 0.45 })
	dimmer.Activated:Connect(function()
		refuse(missing)
	end)

	local card = UIUtil.Create("Frame", {
		Name = "Card",
		Size = UDim2.fromOffset(CARD_SIZE.X, CARD_SIZE.Y),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		BackgroundColor3 = Color3.new(1, 1, 1),
		Active = true,
		ZIndex = 2,
		Parent = window,
	})
	UIUtil.Corner(card, Theme.Radius.XL)
	UIUtil.SinkClicks(card) -- clic dans la carte : ne ferme pas
	UIUtil.Stroke(card, Theme.Colors.Purple, 2.5, 0.2)
	UIUtil.Gradient(card, ColorSequence.new(Color3.new(1, 1, 1), Color3.fromRGB(240, 232, 255)), 90)
	UIUtil.Shadow(card, 6, 0.75, 4)
	local scale = UIUtil.Create("UIScale", { Scale = 0.8, Parent = card })
	UIUtil.Tween(scale, 0.3, { Scale = 1 }, Enum.EasingStyle.Back)

	-- Petite tête qui "tremble" : il en manque !
	local icon = UIUtil.Create("TextLabel", {
		Name = "Icon",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 0, 40),
		Size = UDim2.fromOffset(70, 56),
		BackgroundTransparency = 1,
		Font = Theme.Fonts.Body,
		Text = "😵",
		TextSize = 46,
		ZIndex = 4,
		Parent = card,
	})
	task.spawn(function()
		for index = 1, 6 do
			if not icon.Parent then
				return
			end
			UIUtil.Tween(icon, 0.07, { Rotation = index % 2 == 0 and -10 or 10 })
			task.wait(0.07)
		end
		UIUtil.Tween(icon, 0.1, { Rotation = 0 })
	end)

	UIUtil.Create("TextLabel", {
		Name = "Title",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 70),
		Size = UDim2.new(1, -40, 0, 28),
		BackgroundTransparency = 1,
		Font = Theme.Fonts.Title,
		Text = Locale.T("Not enough Dopamine!"),
		TextColor3 = Theme.Colors.Text,
		TextScaled = true,
		ZIndex = 4,
		Parent = card,
	})
	local text = UIUtil.Create("TextLabel", {
		Name = "Text",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 100),
		Size = UDim2.new(1, -48, 0, 22),
		BackgroundTransparency = 1,
		Font = Theme.Fonts.Body,
		Text = Locale.T("You need %s more Dopamine.", NumberFormatter.Format(missing)),
		TextColor3 = Theme.Colors.TextDim,
		TextSize = 17,
		TextScaled = true,
		ZIndex = 4,
		Parent = card,
	})
	UIUtil.Create("UITextSizeConstraint", { MaxTextSize = 17, MinTextSize = 11, Parent = text })

	-- Jauge "tu as / il faut"
	local track = UIUtil.Create("Frame", {
		Name = "Progress",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 130),
		Size = UDim2.new(1, -60, 0, 20),
		BackgroundColor3 = Color3.fromRGB(232, 226, 246),
		ClipsDescendants = true,
		ZIndex = 4,
		Parent = card,
	})
	UIUtil.Corner(track, UDim.new(1, 0))
	UIUtil.Stroke(track, Theme.Colors.Purple, 1, 0.6)
	local ratio = need > 0 and math.clamp(have / need, 0, 1) or 0
	local fill = UIUtil.Create("Frame", {
		Name = "Fill",
		Size = UDim2.fromScale(0, 1),
		BackgroundColor3 = Color3.new(1, 1, 1),
		BorderSizePixel = 0,
		ZIndex = 5,
		Parent = track,
	})
	UIUtil.Corner(fill, UDim.new(1, 0))
	UIUtil.Gradient(fill, ColorSequence.new(Color3.fromRGB(190, 140, 255), Theme.Colors.Purple), 0)
	UIUtil.Tween(fill, 0.6, { Size = UDim2.fromScale(ratio, 1) }, Enum.EasingStyle.Quint)
	local amounts = UIUtil.Create("TextLabel", {
		Name = "Amounts",
		Size = UDim2.new(1, -16, 1, 0),
		Position = UDim2.fromOffset(8, 0),
		BackgroundTransparency = 1,
		Font = Theme.Fonts.Number,
		Text = string.format("💧 %s / %s", NumberFormatter.Format(have), NumberFormatter.Format(need)),
		TextColor3 = Theme.Colors.TextDark,
		TextSize = 13,
		ZIndex = 6,
		Parent = track,
	})
	local amountsStroke = UIUtil.Stroke(amounts, Color3.new(1, 1, 1), 1.5, 0.2)
	amountsStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual

	-- Conseil honnête : attendre un peu, ou le plus petit pack qui suffit
	local stats = currentStats()
	local production = stats.PerSecond
	local seconds = production > 0 and missing / production or math.huge
	local hint: string
	if seconds <= WAIT_HINT then
		hint = Locale.T("⏳ Or just wait ~%s: your production gets there.", NumberFormatter.Time(math.ceil(seconds)))
	else
		local pack, amount = suggestPack(missing)
		if pack then
			hint = Locale.T("💡 %s gives ≈ %s Dopamine", pack.Icon .. " " .. Locale.T(tostring(pack.Name)), NumberFormatter.Format(amount))
		else
			hint = ""
		end
	end
	local hintLabel = UIUtil.Create("TextLabel", {
		Name = "Hint",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 158),
		Size = UDim2.new(1, -48, 0, 36),
		BackgroundTransparency = 1,
		Font = Theme.Fonts.Body,
		Text = hint,
		TextColor3 = Color3.fromRGB(95, 60, 150),
		TextSize = 15,
		TextWrapped = true,
		TextScaled = true,
		ZIndex = 4,
		Parent = card,
	})
	UIUtil.Create("UITextSizeConstraint", { MaxTextSize = 15, MinTextSize = 10, Parent = hintLabel })

	-- Deux boutons côte à côte, 12 px d'écart, 24 px des bords de la carte
	local margin, gap = 24, 12
	local laterWidth = math.floor((CARD_SIZE.X - margin * 2 - gap) * 0.38)
	local getWidth = CARD_SIZE.X - margin * 2 - gap - laterWidth
	local later = button(card, "Later", Locale.T("Later"), Color3.fromRGB(236, 232, 244), UDim2.new(0, margin + laterWidth / 2, 1, -22), laterWidth)
	later.TextColor3 = Theme.Colors.TextDim
	local get = button(card, "GetDopamine", Locale.T("💎 Get Dopamine"), Theme.Colors.Green, UDim2.new(1, -(margin + getWidth / 2), 1, -22), getWidth)
	later.Activated:Connect(function()
		SoundManager.Play("Click", 1.1)
		refuse(missing)
	end)
	get.Activated:Connect(function()
		SoundManager.Play("Click", 1.3)
		openShop()
	end)
	NeedDopamine.Shown:Fire()
end

--[[
	À appeler quand un achat est refusé faute de Dopamine.
	missing = combien il manque ; fallback = fonction qui affiche la bulle
	habituelle (utilisée si la fenêtre est déjà ouverte ou sans packs).
	Renvoie true si la fenêtre s'est ouverte.
]]
function NeedDopamine.Offer(missing: number, fallback: (() -> ())?): boolean
	missing = math.max(0, tonumber(missing) or 0)
	if current or not hasDopaminePacks() or not layer then
		if fallback and not current then
			fallback()
		end
		return current ~= nil
	end
	SoundManager.Play("Error", 0.7)
	build(missing)
	return true
end

function NeedDopamine.IsVisible(): boolean
	return current ~= nil
end

-- Ferme la fenêtre (sans compter comme un refus)
function NeedDopamine.Close()
	close()
end

return NeedDopamine
