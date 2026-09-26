--[[
	Notifications (ModuleScript)
	Emplacement : ReplicatedStorage > Client > Components > Notifications

	Bandeaux ("toasts") en bas au centre (jamais sur le bandeau d'actualités
	ni sur le bouton / compteur du haut), style clair et soigné :
	  - liseré + badge d'icône colorés (emoji) à gauche ;
	  - titre en gras + texte, ou texte seul ;
	  - barre de temps restant (couleur du type) en bas de la carte ;
	  - empilés (3 au maximum, 2 sur téléphone : le plus ancien part en fondu) ;
	  - doublons regroupés : pastille "x2", "x3"... et le minuteur repart ;
	  - apparition en glissant + fondu, disparition en glissant sur le côté
	    (la place se referme en douceur).
	Un clic ferme le bandeau.

	Réagit aux notifications du serveur : Info, Error, Achievement, Quest,
	Rush, Jackpot, Unlock, Detox, Purchase, Offline (fenêtre "Bon retour !"
	de OfflinePopup), Achievement (grande fenêtre avec médaillon de
	AchievementPopup) et les bonus "Follow" / "Donation" du live.
	Les autres notifications "Bonus" sont montrées par les stimuli
	(StimulusManager).

	API :
	  Notifications.Toast(texte, couleur?, durée?, titre?, fête?, icône?)
	  Notifications.Show({ Text, Title, Color, Duration, Icon, Celebrate })

	v5 : textes du client traduits (Locale) ; les textes envoyés par le
	serveur arrivent déjà dans la langue du joueur. Bandeaux un peu réduits
	sur téléphone ; mode sombre via DarkSkin (calque Toasts).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Client = script.Parent.Parent
local Theme = require(Client.Theme)
local UIUtil = require(Client.UIUtil)
local Effects = require(Client.Effects)
local SoundManager = require(Client.SoundManager)
local ClientState = require(Client.ClientState)
local OfflinePopup = require(script.Parent.OfflinePopup)
local AchievementPopup = require(script.Parent.AchievementPopup)
local NumberFormatter = require(ReplicatedStorage.Shared.NumberFormatter)
local Locale = require(ReplicatedStorage.Shared.Locale)
local Interface = require(Client.Interface)

local Notifications = {}

local container: Frame? = nil
local MAX_TOASTS = 3 -- bandeaux visibles en même temps (2 sur téléphone)
local TOAST_WIDTH = 410
local MARGIN = 8 -- marge autour de la carte (place pour l'ombre dans le CanvasGroup)
local order = 0

type Toast = {
	Key: string,
	Group: CanvasGroup,
	Card: TextButton,
	Count: number,
	CountChip: Frame,
	CountLabel: TextLabel,
	Timer: Frame,
	Lifetime: number,
	Token: number,
	Closing: boolean,
	Close: () -> (),
}

local live: { Toast } = {} -- bandeaux affichés (du plus ancien au plus récent)

-- Icône par défaut selon la couleur d'accent (quand le texte n'en a pas)
local function defaultIcon(color: Color3): string
	if color == Theme.Colors.Red then
		return "⚠️"
	elseif color == Theme.Colors.Green or color == Theme.Colors.Robux then
		return "✅"
	elseif color == Theme.Colors.Gold or color == Theme.Colors.Yellow then
		return "⭐"
	end
	return "💬"
end

-- "🏆 Succès débloqué" -> ("🏆", "Succès débloqué") ; "Bonjour" -> (nil, "Bonjour")
local function splitIcon(text: string): (string?, string)
	local first, rest = string.match(text, "^(%S+)%s+(.+)$")
	if first and rest and not string.find(first, "[%w%p]") then
		return first, rest
	end
	return nil, text
end

local function maxToasts(): number
	return Interface.IsPhone() and 2 or MAX_TOASTS
end

function Notifications.Build(parent: Frame)
	local frame = UIUtil.Create("Frame", {
		Name = "Toasts",
		Size = UDim2.fromOffset(TOAST_WIDTH + MARGIN * 2, 300),
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -10),
		BackgroundTransparency = 1,
		Parent = parent,
	})
	-- Téléphone : bandeaux un peu plus petits (la toile est agrandie) pour ne
	-- pas cacher tout le bas de l'écran
	local scale = UIUtil.Create("UIScale", { Parent = frame })
	local function applyDevice()
		scale.Scale = Interface.IsPhone() and 0.88 or 1
	end
	Interface.DeviceChanged:Connect(applyDevice)
	applyDevice()
	UIUtil.Create("UIListLayout", {
		VerticalAlignment = Enum.VerticalAlignment.Bottom,
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		SortOrder = Enum.SortOrder.LayoutOrder,
		Padding = UDim.new(0, -8), -- les marges des CanvasGroup se chevauchent : ~8 px entre deux cartes
		Parent = frame,
	})
	container = frame
end

-- Relance la barre de temps et la fermeture automatique d'un bandeau
local function arm(toast: Toast)
	toast.Token += 1
	local token = toast.Token
	toast.Timer.Size = UDim2.fromScale(1, 1)
	UIUtil.Tween(toast.Timer, toast.Lifetime, { Size = UDim2.fromScale(0, 1) }, Enum.EasingStyle.Linear)
	task.delay(toast.Lifetime, function()
		if toast.Token == token then
			toast.Close()
		end
	end)
end

-- Même bandeau déjà affiché : "x2", "x3"... au lieu d'en empiler un nouveau
local function bump(toast: Toast)
	toast.Count += 1
	toast.CountLabel.Text = "x" .. tostring(toast.Count)
	if not toast.CountChip.Visible then
		toast.CountChip.Visible = true
	end
	UIUtil.Pop(toast.CountChip, 1.6, 0.35)
	UIUtil.Pop(toast.Card, 1.04, 0.25)
	arm(toast)
end

-- Affiche un bandeau. options : Text, Title?, Color?, Duration?, Icon?, Celebrate?
function Notifications.Show(options: { [string]: any })
	local target = container
	local rawText = tostring(options.Text or "")
	local rawTitle = options.Title and tostring(options.Title) or nil
	if not target or (rawText == "" and not rawTitle) then
		return
	end

	-- Doublon d'un bandeau encore affiché : on le regroupe ("x3")
	local key = (rawTitle or "") .. "\0" .. rawText
	for _, toast in ipairs(live) do
		if toast.Key == key and not toast.Closing then
			bump(toast)
			return
		end
	end

	-- Trop de bandeaux : le plus ancien s'en va (en fondu)
	local limit = maxToasts()
	local open = {}
	for _, toast in ipairs(live) do
		if not toast.Closing then
			table.insert(open, toast)
		end
	end
	for index = 1, #open - limit + 1 do
		open[index].Close()
	end

	local accent: Color3 = options.Color or Theme.Colors.Blue
	local celebrate = options.Celebrate == true
	local lifetime = tonumber(options.Duration) or 3.5

	-- Icône : donnée, sinon 1er emoji du titre (ou du texte), sinon selon la couleur
	local icon: string? = options.Icon
	local title = rawTitle
	local text = rawText
	if title then
		local titleIcon, titleRest = splitIcon(title)
		if titleIcon then
			icon = icon or titleIcon
			title = titleRest
		end
	end
	-- Emoji en tête du texte : devient l'icône (ou disparaît s'il la répète)
	local textIcon, textRest = splitIcon(text)
	if textIcon and (not icon or textIcon == icon) then
		icon = icon or textIcon
		text = textRest
	end
	local finalIcon = icon or defaultIcon(accent)
	local hasTitle = title ~= nil and title ~= ""
	local twoLines = hasTitle and text ~= ""
	local height = twoLines and 62 or 50

	order += 1

	-- CanvasGroup : tout le bandeau (ombre comprise) apparaît / disparaît en fondu
	local group = UIUtil.Create("CanvasGroup", {
		Name = "Toast",
		Size = UDim2.fromOffset(TOAST_WIDTH + MARGIN * 2, height + MARGIN * 2),
		BackgroundTransparency = 1,
		GroupTransparency = 1,
		LayoutOrder = order,
		Parent = target,
	})

	-- TextButton (et non Frame) : le bandeau capte les clics au lieu de les laisser
	-- passer aux cartes / boutons en dessous ; un clic le ferme
	local card = UIUtil.Create("TextButton", {
		Name = "Card",
		Text = "",
		AutoButtonColor = false,
		Size = UDim2.fromOffset(TOAST_WIDTH, height),
		Position = UDim2.fromOffset(MARGIN, MARGIN + 14),
		BackgroundColor3 = Theme.Colors.Card,
		ClipsDescendants = true,
		ZIndex = 2,
		Parent = group,
	})
	UIUtil.Corner(card, 14)
	UIUtil.Stroke(card, celebrate and Theme.Colors.Premium or Theme.Colors.CardBorder, celebrate and 2 or 1, celebrate and 0 or 0.8)
	UIUtil.Shadow(card, 3, 0.84, 2)
	if celebrate then
		UIUtil.Gradient(card, ColorSequence.new({
			ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 252, 235)),
			ColorSequenceKeypoint.new(1, Color3.fromRGB(255, 236, 180)),
		}), 0)
	else
		-- Très léger voile de la couleur du type sur la gauche
		local tint = UIUtil.Create("Frame", {
			Name = "Tint",
			Size = UDim2.new(0.6, 0, 1, 0),
			BackgroundColor3 = accent,
			BackgroundTransparency = 0.88,
			BorderSizePixel = 0,
			ZIndex = 2,
			Parent = card,
		})
		UIUtil.Create("UIGradient", {
			Transparency = NumberSequence.new(0, 1),
			Parent = tint,
		})
	end
	-- Liseré de couleur à gauche
	UIUtil.Create("Frame", {
		Name = "Accent",
		Size = UDim2.new(0, 5, 1, 0),
		BackgroundColor3 = celebrate and Theme.Colors.Premium or accent,
		BorderSizePixel = 0,
		ZIndex = 3,
		Parent = card,
	})

	-- Badge d'icône (carré arrondi coloré)
	local bubbleSize = twoLines and 42 or 34
	local bubble = UIUtil.Create("Frame", {
		Name = "Icon",
		Size = UDim2.fromOffset(bubbleSize, bubbleSize),
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 14, 0.5, -1),
		BackgroundColor3 = accent,
		ZIndex = 3,
		Parent = card,
	})
	UIUtil.Corner(bubble, UDim.new(0, math.floor(bubbleSize * 0.32)))
	UIUtil.Stroke(bubble, accent:Lerp(Color3.new(0, 0, 0), 0.3), 1.5, 0.15)
	UIUtil.Gradient(bubble, ColorSequence.new(Color3.new(1, 1, 1), Color3.fromRGB(196, 196, 196)), 90)
	UIUtil.Create("TextLabel", {
		Name = "Emoji",
		Text = finalIcon,
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Font = Theme.Fonts.Body,
		TextSize = math.floor(bubbleSize * 0.56),
		ZIndex = 4,
		Parent = bubble,
	})
	local bubbleScale = UIUtil.Create("UIScale", { Scale = 0.4, Parent = bubble })

	-- Pastille "x3" (doublons regroupés), à droite
	local countChip = UIUtil.Create("Frame", {
		Name = "Count",
		Size = UDim2.fromOffset(0, 24),
		AutomaticSize = Enum.AutomaticSize.X,
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, celebrate and -44 or -12, 0.5, -1),
		BackgroundColor3 = accent,
		Visible = false,
		ZIndex = 5,
		Parent = card,
	})
	UIUtil.Corner(countChip, UDim.new(1, 0))
	UIUtil.Stroke(countChip, Color3.new(1, 1, 1), 1.5, 0)
	UIUtil.Create("UIPadding", { PaddingLeft = UDim.new(0, 8), PaddingRight = UDim.new(0, 8), Parent = countChip })
	local countLabel = UIUtil.Create("TextLabel", {
		Name = "Label",
		Size = UDim2.fromScale(0, 1),
		AutomaticSize = Enum.AutomaticSize.X,
		BackgroundTransparency = 1,
		Font = Theme.Fonts.Number,
		Text = "x1",
		TextSize = 15,
		TextColor3 = Theme.ContrastText(accent),
		ZIndex = 6,
		Parent = countChip,
	})

	-- Textes (place réservée à droite pour la pastille "x3")
	local left = 14 + bubbleSize + 12
	local right = (celebrate and 46 or 16) + 44
	if hasTitle then
		UIUtil.Label({
			Name = "Title",
			Text = title,
			Font = Theme.Fonts.Title,
			TextColor3 = Theme.Colors.Text,
			TextXAlignment = Enum.TextXAlignment.Left,
			Size = UDim2.new(1, -(left + right), 0, 21),
			Position = UDim2.fromOffset(left, text ~= "" and 9 or 13),
			MaxTextSize = 17,
			ZIndex = 3,
			Parent = card,
		})
		if text ~= "" then
			local body = UIUtil.Create("TextLabel", {
				Name = "Text",
				Text = text,
				Font = Theme.Fonts.Body,
				TextColor3 = Theme.Colors.TextDim,
				TextSize = 14,
				TextWrapped = true,
				TextXAlignment = Enum.TextXAlignment.Left,
				TextYAlignment = Enum.TextYAlignment.Top,
				BackgroundTransparency = 1,
				Size = UDim2.new(1, -(left + right), 0, 30),
				Position = UDim2.fromOffset(left, 30),
				ZIndex = 3,
				Parent = card,
			})
			body.TextTruncate = Enum.TextTruncate.AtEnd
		end
	else
		local body = UIUtil.Create("TextLabel", {
			Name = "Text",
			Text = text,
			Font = Theme.Fonts.Title,
			TextColor3 = Theme.Colors.Text,
			TextSize = 16,
			TextWrapped = true,
			TextXAlignment = Enum.TextXAlignment.Left,
			BackgroundTransparency = 1,
			Size = UDim2.new(1, -(left + right), 1, -10),
			Position = UDim2.fromOffset(left, 4),
			ZIndex = 3,
			Parent = card,
		})
		body.TextTruncate = Enum.TextTruncate.AtEnd
	end

	-- Étincelle qui tourne (style festif)
	if celebrate then
		local sparkle = UIUtil.Label({
			Text = "✨",
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.new(1, -24, 0.5, 0),
			Size = UDim2.fromOffset(30, 30),
			MaxTextSize = 26,
			ZIndex = 3,
			Parent = card,
		})
		UIUtil.Tween(sparkle, lifetime, { Rotation = 360 }, Enum.EasingStyle.Linear)
	end

	-- Barre de temps restant (tout en bas de la carte)
	local track = UIUtil.Create("Frame", {
		Name = "TimerTrack",
		Size = UDim2.new(1, 0, 0, 3),
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.fromScale(0, 1),
		BackgroundColor3 = accent,
		BackgroundTransparency = 0.85,
		BorderSizePixel = 0,
		ZIndex = 3,
		Parent = card,
	})
	local timer = UIUtil.Create("Frame", {
		Name = "Timer",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = celebrate and Theme.Colors.Premium or accent,
		BorderSizePixel = 0,
		ZIndex = 4,
		Parent = track,
	})

	-- Apparition : glissement vers le haut + fondu, l'icône "pop"
	UIUtil.Tween(group, 0.25, { GroupTransparency = 0 })
	UIUtil.Tween(card, 0.4, { Position = UDim2.fromOffset(MARGIN, MARGIN) }, Enum.EasingStyle.Quint)
	UIUtil.Tween(bubbleScale, 0.5, { Scale = 1 }, Enum.EasingStyle.Back)

	-- Survol : léger soulèvement
	card.MouseEnter:Connect(function()
		UIUtil.Tween(card, 0.15, { Position = UDim2.fromOffset(MARGIN, MARGIN - 2) })
	end)
	card.MouseLeave:Connect(function()
		UIUtil.Tween(card, 0.15, { Position = UDim2.fromOffset(MARGIN, MARGIN) })
	end)

	local toast: Toast
	local function close()
		if toast.Closing or not group.Parent then
			return
		end
		toast.Closing = true
		local index = table.find(live, toast)
		if index then
			table.remove(live, index)
		end
		UIUtil.Tween(group, 0.22, { GroupTransparency = 1 })
		UIUtil.Tween(card, 0.25, { Position = UDim2.fromOffset(MARGIN + 60, MARGIN) }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		-- La place se referme en douceur (les autres bandeaux glissent)
		UIUtil.Tween(group, 0.25, { Size = UDim2.fromOffset(TOAST_WIDTH + MARGIN * 2, 0) }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		task.delay(0.27, function()
			group:Destroy()
		end)
	end
	toast = {
		Key = key,
		Group = group,
		Card = card,
		Count = 1,
		CountChip = countChip,
		CountLabel = countLabel,
		Timer = timer,
		Lifetime = lifetime,
		Token = 0,
		Closing = false,
		Close = close,
	}
	table.insert(live, toast)
	card.Activated:Connect(close)
	arm(toast)
end

-- Affiche un bandeau temporaire (API historique).
-- `celebrate` = true : style festif (fond doré, étincelle) pour les achats.
function Notifications.Toast(text: string, color: Color3?, duration: number?, title: string?, celebrate: boolean?, icon: string?)
	Notifications.Show({
		Text = text,
		Color = color,
		Duration = duration,
		Title = title,
		Celebrate = celebrate,
		Icon = icon,
	})
end

-- Petite explosion au centre (vers le bouton) pour les déblocages
local function centerBurst(color: Color3?)
	local layer = Effects.GetLayer()
	if layer then
		Effects.Burst(layer, UDim2.new(0.5, 0, 0, 140), color, 16)
	end
end

-- Achat Robux confirmé : grosse fête
local function celebratePurchase(payload)
	SoundManager.Play("Jackpot", 0.9)
	task.delay(0.12, SoundManager.Play, "Jackpot", 1.2)
	task.delay(0.24, SoundManager.Play, "Achievement", 1.5)
	Effects.Flash(Theme.Colors.Premium, 0.35)
	Effects.Confetti(120)
	centerBurst(Theme.Colors.Premium)
	Effects.BigMessage(Locale.T("💎 THANK YOU! 💎"), Theme.Colors.Premium, 2.2)
	Notifications.Show({
		Text = tostring(payload.Text or Locale.T("Your purchase has arrived!")),
		Title = payload.Title or Locale.T("PURCHASE CONFIRMED"),
		Icon = "💎",
		Color = Theme.Colors.Robux,
		Duration = 6,
		Celebrate = true,
	})
end

-- Bonus du live (abonnement, dons) : en plus du texte flottant du stimulus
local function liveBonus(payload)
	local amount = tonumber(payload.Amount) or 0
	local gain = amount > 0 and ("+" .. NumberFormatter.Format(amount) .. " Dopamine") or ""
	if payload.Source == "Follow" then
		SoundManager.Play("Achievement", 1.25)
		Notifications.Show({
			Title = Locale.T("You followed the stream!"),
			Text = gain ~= "" and Locale.T("%s • donations are about to start 💸", gain) or Locale.T("Donations are about to start 💸"),
			Icon = "💜",
			Color = Theme.Colors.Pink,
			Duration = 4.5,
		})
	elseif payload.Source == "Donation" then
		Notifications.Show({
			Title = Locale.T("Donation received!"),
			Text = gain ~= "" and Locale.T("%s • thanks, viewers", gain) or Locale.T("Thanks, viewers"),
			Icon = "💸",
			Color = Theme.Colors.Robux,
			Duration = 3.5,
		})
	end
end

-- Réagit à une notification envoyée par le serveur
function Notifications.Handle(payload)
	local kind = payload.Type
	local text = payload.Text and tostring(payload.Text) or nil

	if kind == "Achievement" then
		-- Les succès ne se montrent qu'une fois le menu "Succès" débloqué
		if not ClientState.HasFeature("Achievements") then
			return
		end
		-- Grande fenêtre de fête avec le médaillon (+ badge Roblox éventuel)
		AchievementPopup.Show(payload)
	elseif kind == "Quest" then
		SoundManager.Play("Bonus", 1.2)
		Effects.Flash(Theme.Colors.Orange, 0.15)
		Notifications.Show({
			Title = payload.Title or Locale.T("QUEST COMPLETE!"),
			Text = text or "",
			Icon = "📜",
			Color = Theme.Colors.Orange,
			Duration = 4,
		})
	elseif kind == "Jackpot" then
		SoundManager.Play("Jackpot", 0.8)
		task.delay(0.15, SoundManager.Play, "Jackpot", 1.2)
		task.delay(0.3, SoundManager.Play, "Jackpot", 1.6)
		Effects.Flash(Color3.new(1, 1, 1), 0.9)
		Effects.Confetti(150)
		Effects.BigMessage(Locale.T("JACKPOT!!!\nPERFECT CORNER"), Theme.Colors.Yellow, 3.5)
		Notifications.Show({
			Title = Locale.T("THE LOGO HIT THE CORNER!"),
			Text = text or "",
			Icon = "📀",
			Color = Theme.Colors.Gold,
			Duration = 6,
			Celebrate = true,
		})
	elseif kind == "Rush" then
		SoundManager.Play("Rush", 1)
		Effects.Flash(Theme.Colors.Yellow, 0.4)
		Effects.BigMessage("⚡ DOPAMINE RUSH ⚡", Theme.Colors.Yellow, 2)
		Notifications.Show({ Text = text or "", Icon = "⚡", Color = Theme.Colors.Orange, Duration = 5 })
	elseif kind == "Unlock" then
		SoundManager.Play("Achievement", 1.3)
		centerBurst(nil)
		Notifications.Show({ Text = text or Locale.T("✨ New!"), Icon = "✨", Color = Theme.Colors.Green, Duration = 4 })
	elseif kind == "Purchase" then
		celebratePurchase(payload)
	elseif kind == "Offline" then
		OfflinePopup.Show(payload)
	elseif kind == "Detox" then
		-- La cinématique de l'océan (et son son) est jouée par StimulusManager ; le message arrive après
		local multiplier = tonumber(payload.Multiplier) or 1
		task.delay(6.5, function()
			Notifications.Show({
				Title = Locale.T("Welcome back (visit #%s)", tostring(payload.Rebirths or 1)),
				Text = Locale.T(
					"Your gains are now multiplied by %s forever.",
					tostring(math.floor(multiplier * 100 + 0.5) / 100)
				),
				Icon = "🌊",
				Color = Theme.Colors.Cyan,
				Duration = 6,
			})
		end)
	elseif kind == "Error" then
		SoundManager.Play("Error", 0.7)
		Notifications.Show({ Text = text or Locale.T("Error"), Color = Theme.Colors.Red, Duration = 5 })
	elseif kind == "Bonus" then
		-- Texte flottant géré par StimulusManager ; le live a aussi son bandeau
		if payload.Source == "Follow" or payload.Source == "Donation" then
			liveBonus(payload)
		end
		return
	else
		Notifications.Show({ Text = text or "", Title = payload.Title, Color = Theme.Colors.Blue })
	end
end

return Notifications
