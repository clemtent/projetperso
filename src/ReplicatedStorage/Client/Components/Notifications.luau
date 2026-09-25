--[[
	Notifications (ModuleScript)
	Emplacement : ReplicatedStorage > Client > Components > Notifications

	Bandeaux ("toasts") en bas de l'écran, style clair et soigné :
	  - bulle d'icône colorée (emoji) à gauche ;
	  - titre en gras + texte, ou texte seul ;
	  - barre de temps restant (couleur du type) ;
	  - empilés avec un espacement régulier (4 au maximum) ;
	  - apparition en glissant + fondu, disparition en glissant sur le côté.
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
local MAX_TOASTS = 4
local TOAST_WIDTH = 430
local MARGIN = 8 -- marge autour de la carte (place pour l'ombre dans le CanvasGroup)
local order = 0

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

function Notifications.Build(parent: Frame)
	local frame = UIUtil.Create("Frame", {
		Name = "Toasts",
		Size = UDim2.fromOffset(TOAST_WIDTH + MARGIN * 2, 360),
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -8),
		BackgroundTransparency = 1,
		Parent = parent,
	})
	-- Téléphone : bandeaux un peu plus petits (la toile est agrandie) pour ne
	-- pas cacher tout le bas de l'écran
	local toastScale = UIUtil.Create("UIScale", { Parent = frame })
	local function applyDevice()
		toastScale.Scale = Interface.IsPhone() and 0.9 or 1
	end
	Interface.DeviceChanged:Connect(applyDevice)
	applyDevice()
	UIUtil.Create("UIListLayout", {
		VerticalAlignment = Enum.VerticalAlignment.Bottom,
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		SortOrder = Enum.SortOrder.LayoutOrder,
		Padding = UDim.new(0, -6), -- les marges des CanvasGroup se chevauchent : ~10 px entre deux cartes
		Parent = frame,
	})
	container = frame
end

-- Affiche un bandeau. options : Text, Title?, Color?, Duration?, Icon?, Celebrate?
function Notifications.Show(options: { [string]: any })
	local target = container
	local rawText = tostring(options.Text or "")
	local rawTitle = options.Title and tostring(options.Title) or nil
	if not target or (rawText == "" and not rawTitle) then
		return
	end

	-- Supprime les plus anciens s'il y en a trop
	local existing = {}
	for _, child in ipairs(target:GetChildren()) do
		if child:IsA("GuiObject") then
			table.insert(existing, child)
		end
	end
	table.sort(existing, function(a, b)
		return a.LayoutOrder < b.LayoutOrder
	end)
	while #existing >= MAX_TOASTS do
		local oldest = table.remove(existing, 1)
		if oldest then
			oldest:Destroy()
		end
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
	local height = hasTitle and (text ~= "" and 68 or 52) or 54

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
		ZIndex = 2,
		Parent = group,
	})
	UIUtil.Corner(card, 16)
	UIUtil.Stroke(card, celebrate and Theme.Colors.Premium or Theme.Colors.CardBorder, celebrate and 2 or 1, celebrate and 0 or 0.82)
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
			Size = UDim2.new(0.55, 0, 1, 0),
			BackgroundColor3 = accent,
			BackgroundTransparency = 0.9,
			BorderSizePixel = 0,
			ZIndex = 2,
			Parent = card,
		})
		UIUtil.Corner(tint, 16)
		UIUtil.Create("UIGradient", {
			Transparency = NumberSequence.new(0, 1),
			Parent = tint,
		})
	end

	-- Bulle d'icône
	local bubbleSize = hasTitle and text ~= "" and 44 or 38
	local bubble = UIUtil.Create("Frame", {
		Name = "Icon",
		Size = UDim2.fromOffset(bubbleSize, bubbleSize),
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 12, 0.5, 0),
		BackgroundColor3 = accent,
		ZIndex = 3,
		Parent = card,
	})
	UIUtil.Corner(bubble, UDim.new(1, 0))
	UIUtil.Stroke(bubble, accent:Lerp(Color3.new(0, 0, 0), 0.25), 1.5, 0.2)
	UIUtil.Gradient(bubble, ColorSequence.new(Color3.new(1, 1, 1), Color3.fromRGB(200, 200, 200)), 90)
	UIUtil.Label({
		Text = finalIcon,
		Size = UDim2.new(1, -10, 1, -10),
		Position = UDim2.fromOffset(5, 5),
		MaxTextSize = math.floor(bubbleSize * 0.58),
		ZIndex = 4,
		Parent = bubble,
	})
	local bubbleScale = UIUtil.Create("UIScale", { Scale = 0.4, Parent = bubble })

	-- Textes
	local left = 12 + bubbleSize + 12
	local right = celebrate and 46 or 16
	if hasTitle then
		UIUtil.Label({
			Name = "Title",
			Text = title,
			Font = Theme.Fonts.Title,
			TextColor3 = Theme.Colors.Text,
			TextXAlignment = Enum.TextXAlignment.Left,
			Size = UDim2.new(1, -(left + right), 0, 22),
			Position = UDim2.fromOffset(left, text ~= "" and 10 or 15),
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
				TextSize = 15,
				TextWrapped = true,
				TextXAlignment = Enum.TextXAlignment.Left,
				TextYAlignment = Enum.TextYAlignment.Top,
				BackgroundTransparency = 1,
				Size = UDim2.new(1, -(left + right), 0, 32),
				Position = UDim2.fromOffset(left, 32),
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
			Position = UDim2.fromOffset(left, 5),
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

	-- Barre de temps restant (en bas, dans les coins arrondis)
	local track = UIUtil.Create("Frame", {
		Name = "TimerTrack",
		Size = UDim2.new(1, -32, 0, 3),
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -5),
		BackgroundColor3 = accent,
		BackgroundTransparency = 0.85,
		BorderSizePixel = 0,
		ZIndex = 3,
		Parent = card,
	})
	UIUtil.Corner(track, UDim.new(1, 0))
	local timer = UIUtil.Create("Frame", {
		Name = "Timer",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = accent,
		BorderSizePixel = 0,
		ZIndex = 4,
		Parent = track,
	})
	UIUtil.Corner(timer, UDim.new(1, 0))
	UIUtil.Tween(timer, lifetime, { Size = UDim2.fromScale(0, 1) }, Enum.EasingStyle.Linear)

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

	local closing = false
	local function close()
		if closing or not group.Parent then
			return
		end
		closing = true
		UIUtil.Tween(group, 0.22, { GroupTransparency = 1 })
		UIUtil.Tween(card, 0.25, { Position = UDim2.fromOffset(MARGIN + 60, MARGIN) }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		task.delay(0.26, function()
			group:Destroy()
		end)
	end
	card.Activated:Connect(close)
	task.delay(lifetime, close)
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
