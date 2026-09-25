--[[
	PhoneNotifs (ModuleScript - stimulus)
	Emplacement : ReplicatedStorage > Client > Stimuli > PhoneNotifs

	Notifications de téléphone (décidées par le SERVEUR via l'événement
	Spawn "Notif") : une bannière arrondie façon smartphone glisse depuis
	la gauche (icône d'appli, nom, "maintenant", message drôle choisi par
	info.Variant), vibre un peu, et s'empile en haut à gauche (3 au max).
	Un clic = ClaimSpawn (le serveur valide) ; la bannière s'en va toute
	seule à la fin de sa durée de vie (petite barre de temps en bas).
	Le bonus confirmé (OnBonus "Notif") s'affiche en "+X" sur la bannière.
]]

local Debris = game:GetService("Debris")

local Locale = require(game:GetService("ReplicatedStorage").Shared.Locale)

local PhoneNotifs = {}
PhoneNotifs.Slot = "Overlay"

local CARD_W = 288
local CARD_H = 68
local GAP = 8
local LEFT = 16
local TOP = 44
local MAX_VISIBLE = 3

-- Icône, nom de l'appli, couleur de l'icône, message (une liste par langue, même ordre)
local NOTIFS = {
	en = {
		{ Icon = "💬", App = "Messages", Color = Color3.fromRGB(52, 199, 89), Text = "Mom: did you eat?" },
		{ Icon = "📦", App = "Parcel Express", Color = Color3.fromRGB(255, 149, 0), Text = "Your package is on its way! (It got lost, but enthusiastically)" },
		{ Icon = "❤️", App = "Photos", Color = Color3.fromRGB(255, 62, 138), Text = "+3 likes on your photo of toast" },
		{ Icon = "💧", App = "Health", Color = Color3.fromRGB(0, 194, 224), Text = "Reminder: drink some water 💧" },
		{ Icon = "⛈️", App = "Weather", Color = Color3.fromRGB(30, 136, 229), Text = "Lightning likely. Remember to catch it ⚡" },
		{ Icon = "🔋", App = "Battery", Color = Color3.fromRGB(227, 38, 43), Text = "Battery at 3%. Same, honestly." },
		{ Icon = "⏰", App = "Alarm", Color = Color3.fromRGB(255, 138, 26), Text = "You snoozed your alarm 14 times. Impressive." },
		{ Icon = "👟", App = "Step Counter", Color = Color3.fromRGB(61, 200, 61), Text = "12 steps today. Personal best?" },
		{ Icon = "🌱", App = "Smart Plant", Color = Color3.fromRGB(40, 170, 80), Text = "I'm thirsty. Love you. — Your plant" },
		{ Icon = "🍕", App = "Pizza Minute", Color = Color3.fromRGB(255, 120, 40), Text = "Your pizza arrives in 5 minutes (it has for 40 minutes)" },
		{ Icon = "📅", App = "Calendar", Color = Color3.fromRGB(227, 38, 43), Text = "Reminder: do nothing from 2 to 6 p.m." },
		{ Icon = "👵", App = "Grandma", Color = Color3.fromRGB(139, 50, 224), Text = "Grandma sent 27 photos of her cat" },
		{ Icon = "🔒", App = "Security", Color = Color3.fromRGB(60, 60, 70), Text = "New sign-in from your toaster. Was this you?" },
		{ Icon = "⬇️", App = "Software Update", Color = Color3.fromRGB(30, 136, 229), Text = "Update available: 0.2 MB of amazing new features" },
		{ Icon = "🧊", App = "Smart Fridge", Color = Color3.fromRGB(0, 194, 224), Text = "There's one yogurt left. It's staring at you." },
		{ Icon = "🐱", App = "Living Room Cam", Color = Color3.fromRGB(255, 170, 40), Text = "Motion detected: it's the cat. Again." },
		{ Icon = "🎮", App = "Games", Color = Color3.fromRGB(139, 50, 224), Text = "Your friend invited you to play... 3 years ago" },
		{ Icon = "🏦", App = "Bank", Color = Color3.fromRGB(42, 42, 42), Text = "Your Dopamine balance is excellent. Everything else, less so." },
		{ Icon = "✨", App = "Horoscope", Color = Color3.fromRGB(255, 62, 138), Text = "Aries: today, click. A lot." },
		{ Icon = "📸", App = "Memories", Color = Color3.fromRGB(255, 194, 26), Text = "5 years ago today: you were already clicking." },
		{ Icon = "🎵", App = "Music", Color = Color3.fromRGB(255, 45, 85), Text = "Your song of the summer, played 842 times. You OK?" },
		{ Icon = "🦷", App = "Dentist", Color = Color3.fromRGB(90, 160, 255), Text = "Don't forget your appointment. Yes, that one." },
		{ Icon = "👍", App = "Social Network", Color = Color3.fromRGB(30, 110, 230), Text = "Someone liked your comment from 2019" },
		{ Icon = "🌙", App = "Sleep", Color = Color3.fromRGB(88, 86, 214), Text = "It's late. Put the phone down. (No? Okay.)" },
		{ Icon = "🧦", App = "Socks & Co", Color = Color3.fromRGB(227, 38, 43), Text = "Your left sock is on sale!" },
		{ Icon = "🍪", App = "Cookies", Color = Color3.fromRGB(190, 120, 60), Text = "This site uses cookies. Real ones. Chocolate chip." },
		{ Icon = "🤖", App = "Assistant", Color = Color3.fromRGB(0, 170, 200), Text = "Sorry, I didn't understand “5 more minutes”." },
		{ Icon = "🦆", App = "Rubber Duck", Color = Color3.fromRGB(255, 200, 0), Text = "Quack. (You have 1 new quack.)" },
	},
	fr = {
		{ Icon = "💬", App = "Messages", Color = Color3.fromRGB(52, 199, 89), Text = "Maman : t'as mangé ?" },
		{ Icon = "📦", App = "Colis Express", Color = Color3.fromRGB(255, 149, 0), Text = "Ton colis est en route ! (il s'est perdu, mais avec enthousiasme)" },
		{ Icon = "❤️", App = "Photos", Color = Color3.fromRGB(255, 62, 138), Text = "+3 likes sur ta photo de tartine" },
		{ Icon = "💧", App = "Santé", Color = Color3.fromRGB(0, 194, 224), Text = "Rappel : boire de l'eau 💧" },
		{ Icon = "⛈️", App = "Météo", Color = Color3.fromRGB(30, 136, 229), Text = "Risque d'éclairs. Pense à les attraper ⚡" },
		{ Icon = "🔋", App = "Batterie", Color = Color3.fromRGB(227, 38, 43), Text = "Batterie à 3 %. Moi aussi, je suis fatigué." },
		{ Icon = "⏰", App = "Réveil", Color = Color3.fromRGB(255, 138, 26), Text = "Tu as repoussé ton réveil 14 fois. Bravo." },
		{ Icon = "👟", App = "Podomètre", Color = Color3.fromRGB(61, 200, 61), Text = "12 pas aujourd'hui. Record personnel ?" },
		{ Icon = "🌱", App = "Plante connectée", Color = Color3.fromRGB(40, 170, 80), Text = "J'ai soif. Bisous. — Ta plante" },
		{ Icon = "🍕", App = "Pizza Minute", Color = Color3.fromRGB(255, 120, 40), Text = "Ta pizza arrive dans 5 minutes (depuis 40 minutes)" },
		{ Icon = "📅", App = "Calendrier", Color = Color3.fromRGB(227, 38, 43), Text = "Rappel : ne rien faire de 14 h à 18 h" },
		{ Icon = "👵", App = "Mamie", Color = Color3.fromRGB(139, 50, 224), Text = "Mamie a envoyé 27 photos de son chat" },
		{ Icon = "🔒", App = "Sécurité", Color = Color3.fromRGB(60, 60, 70), Text = "Nouvelle connexion depuis ton grille-pain. C'était toi ?" },
		{ Icon = "⬇️", App = "Mise à jour", Color = Color3.fromRGB(30, 136, 229), Text = "Mise à jour dispo : 0,2 Mo de nouveautés incroyables" },
		{ Icon = "🧊", App = "Frigo connecté", Color = Color3.fromRGB(0, 194, 224), Text = "Il reste un yaourt. Il te regarde." },
		{ Icon = "🐱", App = "Caméra du salon", Color = Color3.fromRGB(255, 170, 40), Text = "Mouvement détecté : c'est le chat. Encore." },
		{ Icon = "🎮", App = "Jeux", Color = Color3.fromRGB(139, 50, 224), Text = "Ton ami t'a invité à jouer... il y a 3 ans" },
		{ Icon = "🏦", App = "Banque", Color = Color3.fromRGB(42, 42, 42), Text = "Ton solde de Dopamine est excellent. Le reste, moins." },
		{ Icon = "✨", App = "Horoscope", Color = Color3.fromRGB(255, 62, 138), Text = "Bélier : aujourd'hui, clique. Beaucoup." },
		{ Icon = "📸", App = "Souvenirs", Color = Color3.fromRGB(255, 194, 26), Text = "Il y a 5 ans aujourd'hui : tu cliquais déjà." },
		{ Icon = "🎵", App = "Musique", Color = Color3.fromRGB(255, 45, 85), Text = "Ta chanson de l'été écoutée 842 fois. Ça va ?" },
		{ Icon = "🦷", App = "Dentiste", Color = Color3.fromRGB(90, 160, 255), Text = "N'oublie pas ton rendez-vous. Oui, celui-là." },
		{ Icon = "👍", App = "Réseau social", Color = Color3.fromRGB(30, 110, 230), Text = "Quelqu'un a aimé ton commentaire de 2019" },
		{ Icon = "🌙", App = "Sommeil", Color = Color3.fromRGB(88, 86, 214), Text = "Il est tard. Pose le téléphone. (Non ? D'accord.)" },
		{ Icon = "🧦", App = "Chaussettes & Co", Color = Color3.fromRGB(227, 38, 43), Text = "Ta chaussette gauche est en promo !" },
		{ Icon = "🍪", App = "Cookies", Color = Color3.fromRGB(190, 120, 60), Text = "Ce site utilise des cookies. Des vrais. Au chocolat." },
		{ Icon = "🤖", App = "Assistant", Color = Color3.fromRGB(0, 170, 200), Text = "Désolé, je n'ai pas compris « encore 5 minutes »." },
		{ Icon = "🦆", App = "Canard de bain", Color = Color3.fromRGB(255, 200, 0), Text = "Coin. (Tu as 1 nouveau coin.)" },
	},
}

-- Choix déterministe selon la variante envoyée par le serveur
local function pick(list: { any }, variant: any): any
	local v = math.floor(tonumber(variant) or 1)
	return list[(v - 1) % #list + 1]
end

function PhoneNotifs.Start(ctx)
	local UIUtil = ctx.UIUtil
	local Theme = ctx.Theme
	local container: Frame = ctx.Container
	local random = Random.new()

	local cards: { any } = {} -- du plus récent (en haut) au plus ancien
	local byId: { [string]: any } = {}
	local positions: { [string]: UDim2 } = {} -- pour placer le "+X" du bonus
	local lastPosition = UDim2.fromOffset(LEFT + CARD_W / 2, TOP + CARD_H / 2)

	local function effectsOn(): boolean
		local data = ctx.State.Data
		return not (data and data.Settings and data.Settings.Effects == false)
	end

	local function slotY(index: number): number
		return TOP + (index - 1) * (CARD_H + GAP)
	end

	-- Replace les bannières dans la pile
	local function layout()
		for index, card in ipairs(cards) do
			local target = UDim2.fromOffset(LEFT, slotY(index))
			if card.Entered then
				UIUtil.Tween(card.Root, 0.3, { Position = target }, Enum.EasingStyle.Quad)
			else
				card.Entered = true
				card.Root.Position = UDim2.fromOffset(-CARD_W - 30, slotY(index))
				UIUtil.Tween(card.Root, 0.45, { Position = target }, Enum.EasingStyle.Back)
			end
		end
	end

	local function dismiss(card, claimed: boolean)
		if card.Done then
			return
		end
		card.Done = true
		local index = table.find(cards, card)
		if index then
			table.remove(cards, index)
		end
		byId[card.Id] = nil
		layout()

		local root = card.Root
		root.Active = false
		if claimed then
			-- "Ouverture" : petit gonflement puis disparition
			UIUtil.Tween(card.Scale, 0.12, { Scale = 1.06 }, Enum.EasingStyle.Quad)
			task.delay(0.12, function()
				if root.Parent then
					UIUtil.Tween(card.Scale, 0.25, { Scale = 0.6 }, Enum.EasingStyle.Back, Enum.EasingDirection.In)
					UIUtil.Tween(card.Group, 0.25, { GroupTransparency = 1 })
					UIUtil.Tween(card.Shadow, 0.25, { BackgroundTransparency = 1 })
					UIUtil.Tween(card.Outline, 0.25, { Transparency = 1 })
				end
			end)
		else
			-- Ignorée : repart vers la gauche
			UIUtil.Tween(root, 0.35, { Position = root.Position - UDim2.fromOffset(CARD_W + 40, 0) }, Enum.EasingStyle.Back, Enum.EasingDirection.In)
			UIUtil.Tween(card.Group, 0.35, { GroupTransparency = 0.6 })
		end
		Debris:AddItem(root, 0.5)
	end

	local function spawnNotif(info)
		if not ctx.IsAlive() or type(info) ~= "table" or type(info.Id) ~= "string" or byId[info.Id] then
			return
		end
		-- Trop de bannières : la plus ancienne laisse sa place
		while #cards >= MAX_VISIBLE do
			dismiss(cards[#cards], false)
		end

		local data = pick(Locale.Pick(NOTIFS), info.Variant)
		local lifetime = math.max(1.5, tonumber(info.Lifetime) or 6)
		local variant = math.floor(tonumber(info.Variant) or 1)

		local root = UIUtil.Create("TextButton", {
			Name = "Notif",
			Size = UDim2.fromOffset(CARD_W, CARD_H),
			Position = UDim2.fromOffset(-CARD_W - 30, TOP),
			BackgroundTransparency = 1,
			AutoButtonColor = false,
			Text = "",
			ZIndex = 30,
			Parent = container,
		})
		local scale = UIUtil.Create("UIScale", { Parent = root })

		-- Ombre douce
		local shadow = UIUtil.Create("Frame", {
			Name = "Shadow",
			Size = UDim2.fromScale(1, 1),
			Position = UDim2.fromOffset(0, 4),
			BackgroundColor3 = Color3.new(0, 0, 0),
			BackgroundTransparency = 0.82,
			BorderSizePixel = 0,
			ZIndex = 30,
			Parent = root,
		})
		UIUtil.Corner(shadow, 18)

		-- Carte (CanvasGroup : permet de tout faire disparaître d'un coup)
		local group = UIUtil.Create("CanvasGroup", {
			Name = "Card",
			Size = UDim2.fromScale(1, 1),
			BackgroundColor3 = Color3.fromRGB(250, 250, 252),
			BorderSizePixel = 0,
			ZIndex = 31,
			Parent = root,
		})
		UIUtil.Corner(group, 18)
		-- Contour fin (hors du CanvasGroup pour ne pas être rogné)
		local outline = UIUtil.Create("Frame", {
			Name = "Outline",
			Size = UDim2.fromScale(1, 1),
			BackgroundTransparency = 1,
			ZIndex = 36,
			Parent = root,
		})
		UIUtil.Corner(outline, 18)
		local outlineStroke = UIUtil.Stroke(outline, Theme.Colors.Border, 1.5, 0.7)

		-- Icône de l'appli
		local icon = UIUtil.Create("Frame", {
			Name = "Icon",
			Size = UDim2.fromOffset(44, 44),
			Position = UDim2.fromOffset(11, (CARD_H - 44) / 2),
			BackgroundColor3 = data.Color,
			BorderSizePixel = 0,
			ZIndex = 32,
			Parent = group,
		})
		UIUtil.Corner(icon, 11)
		UIUtil.Gradient(icon, ColorSequence.new(Color3.new(1, 1, 1), Color3.fromRGB(205, 205, 205)), 90)
		UIUtil.Label({
			Text = data.Icon,
			Size = UDim2.fromScale(0.72, 0.72),
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			MaxTextSize = 30,
			ZIndex = 33,
			Parent = icon,
		})

		-- Pastille rouge (nombre de notifs "non lues" de l'appli)
		local badge = UIUtil.Label({
			Text = tostring(variant % 9 + 1),
			Font = Theme.Fonts.Number,
			TextColor3 = Color3.new(1, 1, 1),
			BackgroundColor3 = Theme.Colors.Red,
			BackgroundTransparency = 0,
			Size = UDim2.fromOffset(18, 18),
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.new(0, 11 + 44 - 2, 0, (CARD_H - 44) / 2 + 3),
			MaxTextSize = 13,
			ZIndex = 34,
			Parent = group,
		})
		UIUtil.Corner(badge, UDim.new(1, 0))

		-- Nom de l'appli + "maintenant"
		UIUtil.Create("TextLabel", {
			Name = "App",
			Size = UDim2.fromOffset(CARD_W - 66 - 86, 18),
			Position = UDim2.fromOffset(66, 9),
			BackgroundTransparency = 1,
			Font = Theme.Fonts.Title,
			Text = string.upper(data.App),
			TextColor3 = Theme.Colors.TextDim,
			TextSize = 13,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextTruncate = Enum.TextTruncate.AtEnd,
			ZIndex = 32,
			Parent = group,
		})
		UIUtil.Create("TextLabel", {
			Name = "Time",
			Size = UDim2.fromOffset(76, 18),
			Position = UDim2.fromOffset(CARD_W - 86, 9),
			BackgroundTransparency = 1,
			Font = Theme.Fonts.Body,
			Text = Locale.T("now"),
			TextColor3 = Theme.Colors.TextDim,
			TextSize = 13,
			TextXAlignment = Enum.TextXAlignment.Right,
			ZIndex = 32,
			Parent = group,
		})

		-- Message
		UIUtil.Label({
			Name = "Message",
			Text = data.Text,
			Font = Theme.Fonts.Body,
			TextColor3 = Theme.Colors.TextDark,
			TextWrapped = true,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextYAlignment = Enum.TextYAlignment.Top,
			Size = UDim2.fromOffset(CARD_W - 66 - 12, 34),
			Position = UDim2.fromOffset(66, 27),
			MaxTextSize = 16,
			ZIndex = 32,
			Parent = group,
		})

		-- Barre de temps restant
		local timeBar = UIUtil.Create("Frame", {
			Name = "TimeBar",
			Size = UDim2.fromOffset(CARD_W - 32, 3),
			Position = UDim2.fromOffset(16, CARD_H - 5),
			BackgroundColor3 = data.Color,
			BackgroundTransparency = 0.25,
			BorderSizePixel = 0,
			ZIndex = 33,
			Parent = group,
		})
		UIUtil.Corner(timeBar, UDim.new(1, 0))
		UIUtil.Tween(timeBar, lifetime, { Size = UDim2.fromOffset(0, 3) }, Enum.EasingStyle.Linear)

		local card = {
			Id = info.Id,
			Root = root,
			Scale = scale,
			Group = group,
			Shadow = shadow,
			Outline = outlineStroke,
			Color = data.Color,
			Expires = os.clock() + lifetime,
			Entered = false,
			Done = false,
		}
		byId[card.Id] = card
		table.insert(cards, 1, card)
		layout()

		ctx.Sound.Play("Notif", 0.95 + random:NextNumber() * 0.25)

		-- Vibration du téléphone (petite secousse en rotation)
		task.spawn(function()
			task.wait(0.35)
			for i = 1, 8 do
				if card.Done or not root.Parent or not ctx.IsAlive() then
					break
				end
				root.Rotation = (i % 2 == 0) and 1.6 or -1.6
				task.wait(0.035)
			end
			if root.Parent then
				root.Rotation = 0
			end
		end)

		-- Clic : on "ouvre" la notification
		ctx.Connect(root.Activated, function()
			if card.Done or not ctx.IsAlive() then
				return
			end
			local index = table.find(cards, card) or 1
			local position = UDim2.fromOffset(LEFT + CARD_W / 2, slotY(index) + CARD_H / 2)
			positions[card.Id] = position
			lastPosition = position
			ctx.ClaimSpawn(card.Id)
			ctx.Sound.Play("Click", 1.5)
			if effectsOn() then
				ctx.Effects.Burst(container, position, card.Color, 10)
			end
			dismiss(card, true)
			local id = card.Id
			task.delay(6, function()
				positions[id] = nil
			end)
		end)
	end

	-- Disparition automatique à la fin de la durée de vie
	ctx.OnRender(function()
		if #cards == 0 then
			return
		end
		local now = os.clock()
		for i = #cards, 1, -1 do
			local card = cards[i]
			if card and not card.Done and now >= card.Expires then
				dismiss(card, false)
			end
		end
	end)

	ctx.OnSpawn("Notif", spawnNotif)

	-- Bonus confirmé : "+X" sur la bannière
	ctx.OnBonus("Notif", function(payload)
		if not ctx.IsAlive() then
			return
		end
		local position = (payload.SpawnId and positions[payload.SpawnId]) or lastPosition
		ctx.FloatText(container, position, "+" .. ctx.Format.Format(tonumber(payload.Amount) or 0), Theme.Colors.Green, 34)
	end)
end

function PhoneNotifs.Stop(_ctx)
	-- Les bannières vivent dans ctx.Container (détruit par le StimulusManager)
end

return PhoneNotifs
