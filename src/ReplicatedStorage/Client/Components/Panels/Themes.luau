--[[
	Themes (ModuleScript) — boutique de thèmes (fonds d'écran)
	Emplacement : ReplicatedStorage > Client > Components > Panels > Themes

	Grille de cartes (Config.Themes) avec un mini-aperçu animé de chaque
	fond (le VRAI décor du fond d'écran en miniature, Background.BuildPreview), son nom, son prix en Dopamine et/ou un bouton "💎" (Game Pass
	Robux), un badge "👑 VIP" pour les thèmes Premium, et l'état
	possédé / équipé (ClientState.Data.Themes).
	- Achat / équipement : RemoteFunction "ThemeShop" ("buy" | "equip", id).
	- Robux : MarketplaceService:PromptGamePassPurchase (le serveur vérifie
	  l'achat et débloque le thème).
	Les thèmes sont conservés pour toujours (même après l'océan).
]]

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Client = script.Parent.Parent.Parent
local Theme = require(Client.Theme)
local UIUtil = require(Client.UIUtil)
local ClientState = require(Client.ClientState)
local Effects = require(Client.Effects)
local SoundManager = require(Client.SoundManager)
local Notifications = require(script.Parent.Parent.Notifications)
local NeedDopamine = require(script.Parent.Parent.NeedDopamine)
local Background = require(script.Parent.Parent.Background)
local Config = require(ReplicatedStorage.Shared.Config)
local NumberFormatter = require(ReplicatedStorage.Shared.NumberFormatter)
local Net = require(ReplicatedStorage.Shared.Net)
local Locale = require(ReplicatedStorage.Shared.Locale)

-- Title / Subtitle en anglais : traduits par PanelManager
local Themes = {
	Title = "🎨 Themes",
	Subtitle = "Change the game's background",
	Color = Theme.Colors.Cyan,
	Size = Vector2.new(760, 540),
}

local ROBUX_COLOR = Theme.Colors.Robux or Theme.Colors.Green
local PREMIUM_COLOR = Theme.Colors.Premium or Theme.Colors.Gold
local WHITE = Color3.new(1, 1, 1)

type Card = {
	Theme: any,
	Card: Frame,
	Stroke: UIStroke,
	Primary: TextButton,
	Robux: TextButton,
	Status: TextLabel,
	Check: Frame,
	Lock: TextLabel,
	Action: string, -- action du bouton principal : "equip" | "buy" | "vip" | "robux" | "none"
}

local header: TextLabel
local cards: { [string]: Card } = {}
local previews: { Background.Preview } = {}
local animation: RBXScriptConnection? = nil
local busy = false

----------------------------------------------------------------------
-- Outils
----------------------------------------------------------------------

local function getThemesData(data): ({ [string]: boolean }, string)
	local themes = data and data.Themes
	local owned = (type(themes) == "table" and themes.Owned) or { Classic = true }
	local equipped = (type(themes) == "table" and themes.Equipped) or "Classic"
	return owned, equipped
end

local function getDopamine(): number
	local ok, value = pcall(ClientState.GetConfirmedDopamine)
	if ok and type(value) == "number" then
		return value
	end
	local data = ClientState.Data
	return (data and data.Dopamine) or 0
end

local function vipPassId(): number
	local pass = Config.GamePassesById and Config.GamePassesById.VIP
	return (pass and tonumber(pass.GamePassId)) or 0
end

-- Petite étiquette arrondie (ex. "👑 VIP")
local function chip(parent: Instance, text: string, color: Color3, props: { [string]: any }): Frame
	local frame = UIUtil.Create("Frame", {
		Name = props.Name or "Chip",
		Size = UDim2.fromOffset(0, 20),
		AutomaticSize = Enum.AutomaticSize.X,
		AnchorPoint = props.AnchorPoint or Vector2.zero,
		Position = props.Position or UDim2.new(),
		BackgroundColor3 = color,
		ZIndex = 4,
		Parent = parent,
	})
	UIUtil.Corner(frame, UDim.new(1, 0))
	UIUtil.Stroke(frame, Theme.Colors.Border, 1, 0.5)
	UIUtil.Create("UIPadding", {
		PaddingLeft = UDim.new(0, 7),
		PaddingRight = UDim.new(0, 7),
		Parent = frame,
	})
	UIUtil.Create("TextLabel", {
		Size = UDim2.fromScale(0, 1),
		AutomaticSize = Enum.AutomaticSize.X,
		BackgroundTransparency = 1,
		Font = Theme.Fonts.Title,
		Text = text,
		TextColor3 = Theme.ContrastText(color),
		TextSize = 12,
		ZIndex = 5,
		Parent = frame,
	})
	return frame
end

----------------------------------------------------------------------
-- Mini-aperçu du fond : le vrai décor animé, en miniature
----------------------------------------------------------------------

local function buildPreviewDecor(preview: GuiObject, theme)
	local ok, result = pcall(Background.BuildPreview, preview, theme.Id)
	if ok then
		table.insert(previews, result)
	else
		warn("[Themes] Aperçu impossible pour " .. tostring(theme.Id) .. " : " .. tostring(result))
	end

	-- Voile doux derrière le bouton (lisibilité)
	local veil = UIUtil.Create("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.46),
		Size = UDim2.fromOffset(120, 56),
		BackgroundColor3 = theme.Dark and Color3.new(0, 0, 0) or WHITE,
		BackgroundTransparency = 0.55,
		BorderSizePixel = 0,
		ZIndex = 4,
		Parent = preview,
	})
	UIUtil.Corner(veil, UDim.new(1, 0))
	UIUtil.Create("UIGradient", {
		Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 1),
			NumberSequenceKeypoint.new(0.3, 0.4),
			NumberSequenceKeypoint.new(0.7, 0.4),
			NumberSequenceKeypoint.new(1, 1),
		}),
		Parent = veil,
	})

	-- Mini bouton "Clique-moi" (montre la lisibilité du thème)
	local dark = theme.Dark == true
	local mini = UIUtil.Create("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.42),
		Size = UDim2.fromOffset(66, 22),
		BackgroundColor3 = dark and Theme.DarkColors.Card or WHITE,
		BackgroundTransparency = dark and 0.2 or 0,
		ZIndex = 5,
		Parent = preview,
	})
	UIUtil.Corner(mini, 7)
	UIUtil.Stroke(mini, dark and WHITE or Theme.Colors.Border, 1, dark and 0.5 or 0.2)
	if not dark then
		UIUtil.Gradient(mini, ColorSequence.new(Theme.Colors.Button, Theme.Colors.ButtonBottom), 90)
	end
	UIUtil.Create("TextLabel", {
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Font = Theme.Fonts.Body,
		Text = Locale.T("Click me"),
		TextColor3 = dark and WHITE or Theme.Colors.Text,
		TextSize = 11,
		ZIndex = 6,
		Parent = mini,
	})
	UIUtil.Create("TextLabel", {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0.42, 13),
		Size = UDim2.fromOffset(90, 14),
		BackgroundTransparency = 1,
		Font = Theme.Fonts.Title,
		Text = "123 " .. Locale.T("Dopamine"),
		TextColor3 = dark and WHITE or Theme.Colors.Text,
		TextSize = 11,
		ZIndex = 5,
		Parent = preview,
	})
end

----------------------------------------------------------------------
-- Actions
----------------------------------------------------------------------

local function popCard(card: Card)
	local scale = card.Card:FindFirstChild("PopScale") :: UIScale?
	if scale then
		scale.Scale = 1.07
		UIUtil.Tween(scale, 0.35, { Scale = 1 }, Enum.EasingStyle.Back)
	end
end

local function invoke(action: string, themeId: string): (boolean, string?)
	local ok, success, message = pcall(function()
		return Net.Function("ThemeShop"):InvokeServer(action, themeId)
	end)
	if not ok then
		return false, Locale.T("Network error, try again.")
	end
	return success == true, message and tostring(message) or nil
end

local function request(action: string, theme)
	if busy then
		return
	end
	busy = true
	local ok, message = invoke(action, theme.Id)
	local card = cards[theme.Id]
	if ok and action == "buy" then
		-- Acheté : on l'équipe tout de suite
		SoundManager.Play("Buy", 1.1)
		Effects.Confetti(50)
		Notifications.Toast(Locale.T("%s: yours forever!", theme.Icon .. " " .. Locale.T(theme.Name)), Theme.Colors.Green, 4, Locale.T("New theme"))
		-- (le serveur l'équipe automatiquement après l'achat)
	elseif ok then
		SoundManager.Play("Open", 1.25)
		Notifications.Toast(Locale.T("🎨 Theme equipped: %s", theme.Icon .. " " .. Locale.T(theme.Name)), Theme.Colors.Cyan, 2.5)
	else
		SoundManager.Play("Error", 0.7)
		Notifications.Toast(message or Locale.T("Not possible right now."), Theme.Colors.Red)
		if card then
			UIUtil.Shake(card.Primary)
		end
	end
	busy = false
	if ok and card then
		popCard(card)
	end
end

-- Ouvre la fenêtre d'achat Roblox d'un Game Pass
local function promptPass(passId: number, what: string)
	if passId == 0 then
		SoundManager.Play("Error", 0.7)
		if RunService:IsStudio() then
			Notifications.Toast(Locale.T("Add the Game Pass ID in Config (%s)", what), Theme.Colors.Orange, 4)
		else
			Notifications.Toast(Locale.T("Coming soon!"), Theme.Colors.Orange)
		end
		return
	end
	local ok, err = pcall(function()
		MarketplaceService:PromptGamePassPurchase(Players.LocalPlayer, passId)
	end)
	if not ok then
		warn("[Themes] PromptGamePassPurchase : " .. tostring(err))
		Notifications.Toast(Locale.T("The Roblox store isn't responding, try again."), Theme.Colors.Red)
	end
end

local function onPrimary(card: Card)
	local theme = card.Theme
	local action = card.Action
	if action == "equip" then
		task.spawn(request, "equip", theme)
	elseif action == "buy" then
		if not card.Primary:GetAttribute("Enabled") then
			SoundManager.Play("Error", 0.7)
			UIUtil.Shake(card.Primary)
			local missing = math.max(0, (tonumber(theme.Cost) or 0) - getDopamine())
			NeedDopamine.Offer(missing, function()
				Notifications.Toast(Locale.T("You need %s more Dopamine", NumberFormatter.Format(missing)), Theme.Colors.Red)
			end)
			return
		end
		task.spawn(request, "buy", theme)
	elseif action == "vip" then
		promptPass(vipPassId(), "Monetization.GamePasses VIP")
	elseif action == "robux" then
		promptPass(tonumber(theme.GamePassId) or 0, "Themes." .. theme.Id .. ".GamePassId")
	else
		popCard(card) -- déjà équipé
	end
end

----------------------------------------------------------------------
-- Construction
----------------------------------------------------------------------

local function buildCard(list: ScrollingFrame, theme)
	-- Support transparent (dans la grille) : porte la carte et son ombre
	local cell = UIUtil.Create("Frame", {
		Name = theme.Id,
		BackgroundTransparency = 1,
		LayoutOrder = theme.Order or 0,
		Parent = list,
	})
	local card = UIUtil.Create("Frame", {
		Name = "Card",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Theme.Colors.Card,
		ZIndex = 2,
		Parent = cell,
	})
	UIUtil.Corner(card, 16)
	local stroke = UIUtil.Stroke(card, Theme.Colors.CardBorder, 1.5, 0.15)
	UIUtil.Create("UIScale", { Name = "PopScale", Parent = card })
	pcall(UIUtil.Shadow, card, 4, 0.82)

	-- Aperçu (CanvasGroup : le décor est coupé aux coins arrondis)
	local preview = UIUtil.Create("CanvasGroup", {
		Name = "Preview",
		Position = UDim2.fromOffset(8, 8),
		Size = UDim2.new(1, -16, 0, 104),
		BackgroundColor3 = WHITE,
		BackgroundTransparency = 1,
		ZIndex = 2,
		Parent = card,
	})
	-- L'aperçu montre les vraies couleurs du thème (pas d'habillage sombre)
	preview:SetAttribute("DarkSkinIgnore", true)
	UIUtil.Corner(preview, 11)
	UIUtil.Stroke(preview, Theme.Colors.Border, 1, 0.75)
	-- (un UIGradient directement sur le CanvasGroup teinterait tout son contenu)
	local sky = UIUtil.Create("Frame", {
		Name = "Sky",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = WHITE,
		BorderSizePixel = 0,
		ZIndex = 1,
		Parent = preview,
	})
	UIUtil.Gradient(sky, ColorSequence.new(theme.Top, theme.Bottom), 90)
	buildPreviewDecor(preview, theme)

	if theme.Premium then
		chip(preview, "👑 VIP", PREMIUM_COLOR, { Position = UDim2.fromOffset(6, 6) })
	end
	local check = UIUtil.Create("Frame", {
		Name = "Check",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -6, 0, 6),
		Size = UDim2.fromOffset(22, 22),
		BackgroundColor3 = Theme.Colors.Green,
		Visible = false,
		ZIndex = 6,
		Parent = preview,
	})
	UIUtil.Corner(check, UDim.new(1, 0))
	UIUtil.Stroke(check, WHITE, 2)
	UIUtil.Create("TextLabel", {
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Font = Theme.Fonts.Title,
		Text = "✓",
		TextColor3 = WHITE,
		TextSize = 15,
		ZIndex = 7,
		Parent = check,
	})
	local lock = UIUtil.Create("TextLabel", {
		Name = "Lock",
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.new(1, -4, 1, -2),
		Size = UDim2.fromOffset(22, 22),
		BackgroundTransparency = 1,
		Font = Theme.Fonts.Body,
		Text = "🔒",
		TextSize = 14,
		ZIndex = 6,
		Parent = preview,
	})

	-- Nom + statut
	UIUtil.Create("TextLabel", {
		Name = "Name",
		Position = UDim2.fromOffset(10, 118),
		Size = UDim2.new(1, -20, 0, 20),
		BackgroundTransparency = 1,
		Font = Theme.Fonts.Title,
		Text = theme.Icon .. " " .. Locale.T(theme.Name),
		TextColor3 = Theme.Colors.Text,
		TextSize = 16,
		TextTruncate = Enum.TextTruncate.AtEnd,
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = 2,
		Parent = card,
	})
	local status = UIUtil.Create("TextLabel", {
		Name = "Status",
		Position = UDim2.fromOffset(10, 138),
		Size = UDim2.new(1, -20, 0, 16),
		BackgroundTransparency = 1,
		Font = Theme.Fonts.Body,
		Text = "",
		TextColor3 = Theme.Colors.TextDim,
		TextSize = 13,
		TextTruncate = Enum.TextTruncate.AtEnd,
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = 2,
		Parent = card,
	})

	-- Boutons : action principale + "💎" (Game Pass du thème)
	local primary = UIUtil.NeonButton({
		Name = "Primary",
		Text = "",
		Size = UDim2.new(1, -16, 0, 34),
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, 8, 1, -8),
		Color = Theme.Colors.Green,
		CornerRadius = 17,
		MaxTextSize = 15,
		ZIndex = 2,
		Parent = card,
	})
	local robux = UIUtil.NeonButton({
		Name = "Robux",
		Text = "💎",
		Size = UDim2.fromOffset(40, 34),
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.new(1, -8, 1, -8),
		Color = ROBUX_COLOR,
		CornerRadius = 17,
		MaxTextSize = 17,
		ZIndex = 2,
		Parent = card,
	})
	robux.Visible = false

	local entry: Card = {
		Theme = theme,
		Card = card,
		Stroke = stroke,
		Primary = primary,
		Robux = robux,
		Status = status,
		Check = check,
		Lock = lock,
		Action = "none",
	}
	cards[theme.Id] = entry

	primary.Activated:Connect(function()
		onPrimary(entry)
	end)
	robux.Activated:Connect(function()
		promptPass(tonumber(theme.GamePassId) or 0, "Themes." .. theme.Id .. ".GamePassId")
	end)

	-- Survol : la carte se soulève un peu
	card.MouseEnter:Connect(function()
		UIUtil.Tween(card, 0.15, { Position = UDim2.fromOffset(0, -3) })
	end)
	card.MouseLeave:Connect(function()
		UIUtil.Tween(card, 0.15, { Position = UDim2.fromOffset(0, 0) })
	end)
end

function Themes.Build(content: Frame)
	header = UIUtil.Create("TextLabel", {
		Name = "Header",
		Size = UDim2.new(1, 0, 0, 24),
		BackgroundTransparency = 1,
		Font = Theme.Fonts.Body,
		Text = "",
		TextColor3 = Theme.Colors.TextDim,
		TextSize = 15,
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = content,
	})

	local list = UIUtil.Create("ScrollingFrame", {
		Name = "List",
		Size = UDim2.new(1, 0, 1, -30),
		Position = UDim2.fromOffset(0, 30),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 6,
		ScrollBarImageColor3 = Theme.Colors.Cyan,
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollingDirection = Enum.ScrollingDirection.Y,
		Parent = content,
	})
	UIUtil.Create("UIPadding", {
		PaddingTop = UDim.new(0, 6),
		PaddingLeft = UDim.new(0, 4),
		PaddingRight = UDim.new(0, 12),
		PaddingBottom = UDim.new(0, 10),
		Parent = list,
	})
	UIUtil.Create("UIGridLayout", {
		CellSize = UDim2.new(0.25, -9, 0, 214),
		CellPadding = UDim2.fromOffset(12, 14),
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = list,
	})

	for _, theme in ipairs(Config.Themes) do
		buildCard(list, theme)
	end

	-- Achat Robux terminé (le serveur vérifie et débloque le thème)
	MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(player, passId, purchased)
		if player ~= Players.LocalPlayer or not purchased then
			return
		end
		for _, theme in ipairs(Config.Themes) do
			if theme.GamePassId ~= 0 and theme.GamePassId == passId then
				SoundManager.Play("Buy", 1.1)
				Effects.Confetti(60)
				Notifications.Toast(
					Locale.T("%s unlocked, thank you!", theme.Icon .. " " .. Locale.T(theme.Name)),
					ROBUX_COLOR,
					4,
					Locale.T("💎 Purchase successful")
				)
				return
			end
		end
	end)
end

function Themes.Update(data)
	local owned, equipped = getThemesData(data)
	local dopamine = getDopamine()
	local isVIP = data and data.IsVIP == true
	local ownedCount = 0

	for id, card in pairs(cards) do
		local theme = card.Theme
		local cost = tonumber(theme.Cost)
		local passId = tonumber(theme.GamePassId) or 0
		local isOwned = owned[id] == true
		local isEquipped = isOwned and equipped == id
		if isOwned then
			ownedCount += 1
		end

		local primary = card.Primary
		local showRobux = false
		card.Check.Visible = isEquipped
		card.Lock.Visible = not isOwned

		if isEquipped then
			card.Action = "none"
			primary.Text = Locale.T("✔ Equipped")
			primary:SetAttribute("BaseColor", Theme.Colors.ButtonBottom)
			UIUtil.SetButtonEnabled(primary, true)
			primary.TextColor3 = Theme.Colors.Text
			card.Status.Text = Locale.T("Your current background")
			card.Status.TextColor3 = Theme.Colors.Green
			card.Stroke.Color = Theme.Colors.Green
			card.Stroke.Thickness = 3
			card.Stroke.Transparency = 0
		elseif isOwned then
			card.Action = "equip"
			primary.Text = Locale.T("Equip")
			primary:SetAttribute("BaseColor", Theme.Colors.Blue)
			UIUtil.SetButtonEnabled(primary, true)
			primary.TextColor3 = Theme.Colors.TextLight
			card.Status.Text = (theme.Premium and isVIP) and Locale.T("👑 Included with VIP") or Locale.T("✔ Owned")
			card.Status.TextColor3 = Theme.Colors.TextDim
			card.Stroke.Color = Theme.Colors.CardBorder
			card.Stroke.Thickness = 1.5
			card.Stroke.Transparency = 0.15
		else
			card.Stroke.Color = Theme.Colors.CardBorder
			card.Stroke.Thickness = 1.5
			card.Stroke.Transparency = 0.15
			if cost then
				-- Achetable en Dopamine (et peut-être aussi en Robux)
				local affordable = dopamine >= cost
				card.Action = "buy"
				primary.Text = cost <= 0 and Locale.T("Free") or ("💧 " .. NumberFormatter.Format(cost))
				primary:SetAttribute("BaseColor", Theme.Colors.Green)
				UIUtil.SetButtonEnabled(primary, affordable)
				primary.TextColor3 = Theme.Colors.TextDark
				showRobux = passId ~= 0
				if theme.Premium then
					card.Status.Text = Locale.T("Or free with the VIP pass")
				elseif showRobux then
					card.Status.Text = Locale.T("Dopamine or 💎 Robux")
				else
					card.Status.Text = affordable and Locale.T("You can afford it!") or Locale.T("Not enough Dopamine yet")
				end
				card.Status.TextColor3 = affordable and Theme.Colors.TextDim or Theme.Colors.Red
			elseif passId ~= 0 then
				-- Uniquement en Robux (Game Pass du thème)
				card.Action = "robux"
				primary.Text = "💎 Robux"
				primary:SetAttribute("BaseColor", ROBUX_COLOR)
				UIUtil.SetButtonEnabled(primary, true)
				primary.TextColor3 = Theme.Colors.TextLight
				card.Status.Text = theme.Premium and Locale.T("Robux or VIP pass") or Locale.T("Robux exclusive")
				card.Status.TextColor3 = Theme.Colors.TextDim
			elseif theme.Premium then
				-- Uniquement avec le pass VIP
				card.Action = "vip"
				primary.Text = Locale.T("👑 VIP Pass")
				primary:SetAttribute("BaseColor", PREMIUM_COLOR)
				UIUtil.SetButtonEnabled(primary, true)
				primary.TextColor3 = Theme.Colors.TextDark
				card.Status.Text = Locale.T("VIP exclusive")
				card.Status.TextColor3 = Theme.Colors.TextDim
			else
				card.Action = "none"
				primary.Text = Locale.T("Soon")
				primary:SetAttribute("BaseColor", Theme.Colors.Disabled)
				UIUtil.SetButtonEnabled(primary, false)
				card.Status.Text = Locale.T("Not on sale yet")
				card.Status.TextColor3 = Theme.Colors.TextDim
			end
		end

		card.Robux.Visible = showRobux
		primary.Size = showRobux and UDim2.new(1, -62, 0, 34) or UDim2.new(1, -16, 0, 34)
	end

	header.Text = Locale.T(
		"%d / %d themes unlocked  •  kept forever, even after the ocean 🌊%s",
		ownedCount,
		#Config.Themes,
		isVIP and "  •  👑 VIP" or ""
	)
end

-- Animation des aperçus seulement quand la fenêtre est ouverte
function Themes.OnOpen()
	if animation then
		return
	end
	animation = RunService.Heartbeat:Connect(function(dt: number)
		for _, preview in ipairs(previews) do
			preview.Update(dt)
		end
	end)
end

function Themes.OnClose()
	local connection = animation
	if connection then
		connection:Disconnect()
		animation = nil
	end
end

return Themes
