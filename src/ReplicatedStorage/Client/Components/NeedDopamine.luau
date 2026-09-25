--[[
	NeedDopamine (ModuleScript)
	Emplacement : ReplicatedStorage > Client > Components > NeedDopamine

	Petite fenêtre "Pas assez de Dopamine !" quand un achat est trop cher
	(améliorations, maison 🏠, thèmes, boutique d'objets) :
	  - combien il manque ;
	  - bouton "💎 Get Dopamine" : ouvre la boutique Robux directement sur
	    l'onglet "💧 Dopamine" (packs de Dopamine) ;
	  - bouton "Later" (ou clic à côté) : ferme.
	Pour ne pas agacer : après "Later", simple bulle rouge pendant 45 s.
	S'il n'y a aucun pack de Dopamine à vendre (IDs à 0 hors Studio), on
	affiche juste la bulle.
	La fenêtre vit dans le calque Toasts (au-dessus des panneaux).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Client = script.Parent.Parent
local Theme = require(Client.Theme)
local UIUtil = require(Client.UIUtil)
local SoundManager = require(Client.SoundManager)
local Config = require(ReplicatedStorage.Shared.Config)
local NumberFormatter = require(ReplicatedStorage.Shared.NumberFormatter)
local Locale = require(ReplicatedStorage.Shared.Locale)

local NeedDopamine = {}

local CARD_SIZE = Vector2.new(400, 250)
local SNOOZE_TIME = 45 -- (s) après "Later" : plus de fenêtre, juste la bulle

local layer: Frame? = nil
local current: Frame? = nil
local snoozedUntil = 0

function NeedDopamine.Build(parent: Frame)
	layer = parent
end

-- Au moins un pack de Dopamine achetable ?
local function hasDopaminePacks(): boolean
	for _, product in ipairs(Config.Monetization.Products) do
		if product.Kind == "Dopamine" and ((tonumber(product.ProductId) or 0) ~= 0 or RunService:IsStudio()) then
			return true
		end
	end
	return false
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

local function button(parent: Instance, text: string, color: Color3, position: UDim2, width: number): TextButton
	local node = UIUtil.Create("TextButton", {
		Name = "Button",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = position,
		Size = UDim2.fromOffset(width, 50),
		BackgroundColor3 = color,
		AutoButtonColor = false,
		Font = Theme.Fonts.Title,
		Text = text,
		TextColor3 = Theme.ContrastText(color),
		TextSize = 20,
		ZIndex = 5,
		Parent = parent,
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
		snoozedUntil = os.clock() + SNOOZE_TIME
		close()
	end)

	local card = UIUtil.Create("Frame", {
		Name = "Card",
		Size = UDim2.fromOffset(CARD_SIZE.X, CARD_SIZE.Y),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		BackgroundColor3 = Color3.new(1, 1, 1),
		ZIndex = 2,
		Parent = window,
	})
	UIUtil.Corner(card, Theme.Radius.XL)
	UIUtil.Stroke(card, Theme.Colors.Purple, 2.5, 0.2)
	UIUtil.Gradient(card, ColorSequence.new(Color3.new(1, 1, 1), Color3.fromRGB(240, 232, 255)), 90)
	UIUtil.Shadow(card, 6, 0.75, 4)
	local scale = UIUtil.Create("UIScale", { Scale = 0.8, Parent = card })
	UIUtil.Tween(scale, 0.3, { Scale = 1 }, Enum.EasingStyle.Back)

	-- Petite pilule qui "tremble" : il en manque !
	local icon = UIUtil.Create("TextLabel", {
		Name = "Icon",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 0, 44),
		Size = UDim2.fromOffset(70, 60),
		BackgroundTransparency = 1,
		Font = Theme.Fonts.Body,
		Text = "😵",
		TextSize = 50,
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
		Position = UDim2.new(0.5, 0, 0, 78),
		Size = UDim2.new(1, -40, 0, 30),
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
		Position = UDim2.new(0.5, 0, 0, 112),
		Size = UDim2.new(1, -48, 0, 44),
		BackgroundTransparency = 1,
		Font = Theme.Fonts.Body,
		Text = Locale.T("You need %s more Dopamine. Grab a pack in the shop and buy it right now!", NumberFormatter.Format(missing)),
		TextColor3 = Theme.Colors.TextDim,
		TextSize = 17,
		TextWrapped = true,
		ZIndex = 4,
		Parent = card,
	})
	UIUtil.Create("UITextSizeConstraint", { MaxTextSize = 17, MinTextSize = 11, Parent = text })
	text.TextScaled = true

	local later = button(card, Locale.T("Later"), Color3.fromRGB(236, 232, 244), UDim2.new(0.27, 0, 1, -22), 150)
	later.TextColor3 = Theme.Colors.TextDim
	local get = button(card, Locale.T("💎 Get Dopamine"), Theme.Colors.Green, UDim2.new(0.68, 0, 1, -22), 210)
	later.Activated:Connect(function()
		snoozedUntil = os.clock() + SNOOZE_TIME
		SoundManager.Play("Click", 1.1)
		close()
	end)
	get.Activated:Connect(function()
		SoundManager.Play("Click", 1.3)
		openShop()
	end)
end

--[[
	À appeler quand un achat est refusé faute de Dopamine.
	missing = combien il manque ; fallback = fonction qui affiche la bulle
	habituelle (utilisée pendant la pause "Later" ou sans packs).
	Renvoie true si la fenêtre s'est ouverte.
]]
function NeedDopamine.Offer(missing: number, fallback: (() -> ())?): boolean
	missing = math.max(0, tonumber(missing) or 0)
	if current or os.clock() < snoozedUntil or not hasDopaminePacks() or not layer then
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

return NeedDopamine
