--[[
	Arcade (ModuleScript) — 🕹️ salle d'arcade
	Emplacement : ReplicatedStorage > Client > Components > Panels > Arcade

	Fenêtre "néon kawaii" (débloquée par l'amélioration "Arcade", Feature
	"Minigames") :
	  - en-tête : onglets Jeux / Duels / Boutique à tickets / Records +
	    portefeuille : 🎟️ tickets (= boutique, bouton "+" pour en acheter) et
	    🏆 trophées (= mises des duels, gagnés seulement en jouant) ; le
	    sous-titre de la fenêtre l'explique en une ligne ;
	  - Jeux : cartes illustrées (solo et duels) ; un jeu solo se charge à la
	    demande (Client > Minigames > Solo_<Id>) dans une grande zone de jeu
	    avec bouton retour ;
	  - Duels : choix du jeu et de la mise (en 🏆 trophées, jamais en tickets :
	    ils s'achètent en Robux), joueurs du serveur qui ont l'arcade,
	    invitations envoyées / reçues ;
	  - duel en cours : bandeau "toi VS adversaire" (scores, pot, temps),
	    plateau (Client > Minigames > Duel_<Id>), écran de résultat ;
	  - Boutique à tickets : petits boosts, Dopamine, badges d'arcade. Pas
	    assez de tickets -> fenêtre NeedTickets À CHAQUE fois (propose un pack
	    de la boutique Robux, onglet 🎟️ Tickets) ;
	  - Records : meilleurs scores, victoires, derniers duels.
	Les invitations arrivent même fenêtre fermée : petite carte "défi" (calque
	Toasts) avec Accepter / Refuser, et bandeaux Notifications.Show.
	API : ShowTab(id) ("Games" | "Duels" | "Shop" | "Records").

	Contrat d'un module de jeu (Client > Minigames) :
	  { Id, Kind = "Solo" | "Duel", Build = function(container, api) -> { Destroy } }
	  api = { Invoke(action, arg) -> (ok, result), OnEvent(callback(kind, payload)) -> connexion,
	          Close(), T = Locale.T, Colors, Sounds = { Play(name, pitch?) }, Notify(text, color?),
	          Game (entrée d'ArcadeConfig), Tickets() -> solde, UserId,
	          -- duels : Duel (état de départ), Seat (1 | 2), Move(coup) -> (ok, résultat) }
	  Pour un jeu solo, Invoke ajoute le préfixe "solo:" s'il manque.
	Le serveur (MinigameService) décide de TOUT : le client affiche et demande.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Players = game:GetService("Players")

local Client = script.Parent.Parent.Parent
local Theme = require(Client.Theme)
local UIUtil = require(Client.UIUtil)
local Interface = require(Client.Interface)
local ClientState = require(Client.ClientState)
local Effects = require(Client.Effects)
local SoundManager = require(Client.SoundManager)
local Notifications = require(script.Parent.Parent.Notifications)
local PanelManager = require(script.Parent.Parent.PanelManager)
local Signal = require(ReplicatedStorage.Shared.Signal)
local Net = require(ReplicatedStorage.Shared.Net)
local Locale = require(ReplicatedStorage.Shared.Locale)
local NumberFormatter = require(ReplicatedStorage.Shared.NumberFormatter)
local ArcadeConfig = require(ReplicatedStorage.Shared.ArcadeConfig)

-- Fenêtre "Pas assez de tickets" (chargée prudemment : son absence ne casse pas l'arcade)
local NeedTickets: any = nil
do
	local module = script.Parent.Parent:FindFirstChild("NeedTickets")
	if module and module:IsA("ModuleScript") then
		local ok, result = pcall(require, module)
		if ok and type(result) == "table" then
			NeedTickets = result
		else
			warn("[Arcade] NeedTickets : " .. tostring(result))
		end
	end
end

-- Title / Subtitle en anglais : traduits par PanelManager.
-- Le sous-titre est LA ligne qui explique honnêtement les deux monnaies.
local Arcade = {
	Title = "🕹️ Arcade",
	Subtitle = "🎟️ Tickets: for the ticket shop • 🏆 Trophies: duel stakes, earned only by playing",
	Color = Color3.fromRGB(166, 90, 255),
	Size = Vector2.new(900, 600),
}

local T = Locale.T
local TICKET = ArcadeConfig.Tickets.Icon
local TROPHY = ArcadeConfig.Trophies.Icon

----------------------------------------------------------------------
-- Palette néon (fond sombre violet, couleurs vives)
----------------------------------------------------------------------
local C = {
	Bg = Color3.fromRGB(24, 14, 48),
	Bg2 = Color3.fromRGB(46, 18, 84),
	Panel = Color3.fromRGB(34, 22, 70),
	Card = Color3.fromRGB(44, 30, 92),
	CardHi = Color3.fromRGB(62, 44, 124),
	Line = Color3.fromRGB(92, 70, 170),
	Text = Color3.fromRGB(255, 255, 255),
	TextDim = Color3.fromRGB(190, 178, 232),
	Pink = Color3.fromRGB(255, 79, 176),
	Cyan = Color3.fromRGB(59, 232, 255),
	Yellow = Color3.fromRGB(255, 216, 74),
	Green = Color3.fromRGB(92, 240, 138),
	Purple = Color3.fromRGB(166, 107, 255),
	Orange = Color3.fromRGB(255, 154, 60),
	Red = Color3.fromRGB(255, 90, 110),
	Blue = Color3.fromRGB(91, 140, 255),
}
-- Couleur de chaque place dans un duel (1 = rose, 2 = cyan)
local SEAT_COLORS = { C.Pink, C.Cyan }
local WHITE = Color3.new(1, 1, 1)
local BLACK = Color3.new(0, 0, 0)

-- Couleurs données aux modules de jeu (palette néon + couleurs du thème)
local API_COLORS = {}
for key, value in pairs(Theme.Colors) do
	API_COLORS[key] = value
end
for key, value in pairs(C) do
	API_COLORS[key] = value
end
API_COLORS.Seat1 = SEAT_COLORS[1]
API_COLORS.Seat2 = SEAT_COLORS[2]

-- Portefeuille de l'en-tête (🎟️ | 🏆)
local TICKET_CHIP_WIDTH = 158
local TROPHY_CHIP_WIDTH = 118
local WALLET_WIDTH = TICKET_CHIP_WIDTH + 6 + TROPHY_CHIP_WIDTH

local TABS = {
	{ Id = "Games", Text = "🎮 Games" },
	{ Id = "Duels", Text = "⚔️ Duels" },
	{ Id = "Shop", Text = "🎟️ Ticket Shop" },
	{ Id = "Records", Text = "🏅 Records" },
}

local REASONS = {
	line = "Lined up!",
	draw = "Board full: it's a draw",
	timeout = "Time's up!",
	forfeit = "Gave up",
	left = "Left the server",
	score = "First to the winning score",
	rounds = "Last round played",
	time = "Duel too long: stakes refunded",
	shutdown = "Server closing: stakes refunded",
}

----------------------------------------------------------------------
-- État
----------------------------------------------------------------------
local S: any = {
	Root = nil,
	Body = nil,
	Pages = {},
	TabButtons = {},
	Tab = "Games",
	Visible = false,
	Built = false,
	Width = 860,
	Height = 512,
	Incoming = {}, -- [id] = invitation reçue
	IncomingOrder = {},
	Outgoing = nil, -- invitation envoyée (vue serveur) + ReceivedAt
	Lobby = nil, -- dernière réponse "lobby"
	LobbyAt = 0,
	SelectedGame = ArcadeConfig.DuelGames[1] and ArcadeConfig.DuelGames[1].Id or "TicTacToe",
	SelectedStake = 0,
	Duel = nil, -- dernier état du duel en cours
	Active = nil, -- jeu affiché { Entry, Handle, Host, Listeners, IsDuel }
	Busy = false,
	Tickets = 0,
	Trophies = 0,
	ShownTickets = 0,
	Connections = {},
	LoopAccumulator = 0,
}

local arcadeRemote: RemoteFunction? = nil
local eventSignal = Signal.new() -- (kind, payload) : relais des ArcadeEvent vers le jeu affiché

----------------------------------------------------------------------
-- Petits outils d'interface (style néon)
----------------------------------------------------------------------

local function make(className: string, props)
	return UIUtil.Create(className, props)
end

local function text(props)
	local label = make("TextLabel", {
		Name = props.Name or "Text",
		BackgroundTransparency = 1,
		Font = props.Font or Theme.Fonts.Title,
		Text = props.Text or "",
		TextColor3 = props.Color or C.Text,
		TextSize = props.TextSize or 16,
		TextXAlignment = props.XAlign or Enum.TextXAlignment.Left,
		TextYAlignment = props.YAlign or Enum.TextYAlignment.Center,
		TextWrapped = props.Wrapped == true,
		TextTruncate = Enum.TextTruncate.AtEnd,
		Size = props.Size or UDim2.new(1, 0, 0, 20),
		Position = props.Position or UDim2.new(),
		AnchorPoint = props.AnchorPoint or Vector2.zero,
		ZIndex = props.ZIndex or 5,
		LayoutOrder = props.LayoutOrder or 0,
		Parent = props.Parent,
	})
	return label
end

local function panel(props)
	local frame = make(props.Class or "Frame", {
		Name = props.Name or "Panel",
		Size = props.Size or UDim2.fromScale(1, 1),
		Position = props.Position or UDim2.new(),
		AnchorPoint = props.AnchorPoint or Vector2.zero,
		BackgroundColor3 = props.Color or C.Card,
		BackgroundTransparency = props.Transparency or 0,
		BorderSizePixel = 0,
		ZIndex = props.ZIndex or 4,
		LayoutOrder = props.LayoutOrder or 0,
		ClipsDescendants = props.Clip == true,
		Parent = props.Parent,
	})
	if frame:IsA("TextButton") then
		frame.Text = ""
		frame.AutoButtonColor = false
	end
	UIUtil.Corner(frame, props.Radius or 14)
	if props.Stroke ~= false then
		UIUtil.Stroke(frame, props.StrokeColor or C.Line, props.StrokeThickness or 1.5, props.StrokeTransparency or 0.35)
	end
	return frame
end

-- Bouton néon (dégradé vif, texte blanc, animé)
local function neonButton(props)
	local color: Color3 = props.Color or C.Pink
	local button = make("TextButton", {
		Name = props.Name or "Button",
		Size = props.Size or UDim2.fromOffset(120, 36),
		Position = props.Position or UDim2.new(),
		AnchorPoint = props.AnchorPoint or Vector2.zero,
		BackgroundColor3 = color,
		AutoButtonColor = false,
		Font = Theme.Fonts.Title,
		Text = props.Text or "",
		TextColor3 = props.TextColor or (Theme.Luminance(color) > 0.7 and Color3.fromRGB(40, 20, 60) or WHITE),
		TextSize = props.TextSize or 16,
		TextTruncate = Enum.TextTruncate.AtEnd,
		ZIndex = props.ZIndex or 6,
		LayoutOrder = props.LayoutOrder or 0,
		Parent = props.Parent,
	})
	UIUtil.Corner(button, props.Radius or UDim.new(1, 0))
	-- Style v9 partagé (relief, reflet, animations) ; contour néon clair sur le fond sombre
	UIUtil.DressButton(button, color, { StrokeColor = color:Lerp(WHITE, 0.45), StrokeThickness = 1.5, StrokeTransparency = 0.15 })
	return button
end

local function setButton(button: TextButton, enabled: boolean, label: string?)
	local base = button:GetAttribute("BaseColor") or C.Pink
	button.BackgroundColor3 = enabled and base or Color3.fromRGB(80, 70, 110)
	button.TextTransparency = enabled and 0 or 0.3
	button:SetAttribute("Enabled", enabled)
	if label then
		button.Text = label
	end
end

-- Petite étiquette arrondie ("chip") néon
local function chip(parent: Instance, label: string, color: Color3, props)
	props = props or {}
	local frame = make("Frame", {
		Name = props.Name or "Chip",
		Size = UDim2.fromOffset(0, props.Height or 22),
		AutomaticSize = Enum.AutomaticSize.X,
		Position = props.Position or UDim2.new(),
		AnchorPoint = props.AnchorPoint or Vector2.zero,
		BackgroundColor3 = color,
		BackgroundTransparency = props.Transparency or 0.15,
		ZIndex = props.ZIndex or 6,
		LayoutOrder = props.LayoutOrder or 0,
		Parent = parent,
	})
	UIUtil.Corner(frame, UDim.new(1, 0))
	make("UIPadding", { PaddingLeft = UDim.new(0, 9), PaddingRight = UDim.new(0, 9), Parent = frame })
	make("TextLabel", {
		Name = "Label",
		Size = UDim2.fromScale(0, 1),
		AutomaticSize = Enum.AutomaticSize.X,
		BackgroundTransparency = 1,
		Font = Theme.Fonts.Title,
		Text = label,
		TextColor3 = props.TextColor or (Theme.Luminance(color) > 0.7 and Color3.fromRGB(40, 20, 60) or WHITE),
		TextSize = props.TextSize or 13,
		ZIndex = (props.ZIndex or 6) + 1,
		Parent = frame,
	})
	return frame
end

local function sound(name: string, pitch: number?)
	pcall(SoundManager.Play, name, pitch or 1)
end

local function toast(message: string, color: Color3?, title: string?, icon: string?)
	Notifications.Show({ Text = message, Title = title, Color = color or Theme.Colors.Purple, Icon = icon, Duration = 3.5 })
end

local function invoke(action: string, arg: any): (boolean, any)
	local remote = arcadeRemote
	if not remote then
		return false, T("Loading...")
	end
	local ok, success, result = pcall(remote.InvokeServer, remote, action, arg)
	if not ok then
		return false, T("Connection problem")
	end
	return success == true, result
end

local function formatTime(seconds: number): string
	if seconds < 60 then
		return string.format("%.1fs", seconds)
	end
	return UIUtil.FormatClock(seconds)
end

local function gameName(id: string): string
	local entry = ArcadeConfig.GamesById[id]
	return entry and T(entry.Name) or id
end

-- Avatar rond (tête du joueur) avec anneau de couleur
local function avatar(parent: Instance, userId: number, size: number, ring: Color3, props)
	props = props or {}
	local holder = make("Frame", {
		Name = "Avatar",
		Size = UDim2.fromOffset(size, size),
		Position = props.Position or UDim2.new(),
		AnchorPoint = props.AnchorPoint or Vector2.zero,
		BackgroundColor3 = C.CardHi,
		ZIndex = props.ZIndex or 6,
		LayoutOrder = props.LayoutOrder or 0,
		Parent = parent,
	})
	UIUtil.Corner(holder, UDim.new(1, 0))
	UIUtil.Stroke(holder, ring, 2, 0)
	local image = make("ImageLabel", {
		Name = "Head",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Image = userId > 0 and UIUtil.HeadshotUrl(userId, 100) or "",
		ZIndex = (props.ZIndex or 6) + 1,
		Parent = holder,
	})
	UIUtil.Corner(image, UDim.new(1, 0))
	return holder
end

----------------------------------------------------------------------
-- Portefeuille : 🎟️ tickets (boutique) et 🏆 trophées (duels)
----------------------------------------------------------------------

local ticketChip: Frame
local ticketLabel: TextLabel
local trophyChip: Frame
local trophyLabel: TextLabel

local function arcadeData()
	local data = ClientState.Data
	return (data and type(data.Arcade) == "table") and data.Arcade or {}
end

-- (nom historique : met à jour les DEUX soldes)
local function refreshTickets(animate: boolean?)
	local data = ClientState.Data
	local tickets = (data and tonumber(data.Tickets)) or 0
	local trophies = (data and tonumber(data.Trophies)) or 0
	local previousTickets, previousTrophies = S.Tickets, S.Trophies
	S.Tickets = tickets
	S.Trophies = trophies
	if ticketLabel then
		ticketLabel.Text = NumberFormatter.Format(tickets)
		trophyLabel.Text = NumberFormatter.Format(trophies)
		if animate and S.Visible then
			if tickets ~= previousTickets then
				UIUtil.Pop(ticketChip, tickets > previousTickets and 1.15 or 0.92, 0.35)
			end
			if trophies ~= previousTrophies then
				UIUtil.Pop(trophyChip, trophies > previousTrophies and 1.15 or 0.92, 0.35)
			end
		end
	end
end

-- Ouvre la boutique Robux sur l'onglet 🎟️ Tickets
local function openTicketShop()
	if not PanelManager.IsRegistered("RobuxShop") then
		return
	end
	PanelManager.Open("RobuxShop")
	local module = script.Parent:FindFirstChild("RobuxShop")
	if module and module:IsA("ModuleScript") then
		local ok, shop = pcall(require, module)
		if ok and type(shop) == "table" and type((shop :: any).ShowTab) == "function" then
			(shop :: any).ShowTab("Tickets")
		end
	end
end

-- Pas assez de 🎟️ tickets : fenêtre NeedTickets À CHAQUE fois (propose d'en acheter)
local function needTickets(missing: number, itemName: string?)
	local function fallback()
		toast(T("Not enough tickets"), Theme.Colors.Red)
	end
	if NeedTickets then
		local ok = pcall(NeedTickets.Offer, missing, { Have = S.Tickets, Item = itemName, Fallback = fallback })
		if ok then
			return
		end
	end
	fallback()
end

-- Pas assez de 🏆 trophées : ils ne s'achètent PAS, on explique comment en gagner
local function needTrophies()
	sound("Error", 0.8)
	toast(T("Not enough trophies: win arcade games to earn some!"), Theme.Colors.Orange, nil, TROPHY)
end

----------------------------------------------------------------------
-- Déclarations (fonctions qui s'appellent entre elles)
----------------------------------------------------------------------
local selectTab
local refreshLobby
local renderLobby
local openGame
local closeGame
local showDuel
local renderShop
local renderRecords
local showInvitePopup
local hideInvitePopup
local updateDuelStrip
local showResult

----------------------------------------------------------------------
-- Onglets + en-tête
----------------------------------------------------------------------

local function paintTabs()
	for id, button in pairs(S.TabButtons) do
		local selected = id == S.Tab
		-- v9.1 : le dégradé est sur un fond séparé ("GlowFill") : posé sur le
		-- bouton lui-même, il teintait aussi le texte blanc, qui devenait
		-- invisible sur l'onglet choisi (seul l'emoji restait)
		button.BackgroundTransparency = selected and 1 or 0.55
		button.BackgroundColor3 = C.Card
		local label = button:FindFirstChild("Label") :: TextLabel?
		if label then
			label.TextColor3 = selected and WHITE or C.TextDim
			local labelStroke = label:FindFirstChildOfClass("UIStroke")
			if labelStroke then
				labelStroke.Enabled = selected
			end
		end
		local fill = button:FindFirstChild("GlowFill") :: Frame?
		if fill then
			fill.Visible = selected
		end
		local stroke = button:FindFirstChildOfClass("UIStroke")
		if stroke then
			stroke.Transparency = selected and 0.1 or 0.6
		end
	end
end

local tabBadge: TextLabel

local function refreshTabBadge()
	local count = 0
	for _ in pairs(S.Incoming) do
		count += 1
	end
	if tabBadge then
		UIUtil.SetBadge(tabBadge, count)
	end
end

local function buildHeader(root: Frame)
	local bar = make("Frame", {
		Name = "TopBar",
		Size = UDim2.new(1, -24, 0, 44),
		Position = UDim2.fromOffset(12, 10),
		BackgroundTransparency = 1,
		ZIndex = 5,
		Parent = root,
	})
	local tabs = make("Frame", {
		Name = "Tabs",
		Size = UDim2.new(1, -(WALLET_WIDTH + 8), 1, 0),
		BackgroundTransparency = 1,
		ZIndex = 5,
		Parent = bar,
	})
	make("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		VerticalAlignment = Enum.VerticalAlignment.Center,
		Padding = UDim.new(0, 8),
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = tabs,
	})
	for index, tab in ipairs(TABS) do
		local button = make("TextButton", {
			Name = "Tab_" .. tab.Id,
			Size = UDim2.fromOffset(0, 38),
			AutomaticSize = Enum.AutomaticSize.X,
			BackgroundColor3 = C.Card,
			BackgroundTransparency = 0.55,
			AutoButtonColor = false,
			Text = "",
			LayoutOrder = index,
			ZIndex = 6,
			Parent = tabs,
		})
		UIUtil.Corner(button, UDim.new(1, 0))
		UIUtil.Stroke(button, C.Pink:Lerp(WHITE, 0.3), 1.5, 0.6)
		make("UIPadding", { PaddingLeft = UDim.new(0, 14), PaddingRight = UDim.new(0, 14), Parent = button })
		-- Fond dégradé de l'onglet choisi (déborde sur le rembourrage)
		local glowFill = make("Frame", {
			Name = "GlowFill",
			Size = UDim2.new(1, 28, 1, 0),
			Position = UDim2.fromOffset(-14, 0),
			BackgroundColor3 = WHITE,
			BorderSizePixel = 0,
			Visible = false,
			ZIndex = 6,
			Parent = button,
		})
		UIUtil.Corner(glowFill, UDim.new(1, 0))
		make("UIGradient", {
			Name = "Glow",
			Color = ColorSequence.new(C.Pink:Lerp(WHITE, 0.1), C.Purple),
			Rotation = 0,
			Parent = glowFill,
		})
		local tabLabel = make("TextLabel", {
			Name = "Label",
			Size = UDim2.fromScale(0, 1),
			AutomaticSize = Enum.AutomaticSize.X,
			BackgroundTransparency = 1,
			Font = Theme.Fonts.Title,
			Text = T(tab.Text),
			TextColor3 = C.TextDim,
			TextSize = 16,
			ZIndex = 7,
			Parent = button,
		})
		local labelStroke = UIUtil.Stroke(tabLabel, C.Purple:Lerp(Color3.new(0, 0, 0), 0.4), 1.2, 0.3)
		labelStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
		labelStroke.Enabled = false
		UIUtil.AnimateButton(button, 1.04, 0.95)
		button.Activated:Connect(function()
			if S.Tab ~= tab.Id then
				sound("Click", 1.1)
			end
			selectTab(tab.Id)
		end)
		S.TabButtons[tab.Id] = button
		if tab.Id == "Duels" then
			tabBadge = UIUtil.Badge(button, 20)
			tabBadge.Position = UDim2.new(1, 10, 0, 2)
		end
	end

	-- Portefeuille : 🎟️ tickets (néon jaune, "+" = en acheter) | 🏆 trophées (néon cyan)
	local wallet = make("Frame", {
		Name = "Wallet",
		Size = UDim2.fromOffset(WALLET_WIDTH, 44),
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, 0, 0, 0),
		BackgroundTransparency = 1,
		ZIndex = 6,
		Parent = bar,
	})
	make("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		HorizontalAlignment = Enum.HorizontalAlignment.Right,
		VerticalAlignment = Enum.VerticalAlignment.Center,
		Padding = UDim.new(0, 6),
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = wallet,
	})
	local function walletChip(name: string, icon: string, color: Color3, top: Color3, bottom: Color3, caption: string, width: number, order: number)
		local chipFrame = panel({
			Name = name,
			Size = UDim2.fromOffset(width, 44),
			Color = WHITE,
			StrokeColor = color,
			StrokeTransparency = 0.05,
			StrokeThickness = 2,
			Radius = 14,
			LayoutOrder = order,
			ZIndex = 6,
			Parent = wallet,
		})
		UIUtil.Gradient(chipFrame, ColorSequence.new(top, bottom), 90)
		text({
			Name = "Icon",
			Text = icon,
			TextSize = 24,
			Size = UDim2.fromOffset(32, 32),
			AnchorPoint = Vector2.new(0, 0.5),
			Position = UDim2.new(0, 6, 0.5, 0),
			XAlign = Enum.TextXAlignment.Center,
			ZIndex = 7,
			Parent = chipFrame,
		})
		local balance = text({
			Name = "Balance",
			Text = "0",
			Font = Theme.Fonts.Number,
			TextSize = 21,
			Color = color,
			Size = UDim2.new(1, -44, 0, 22),
			Position = UDim2.fromOffset(40, 3),
			ZIndex = 7,
			Parent = chipFrame,
		})
		text({
			Name = "Caption",
			Text = caption,
			Font = Theme.Fonts.Body,
			TextSize = 11,
			Color = color:Lerp(WHITE, 0.55),
			Size = UDim2.new(1, -44, 0, 13),
			Position = UDim2.fromOffset(40, 25),
			ZIndex = 7,
			Parent = chipFrame,
		})
		return chipFrame, balance
	end
	ticketChip, ticketLabel = walletChip("Tickets", TICKET, C.Yellow, Color3.fromRGB(110, 60, 24), Color3.fromRGB(60, 26, 72),
		T("for the shop"), TICKET_CHIP_WIDTH, 1)
	trophyChip, trophyLabel = walletChip("Trophies", TROPHY, C.Cyan, Color3.fromRGB(20, 80, 110), Color3.fromRGB(44, 26, 90),
		T("for duels"), TROPHY_CHIP_WIDTH, 2)
	-- Bouton "+" : acheter des tickets (boutique Robux, onglet 🎟️ Tickets)
	ticketLabel.Size = UDim2.new(1, -72, 0, 22)
	local caption = ticketChip:FindFirstChild("Caption") :: TextLabel?
	if caption then
		caption.Size = UDim2.new(1, -72, 0, 13)
	end
	local plus = make("TextButton", {
		Name = "BuyTickets",
		Size = UDim2.fromOffset(26, 26),
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -7, 0.5, 0),
		BackgroundColor3 = C.Green,
		AutoButtonColor = false,
		Font = Theme.Fonts.Title,
		Text = "+",
		TextColor3 = Color3.fromRGB(20, 60, 30),
		TextSize = 22,
		ZIndex = 8,
		Parent = ticketChip,
	})
	UIUtil.Corner(plus, UDim.new(1, 0))
	UIUtil.DressButton(plus, C.Green, { StrokeColor = WHITE, StrokeThickness = 1.5, StrokeTransparency = 0.2, Hover = 1.12, Press = 0.9 })
	plus.Activated:Connect(function()
		sound("Click", 1.2)
		openTicketShop()
	end)
	-- Grandes zones tactiles (téléphone) : toucher le solde 🎟️ = en acheter ;
	-- toucher le solde 🏆 = rappel honnête de ce que sont les trophées
	local function hitbox(parent: Frame, name: string): TextButton
		return make("TextButton", {
			Name = name,
			Size = UDim2.fromScale(1, 1),
			BackgroundTransparency = 1,
			Text = "",
			AutoButtonColor = false,
			ZIndex = 7,
			Parent = parent,
		})
	end
	hitbox(ticketChip, "TicketsHitbox").Activated:Connect(function()
		sound("Click", 1.2)
		openTicketShop()
	end)
	hitbox(trophyChip, "TrophiesHitbox").Activated:Connect(function()
		sound("Click", 1.1)
		UIUtil.Pop(trophyChip, 1.1, 0.3)
		toast(T("Trophies are your duel stakes: win arcade games to earn them. They can't be bought."), Theme.Colors.Cyan, nil, TROPHY)
	end)
end

----------------------------------------------------------------------
-- Onglet Jeux : cartes illustrées
----------------------------------------------------------------------

local function recordText(entry): string?
	local arcade = arcadeData()
	local best = arcade.Best and arcade.Best[entry.Id]
	if type(best) ~= "number" then
		return nil
	end
	if entry.RecordFormat == "Time" then
		return formatTime(best)
	end
	return NumberFormatter.Format(best)
end

-- Illustration d'une carte : dégradé, losange lumineux, étincelles, grosse icône
local function cardArt(parent: Instance, entry, height: number)
	local art = make("Frame", {
		Name = "Art",
		Size = UDim2.new(1, -10, 0, height),
		Position = UDim2.fromOffset(5, 5),
		BackgroundColor3 = entry.Color,
		ClipsDescendants = true,
		ZIndex = 6,
		Parent = parent,
	})
	UIUtil.Corner(art, 11)
	art.BackgroundColor3 = WHITE
	UIUtil.Gradient(art, ColorSequence.new(entry.Color, entry.Accent or entry.Color:Lerp(BLACK, 0.3)), 35)
	-- Rayures "rétro" (3 bandes claires)
	for index = 1, 3 do
		local stripe = make("Frame", {
			Name = "Stripe",
			Size = UDim2.new(1.6, 0, 0, 5),
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.new(0.5, 0, 0, height - 10 - index * 9),
			Rotation = -12,
			BackgroundColor3 = WHITE,
			BackgroundTransparency = 0.72 + index * 0.06,
			BorderSizePixel = 0,
			ZIndex = 6,
			Parent = art,
		})
		UIUtil.Corner(stripe, 3)
	end
	-- Losange lumineux derrière l'icône
	local diamond = make("Frame", {
		Name = "Diamond",
		Size = UDim2.fromOffset(height * 0.72, height * 0.72),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Rotation = 45,
		BackgroundColor3 = WHITE,
		BackgroundTransparency = 0.72,
		ZIndex = 6,
		Parent = art,
	})
	UIUtil.Corner(diamond, 12)
	UIUtil.Stroke(diamond, WHITE, 2, 0.4)
	-- Étincelles
	local sparkles = { { 0.12, 0.56, 13 }, { 0.88, 0.5, 11 }, { 0.78, 0.84, 12 }, { 0.24, 0.82, 9 } }
	for _, spec in ipairs(sparkles) do
		text({
			Text = "✦",
			TextSize = spec[3],
			Color = WHITE,
			Size = UDim2.fromOffset(16, 16),
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(spec[1], spec[2]),
			XAlign = Enum.TextXAlignment.Center,
			ZIndex = 7,
			Parent = art,
		}).TextTransparency = 0.25
	end
	local icon = text({
		Name = "Icon",
		Text = entry.Icon,
		TextSize = math.floor(height * 0.52),
		Size = UDim2.fromOffset(height, height),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.52),
		XAlign = Enum.TextXAlignment.Center,
		ZIndex = 8,
		Parent = art,
	})
	return art, icon
end

local gameCards = {} -- [id] = { Record = TextLabel, Entry }

local function buildGameCard(parent: Instance, entry, order: number)
	local card = panel({
		Class = "TextButton",
		Name = entry.Id,
		Color = C.Card,
		StrokeColor = entry.Color,
		StrokeTransparency = 0.45,
		Radius = 16,
		LayoutOrder = order,
		ZIndex = 5,
		Parent = parent,
	})
	local artHeight = 96
	cardArt(card, entry, artHeight)
	-- Pastille "SOLO" / "DUEL" + récompense
	local isDuel = entry.Kind == "Duel"
	chip(card, isDuel and T("DUEL") or T("SOLO"), isDuel and C.Pink or C.Purple, {
		Position = UDim2.fromOffset(11, 11), ZIndex = 9, Height = 20, TextSize = 12, Transparency = 0.05,
	})
	-- Récompense : duel = mise x2 (en 🏆) ; solo = 🎟️ + 🏆 par victoire
	local reward = isDuel and ("x2 " .. TROPHY)
		or string.format("+%s %s  +%s %s", tostring(entry.Tickets or 0), TICKET, tostring(ArcadeConfig.Trophies.PerSoloWin), TROPHY)
	chip(card, reward, Color3.fromRGB(40, 24, 70), {
		AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -11, 0, 11), ZIndex = 9, Height = 20, TextSize = 12,
		Transparency = 0.2, TextColor = C.Yellow,
	})
	text({
		Name = "Name",
		Text = T(entry.Name),
		TextSize = 17,
		Size = UDim2.new(1, -20, 0, 20),
		Position = UDim2.fromOffset(10, artHeight + 10),
		ZIndex = 6,
		Parent = card,
	})
	text({
		Name = "Description",
		Text = T(entry.Description),
		Font = Theme.Fonts.Body,
		TextSize = 13,
		Color = C.TextDim,
		Wrapped = true,
		YAlign = Enum.TextYAlignment.Top,
		Size = UDim2.new(1, -20, 0, 34),
		Position = UDim2.fromOffset(10, artHeight + 31),
		ZIndex = 6,
		Parent = card,
	})
	local record = text({
		Name = "Record",
		Text = "",
		TextSize = 13,
		Color = C.Yellow,
		Size = UDim2.new(1, -90, 0, 18),
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, 10, 1, -8),
		ZIndex = 6,
		Parent = card,
	})
	local play = chip(card, isDuel and T("⚔️ Challenge") or T("▶ Play"), entry.Color, {
		AnchorPoint = Vector2.new(1, 1), Position = UDim2.new(1, -9, 1, -7), ZIndex = 7, Height = 22, TextSize = 13, Transparency = 0,
	})
	UIUtil.Stroke(play, WHITE, 1, 0.55)
	UIUtil.AnimateButton(card, 1.03, 0.97)
	card.MouseEnter:Connect(function()
		local stroke = card:FindFirstChildOfClass("UIStroke")
		if stroke then
			stroke.Transparency = 0
		end
	end)
	card.MouseLeave:Connect(function()
		local stroke = card:FindFirstChildOfClass("UIStroke")
		if stroke then
			stroke.Transparency = 0.45
		end
	end)
	card.Activated:Connect(function()
		sound("Click", 1.15)
		if isDuel then
			S.SelectedGame = entry.Id
			selectTab("Duels")
		else
			openGame(entry, nil)
		end
	end)
	gameCards[entry.Id] = { Record = record, Entry = entry }
end

local function refreshGameCards()
	local arcade = arcadeData()
	-- Gains du jour (plafonnés) : 🎟️ tickets et 🏆 trophées
	local soloNote = S.SoloNote
	if soloNote then
		soloNote.Text = T("Today: %s / %s %s • %s / %s %s",
			tostring(arcade.DayTickets or 0), tostring(arcade.DailyCap or ArcadeConfig.Tickets.DailyCap), TICKET,
			tostring(arcade.DayTrophies or 0), tostring(arcade.TrophyCap or ArcadeConfig.Trophies.DailyCap), TROPHY)
	end
	for id, info in pairs(gameCards) do
		local entry = info.Entry
		if entry.Kind == "Duel" then
			local wins = arcade.Wins and arcade.Wins[id] or 0
			info.Record.Text = wins > 0 and T("🏅 %s wins", tostring(wins)) or ""
		else
			local best = recordText(entry)
			info.Record.Text = best and ("🏅 " .. best) or ""
		end
	end
end

local function sectionTitle(parent: Instance, label: string, color: Color3, order: number, note: string?)
	local row = make("Frame", {
		Name = "Section",
		Size = UDim2.new(1, 0, 0, 28),
		BackgroundTransparency = 1,
		LayoutOrder = order,
		ZIndex = 5,
		Parent = parent,
	})
	local bar = make("Frame", {
		Size = UDim2.fromOffset(5, 18),
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 2, 0.5, 0),
		BackgroundColor3 = color,
		BorderSizePixel = 0,
		ZIndex = 6,
		Parent = row,
	})
	UIUtil.Corner(bar, 3)
	text({
		Text = label,
		TextSize = 17,
		Color = C.Text,
		Size = UDim2.new(0.6, 0, 1, 0),
		Position = UDim2.fromOffset(14, 0),
		ZIndex = 6,
		Parent = row,
	})
	if note then
		text({
			Name = "Note",
			Text = note,
			Font = Theme.Fonts.Body,
			TextSize = 13,
			Color = C.TextDim,
			XAlign = Enum.TextXAlignment.Right,
			Size = UDim2.new(0.55, -6, 1, 0),
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.new(1, -6, 0, 0),
			ZIndex = 6,
			Parent = row,
		})
	end
	return row
end

-- Grille de cartes à 4 colonnes (hauteur fixe) -> cadre
local function cardGrid(parent: Instance, count: number, columns: number, cellHeight: number, order: number, name: string)
	local rows = math.max(1, math.ceil(count / columns))
	local grid = make("Frame", {
		Name = name,
		Size = UDim2.new(1, 0, 0, rows * cellHeight + (rows - 1) * 12),
		BackgroundTransparency = 1,
		LayoutOrder = order,
		ZIndex = 5,
		Parent = parent,
	})
	make("UIGridLayout", {
		CellSize = UDim2.new(1 / columns, -math.ceil(12 * (columns - 1) / columns), 0, cellHeight),
		CellPadding = UDim2.fromOffset(12, 12),
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = grid,
	})
	return grid
end

local function scrollPage(parent: Instance, name: string)
	local scroll = make("ScrollingFrame", {
		Name = name,
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 5,
		ScrollBarImageColor3 = C.Purple,
		ScrollingDirection = Enum.ScrollingDirection.Y,
		CanvasSize = UDim2.new(),
		ZIndex = 5,
		Visible = false,
		Parent = parent,
	})
	local list = make("UIListLayout", {
		Padding = UDim.new(0, 10),
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = scroll,
	})
	make("UIPadding", {
		PaddingLeft = UDim.new(0, 2),
		PaddingRight = UDim.new(0, 10),
		PaddingTop = UDim.new(0, 2),
		PaddingBottom = UDim.new(0, 8),
		Parent = scroll,
	})
	return scroll, list
end

-- Hauteur totale d'une page défilante (somme des enfants + espacements)
local function fitCanvas(scroll: ScrollingFrame, list: UIListLayout)
	local total, count = 10, 0
	for _, child in ipairs(scroll:GetChildren()) do
		if child:IsA("GuiObject") and child.Visible then
			total += child.Size.Y.Offset
			count += 1
		end
	end
	total += math.max(0, count - 1) * list.Padding.Offset
	scroll.CanvasSize = UDim2.fromOffset(0, total)
end

local function buildGamesPage(body: Frame)
	local scroll, list = scrollPage(body, "Games")
	S.Pages.Games = scroll
	local solo, duel = ArcadeConfig.SoloGames, ArcadeConfig.DuelGames
	-- Duels d'abord (une rangée), puis les jeux solo : les deux sont visibles dès l'ouverture
	sectionTitle(scroll, T("Duels"), C.Pink, 1, T("Challenge a player of this server • stakes in %s trophies", TROPHY))
	local duelGrid = cardGrid(scroll, #duel, 4, 194, 2, "DuelGrid")
	for index, entry in ipairs(duel) do
		buildGameCard(duelGrid, entry, index)
	end
	local soloNote = sectionTitle(scroll, T("Solo games"), C.Purple, 3, "")
	S.SoloNote = soloNote:FindFirstChild("Note")
	local soloGrid = cardGrid(scroll, #solo, 4, 194, 4, "SoloGrid")
	for index, entry in ipairs(solo) do
		buildGameCard(soloGrid, entry, index)
	end
	fitCanvas(scroll, list)
end

----------------------------------------------------------------------
-- Onglet Duels : choix du jeu, mise, joueurs, invitations
----------------------------------------------------------------------

local L: any = {} -- éléments du lobby

local function paintDuelSetup()
	for id, tile in pairs(L.GameTiles or {}) do
		local selected = id == S.SelectedGame
		local entry = ArcadeConfig.GamesById[id]
		tile.BackgroundColor3 = selected and entry.Color:Lerp(C.Card, 0.55) or C.Card
		local stroke = tile:FindFirstChildOfClass("UIStroke")
		if stroke then
			stroke.Color = selected and entry.Color or C.Line
			stroke.Transparency = selected and 0 or 0.5
			stroke.Thickness = selected and 2.5 or 1.5
		end
		local check = tile:FindFirstChild("Check") :: GuiObject?
		if check then
			check.Visible = selected
		end
	end
	for stake, button in pairs(L.StakeButtons or {}) do
		local selected = stake == S.SelectedStake
		local affordable = S.Trophies >= stake
		button.BackgroundColor3 = selected and C.Yellow or C.Card
		button.TextColor3 = selected and Color3.fromRGB(50, 24, 60) or (affordable and C.Text or Color3.fromRGB(120, 108, 160))
		local stroke = button:FindFirstChildOfClass("UIStroke")
		if stroke then
			stroke.Color = selected and C.Yellow:Lerp(WHITE, 0.4) or C.Line
			stroke.Transparency = selected and 0 or 0.45
		end
	end
	local chosen = ArcadeConfig.GamesById[S.SelectedGame]
	if L.Preview and chosen then
		L.PreviewIcon.Text = chosen.Icon
		L.PreviewName.Text = T(chosen.Name)
		L.PreviewText.Text = T(chosen.Description)
		L.PreviewGradient.Color = ColorSequence.new(chosen.Color, chosen.Accent or chosen.Color)
	end
	if L.PotLabel then
		local stake = S.SelectedStake
		L.PotLabel.Text = stake > 0 and T("Winner takes %s %s • draw = refund", tostring(stake * 2), TROPHY)
			or T("Friendly duel: no stake, just glory")
	end
	if L.StakeTitle then
		L.StakeTitle.Text = T("2. Stake in %s trophies (you have %s)", TROPHY, NumberFormatter.Format(S.Trophies))
	end
end

local function buildDuelSetup(parent: Frame)
	local setup = panel({
		Name = "Setup",
		Size = UDim2.new(0.42, -6, 1, 0),
		Color = C.Panel,
		Radius = 16,
		ZIndex = 5,
		Parent = parent,
	})
	text({ Text = T("1. Pick a duel"), TextSize = 16, Size = UDim2.new(1, -24, 0, 22), Position = UDim2.fromOffset(12, 10), Parent = setup })
	local grid = make("Frame", {
		Name = "GameGrid",
		Size = UDim2.new(1, -24, 0, 132),
		Position = UDim2.fromOffset(12, 36),
		BackgroundTransparency = 1,
		ZIndex = 5,
		Parent = setup,
	})
	make("UIGridLayout", {
		CellSize = UDim2.new(0.5, -5, 0, 61),
		CellPadding = UDim2.fromOffset(10, 10),
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = grid,
	})
	L.GameTiles = {}
	for index, entry in ipairs(ArcadeConfig.DuelGames) do
		local tile = panel({
			Class = "TextButton",
			Name = entry.Id,
			Color = C.Card,
			Radius = 12,
			LayoutOrder = index,
			ZIndex = 6,
			Parent = grid,
		})
		local badge = make("Frame", {
			Size = UDim2.fromOffset(40, 40),
			AnchorPoint = Vector2.new(0, 0.5),
			Position = UDim2.new(0, 9, 0.5, 0),
			BackgroundColor3 = entry.Color,
			ZIndex = 7,
			Parent = tile,
		})
		UIUtil.Corner(badge, 11)
		badge.BackgroundColor3 = WHITE
		UIUtil.Gradient(badge, ColorSequence.new(entry.Color:Lerp(WHITE, 0.1), entry.Accent or entry.Color), 45)
		text({ Text = entry.Icon, TextSize = 24, Size = UDim2.fromScale(1, 1), XAlign = Enum.TextXAlignment.Center, ZIndex = 8, Parent = badge })
		text({ Text = T(entry.Name), TextSize = 14, Wrapped = true, YAlign = Enum.TextYAlignment.Bottom,
			Size = UDim2.new(1, -62, 0, 32), Position = UDim2.fromOffset(56, 5), ZIndex = 7, Parent = tile }).LineHeight = 0.95
		text({ Text = T(entry.Tagline or ""), Font = Theme.Fonts.Body, TextSize = 12, Color = C.TextDim,
			Size = UDim2.new(1, -62, 0, 16), Position = UDim2.fromOffset(56, 38), ZIndex = 7, Parent = tile })
		local check = text({ Name = "Check", Text = "✓", TextSize = 14, Color = WHITE, XAlign = Enum.TextXAlignment.Center,
			Size = UDim2.fromOffset(18, 18), AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -5, 0, 5), ZIndex = 9, Parent = tile })
		check.BackgroundTransparency = 0
		check.BackgroundColor3 = entry.Color
		UIUtil.Corner(check, UDim.new(1, 0))
		tile.Activated:Connect(function()
			sound("Click", 1.2)
			S.SelectedGame = entry.Id
			paintDuelSetup()
		end)
		L.GameTiles[entry.Id] = tile
	end

	L.StakeTitle = text({ Text = T("2. Stake (each player)"), TextSize = 16, Size = UDim2.new(1, -24, 0, 22), Position = UDim2.fromOffset(12, 180), Parent = setup })
	local stakes = make("Frame", {
		Name = "Stakes",
		Size = UDim2.new(1, -24, 0, 36),
		Position = UDim2.fromOffset(12, 206),
		BackgroundTransparency = 1,
		ZIndex = 5,
		Parent = setup,
	})
	make("UIGridLayout", {
		CellSize = UDim2.new(1 / #ArcadeConfig.Duels.Stakes, -6, 1, 0),
		CellPadding = UDim2.fromOffset(6, 0),
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = stakes,
	})
	L.StakeButtons = {}
	for index, stake in ipairs(ArcadeConfig.Duels.Stakes) do
		local button = make("TextButton", {
			Name = "Stake" .. stake,
			BackgroundColor3 = C.Card,
			AutoButtonColor = false,
			Font = Theme.Fonts.Title,
			Text = stake == 0 and T("Free") or (tostring(stake) .. " " .. TROPHY),
			TextColor3 = C.Text,
			TextSize = 14,
			LayoutOrder = index,
			ZIndex = 6,
			Parent = stakes,
		})
		UIUtil.Corner(button, 10)
		UIUtil.Stroke(button, C.Line, 1.5, 0.45)
		UIUtil.AnimateButton(button, 1.05, 0.94)
		button.Activated:Connect(function()
			if S.Trophies < stake then
				-- 🏆 jamais achetables : on explique comment en gagner
				UIUtil.Shake(button)
				needTrophies()
				return
			end
			sound("Click", 1.25)
			S.SelectedStake = stake
			paintDuelSetup()
		end)
		L.StakeButtons[stake] = button
	end
	-- (une seule ligne compacte : la boîte des règles, collée en bas, ne la touche jamais, même sur téléphone)
	L.PotLabel = text({
		Name = "Pot",
		Text = "",
		Font = Theme.Fonts.Body,
		TextSize = 13,
		Color = C.Yellow,
		Size = UDim2.new(1, -24, 0, 20),
		Position = UDim2.fromOffset(12, 247),
		ZIndex = 6,
		Parent = setup,
	})
	L.PotLabel.TextScaled = true
	make("UITextSizeConstraint", { MaxTextSize = 13, MinTextSize = 9, Parent = L.PotLabel })
	-- Aperçu du duel choisi (seulement s'il reste de la place : pas sur téléphone)
	local bodyHeight = Arcade.GetSize().Y - 88 - 72
	local previewHeight = bodyHeight - 284 - 84
	local preview = panel({
		Name = "Preview",
		Size = UDim2.new(1, -24, 0, math.max(0, previewHeight)),
		Position = UDim2.fromOffset(12, 282),
		Color = C.Card,
		StrokeTransparency = 0.5,
		Radius = 12,
		ZIndex = 6,
		Parent = setup,
	})
	preview.Visible = previewHeight >= 60
	local previewIcon = make("Frame", { Size = UDim2.fromOffset(44, 44), AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 10, 0.5, 0),
		BackgroundColor3 = WHITE, ZIndex = 7, Parent = preview })
	UIUtil.Corner(previewIcon, 12)
	L.PreviewGradient = UIUtil.Gradient(previewIcon, ColorSequence.new(C.Pink, C.Cyan), 45)
	L.PreviewIcon = text({ Text = "", TextSize = 26, Size = UDim2.fromScale(1, 1), XAlign = Enum.TextXAlignment.Center, ZIndex = 8, Parent = previewIcon })
	L.PreviewName = text({ Text = "", TextSize = 15, Size = UDim2.new(1, -74, 0, 18), Position = UDim2.new(0, 64, 0.5, -20), ZIndex = 7, Parent = preview })
	L.PreviewText = text({ Text = "", Font = Theme.Fonts.Body, TextSize = 12, Color = C.TextDim, Wrapped = true, YAlign = Enum.TextYAlignment.Top,
		Size = UDim2.new(1, -74, 0, 30), Position = UDim2.new(0, 64, 0.5, -1), ZIndex = 7, Parent = preview })
	L.Preview = preview

	-- Règles en bref (en bas)
	local rules = panel({
		Name = "Rules",
		Size = UDim2.new(1, -24, 0, 0),
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, 12, 1, -12),
		Color = Color3.fromRGB(28, 18, 58),
		Radius = 12,
		StrokeTransparency = 0.6,
		ZIndex = 6,
		Parent = setup,
	})
	rules.AutomaticSize = Enum.AutomaticSize.Y
	make("UIPadding", { PaddingLeft = UDim.new(0, 10), PaddingRight = UDim.new(0, 10), PaddingTop = UDim.new(0, 7), PaddingBottom = UDim.new(0, 7), Parent = rules })
	local rulesText = text({
		Text = T("🏆 Stakes in trophies, never sold\n🥇 Winner: both stakes + Dopamine + bonus 🎟️\n🏳️ Leaving or giving up = defeat"),
		Font = Theme.Fonts.Body,
		TextSize = 12,
		Color = C.TextDim,
		Wrapped = true,
		Size = UDim2.new(1, 0, 0, 0),
		ZIndex = 7,
		Parent = rules,
	})
	rulesText.AutomaticSize = Enum.AutomaticSize.Y
	rulesText.LineHeight = 1.1
	L.Rules = rules
	paintDuelSetup()
end

-- Ligne d'un joueur (ou d'une invitation reçue) dans la liste
local function playerRow(parent: Instance, info, order: number, mode: string, invite)
	local row = panel({
		Name = "Row" .. tostring(info.UserId),
		Size = UDim2.new(1, 0, 0, 58),
		Color = mode == "invite" and Color3.fromRGB(70, 30, 90) or C.Card,
		StrokeColor = mode == "invite" and C.Pink or C.Line,
		StrokeTransparency = mode == "invite" and 0.1 or 0.55,
		Radius = 14,
		LayoutOrder = order,
		ZIndex = 6,
		Parent = parent,
	})
	avatar(row, info.UserId or 0, 40, mode == "invite" and C.Pink or (info.Busy and C.Orange or C.Green), {
		AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 10, 0.5, 0), ZIndex = 7,
	})
	local name = tostring(info.Name or "?")
	if info.Badge and info.Badge ~= "" then
		name = info.Badge .. " " .. name
	end
	text({ Text = name, TextSize = 16, Size = UDim2.new(1, -200, 0, 20), Position = UDim2.fromOffset(60, 9), ZIndex = 7, Parent = row })
	local status, statusColor
	if mode == "invite" then
		local entry = ArcadeConfig.GamesById[invite.Game]
		status = string.format("%s %s • %s", entry and entry.Icon or "", gameName(invite.Game),
			invite.Stake > 0 and (tostring(invite.Stake) .. " " .. TROPHY) or T("Free"))
		statusColor = C.Yellow
	elseif info.Busy then
		status, statusColor = T("🟠 In a duel"), C.Orange
	elseif (info.PairLeft or 1) <= 0 then
		status, statusColor = T("💤 No more duels together today"), C.TextDim
	else
		status, statusColor = T("🟢 Ready to play"), C.Green
	end
	-- Trophées du joueur (pour choisir une mise qu'il peut payer)
	if mode ~= "invite" and type(info.Trophies) == "number" then
		status ..= "  •  " .. TROPHY .. " " .. NumberFormatter.Format(info.Trophies)
	end
	text({ Text = status, Font = Theme.Fonts.Body, TextSize = 13, Color = statusColor, Size = UDim2.new(1, -200, 0, 16),
		Position = UDim2.fromOffset(60, 31), ZIndex = 7, Parent = row })

	if mode == "invite" then
		local accept = neonButton({ Name = "Accept", Text = T("Accept"), Color = C.Green, Size = UDim2.fromOffset(82, 34),
			AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -96, 0.5, 0), TextSize = 14, ZIndex = 8, Parent = row })
		local decline = neonButton({ Name = "Decline", Text = T("No"), Color = Color3.fromRGB(110, 90, 150), Size = UDim2.fromOffset(74, 34),
			AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -12, 0.5, 0), TextSize = 14, ZIndex = 8, Parent = row })
		accept.Activated:Connect(function()
			Arcade.AcceptInvite(invite.Id)
		end)
		decline.Activated:Connect(function()
			Arcade.DeclineInvite(invite.Id)
		end)
	else
		local invited = S.Outgoing and S.Outgoing.To and S.Outgoing.To.UserId == info.UserId
		local canInvite = not info.Busy and (info.PairLeft or 1) > 0 and not (S.Duel and not S.Duel.Over)
		local button = neonButton({
			Name = "Challenge",
			Text = invited and T("Waiting...") or T("⚔️ Challenge"),
			Color = invited and C.Purple or C.Pink,
			Size = UDim2.fromOffset(130, 36),
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.new(1, -12, 0.5, 0),
			TextSize = 15,
			ZIndex = 8,
			Parent = row,
		})
		setButton(button, canInvite and not invited)
		button.Activated:Connect(function()
			if not button:GetAttribute("Enabled") or S.Busy then
				sound("Error", 0.8)
				UIUtil.Shake(button)
				return
			end
			-- Mise en 🏆 : vérifiée ici pour l'affichage, et par le serveur pour de vrai
			if S.Trophies < S.SelectedStake then
				UIUtil.Shake(button)
				needTrophies()
				return
			end
			if type(info.Trophies) == "number" and info.Trophies < S.SelectedStake then
				sound("Error", 0.8)
				UIUtil.Shake(button)
				toast(T("%s doesn't have enough trophies for this stake", tostring(info.Name or "?")), Theme.Colors.Orange, nil, TROPHY)
				return
			end
			S.Busy = true
			local ok, result = invoke("invite", { Target = info.UserId, Game = S.SelectedGame, Stake = S.SelectedStake })
			S.Busy = false
			if ok and type(result) == "table" then
				sound("Pop", 1.2)
				S.Outgoing = result.Invite
				if S.Outgoing then
					S.Outgoing.ReceivedAt = os.clock()
				end
				renderLobby()
			else
				sound("Error", 0.8)
				UIUtil.Shake(button)
				toast(tostring(result or T("Error")), Theme.Colors.Red)
			end
		end)
	end
	return row
end

local function buildDuelsPage(body: Frame)
	local page = make("Frame", { Name = "Duels", Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Visible = false, ZIndex = 5, Parent = body })
	S.Pages.Duels = page
	buildDuelSetup(page)
	local right = panel({
		Name = "Lobby",
		Size = UDim2.new(0.58, -6, 1, 0),
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, 0, 0, 0),
		Color = C.Panel,
		Radius = 16,
		ZIndex = 5,
		Parent = page,
	})
	L.Title = text({ Text = T("3. Challenge a player"), TextSize = 16, Size = UDim2.new(1, -120, 0, 22), Position = UDim2.fromOffset(12, 10), Parent = right })
	local refresh = neonButton({ Name = "Refresh", Text = T("↻ Refresh"), Color = C.Purple, Size = UDim2.fromOffset(100, 28),
		AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -12, 0, 7), TextSize = 13, ZIndex = 7, Parent = right })
	refresh.Activated:Connect(function()
		sound("Click", 1.1)
		refreshLobby(true)
	end)
	-- Invitation envoyée : bandeau d'attente
	local waiting = panel({
		Name = "Waiting",
		Size = UDim2.new(1, -24, 0, 44),
		Position = UDim2.fromOffset(12, 40),
		Color = Color3.fromRGB(58, 30, 100),
		StrokeColor = C.Purple,
		StrokeTransparency = 0.1,
		Radius = 12,
		ZIndex = 6,
		Parent = right,
	})
	waiting.Visible = false
	L.WaitingText = text({ Text = "", TextSize = 14, Size = UDim2.new(1, -110, 1, 0), Position = UDim2.fromOffset(12, 0), ZIndex = 7, Parent = waiting })
	local cancel = neonButton({ Name = "Cancel", Text = T("Cancel"), Color = Color3.fromRGB(120, 96, 170), Size = UDim2.fromOffset(84, 30),
		AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -8, 0.5, 0), TextSize = 13, ZIndex = 8, Parent = waiting })
	cancel.Activated:Connect(function()
		sound("Click", 0.9)
		invoke("cancel", nil)
		S.Outgoing = nil
		renderLobby()
	end)
	L.Waiting = waiting
	local list = make("ScrollingFrame", {
		Name = "Players",
		Size = UDim2.new(1, -16, 1, -48),
		Position = UDim2.fromOffset(12, 40),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 5,
		ScrollBarImageColor3 = C.Purple,
		ScrollingDirection = Enum.ScrollingDirection.Y,
		CanvasSize = UDim2.new(),
		ZIndex = 6,
		Parent = right,
	})
	make("UIListLayout", { Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder, Parent = list })
	make("UIPadding", { PaddingRight = UDim.new(0, 8), PaddingTop = UDim.new(0, 1), PaddingLeft = UDim.new(0, 1), Parent = list })
	L.List = list
	-- Personne : petit dessin
	local empty = make("Frame", { Name = "Empty", Size = UDim2.new(1, -24, 0, 170), AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 0.55, 0), BackgroundTransparency = 1, Visible = false, ZIndex = 6, Parent = right })
	local ufo = text({ Text = "🛸", TextSize = 56, Size = UDim2.new(1, 0, 0, 64), XAlign = Enum.TextXAlignment.Center, ZIndex = 7, Parent = empty })
	ufo.Rotation = -8
	text({ Text = T("Nobody to duel yet..."), TextSize = 18, Size = UDim2.new(1, 0, 0, 24), Position = UDim2.fromOffset(0, 72),
		XAlign = Enum.TextXAlignment.Center, ZIndex = 7, Parent = empty })
	text({ Text = T("Players who unlock the Arcade on this server appear here. Invite your friends!"), Font = Theme.Fonts.Body,
		TextSize = 14, Color = C.TextDim, Wrapped = true, Size = UDim2.new(1, -20, 0, 40), Position = UDim2.fromOffset(10, 100),
		XAlign = Enum.TextXAlignment.Center, YAlign = Enum.TextYAlignment.Top, ZIndex = 7, Parent = empty })
	L.Empty = empty
end

renderLobby = function()
	if not L.List then
		return
	end
	paintDuelSetup()
	for _, child in ipairs(L.List:GetChildren()) do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end
	local order = 0
	local total = 0
	-- Invitations reçues d'abord
	for _, id in ipairs(S.IncomingOrder) do
		local invite = S.Incoming[id]
		if invite then
			order += 1
			playerRow(L.List, invite.From, order, "invite", invite)
			total += 58 + 8
		end
	end
	local players = S.Lobby and S.Lobby.Players or {}
	for _, info in ipairs(players) do
		order += 1
		playerRow(L.List, info, order, "player", nil)
		total += 58 + 8
	end
	L.List.CanvasSize = UDim2.fromOffset(0, total + 4)
	L.Empty.Visible = order == 0
	-- Bandeau d'attente
	local outgoing = S.Outgoing
	L.Waiting.Visible = outgoing ~= nil
	L.List.Position = UDim2.fromOffset(12, outgoing and 92 or 40)
	L.List.Size = UDim2.new(1, -16, 1, outgoing and -100 or -48)
	L.Title.Text = T("3. Challenge a player") .. (#players > 0 and ("  (" .. #players .. ")") or "")
end

local function updateWaitingText()
	local outgoing = S.Outgoing
	if not outgoing or not L.WaitingText then
		return
	end
	local left = math.max(0, math.ceil((outgoing.Seconds or 0) - (os.clock() - (outgoing.ReceivedAt or os.clock()))))
	local to = outgoing.To and outgoing.To.Name or "?"
	L.WaitingText.Text = T("⏳ Waiting for %s... %ds", to, left)
end

refreshLobby = function(force: boolean?)
	if not force and os.clock() - S.LobbyAt < 1.5 then
		renderLobby()
		return
	end
	S.LobbyAt = os.clock()
	task.spawn(function()
		local ok, result = invoke("lobby", nil)
		if ok and type(result) == "table" then
			S.Lobby = result
			-- Invitations et duel : le serveur a le dernier mot
			S.Incoming = {}
			S.IncomingOrder = {}
			for _, invite in ipairs(result.Incoming or {}) do
				invite.ReceivedAt = os.clock()
				S.Incoming[invite.Id] = invite
				table.insert(S.IncomingOrder, invite.Id)
			end
			S.Outgoing = result.Outgoing
			if S.Outgoing then
				S.Outgoing.ReceivedAt = os.clock()
			end
			refreshTabBadge()
			if result.Duel and not (S.Active and S.Active.IsDuel) and S.Visible and S.Tab == "Duels" then
				showDuel(result.Duel)
			elseif not result.Duel and S.Duel and not S.Duel.Over then
				S.Duel = nil
			end
		end
		renderLobby()
	end)
end

----------------------------------------------------------------------
-- Boutique à tickets
----------------------------------------------------------------------

local shopCards = {} -- [id] = { Button, Item, Count }

local function shopState(item): (string, boolean, Color3)
	local arcade = arcadeData()
	if item.Kind == "Badge" then
		local owned = arcade.Badges and arcade.Badges[item.Id]
		if owned then
			if arcade.Badge == item.Id then
				return T("✓ Equipped"), false, C.Green
			end
			return T("Equip"), true, C.Cyan
		end
	elseif item.MaxPerDay then
		local bought = arcade.DayShop and arcade.DayShop[item.Id] or 0
		if bought >= item.MaxPerDay then
			return T("Sold out today"), false, Color3.fromRGB(110, 96, 150)
		end
	end
	return tostring(item.Price) .. " " .. TICKET, S.Tickets >= item.Price, C.Yellow
end

local function refreshShop()
	local arcade = arcadeData()
	for _, info in pairs(shopCards) do
		local label, enabled, color = shopState(info.Item)
		info.Button:SetAttribute("BaseColor", color)
		setButton(info.Button, enabled, label)
		info.Button.TextColor3 = Theme.Luminance(color) > 0.6 and Color3.fromRGB(50, 24, 60) or WHITE
		if info.Count then
			local item = info.Item
			local bought = arcade.DayShop and arcade.DayShop[item.Id] or 0
			info.Count.Text = T("%s left today", tostring(math.max(0, item.MaxPerDay - bought)))
		end
	end
end

local function buildShopCard(parent: Instance, item, order: number)
	local isBadge = item.Kind == "Badge"
	local tint = isBadge and C.Purple or (item.Kind == "Boost" and C.Orange or C.Pink)
	local card = panel({
		Name = item.Id,
		Color = C.Card,
		StrokeColor = tint,
		StrokeTransparency = 0.4,
		Radius = 16,
		LayoutOrder = order,
		ZIndex = 6,
		Parent = parent,
	})
	card.BackgroundColor3 = WHITE
	UIUtil.Gradient(card, ColorSequence.new(tint:Lerp(C.Card, 0.72), C.Card), 90)
	local halo = make("Frame", {
		Size = UDim2.fromOffset(62, 62),
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 12),
		BackgroundColor3 = tint,
		BackgroundTransparency = 0.25,
		ZIndex = 7,
		Parent = card,
	})
	UIUtil.Corner(halo, UDim.new(1, 0))
	UIUtil.Stroke(halo, tint:Lerp(WHITE, 0.5), 2, 0.1)
	halo.BackgroundColor3 = WHITE
	UIUtil.Gradient(halo, ColorSequence.new(tint:Lerp(WHITE, 0.35), tint:Lerp(BLACK, 0.1)), 90)
	text({ Text = item.Icon, TextSize = 34, Size = UDim2.fromScale(1, 1), XAlign = Enum.TextXAlignment.Center, ZIndex = 8, Parent = halo })
	text({ Text = T(item.Name), TextSize = 15, Size = UDim2.new(1, -16, 0, 20), Position = UDim2.fromOffset(8, 80),
		XAlign = Enum.TextXAlignment.Center, ZIndex = 7, Parent = card })
	text({ Text = T(item.Description), Font = Theme.Fonts.Body, TextSize = 12, Color = C.TextDim, Wrapped = true,
		YAlign = Enum.TextYAlignment.Top, Size = UDim2.new(1, -16, 0, 30), Position = UDim2.fromOffset(8, 101),
		XAlign = Enum.TextXAlignment.Center, ZIndex = 7, Parent = card })
	local count
	if item.MaxPerDay then
		count = text({ Name = "Count", Text = "", Font = Theme.Fonts.Body, TextSize = 11, Color = C.TextDim,
			Size = UDim2.new(1, -16, 0, 14), AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 8, 1, -44),
			XAlign = Enum.TextXAlignment.Center, ZIndex = 7, Parent = card })
	end
	local button = neonButton({
		Name = "Buy",
		Text = tostring(item.Price) .. " " .. TICKET,
		Color = C.Yellow,
		Size = UDim2.new(1, -20, 0, 32),
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -9),
		TextSize = 15,
		ZIndex = 8,
		Parent = card,
	})
	button.Activated:Connect(function()
		if S.Busy then
			return
		end
		local arcade = arcadeData()
		local owned = isBadge and arcade.Badges and arcade.Badges[item.Id]
		local soldOut = item.MaxPerDay ~= nil and ((arcade.DayShop and arcade.DayShop[item.Id]) or 0) >= item.MaxPerDay
		if not owned and not soldOut and S.Tickets < item.Price then
			-- Pas assez de tickets : on propose d'en avoir (À CHAQUE fois)
			UIUtil.Shake(card)
			needTickets(item.Price - S.Tickets, T(item.Name))
			return
		end
		if not button:GetAttribute("Enabled") then
			sound("Error", 0.8)
			UIUtil.Shake(card)
			return
		end
		S.Busy = true
		local ok, result
		if owned then
			ok, result = invoke("badge", item.Id)
		else
			ok, result = invoke("buy", item.Id)
		end
		S.Busy = false
		if ok then
			sound(owned and "Click" or "Buy", 1)
			if not owned then
				Effects.Burst(card, UDim2.fromScale(0.5, 0.3), tint, 14)
			end
			local message = type(result) == "table" and result.Text or result
			toast(tostring(message or T("Done!")), Theme.Colors.Green, nil, item.Icon)
		elseif type(result) == "table" and tonumber(result.Missing) then
			-- Refus du serveur faute de tickets (solde pas encore à jour ici)
			UIUtil.Shake(card)
			needTickets(tonumber(result.Missing) or 1, T(item.Name))
		else
			sound("Error", 0.8)
			UIUtil.Shake(card)
			local message = type(result) == "table" and result.Text or result
			toast(tostring(message or T("Error")), Theme.Colors.Red)
		end
	end)
	shopCards[item.Id] = { Button = button, Item = item, Count = count }
end

local function buildShopPage(body: Frame)
	local scroll, list = scrollPage(body, "Shop")
	S.Pages.Shop = scroll
	-- Bandeau d'explication : d'où viennent les tickets (+ bouton pour en acheter)
	local banner = panel({
		Name = "Banner",
		Size = UDim2.new(1, 0, 0, 56),
		Color = Color3.fromRGB(70, 40, 30),
		StrokeColor = C.Yellow,
		StrokeTransparency = 0.3,
		Radius = 14,
		LayoutOrder = 1,
		ZIndex = 6,
		Parent = scroll,
	})
	banner.BackgroundColor3 = WHITE
	UIUtil.Gradient(banner, ColorSequence.new(Color3.fromRGB(120, 66, 30), Color3.fromRGB(80, 34, 104)), 0)
	text({ Text = TICKET, TextSize = 30, Size = UDim2.fromOffset(44, 44), Position = UDim2.fromOffset(10, 6),
		XAlign = Enum.TextXAlignment.Center, ZIndex = 7, Parent = banner })
	text({ Text = T("Arcade-exclusive rewards"), TextSize = 16, Color = C.Yellow, Size = UDim2.new(1, -230, 0, 20),
		Position = UDim2.fromOffset(60, 8), ZIndex = 7, Parent = banner })
	local bannerText = text({ Text = T("Win tickets by playing, or get more in the 💎 shop. Duels use 🏆 trophies instead."),
		Font = Theme.Fonts.Body, TextSize = 13, Color = Color3.fromRGB(255, 232, 190), Size = UDim2.new(1, -230, 0, 18),
		Position = UDim2.fromOffset(60, 29), ZIndex = 7, Parent = banner })
	-- (traduction plus longue : le texte rétrécit un peu au lieu d'être coupé)
	bannerText.TextScaled = true
	make("UITextSizeConstraint", { MaxTextSize = 13, MinTextSize = 9, Parent = bannerText })
	local getTickets = neonButton({ Name = "GetTickets", Text = T("🎟️ Get tickets"), Color = C.Yellow, Size = UDim2.fromOffset(156, 36),
		AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -12, 0.5, 0), TextSize = 15, ZIndex = 8, Parent = banner })
	getTickets.Activated:Connect(function()
		sound("Click", 1.2)
		openTicketShop()
	end)

	local treats, badges = {}, {}
	for _, item in ipairs(ArcadeConfig.Shop) do
		table.insert(item.Kind == "Badge" and badges or treats, item)
	end
	sectionTitle(scroll, T("Treats"), C.Pink, 2, T("Instant Dopamine and short boosts"))
	local treatGrid = cardGrid(scroll, #treats, 4, 196, 3, "Treats")
	for index, item in ipairs(treats) do
		buildShopCard(treatGrid, item, index)
	end
	sectionTitle(scroll, T("Arcade badges"), C.Purple, 4, T("Shown next to your name in duels"))
	local badgeGrid = cardGrid(scroll, #badges, 4, 196, 5, "Badges")
	for index, item in ipairs(badges) do
		buildShopCard(badgeGrid, item, index)
	end
	fitCanvas(scroll, list)
end

renderShop = function()
	refreshShop()
end

----------------------------------------------------------------------
-- Records
----------------------------------------------------------------------

local R: any = {}

local function statTile(parent: Instance, icon: string, label: string, color: Color3, order: number)
	local tile = panel({ Name = "Stat", Color = C.Card, StrokeColor = color, StrokeTransparency = 0.45, Radius = 14, LayoutOrder = order, ZIndex = 6, Parent = parent })
	tile.BackgroundColor3 = WHITE
	UIUtil.Gradient(tile, ColorSequence.new(color:Lerp(C.Card, 0.7), C.Card), 0)
	text({ Text = icon, TextSize = 26, Size = UDim2.fromOffset(40, 40), AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 8, 0.5, 0),
		XAlign = Enum.TextXAlignment.Center, ZIndex = 7, Parent = tile })
	local value = text({ Name = "Value", Text = "0", Font = Theme.Fonts.Number, TextSize = 22, Color = color:Lerp(WHITE, 0.3),
		Size = UDim2.new(1, -58, 0, 24), Position = UDim2.fromOffset(52, 8), ZIndex = 7, Parent = tile })
	text({ Text = label, Font = Theme.Fonts.Body, TextSize = 12, Color = C.TextDim, Size = UDim2.new(1, -58, 0, 16),
		Position = UDim2.fromOffset(52, 33), ZIndex = 7, Parent = tile })
	return value
end

local function buildRecordsPage(body: Frame)
	local page = make("Frame", { Name = "Records", Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Visible = false, ZIndex = 5, Parent = body })
	S.Pages.Records = page
	local stats = make("Frame", { Name = "Stats", Size = UDim2.new(1, 0, 0, 60), BackgroundTransparency = 1, ZIndex = 5, Parent = page })
	-- (5 tuiles : -9 px chacune pour que la 5e ne passe jamais à la ligne)
	make("UIGridLayout", { CellSize = UDim2.new(0.2, -9, 1, 0), CellPadding = UDim2.fromOffset(10, 0), SortOrder = Enum.SortOrder.LayoutOrder, Parent = stats })
	R.Earned = statTile(stats, TICKET, T("Tickets earned"), C.Yellow, 1)
	R.Trophies = statTile(stats, TROPHY, T("Trophies earned"), C.Cyan, 2)
	R.Duels = statTile(stats, "⚔️", T("Duels won"), C.Pink, 3)
	R.Won = statTile(stats, "🥇", T("Games won"), C.Green, 4)
	R.Played = statTile(stats, "🎮", T("Games played"), C.Purple, 5)

	local left = panel({ Name = "Best", Size = UDim2.new(0.5, -5, 1, -70), Position = UDim2.fromOffset(0, 70), Color = C.Panel, Radius = 16, ZIndex = 5, Parent = page })
	text({ Text = T("🏅 Best scores"), TextSize = 16, Size = UDim2.new(1, -24, 0, 22), Position = UDim2.fromOffset(12, 8), Parent = left })
	local bestList = make("ScrollingFrame", { Name = "List", Size = UDim2.new(1, -16, 1, -40), Position = UDim2.fromOffset(12, 34),
		BackgroundTransparency = 1, BorderSizePixel = 0, ScrollBarThickness = 4, ScrollBarImageColor3 = C.Purple, CanvasSize = UDim2.new(), ZIndex = 6, Parent = left })
	make("UIListLayout", { Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder, Parent = bestList })
	make("UIPadding", { PaddingRight = UDim.new(0, 6), Parent = bestList })
	R.Best = bestList

	local right = panel({ Name = "History", Size = UDim2.new(0.5, -5, 1, -70), AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, 0, 0, 70),
		Color = C.Panel, Radius = 16, ZIndex = 5, Parent = page })
	text({ Text = T("⚔️ Recent duels"), TextSize = 16, Size = UDim2.new(1, -24, 0, 22), Position = UDim2.fromOffset(12, 8), Parent = right })
	local historyList = make("ScrollingFrame", { Name = "List", Size = UDim2.new(1, -16, 1, -40), Position = UDim2.fromOffset(12, 34),
		BackgroundTransparency = 1, BorderSizePixel = 0, ScrollBarThickness = 4, ScrollBarImageColor3 = C.Purple, CanvasSize = UDim2.new(), ZIndex = 6, Parent = right })
	make("UIListLayout", { Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder, Parent = historyList })
	make("UIPadding", { PaddingRight = UDim.new(0, 6), Parent = historyList })
	R.History = historyList
end

local function clearList(frame: Instance)
	for _, child in ipairs(frame:GetChildren()) do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end
end

renderRecords = function()
	if not R.Best then
		return
	end
	local data = ClientState.Data or {}
	local stats = data.Stats or {}
	local arcade = arcadeData()
	R.Earned.Text = NumberFormatter.Format(arcade.TicketsEarned or 0)
	R.Trophies.Text = NumberFormatter.Format(arcade.TrophiesEarned or 0)
	R.Duels.Text = NumberFormatter.Format(stats.DuelsWon or 0)
	R.Won.Text = NumberFormatter.Format(stats.MinigamesWon or 0)
	R.Played.Text = NumberFormatter.Format(stats.MinigamesPlayed or 0)

	clearList(R.Best)
	local height = 0
	for index, entry in ipairs(ArcadeConfig.Games) do
		local row = panel({ Name = entry.Id, Size = UDim2.new(1, 0, 0, 40), Color = C.Card, StrokeTransparency = 0.7, Radius = 10, LayoutOrder = index, ZIndex = 7, Parent = R.Best })
		local dot = make("Frame", { Size = UDim2.fromOffset(30, 30), AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 6, 0.5, 0),
			BackgroundColor3 = entry.Color, ZIndex = 8, Parent = row })
		UIUtil.Corner(dot, 9)
		text({ Text = entry.Icon, TextSize = 17, Size = UDim2.fromScale(1, 1), XAlign = Enum.TextXAlignment.Center, ZIndex = 9, Parent = dot })
		text({ Text = T(entry.Name), TextSize = 14, Size = UDim2.new(0.55, -44, 1, 0), Position = UDim2.fromOffset(44, 0), ZIndex = 8, Parent = row })
		local value
		if entry.Kind == "Duel" then
			local w = arcade.Wins and arcade.Wins[entry.Id] or 0
			local l = arcade.Losses and arcade.Losses[entry.Id] or 0
			local d = arcade.Draws and arcade.Draws[entry.Id] or 0
			value = T("%sW %sL %sD", tostring(w), tostring(l), tostring(d))
		else
			value = recordText(entry) or "—"
		end
		text({ Text = value, Font = Theme.Fonts.Number, TextSize = 15, Color = C.Yellow, XAlign = Enum.TextXAlignment.Right,
			Size = UDim2.new(0.45, -10, 1, 0), AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -10, 0, 0), ZIndex = 8, Parent = row })
		height += 46
	end
	R.Best.CanvasSize = UDim2.fromOffset(0, height)

	clearList(R.History)
	local history = arcade.History or {}
	height = 0
	for index, item in ipairs(history) do
		local outcome = item.R == "W" and C.Green or (item.R == "L" and C.Red or C.TextDim)
		local row = panel({ Name = "Duel" .. index, Size = UDim2.new(1, 0, 0, 40), Color = C.Card, StrokeColor = outcome, StrokeTransparency = 0.6, Radius = 10,
			LayoutOrder = index, ZIndex = 7, Parent = R.History })
		local tag = chip(row, item.R == "W" and T("WIN") or (item.R == "L" and T("LOSS") or T("DRAW")), outcome, {
			AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 7, 0.5, 0), Height = 22, TextSize = 12, Transparency = 0, ZIndex = 8,
		})
		tag.Size = UDim2.fromOffset(58, 22)
		tag.AutomaticSize = Enum.AutomaticSize.None
		local entry = ArcadeConfig.GamesById[item.G]
		text({ Text = string.format("%s %s", entry and entry.Icon or "", T("vs %s", tostring(item.O or "?"))), TextSize = 14,
			Size = UDim2.new(1, -150, 1, 0), Position = UDim2.fromOffset(74, 0), ZIndex = 8, Parent = row })
		local stake = tonumber(item.S) or 0
		local delta = item.R == "W" and ("+" .. stake) or (item.R == "L" and ("-" .. stake) or "±0")
		-- K = "T" : mise en 🏆 trophées ; sans K : ancien duel, misé en tickets
		local unit = item.K == "T" and TROPHY or TICKET
		text({ Text = stake > 0 and (delta .. " " .. unit) or T("Free"), Font = Theme.Fonts.Number, TextSize = 14, Color = outcome,
			XAlign = Enum.TextXAlignment.Right, Size = UDim2.fromOffset(80, 40), AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -10, 0, 0), ZIndex = 8, Parent = row })
		height += 46
	end
	if #history == 0 then
		text({ Text = T("No duels yet. Go challenge someone!"), Font = Theme.Fonts.Body, TextSize = 14, Color = C.TextDim, Wrapped = true,
			XAlign = Enum.TextXAlignment.Center, Size = UDim2.new(1, 0, 0, 60), ZIndex = 7, Parent = R.History })
	end
	R.History.CanvasSize = UDim2.fromOffset(0, height)
end

----------------------------------------------------------------------
-- Zone de jeu (solo ou duel)
----------------------------------------------------------------------

local G: any = {} -- éléments de la vue de jeu

local function buildGameView(root: Frame)
	local view = make("Frame", { Name = "GameView", Size = UDim2.new(1, -24, 1, -20), Position = UDim2.fromOffset(12, 10),
		BackgroundTransparency = 1, Visible = false, ZIndex = 20, Parent = root })
	G.View = view
	-- Barre du haut : retour | titre (solo) ou bandeau VS (duel) | abandon
	local back = neonButton({ Name = "Back", Text = T("← Back"), Color = C.Purple, Size = UDim2.fromOffset(96, 40), TextSize = 15, ZIndex = 22, Parent = view })
	back.Activated:Connect(function()
		sound("Click", 0.95)
		local running = S.Active and S.Active.IsDuel and S.Duel and not S.Duel.Over
		closeGame()
		if running then
			-- Le duel continue : il revient dès qu'on rouvre l'onglet Duels
			toast(T("Your duel is still running!"), Theme.Colors.Orange, nil, "⚔️")
			selectTab("Games")
		end
	end)
	G.Back = back
	local forfeit = neonButton({ Name = "Forfeit", Text = T("🏳️ Give up"), Color = Color3.fromRGB(150, 60, 90), Size = UDim2.fromOffset(122, 40),
		AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, 0, 0, 0), TextSize = 14, ZIndex = 22, Parent = view })
	local confirmUntil = 0
	forfeit.Activated:Connect(function()
		local duel = S.Duel
		if not duel or duel.Over then
			return
		end
		if os.clock() > confirmUntil then
			confirmUntil = os.clock() + 2.5
			forfeit.Text = T("Sure?")
			sound("Error", 1.2)
			task.delay(2.5, function()
				if os.clock() >= confirmUntil then
					forfeit.Text = T("🏳️ Give up")
				end
			end)
			return
		end
		confirmUntil = 0
		forfeit.Text = T("🏳️ Give up")
		invoke("forfeit", duel.Id)
	end)
	G.Forfeit = forfeit

	-- Titre (solo)
	local title = make("Frame", { Name = "SoloTitle", Size = UDim2.new(1, -240, 0, 40), Position = UDim2.fromOffset(108, 0), BackgroundTransparency = 1, ZIndex = 21, Parent = view })
	G.TitleIcon = text({ Text = "", TextSize = 26, Size = UDim2.fromOffset(40, 40), XAlign = Enum.TextXAlignment.Center, ZIndex = 22, Parent = title })
	G.TitleName = text({ Text = "", TextSize = 20, Size = UDim2.new(1, -48, 0, 24), Position = UDim2.fromOffset(44, 0), ZIndex = 22, Parent = title })
	G.TitleSub = text({ Text = "", Font = Theme.Fonts.Body, TextSize = 13, Color = C.TextDim, Size = UDim2.new(1, -48, 0, 16), Position = UDim2.fromOffset(44, 23), ZIndex = 22, Parent = title })
	G.SoloTitle = title

	-- Bandeau VS (duel) : carte joueur | pot + temps | carte adversaire
	local strip = make("Frame", { Name = "VersusStrip", Size = UDim2.new(1, -246, 0, 52), Position = UDim2.fromOffset(106, -6), BackgroundTransparency = 1, ZIndex = 21, Parent = view })
	G.Strip = strip
	G.Cards = {}
	for side = 1, 2 do
		local card = panel({
			Name = side == 1 and "Me" or "Them",
			Size = UDim2.new(0.5, -62, 1, 0),
			AnchorPoint = Vector2.new(side == 1 and 0 or 1, 0),
			Position = UDim2.new(side == 1 and 0 or 1, 0, 0, 0),
			Color = C.Card,
			Radius = 14,
			ZIndex = 22,
			Parent = strip,
		})
		local av = avatar(card, 0, 36, WHITE, {
			AnchorPoint = Vector2.new(side == 1 and 0 or 1, 0.5),
			Position = side == 1 and UDim2.new(0, 8, 0.5, 0) or UDim2.new(1, -8, 0.5, 0),
			ZIndex = 23,
		})
		local align = side == 1 and Enum.TextXAlignment.Left or Enum.TextXAlignment.Right
		local name = text({ Text = "", TextSize = 15, XAlign = align, Size = UDim2.new(1, -104, 0, 19),
			Position = side == 1 and UDim2.fromOffset(52, 7) or UDim2.new(0, 52, 0, 7), ZIndex = 23, Parent = card })
		if side == 2 then
			name.Position = UDim2.fromOffset(52, 7)
		end
		local status = text({ Text = "", Font = Theme.Fonts.Body, TextSize = 12, Color = C.TextDim, XAlign = align,
			Size = UDim2.new(1, -104, 0, 15), Position = UDim2.fromOffset(52, 27), ZIndex = 23, Parent = card })
		if side == 1 then
			name.Position = UDim2.fromOffset(52, 7)
			status.Position = UDim2.fromOffset(52, 27)
		else
			name.Position = UDim2.fromOffset(52, 7)
			status.Position = UDim2.fromOffset(52, 27)
		end
		local score = text({ Text = "", Font = Theme.Fonts.Number, TextSize = 26, XAlign = Enum.TextXAlignment.Center,
			Size = UDim2.fromOffset(40, 40), AnchorPoint = Vector2.new(side == 1 and 1 or 0, 0.5),
			Position = side == 1 and UDim2.new(1, -6, 0.5, 0) or UDim2.new(0, 6, 0.5, 0), ZIndex = 23, Parent = card })
		if side == 2 then
			name.Position = UDim2.fromOffset(50, 7)
			name.Size = UDim2.new(1, -104, 0, 19)
			status.Position = UDim2.fromOffset(50, 27)
		end
		local timer = make("Frame", { Name = "Timer", Size = UDim2.new(1, -28, 0, 3), AnchorPoint = Vector2.new(0.5, 1),
			Position = UDim2.new(0.5, 0, 1, -2), BackgroundColor3 = WHITE, BorderSizePixel = 0, ZIndex = 24, Visible = false, Parent = card })
		UIUtil.Corner(timer, 2)
		G.Cards[side] = { Card = card, Avatar = av, Name = name, Status = status, Score = score, Timer = timer }
	end
	local center = panel({ Name = "Pot", Size = UDim2.fromOffset(112, 52), AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 0),
		Color = Color3.fromRGB(60, 30, 40), StrokeColor = C.Yellow, StrokeTransparency = 0.2, Radius = 14, ZIndex = 22, Parent = strip })
	center.BackgroundColor3 = WHITE
	UIUtil.Gradient(center, ColorSequence.new(Color3.fromRGB(110, 56, 40), Color3.fromRGB(64, 26, 86)), 90)
	G.Vs = text({ Text = "VS", Font = Theme.Fonts.Number, TextSize = 18, Color = C.Yellow, XAlign = Enum.TextXAlignment.Center,
		Size = UDim2.new(1, 0, 0, 22), Position = UDim2.fromOffset(0, 5), ZIndex = 23, Parent = center })
	G.Pot = text({ Text = "", TextSize = 13, Color = Color3.fromRGB(255, 232, 190), XAlign = Enum.TextXAlignment.Center,
		Size = UDim2.new(1, -6, 0, 16), Position = UDim2.fromOffset(3, 29), ZIndex = 23, Parent = center })

	-- Hôte du module de jeu
	local host = panel({ Name = "Host", Size = UDim2.new(1, 0, 1, -54), Position = UDim2.fromOffset(0, 54), Color = Color3.fromRGB(16, 10, 34),
		StrokeColor = C.Purple, StrokeTransparency = 0.25, StrokeThickness = 2, Radius = 18, Clip = true, ZIndex = 20, Parent = view })
	host.BackgroundColor3 = WHITE
	UIUtil.Gradient(host, ColorSequence.new(Color3.fromRGB(34, 18, 70), Color3.fromRGB(16, 9, 34)), 90)
	G.Host = host

	-- Écran de résultat du duel (au-dessus de la zone de jeu)
	local result = make("Frame", { Name = "Result", Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.fromRGB(10, 4, 24),
		BackgroundTransparency = 0.3, Visible = false, ZIndex = 60, Parent = host })
	UIUtil.Corner(result, 18)
	local card = panel({ Name = "Card", Size = UDim2.fromOffset(380, 250), AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5),
		Color = C.Panel, StrokeColor = C.Yellow, StrokeThickness = 2.5, StrokeTransparency = 0, Radius = 22, ZIndex = 61, Parent = result })
	G.ResultScale = make("UIScale", { Parent = card })
	G.ResultCard = card
	G.ResultRays = UIUtil.Rays(card, C.Yellow, 8, 300, UDim2.new(0.5, 0, 0, 44), 61)
	G.ResultIcon = text({ Text = "🏆", TextSize = 52, Size = UDim2.fromOffset(80, 70), AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 8),
		XAlign = Enum.TextXAlignment.Center, ZIndex = 63, Parent = card })
	G.ResultTitle = text({ Text = "", Font = Theme.Fonts.Number, TextSize = 30, XAlign = Enum.TextXAlignment.Center, Size = UDim2.new(1, -20, 0, 34),
		Position = UDim2.fromOffset(10, 78), ZIndex = 63, Parent = card })
	G.ResultReason = text({ Text = "", Font = Theme.Fonts.Body, TextSize = 14, Color = C.TextDim, XAlign = Enum.TextXAlignment.Center,
		Size = UDim2.new(1, -20, 0, 18), Position = UDim2.fromOffset(10, 112), ZIndex = 63, Parent = card })
	G.ResultGains = text({ Text = "", TextSize = 17, Color = C.Yellow, XAlign = Enum.TextXAlignment.Center, Wrapped = true,
		Size = UDim2.new(1, -20, 0, 44), Position = UDim2.fromOffset(10, 136), ZIndex = 63, Parent = card })
	local lobby = neonButton({ Name = "Lobby", Text = T("Back to lobby"), Color = C.Purple, Size = UDim2.new(0.5, -21, 0, 40),
		Position = UDim2.new(0, 14, 1, -54), TextSize = 15, ZIndex = 64, Parent = card })
	lobby.Activated:Connect(function()
		sound("Click", 1)
		closeGame()
		selectTab("Duels")
	end)
	G.Lobby = lobby
	local rematch = neonButton({ Name = "Rematch", Text = T("🔁 Rematch"), Color = C.Pink, Size = UDim2.new(0.5, -21, 0, 40),
		AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -14, 1, -54), TextSize = 15, ZIndex = 64, Parent = card })
	rematch.Activated:Connect(function()
		local duel = S.Duel
		if not duel or S.Busy then
			return
		end
		local other = duel.Players and duel.Players[3 - (duel.You or 1)]
		if not other then
			return
		end
		S.Busy = true
		local ok, response = invoke("invite", { Target = other.UserId, Game = duel.Game, Stake = duel.Stake })
		S.Busy = false
		if ok and type(response) == "table" then
			sound("Pop", 1.2)
			S.Outgoing = response.Invite
			if S.Outgoing then
				S.Outgoing.ReceivedAt = os.clock()
			end
			toast(tostring(response.Text or T("Invitation sent")), Theme.Colors.Purple, nil, "🔁")
			closeGame()
			selectTab("Duels")
		else
			sound("Error", 0.8)
			UIUtil.Shake(rematch)
			toast(tostring(response or T("Error")), Theme.Colors.Red)
		end
	end)
	G.Rematch = rematch
	G.Result = result
end

local function playerText(info): string
	if not info then
		return "?"
	end
	local name = tostring(info.Name or "?")
	if info.Badge and info.Badge ~= "" then
		return info.Badge .. " " .. name
	end
	return name
end

-- Bandeau VS : noms, scores, tour, temps
updateDuelStrip = function()
	local duel = S.Duel
	if not duel or not G.Cards then
		return
	end
	local you = duel.You or 1
	local entry = ArcadeConfig.GamesById[duel.Game] or {}
	local seats = { you, 3 - you } -- côté gauche = toi
	local turnBased = entry.TurnSeconds ~= nil
	local now = os.clock()
	for side = 1, 2 do
		local seat = seats[side]
		local info = duel.Players and duel.Players[seat]
		local card = G.Cards[side]
		local color = SEAT_COLORS[seat]
		card.Name.Text = side == 1 and (playerText(info) .. " " .. T("(you)")) or playerText(info)
		local stroke = card.Card:FindFirstChildOfClass("UIStroke")
		local active = turnBased and not duel.Over and duel.Turn == seat
		if stroke then
			stroke.Color = color
			stroke.Transparency = active and 0 or 0.55
			stroke.Thickness = active and 2.5 or 1.5
		end
		card.Card.BackgroundColor3 = active and color:Lerp(C.Card, 0.7) or C.Card
		local head = card.Avatar:FindFirstChild("Head") :: ImageLabel?
		if head and info then
			local url = UIUtil.HeadshotUrl(info.UserId or 0, 100)
			if head.Image ~= url then
				head.Image = url
			end
		end
		local ring = card.Avatar:FindFirstChildOfClass("UIStroke")
		if ring then
			ring.Color = color
		end
		if turnBased then
			card.Score.Text = seat == 1 and (duel.Game == "TicTacToe" and "✕" or "●") or (duel.Game == "TicTacToe" and "◯" or "●")
			card.Score.TextColor3 = color
			if duel.Over then
				card.Status.Text = duel.Winner == seat and T("🏆 Winner!") or (duel.Winner == 0 and T("🤝 Draw") or "")
			elseif duel.Turn == seat then
				local left = math.max(0, math.ceil((duel.TurnLeft or 0) - (now - (duel.ReceivedAt or now))))
				card.Status.Text = side == 1 and T("Your turn! %ds", left) or T("Thinking... %ds", left)
			else
				card.Status.Text = T("Waiting")
			end
			card.Timer.Visible = active
			card.Timer.BackgroundColor3 = color
			if active and entry.TurnSeconds then
				local left = math.max(0, (duel.TurnLeft or 0) - (now - (duel.ReceivedAt or now)))
				card.Timer.Size = UDim2.new(math.clamp(left / entry.TurnSeconds, 0, 1), -28, 0, 3)
			end
		else
			card.Score.Text = tostring(duel.Scores and duel.Scores[seat] or 0)
			card.Score.TextColor3 = color
			card.Timer.Visible = false
			if duel.Over then
				card.Status.Text = duel.Winner == seat and T("🏆 Winner!") or (duel.Winner == 0 and T("🤝 Draw") or "")
			else
				card.Status.Text = T("First to %d", entry.WinScore or 3)
			end
		end
	end
	G.Pot.Text = (duel.Pot or 0) > 0 and (T("Pot") .. " " .. tostring(duel.Pot) .. " " .. TROPHY) or T("Friendly")
	G.Forfeit.Visible = not duel.Over
end

-- Détruit le jeu affiché
local function destroyActive()
	local active = S.Active
	S.Active = nil
	if not active then
		return
	end
	for _, connection in ipairs(active.Listeners) do
		pcall(function()
			connection:Disconnect()
		end)
	end
	if active.Handle and type(active.Handle.Destroy) == "function" then
		local ok, err = pcall(active.Handle.Destroy)
		if not ok then
			warn("[Arcade] Destroy : " .. tostring(err))
		end
	end
	if active.Frame then
		active.Frame:Destroy()
	end
end

closeGame = function()
	destroyActive()
	if G.View then
		G.View.Visible = false
		G.Result.Visible = false
	end
	if S.Body then
		S.Body.Visible = true
	end
	if S.TopBar then
		S.TopBar.Visible = true
	end
	refreshTickets(false)
	refreshGameCards()
	if S.Tab == "Duels" then
		refreshLobby(true)
	elseif S.Tab == "Records" then
		renderRecords()
	end
end

-- "Bientôt disponible" (module absent ou en erreur)
local function placeholder(frame: Frame, entry, message: string)
	local box = make("Frame", { Size = UDim2.fromOffset(420, 200), AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5),
		BackgroundTransparency = 1, ZIndex = 25, Parent = frame })
	text({ Text = entry.Icon, TextSize = 64, Size = UDim2.new(1, 0, 0, 80), XAlign = Enum.TextXAlignment.Center, ZIndex = 26, Parent = box })
	text({ Text = message, TextSize = 20, Size = UDim2.new(1, 0, 0, 28), Position = UDim2.fromOffset(0, 90), XAlign = Enum.TextXAlignment.Center, ZIndex = 26, Parent = box })
	text({ Text = T("This machine is warming up. Try another game!"), Font = Theme.Fonts.Body, TextSize = 14, Color = C.TextDim,
		Size = UDim2.new(1, 0, 0, 20), Position = UDim2.fromOffset(0, 122), XAlign = Enum.TextXAlignment.Center, ZIndex = 26, Parent = box })
end

-- Ouvre un jeu (solo : duel = nil ; duel : état de départ)
openGame = function(entry, duel)
	destroyActive()
	S.Body.Visible = false
	S.TopBar.Visible = false
	G.View.Visible = true
	G.Result.Visible = false
	local isDuel = entry.Kind == "Duel"
	G.SoloTitle.Visible = not isDuel
	G.Strip.Visible = isDuel
	G.Forfeit.Visible = isDuel
	if not isDuel then
		G.TitleIcon.Text = entry.Icon
		G.TitleName.Text = T(entry.Name)
		local best = recordText(entry)
		G.TitleSub.Text = T(entry.Description) .. (best and ("  •  🏅 " .. best) or "")
	end

	local frame = make("Frame", { Name = "Game_" .. entry.Id, Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, ZIndex = 21, Parent = G.Host })
	local active = { Entry = entry, Frame = frame, Listeners = {}, IsDuel = isDuel, Handle = nil }
	S.Active = active

	local api = {
		Game = entry,
		T = Locale.T,
		Colors = API_COLORS,
		UserId = Players.LocalPlayer and Players.LocalPlayer.UserId or 0,
		Sounds = {
			Play = function(name: string, pitch: number?)
				sound(name, pitch)
			end,
		},
		Notify = function(message: string, color: Color3?)
			toast(tostring(message), color)
		end,
		Tickets = function(): number
			return S.Tickets
		end,
		Close = function()
			if S.Active == active then
				closeGame()
			end
		end,
		Invoke = function(action: string, arg: any): (boolean, any)
			if not isDuel and type(action) == "string" and string.sub(action, 1, 5) ~= "solo:" then
				action = "solo:" .. action
			end
			return invoke(action, arg)
		end,
		OnEvent = function(callback)
			local connection = eventSignal:Connect(function(kind, payload)
				local ok, err = pcall(callback, kind, payload)
				if not ok then
					warn("[Arcade] " .. entry.Id .. " OnEvent : " .. tostring(err))
				end
			end)
			table.insert(active.Listeners, connection)
			return connection
		end,
	}
	if isDuel and duel then
		api.Duel = duel
		api.Seat = duel.You
		api.Move = function(move: any): (boolean, any)
			local current = S.Duel
			if not current or current.Over then
				return false, nil
			end
			return invoke("move", { Id = current.Id, Move = move })
		end
		api.SeatColors = SEAT_COLORS
	end

	local folder = Client:FindFirstChild("Minigames")
	local moduleScript = folder and folder:FindFirstChild(ArcadeConfig.ModuleName(entry))
	if not moduleScript or not moduleScript:IsA("ModuleScript") then
		placeholder(frame, entry, T("Coming soon!"))
		return
	end
	local okRequire, module = pcall(require, moduleScript)
	if not okRequire or type(module) ~= "table" or type(module.Build) ~= "function" then
		warn("[Arcade] Module " .. moduleScript.Name .. " : " .. tostring(module))
		placeholder(frame, entry, T("Out of order"))
		return
	end
	local okBuild, handle = pcall(module.Build, frame, api)
	if not okBuild then
		warn("[Arcade] Build " .. moduleScript.Name .. " : " .. tostring(handle))
		frame:ClearAllChildren()
		placeholder(frame, entry, T("Out of order"))
		return
	end
	active.Handle = type(handle) == "table" and handle or nil
end

showDuel = function(duel)
	duel.ReceivedAt = os.clock()
	S.Duel = duel
	local entry = ArcadeConfig.GamesById[duel.Game]
	if not entry then
		return
	end
	if not (S.Active and S.Active.IsDuel) then
		openGame(entry, duel)
	end
	updateDuelStrip()
end

-- Écran de fin de duel
showResult = function(duel)
	local result = duel.Result or {}
	local outcome = result.Outcome or "Draw"
	local you = duel.You or 1
	local other = duel.Players and duel.Players[3 - you]
	local otherName = other and other.Name or "?"
	local color = outcome == "Win" and C.Yellow or (outcome == "Lose" and C.Red or C.Cyan)
	G.ResultIcon.Text = outcome == "Win" and "🏆" or (outcome == "Lose" and "💔" or "🤝")
	G.ResultTitle.Text = outcome == "Win" and T("VICTORY!") or (outcome == "Lose" and T("Defeat...") or T("Draw!"))
	G.ResultTitle.TextColor3 = color
	local reason = result.Reason or duel.Reason
	local reasonText = reason and REASONS[reason] and T(REASONS[reason]) or ""
	if reason == "timeout" or reason == "forfeit" or reason == "left" then
		local loserIsMe = outcome == "Lose"
		reasonText = (loserIsMe and T("You") or otherName) .. " • " .. reasonText
	end
	G.ResultReason.Text = reasonText
	local gains = {}
	-- Mise gagnée / perdue (🏆 trophées)
	local staked = tonumber(result.Trophies) or 0
	if staked > 0 then
		table.insert(gains, "+" .. tostring(staked) .. " " .. TROPHY)
	elseif staked < 0 then
		table.insert(gains, tostring(staked) .. " " .. TROPHY)
	end
	if (result.TrophyBonus or 0) > 0 then
		table.insert(gains, T("+%s %s bonus", tostring(result.TrophyBonus), TROPHY))
	end
	if (result.Bonus or 0) > 0 then
		table.insert(gains, T("+%s %s bonus", tostring(result.Bonus), TICKET))
	end
	if (result.Dopamine or 0) > 0 then
		table.insert(gains, "+" .. NumberFormatter.Format(result.Dopamine) .. " Dopamine")
	end
	if outcome == "Win" and not result.Rewarded then
		table.insert(gains, T("(daily prize limit reached with this player)"))
	end
	if outcome == "Draw" and (duel.Stake or 0) > 0 then
		table.insert(gains, T("Stakes refunded"))
	end
	G.ResultGains.Text = #gains > 0 and table.concat(gains, "  •  ") or T("Good game!")
	G.ResultGains.TextColor3 = outcome == "Lose" and C.TextDim or C.Yellow
	local stroke = G.ResultCard:FindFirstChildOfClass("UIStroke")
	if stroke then
		stroke.Color = color
	end
	G.ResultRays.Visible = outcome == "Win"
	local stillHere = other and Players:GetPlayerByUserId(other.UserId or 0) ~= nil
	G.Rematch.Visible = stillHere == true and result.Reason ~= "left"
	G.Lobby.AnchorPoint = G.Rematch.Visible and Vector2.zero or Vector2.new(0.5, 0)
	G.Lobby.Position = G.Rematch.Visible and UDim2.new(0, 14, 1, -54) or UDim2.new(0.5, 0, 1, -54)
	G.Result.Visible = true
	G.Result.BackgroundTransparency = 1
	UIUtil.Tween(G.Result, 0.3, { BackgroundTransparency = 0.3 })
	G.ResultScale.Scale = 0.6
	UIUtil.Tween(G.ResultScale, 0.45, { Scale = 1 }, Enum.EasingStyle.Back)
	if outcome == "Win" then
		sound("Achievement", 1.1)
		task.delay(0.15, sound, "Cash", 1.2)
		pcall(Effects.Confetti, 90)
	elseif outcome == "Lose" then
		sound("Error", 0.6)
	else
		sound("Pop", 0.9)
	end
end

----------------------------------------------------------------------
-- Invitation reçue : petite carte "défi" (même fenêtre fermée)
----------------------------------------------------------------------

local P: any = {} -- popup

local function buildInvitePopup()
	local layer = Interface.Layers and Interface.Layers.Toasts
	if not layer then
		return
	end
	local holder = make("Frame", { Name = "ArcadeInvite", Size = UDim2.fromOffset(400, 116), AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 34), BackgroundTransparency = 1, Visible = false, ZIndex = 50, Parent = layer })
	holder:SetAttribute("DarkSkinIgnore", true)
	P.Scale = make("UIScale", { Parent = holder })
	local card = panel({ Name = "Card", Color = C.Bg, StrokeColor = C.Pink, StrokeThickness = 2.5, StrokeTransparency = 0, Radius = 20, ZIndex = 51, Parent = holder })
	card.BackgroundColor3 = WHITE
	UIUtil.Gradient(card, ColorSequence.new(Color3.fromRGB(78, 26, 108), Color3.fromRGB(30, 16, 64)), 90)
	UIUtil.Shadow(card, 4, 0.7, 3)
	P.Avatar = avatar(card, 0, 52, C.Pink, { Position = UDim2.fromOffset(14, 12), ZIndex = 52 })
	local swords = text({ Text = "⚔️", TextSize = 20, Size = UDim2.fromOffset(26, 26), AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromOffset(62, 58), XAlign = Enum.TextXAlignment.Center, ZIndex = 54, Parent = card })
	swords.BackgroundTransparency = 0
	swords.BackgroundColor3 = C.Pink
	UIUtil.Corner(swords, UDim.new(1, 0))
	P.Title = text({ Text = "", TextSize = 17, Size = UDim2.new(1, -124, 0, 22), Position = UDim2.fromOffset(80, 10), ZIndex = 52, Parent = card })
	P.Info = text({ Text = "", Font = Theme.Fonts.Body, TextSize = 14, Color = C.Yellow, Size = UDim2.new(1, -94, 0, 18), Position = UDim2.fromOffset(80, 33), ZIndex = 52, Parent = card })
	P.Accept = neonButton({ Name = "Accept", Text = T("✓ Accept"), Color = C.Green, Size = UDim2.fromOffset(136, 36), Position = UDim2.fromOffset(80, 62), TextSize = 15, ZIndex = 53, Parent = card })
	P.Decline = neonButton({ Name = "Decline", Text = T("✕ No thanks"), Color = Color3.fromRGB(110, 90, 150), Size = UDim2.fromOffset(136, 36),
		Position = UDim2.fromOffset(224, 62), TextSize = 15, ZIndex = 53, Parent = card })
	P.Later = text({ Text = "", Font = Theme.Fonts.Body, TextSize = 12, Color = C.TextDim, XAlign = Enum.TextXAlignment.Right,
		Size = UDim2.fromOffset(40, 16), AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -14, 0, 14), ZIndex = 52, Parent = card })
	local track = make("Frame", { Size = UDim2.new(1, -36, 0, 4), AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -7),
		BackgroundColor3 = WHITE, BackgroundTransparency = 0.85, BorderSizePixel = 0, ZIndex = 52, Parent = card })
	UIUtil.Corner(track, 2)
	P.Bar = make("Frame", { Size = UDim2.fromScale(1, 1), BackgroundColor3 = C.Pink, BorderSizePixel = 0, ZIndex = 53, Parent = track })
	UIUtil.Corner(P.Bar, 2)
	P.Accept.Activated:Connect(function()
		if P.Id then
			Arcade.AcceptInvite(P.Id)
		end
	end)
	P.Decline.Activated:Connect(function()
		if P.Id then
			Arcade.DeclineInvite(P.Id)
		end
	end)
	P.Holder = holder
	local function applyDevice()
		P.Scale.Scale = Interface.IsPhone() and 0.9 or 1
	end
	Interface.DeviceChanged:Connect(applyDevice)
	applyDevice()
end

hideInvitePopup = function(id: string?)
	if not P.Holder or (id and P.Id ~= id) then
		return
	end
	P.Id = nil
	P.Token = (P.Token or 0) + 1
	local token = P.Token
	UIUtil.Tween(P.Scale, 0.18, { Scale = 0.7 * (Interface.IsPhone() and 0.9 or 1) }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
	task.delay(0.18, function()
		if P.Token == token then
			P.Holder.Visible = false
		end
	end)
	-- Une autre invitation attend ? on la montre
	task.delay(0.3, function()
		if P.Id == nil then
			for _, other in ipairs(S.IncomingOrder) do
				if S.Incoming[other] then
					showInvitePopup(S.Incoming[other])
					break
				end
			end
		end
	end)
end

showInvitePopup = function(invite)
	if not P.Holder or not invite then
		return
	end
	-- Déjà en duel : pas de carte, l'invitation reste dans l'onglet Duels
	if S.Duel and not S.Duel.Over then
		return
	end
	P.Id = invite.Id
	P.Token = (P.Token or 0) + 1
	local entry = ArcadeConfig.GamesById[invite.Game]
	local from = invite.From or {}
	P.Title.Text = T("%s challenges you!", playerText(from))
	P.Info.Text = string.format("%s %s  •  %s", entry and entry.Icon or "", gameName(invite.Game),
		(invite.Stake or 0) > 0 and T("%s %s each", tostring(invite.Stake), TROPHY) or T("Free duel"))
	local head = P.Avatar:FindFirstChild("Head") :: ImageLabel?
	if head then
		head.Image = UIUtil.HeadshotUrl(from.UserId or 0, 100)
	end
	local canPay = S.Trophies >= (invite.Stake or 0)
	setButton(P.Accept, canPay, canPay and T("✓ Accept") or T("Not enough 🏆"))
	local left = math.max(1, (invite.Seconds or 20) - (os.clock() - (invite.ReceivedAt or os.clock())))
	P.Bar.Size = UDim2.fromScale(math.clamp(left / (invite.Total or 30), 0, 1), 1)
	UIUtil.Tween(P.Bar, left, { Size = UDim2.fromScale(0, 1) }, Enum.EasingStyle.Linear)
	local count = 0
	for _ in pairs(S.Incoming) do
		count += 1
	end
	P.Later.Text = count > 1 and ("+" .. (count - 1)) or ""
	P.Holder.Visible = true
	local base = Interface.IsPhone() and 0.9 or 1
	P.Scale.Scale = 0.6 * base
	UIUtil.Tween(P.Scale, 0.4, { Scale = base }, Enum.EasingStyle.Back)
	local token = P.Token
	task.delay(left + 0.2, function()
		if P.Token == token and P.Id == invite.Id then
			hideInvitePopup(invite.Id)
		end
	end)
end

function Arcade.AcceptInvite(id: string)
	if S.Busy then
		return
	end
	local invite = S.Incoming[id]
	if invite and S.Trophies < (invite.Stake or 0) then
		needTrophies()
		return
	end
	S.Busy = true
	local ok, result = invoke("accept", id)
	S.Busy = false
	S.Incoming[id] = nil
	refreshTabBadge()
	hideInvitePopup(id)
	if ok and type(result) == "table" then
		sound("Pop", 1.3)
		if not PanelManager.IsOpen("Arcade") then
			PanelManager.Open("Arcade")
		end
		-- (l'événement duelStart est souvent arrivé avant : on ne remplace pas un état plus récent)
		if not (S.Duel and S.Duel.Id == result.Id) then
			showDuel(result)
		end
	else
		sound("Error", 0.8)
		toast(tostring(result or T("This invitation has expired")), Theme.Colors.Red)
		if S.Visible and S.Tab == "Duels" then
			refreshLobby(true)
		end
	end
end

function Arcade.DeclineInvite(id: string)
	sound("Click", 0.9)
	S.Incoming[id] = nil
	refreshTabBadge()
	hideInvitePopup(id)
	task.spawn(invoke, "decline", id)
	if S.Visible and S.Tab == "Duels" then
		renderLobby()
	end
end

----------------------------------------------------------------------
-- Événements du serveur (ArcadeEvent)
----------------------------------------------------------------------

local CLOSED_MESSAGES = {
	declined = "%s said no this time",
	expired = "Invitation to %s expired",
	left = "%s left the server",
	busy = "%s is busy in another duel",
	trophies = "%s doesn't have enough trophies anymore",
	limit = "You've dueled %s a lot today. Come back tomorrow!",
}

local function onArcadeEvent(kind: string, payload: any)
	if type(payload) ~= "table" then
		payload = {}
	end
	if kind == "invite" then
		payload.ReceivedAt = os.clock()
		if not S.Incoming[payload.Id] then
			table.insert(S.IncomingOrder, payload.Id)
		end
		S.Incoming[payload.Id] = payload
		refreshTabBadge()
		sound("Notif", 1.1)
		if not P.Id then
			showInvitePopup(payload)
		else
			P.Later.Text = "+" .. tostring(#S.IncomingOrder - 1)
		end
		if S.Visible and S.Tab == "Duels" and not S.Active then
			renderLobby()
		end
	elseif kind == "inviteClosed" then
		local id = payload.Id
		if S.Incoming[id] then
			S.Incoming[id] = nil
			refreshTabBadge()
			hideInvitePopup(id)
		end
		if S.Outgoing and S.Outgoing.Id == id then
			S.Outgoing = nil
			local message = CLOSED_MESSAGES[payload.Reason]
			if message then
				toast(T(message, tostring(payload.To or "?")), Theme.Colors.Orange, nil, "⚔️")
			end
		end
		if S.Visible and S.Tab == "Duels" and not S.Active then
			refreshLobby(false)
		end
	elseif kind == "duelStart" then
		S.Outgoing = nil
		hideInvitePopup(nil)
		sound("Rush", 1)
		if not PanelManager.IsOpen("Arcade") then
			PanelManager.Open("Arcade")
		end
		destroyActive()
		showDuel(payload)
		eventSignal:Fire(kind, payload)
	elseif kind == "duelUpdate" then
		if S.Duel and S.Duel.Id == payload.Id then
			payload.ReceivedAt = os.clock()
			S.Duel = payload
			updateDuelStrip()
		end
		eventSignal:Fire(kind, payload)
	elseif kind == "duelEnd" then
		payload.ReceivedAt = os.clock()
		S.Duel = payload
		updateDuelStrip()
		eventSignal:Fire(kind, payload)
		local result = payload.Result or {}
		if S.Visible and S.Active and S.Active.IsDuel then
			task.delay(0.9, function()
				if S.Duel == payload and S.Active and S.Active.IsDuel then
					showResult(payload)
				end
			end)
		else
			local outcome = result.Outcome
			toast(outcome == "Win" and T("You won the duel! +%s %s", tostring(math.max(0, tonumber(result.Trophies) or 0)), TROPHY)
				or (outcome == "Lose" and T("You lost the duel") or T("Duel ended in a draw")),
				outcome == "Win" and Theme.Colors.Gold or Theme.Colors.Purple, nil, "⚔️")
		end
	else
		eventSignal:Fire(kind, payload)
	end
end

----------------------------------------------------------------------
-- Construction / cycle de vie du panneau
----------------------------------------------------------------------

selectTab = function(id: string)
	S.Tab = id
	paintTabs()
	for name, page in pairs(S.Pages) do
		page.Visible = name == id
	end
	if id == "Duels" then
		refreshLobby(false)
	elseif id == "Shop" then
		renderShop()
	elseif id == "Records" then
		renderRecords()
	elseif id == "Games" then
		refreshGameCards()
	end
end

-- Ouvre un onglet de l'arcade ("Games" | "Duels" | "Shop" | "Records"),
-- ex. "Shop" depuis l'onglet 🎟️ Tickets de la boutique Robux
function Arcade.ShowTab(id: string)
	if S.Pages[id] == nil or S.Active then
		return
	end
	selectTab(id)
end

function Arcade.GetSize(): Vector2
	local canvas = Interface.CanvasSize
	local width = math.min(900, math.floor(canvas.X * 0.94))
	local height = math.min(600, math.floor(canvas.Y * 0.94))
	return Vector2.new(width, height)
end

function Arcade.Build(content: Frame)
	content:SetAttribute("DarkSkinIgnore", true)
	local root = panel({
		Name = "ArcadeRoot",
		Color = C.Bg,
		StrokeColor = C.Pink,
		StrokeThickness = 2,
		StrokeTransparency = 0.2,
		Radius = 18,
		Clip = true,
		ZIndex = 4,
		Parent = content,
	})
	root:SetAttribute("DarkSkinIgnore", true)
	root.BackgroundColor3 = WHITE
	UIUtil.Gradient(root, ColorSequence.new({
		ColorSequenceKeypoint.new(0, C.Bg2),
		ColorSequenceKeypoint.new(0.55, C.Bg),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(16, 10, 36)),
	}), 90)
	local rootStroke = root:FindFirstChildOfClass("UIStroke")
	if rootStroke then
		make("UIGradient", { Color = ColorSequence.new(C.Pink, C.Cyan), Rotation = 20, Parent = rootStroke })
	end
	-- Décor : grille rétro en bas + petites étoiles (statiques, gratuites)
	local floor = make("Frame", { Name = "Grid", Size = UDim2.new(1, 0, 0, 120), AnchorPoint = Vector2.new(0, 1), Position = UDim2.fromScale(0, 1),
		BackgroundTransparency = 1, ZIndex = 4, Parent = root })
	for index = 1, 4 do
		make("Frame", { Size = UDim2.new(1, 0, 0, 1), Position = UDim2.new(0, 0, 1, -index * index * 7), BackgroundColor3 = C.Pink,
			BackgroundTransparency = 0.78 + index * 0.04, BorderSizePixel = 0, ZIndex = 4, Parent = floor })
	end
	local stars = { { 0.08, 0.2 }, { 0.3, 0.12 }, { 0.62, 0.18 }, { 0.9, 0.3 }, { 0.46, 0.4 }, { 0.18, 0.6 }, { 0.78, 0.66 } }
	for _, spec in ipairs(stars) do
		local star = make("Frame", { Size = UDim2.fromOffset(3, 3), Position = UDim2.fromScale(spec[1], spec[2]), BackgroundColor3 = WHITE,
			BackgroundTransparency = 0.55, BorderSizePixel = 0, ZIndex = 4, Parent = root })
		UIUtil.Corner(star, UDim.new(1, 0))
	end
	S.Root = root

	buildHeader(root)
	S.TopBar = root:FindFirstChild("TopBar")
	local body = make("Frame", { Name = "Body", Size = UDim2.new(1, -24, 1, -72), Position = UDim2.fromOffset(12, 62), BackgroundTransparency = 1, ZIndex = 5, Parent = root })
	S.Body = body
	buildGamesPage(body)
	buildDuelsPage(body)
	buildShopPage(body)
	buildRecordsPage(body)
	buildGameView(root)
	buildInvitePopup()
	selectTab("Games")
	refreshTickets(false)
	refreshGameCards()

	-- Remotes
	task.spawn(function()
		local ok, remote = pcall(Net.Function, "Arcade")
		if ok then
			arcadeRemote = remote
		end
		local okEvent, event = pcall(Net.Event, "ArcadeEvent")
		if okEvent and event then
			event.OnClientEvent:Connect(function(kind, payload)
				local okHandle, err = pcall(onArcadeEvent, kind, payload)
				if not okHandle then
					warn("[Arcade] ArcadeEvent " .. tostring(kind) .. " : " .. tostring(err))
				end
			end)
		end
	end)

	-- Horloge légère (5 fois / s) : temps du duel, attente d'une invitation — seulement fenêtre ouverte
	RunService.Heartbeat:Connect(function(dt)
		if not S.Visible then
			return
		end
		S.LoopAccumulator += dt
		if S.LoopAccumulator < 0.2 then
			return
		end
		S.LoopAccumulator = 0
		if S.Active and S.Active.IsDuel and S.Duel and not S.Duel.Over then
			updateDuelStrip()
		end
		if S.Outgoing and not S.Active and S.Tab == "Duels" then
			updateWaitingText()
		end
	end)
	-- Rafraîchit le lobby régulièrement quand l'onglet Duels est affiché
	task.spawn(function()
		while true do
			task.wait(6)
			if S.Visible and S.Tab == "Duels" and not S.Active then
				refreshLobby(true)
			end
		end
	end)
end

function Arcade.Update(_data)
	refreshTickets(true)
	if not S.Visible then
		return
	end
	if S.Active then
		return
	end
	if S.Tab == "Games" then
		refreshGameCards()
	elseif S.Tab == "Shop" then
		refreshShop()
	elseif S.Tab == "Records" then
		renderRecords()
	elseif S.Tab == "Duels" then
		paintDuelSetup()
	end
end

function Arcade.OnOpen()
	S.Visible = true
	refreshTickets(false)
	-- Un duel est en cours : on le remontre
	if S.Duel and not S.Duel.Over and not S.Active then
		local entry = ArcadeConfig.GamesById[S.Duel.Game]
		if entry then
			openGame(entry, S.Duel)
			updateDuelStrip()
		end
	elseif not S.Active then
		selectTab(S.Tab)
	end
end

function Arcade.OnClose()
	S.Visible = false
	if S.Active and not S.Active.IsDuel then
		-- Jeu solo : on le ferme (il sera relancé à la prochaine ouverture)
		closeGame()
	elseif S.Duel and not S.Duel.Over then
		toast(T("Your duel is still running!"), Theme.Colors.Orange, nil, "⚔️")
	end
end

-- (outils de test) accès à l'état interne
Arcade._State = S
Arcade._OnEvent = onArcadeEvent
Arcade._OpenGame = function(id: string)
	local entry = ArcadeConfig.GamesById[id]
	if entry then
		openGame(entry, nil)
	end
end

return Arcade
