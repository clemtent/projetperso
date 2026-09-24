--[[
	Email (ModuleScript - stimulus)
	Emplacement : ReplicatedStorage > Client > Stimuli > Email

	Mails qui arrivent en volant (décidés par le SERVEUR via l'événement
	Spawn "Email") : une enveloppe dessinée en code (rabat, cachet, pastille
	rouge "non lu") entre par la droite, se pose en (X, Y) et se dandine.
	Un clic l'ouvre : petite fenêtre de mail (expéditeur, objet, texte
	absurde choisi par info.Variant) + ClaimSpawn (le serveur valide) ;
	le "+X" confirmé (OnBonus "Email") s'affiche à côté.
	Si on l'ignore trop longtemps, elle repart... et s'ajoute au compteur
	"📬 non lus" (en haut à droite), qui ne fait que grossir.
]]

local Debris = game:GetService("Debris")

local Email = {}
Email.Slot = "Overlay"

local MAX_ENVELOPES = 4
local ENVELOPE_W = 92
local ENVELOPE_H = 62
local POPUP_W = 316
local POPUP_H = 192
local POPUP_AUTO_CLOSE = 9
local HURRY_TIME = 3 -- dernières secondes : l'enveloppe s'agite

-- Avatar, expéditeur, objet, texte
local EMAILS = {
	{ Avatar = "🤴", Sender = "Prince de Pixelie", Subject = "URGENT : héritage de 1 000 000 Dopamine",
		Body = "Cher ami, je suis coincé dans un menu. Envoie-moi 3 clics et je te rends le double. Promis juré." },
	{ Avatar = "🧊", Sender = "Ton frigo", Subject = "Il reste un yaourt",
		Body = "Je voulais juste te le dire. Il est périmé depuis mardi. Je t'aime quand même." },
	{ Avatar = "☎️", Sender = "Service Client du Bonheur", Subject = "Votre dose de Dopamine est prête",
		Body = "Merci de patienter. Votre bonheur est important pour nous. Temps d'attente estimé : 47 minutes." },
	{ Avatar = "🗿", Sender = "Newsletter des Cailloux", Subject = "Les cailloux de la semaine",
		Body = "Cette semaine : un caillou rond. Un autre caillou rond. Et, surprise... un caillou." },
	{ Avatar = "👵", Sender = "Mamie", Subject = "Fwd: Fwd: Fwd: TROP DRÔLE",
		Body = "REGARDE CE CHAT QUI FAIT DU SKI !!! BISOUS. PS : COMMENT ON ENLÈVE LES MAJUSCULES ?" },
	{ Avatar = "🔮", Sender = "Toi, dans le futur", Subject = "Ne clique pas sur...",
		Body = "...trop tard. Bon, puisque tu es là : bois un verre d'eau et pense à aller voir l'océan." },
	{ Avatar = "🙋", Sender = "Club des Cliqueurs Anonymes", Subject = "Réunion ce soir",
		Body = "« Bonjour, je m'appelle Kévin et j'ai cliqué 40 000 fois aujourd'hui. » (applaudissements)" },
	{ Avatar = "🎰", Sender = "Loterie Cosmique", Subject = "VOUS AVEZ GAGNÉ !!!",
		Body = "Félicitations ! Vous avez gagné... cet e-mail. Il est à vous. Profitez-en bien." },
	{ Avatar = "👔", Sender = "Le Boss", Subject = "Réunion demain à 8 h",
		Body = "Ordre du jour : parler de la réunion d'avant. Et prévoir celle d'après. Croissants non fournis." },
	{ Avatar = "🐦", Sender = "Pigeon Voyageur", Subject = "Désolé pour le retard",
		Body = "J'ai pris un raccourci par l'Islande. Le message était : « à ce soir ». C'était il y a deux semaines." },
	{ Avatar = "🌱", Sender = "Ta plante", Subject = "Lettre ouverte",
		Body = "Je vois le soleil par la fenêtre. Je le vois. Mais je ne l'ai pas. Réfléchis-y." },
	{ Avatar = "🧦", Sender = "Assurance Chaussettes", Subject = "Protégez vos chaussettes !",
		Body = "72 % des chaussettes disparaissent dans la machine à laver. Ne laissez pas la vôtre devenir une statistique." },
	{ Avatar = "🤖", Sender = "Robot Aspirateur", Subject = "Je suis coincé",
		Body = "Sous le canapé. Depuis mardi. J'ai trouvé 3 pièces, un bonbon et le sens de la vie." },
	{ Avatar = "🌊", Sender = "Agence Voyage Océan", Subject = "L'océan vous attend",
		Body = "Respirez. Détendez-vous. Oubliez les clics. Offre valable jusqu'à votre prochain clic." },
	{ Avatar = "🐱", Sender = "Le Chat", Subject = "Miaou",
		Body = "Miaou miaou. Miaou ? MIAOU. (Traduction : la gamelle est vide, c'est inadmissible.)" },
	{ Avatar = "😴", Sender = "Sieste Magazine", Subject = "Spécial été : 50 positions de sieste",
		Body = "Découvrez l'« étoile de mer », la « crêpe » et notre préférée : « encore 5 minutes »." },
	{ Avatar = "🚨", Sender = "Détecteur de fumée", Subject = "Bip.",
		Body = "Bip. Ma pile est faible. Je vais biper toutes les 30 secondes à 3 h du matin. Bip." },
	{ Avatar = "🏛️", Sender = "Mairie de Clicville", Subject = "Nouvelle loi sur les boutons",
		Body = "Il est désormais interdit de ne pas cliquer le mardi. Merci de votre compréhension." },
	{ Avatar = "⏳", Sender = "Toi, il y a une heure", Subject = "Juste 5 minutes",
		Body = "Je me suis dit « juste 5 minutes ». Si tu lis ceci, c'est que c'était un mensonge." },
	{ Avatar = "☀️", Sender = "Le Soleil", Subject = "Message d'absence",
		Body = "Je serai absent cette nuit. Pour toute urgence, merci de contacter la Lune." },
	{ Avatar = "📀", Sender = "Fan-club du Logo", Subject = "IL A PRESQUE TOUCHÉ LE COIN",
		Body = "Presque. PRESQUE. Nous nous réunissons ce soir pour en parler. Venez avec des mouchoirs." },
	{ Avatar = "🥖", Sender = "Boulangerie du Coin", Subject = "Votre baguette est prête",
		Body = "Elle vous attend depuis ce matin. Elle a un peu durci, mais elle reste positive." },
}

-- Réponses quand on clique sur "Répondre"
local REPLIES = {
	"Envoyé... à personne 📭",
	"Brouillon enregistré pour 2087",
	"Tu as répondu « ok ». Classique.",
	"Réponse : « mdr » 👍",
	"Message parti dans les spams 🗑️",
}

local function pick(list: { any }, variant: any): any
	local v = math.floor(tonumber(variant) or 1)
	return list[(v - 1) % #list + 1]
end

function Email.Start(ctx)
	local UIUtil = ctx.UIUtil
	local Theme = ctx.Theme
	local container: Frame = ctx.Container
	local random = Random.new()

	local cream = Color3.fromRGB(255, 249, 235)
	local creamDark = Color3.fromRGB(240, 225, 195)
	local blue = Theme.Colors.Blue
	local border = Theme.Colors.Border

	local envelopes: { [string]: any } = {}
	local envelopeCount = 0
	local missed = 0
	local positions: { [string]: UDim2 } = {}
	local lastPosition = UDim2.fromScale(0.5, 0.45)
	local popup: any = nil -- fenêtre de mail ouverte

	local function effectsOn(): boolean
		local data = ctx.State.Data
		return not (data and data.Settings and data.Settings.Effects == false)
	end

	------------------------------------------------------------------
	-- Compteur "📬 non lus" (dans le bandeau d'actu, juste à gauche de
	-- l'horloge de 62 px : hors de toute carte, il ne cache pas la bourse)
	------------------------------------------------------------------
	local counter = UIUtil.Label({
		Name = "Unread",
		Text = "",
		Font = Theme.Fonts.Title,
		TextColor3 = Theme.Colors.TextDark,
		BackgroundColor3 = Color3.new(1, 1, 1),
		BackgroundTransparency = 0,
		Size = UDim2.fromOffset(128, 22),
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -70, 0, 4),
		Visible = false,
		MaxTextSize = 15,
		ZIndex = 40,
		Parent = container,
	})
	UIUtil.Corner(counter, UDim.new(1, 0))
	UIUtil.Stroke(counter, border, 1.5, 0.1)
	local counterScale = UIUtil.Create("UIScale", { Parent = counter })

	local function refreshCounter()
		local unread = envelopeCount + missed
		counter.Visible = unread > 0
		local suffix = ""
		if unread >= 50 then
			suffix = " 😱"
		elseif unread >= 10 then
			suffix = " 😬"
		end
		counter.Text = "📬 " .. tostring(unread) .. (unread > 1 and " non lus" or " non lu") .. suffix
		counterScale.Scale = 1.25
		UIUtil.Tween(counterScale, 0.3, { Scale = 1 }, Enum.EasingStyle.Back)
	end

	------------------------------------------------------------------
	-- Fenêtre de mail
	------------------------------------------------------------------
	local function closePopup(target)
		local current = target or popup
		if not current or current.Closed then
			return
		end
		current.Closed = true
		if popup == current then
			popup = nil
		end
		UIUtil.Tween(current.Scale, 0.2, { Scale = 0.5 }, Enum.EasingStyle.Back, Enum.EasingDirection.In)
		UIUtil.Tween(current.Group, 0.2, { GroupTransparency = 1 })
		UIUtil.Tween(current.Outline, 0.2, { Transparency = 1 })
		UIUtil.Tween(current.Shadow, 0.2, { BackgroundTransparency = 1 })
		Debris:AddItem(current.Root, 0.25)
	end

	local function makeButton(parent: Instance, text: string, color: Color3, textColor: Color3, position: UDim2, width: number): TextButton
		local button = UIUtil.Create("TextButton", {
			Size = UDim2.fromOffset(width, 28),
			Position = position,
			BackgroundColor3 = color,
			AutoButtonColor = true,
			Font = Theme.Fonts.Title,
			Text = text,
			TextColor3 = textColor,
			TextSize = 15,
			ZIndex = 66,
			Parent = parent,
		})
		UIUtil.Corner(button, UDim.new(1, 0))
		UIUtil.Stroke(button, border, 1.5, 0.3)
		return button
	end

	local function openPopup(email, sx: number, sy: number)
		closePopup(nil)
		local ax = math.clamp(sx, 0.02, 0.98)
		local ay = math.clamp(sy, 0.05, 0.95)

		-- AnchorPoint = position : la fenêtre reste toujours dans l'écran.
		-- Racine = TextButton vide : elle absorbe les clics sur la fenêtre
		-- (sinon ils traversent jusqu'au bouton principal / aux cartes).
		local root = UIUtil.Create("TextButton", {
			Name = "MailPopup",
			Size = UDim2.fromOffset(POPUP_W, POPUP_H),
			AnchorPoint = Vector2.new(ax, ay),
			Position = UDim2.fromScale(ax, ay),
			BackgroundTransparency = 1,
			Text = "",
			AutoButtonColor = false,
			ZIndex = 60,
			Parent = container,
		})
		local scale = UIUtil.Create("UIScale", { Scale = 0.5, Parent = root })
		local shadow = UIUtil.Create("Frame", {
			Size = UDim2.fromScale(1, 1),
			Position = UDim2.fromOffset(0, 6),
			BackgroundColor3 = Color3.new(0, 0, 0),
			BackgroundTransparency = 0.8,
			BorderSizePixel = 0,
			ZIndex = 60,
			Parent = root,
		})
		UIUtil.Corner(shadow, 14)

		local group = UIUtil.Create("CanvasGroup", {
			Name = "Window",
			Size = UDim2.fromScale(1, 1),
			BackgroundColor3 = Color3.new(1, 1, 1),
			BorderSizePixel = 0,
			GroupTransparency = 0,
			ZIndex = 61,
			Parent = root,
		})
		UIUtil.Corner(group, 14)

		-- Barre de titre
		local titleBar = UIUtil.Create("Frame", {
			Size = UDim2.new(1, 0, 0, 32),
			BackgroundColor3 = blue,
			BorderSizePixel = 0,
			ZIndex = 62,
			Parent = group,
		})
		UIUtil.Create("TextLabel", {
			Size = UDim2.new(1, -44, 1, 0),
			Position = UDim2.fromOffset(12, 0),
			BackgroundTransparency = 1,
			Font = Theme.Fonts.Title,
			Text = "📧 Nouveau message",
			TextColor3 = Color3.new(1, 1, 1),
			TextSize = 16,
			TextXAlignment = Enum.TextXAlignment.Left,
			ZIndex = 63,
			Parent = titleBar,
		})
		local closeButton = UIUtil.Create("TextButton", {
			Size = UDim2.fromOffset(26, 26),
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.new(1, -4, 0.5, 0),
			BackgroundColor3 = Color3.new(1, 1, 1),
			BackgroundTransparency = 0.8,
			AutoButtonColor = true,
			Font = Theme.Fonts.Title,
			Text = "✕",
			TextColor3 = Color3.new(1, 1, 1),
			TextSize = 16,
			ZIndex = 64,
			Parent = titleBar,
		})
		UIUtil.Corner(closeButton, UDim.new(1, 0))

		-- Avatar + expéditeur + objet
		local avatar = UIUtil.Create("Frame", {
			Size = UDim2.fromOffset(40, 40),
			Position = UDim2.fromOffset(12, 40),
			BackgroundColor3 = Theme.Colors.PanelLight,
			BorderSizePixel = 0,
			ZIndex = 62,
			Parent = group,
		})
		UIUtil.Corner(avatar, UDim.new(1, 0))
		UIUtil.Stroke(avatar, border, 1.5, 0.5)
		UIUtil.Label({
			Text = email.Avatar,
			Size = UDim2.fromScale(0.7, 0.7),
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			MaxTextSize = 26,
			ZIndex = 63,
			Parent = avatar,
		})
		UIUtil.Create("TextLabel", {
			Size = UDim2.new(1, -72, 0, 18),
			Position = UDim2.fromOffset(60, 40),
			BackgroundTransparency = 1,
			Font = Theme.Fonts.Body,
			Text = "De : " .. email.Sender,
			TextColor3 = Theme.Colors.TextDim,
			TextSize = 14,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextTruncate = Enum.TextTruncate.AtEnd,
			ZIndex = 62,
			Parent = group,
		})
		UIUtil.Create("TextLabel", {
			Size = UDim2.new(1, -72, 0, 22),
			Position = UDim2.fromOffset(60, 58),
			BackgroundTransparency = 1,
			Font = Theme.Fonts.Title,
			Text = email.Subject,
			TextColor3 = Theme.Colors.TextDark,
			TextSize = 16,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextTruncate = Enum.TextTruncate.AtEnd,
			ZIndex = 62,
			Parent = group,
		})
		UIUtil.Create("Frame", {
			Size = UDim2.new(1, -24, 0, 1),
			Position = UDim2.fromOffset(12, 87),
			BackgroundColor3 = Theme.Colors.Disabled,
			BorderSizePixel = 0,
			ZIndex = 62,
			Parent = group,
		})
		UIUtil.Label({
			Text = email.Body,
			Font = Theme.Fonts.Body,
			TextColor3 = Theme.Colors.TextDark,
			TextWrapped = true,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextYAlignment = Enum.TextYAlignment.Top,
			Size = UDim2.new(1, -24, 0, 56),
			Position = UDim2.fromOffset(12, 93),
			MaxTextSize = 15,
			ZIndex = 62,
			Parent = group,
		})

		-- Boutons
		local replyButton = makeButton(group, "↩️ Répondre", blue, Color3.new(1, 1, 1), UDim2.fromOffset(12, POPUP_H - 38), 136)
		local deleteButton = makeButton(group, "🗑️ Supprimer", Theme.Colors.PanelLight, Theme.Colors.TextDark, UDim2.fromOffset(POPUP_W - 12 - 136, POPUP_H - 38), 136)

		-- Contour (hors du CanvasGroup)
		local outline = UIUtil.Create("Frame", {
			Size = UDim2.fromScale(1, 1),
			BackgroundTransparency = 1,
			ZIndex = 67,
			Parent = root,
		})
		UIUtil.Corner(outline, 14)
		local outlineStroke = UIUtil.Stroke(outline, border, 2, 0)

		local current = {
			Root = root,
			Scale = scale,
			Group = group,
			Shadow = shadow,
			Outline = outlineStroke,
			Closed = false,
		}
		popup = current

		UIUtil.Tween(scale, 0.35, { Scale = 1 }, Enum.EasingStyle.Back)

		local function close()
			closePopup(current)
		end

		ctx.Connect(closeButton.Activated, close)
		ctx.Connect(deleteButton.Activated, function()
			ctx.Sound.Play("Click", 0.8)
			close()
		end)
		ctx.Connect(replyButton.Activated, function()
			if current.Closed then
				return
			end
			ctx.Sound.Play("Mail", 1.3)
			ctx.FloatText(container, UDim2.fromScale(ax, ay), REPLIES[random:NextInteger(1, #REPLIES)], blue, 30)
			close()
		end)
		task.delay(POPUP_AUTO_CLOSE, function()
			if ctx.IsAlive() then
				close()
			end
		end)
	end

	------------------------------------------------------------------
	-- Enveloppes volantes
	------------------------------------------------------------------
	local function line(parent: Instance, a: Vector2, b: Vector2, thickness: number, color: Color3, zIndex: number)
		local delta = b - a
		local middle = (a + b) / 2
		return UIUtil.Create("Frame", {
			Size = UDim2.fromOffset(delta.Magnitude + thickness * 0.5, thickness),
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromOffset(middle.X, middle.Y),
			Rotation = math.deg(math.atan2(delta.Y, delta.X)),
			BackgroundColor3 = color,
			BorderSizePixel = 0,
			ZIndex = zIndex,
			Parent = parent,
		})
	end

	local function removeEnvelope(envelope, opened: boolean)
		if envelope.Done then
			return
		end
		envelope.Done = true
		envelopes[envelope.Id] = nil
		envelopeCount -= 1
		local root = envelope.Root
		if opened then
			UIUtil.Tween(envelope.Scale, 0.25, { Scale = 1.4 }, Enum.EasingStyle.Quad)
			for _, item in ipairs(root:GetDescendants()) do
				if item:IsA("TextLabel") then
					UIUtil.Tween(item, 0.25, { TextTransparency = 1, BackgroundTransparency = 1 })
				elseif item:IsA("Frame") then
					UIUtil.Tween(item, 0.25, { BackgroundTransparency = 1 })
				elseif item:IsA("UIStroke") then
					UIUtil.Tween(item, 0.25, { Transparency = 1 })
				end
			end
		else
			-- Ignorée : elle s'envole vers le haut à gauche
			missed += 1
			UIUtil.Tween(root, 0.8, {
				Position = root.Position + UDim2.new(-0.25, 0, -0.35, 0),
				Rotation = -40,
			}, Enum.EasingStyle.Back, Enum.EasingDirection.In)
			UIUtil.Tween(envelope.Scale, 0.8, { Scale = 0.3 }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		end
		refreshCounter()
		Debris:AddItem(root, opened and 0.3 or 0.85)
	end

	local function spawnEmail(info)
		if not ctx.IsAlive() or type(info) ~= "table" or type(info.Id) ~= "string" then
			return
		end
		if envelopes[info.Id] or envelopeCount >= MAX_ENVELOPES then
			return
		end
		local email = pick(EMAILS, info.Variant)
		local x = math.clamp(tonumber(info.X) or 0.5, 0.05, 0.95)
		local y = math.clamp(tonumber(info.Y) or 0.5, 0.1, 0.9)
		local lifetime = math.max(2, tonumber(info.Lifetime) or 15)
		local target = UDim2.fromScale(x, y)

		local root = UIUtil.Create("TextButton", {
			Name = "Envelope",
			Size = UDim2.fromOffset(128, 100),
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(1.12, math.max(0.05, y - 0.2)),
			Rotation = 25,
			BackgroundTransparency = 1,
			AutoButtonColor = false,
			Text = "",
			ZIndex = 30,
			Parent = container,
		})
		local scale = UIUtil.Create("UIScale", { Scale = 0.6, Parent = root })

		-- Corps de l'enveloppe
		local body = UIUtil.Create("Frame", {
			Name = "Body",
			Size = UDim2.fromOffset(ENVELOPE_W, ENVELOPE_H),
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.new(0.5, 0, 0, 40),
			BackgroundColor3 = cream,
			BorderSizePixel = 0,
			ZIndex = 31,
			Parent = root,
		})
		UIUtil.Corner(body, 7)
		UIUtil.Stroke(body, border, 2, 0)
		UIUtil.Gradient(body, ColorSequence.new(Color3.new(1, 1, 1), Color3.fromRGB(235, 235, 235)), 90)

		-- Rabat (un "V" + deux plis du bas)
		local center = Vector2.new(ENVELOPE_W / 2, ENVELOPE_H * 0.56)
		line(body, Vector2.new(3, 3), center, 2, border, 32)
		line(body, Vector2.new(ENVELOPE_W - 3, 3), center, 2, border, 32)
		line(body, Vector2.new(4, ENVELOPE_H - 4), Vector2.new(ENVELOPE_W * 0.38, ENVELOPE_H * 0.62), 1.5, creamDark, 32)
		line(body, Vector2.new(ENVELOPE_W - 4, ENVELOPE_H - 4), Vector2.new(ENVELOPE_W * 0.62, ENVELOPE_H * 0.62), 1.5, creamDark, 32)

		-- Cachet de cire
		local seal = UIUtil.Create("Frame", {
			Name = "Seal",
			Size = UDim2.fromOffset(20, 20),
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromOffset(center.X, center.Y),
			BackgroundColor3 = Theme.Colors.Red,
			BorderSizePixel = 0,
			ZIndex = 33,
			Parent = body,
		})
		UIUtil.Corner(seal, UDim.new(1, 0))
		UIUtil.Label({
			Text = "@",
			Font = Theme.Fonts.Title,
			TextColor3 = Color3.new(1, 1, 1),
			Size = UDim2.fromScale(0.8, 0.8),
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.45),
			MaxTextSize = 14,
			ZIndex = 34,
			Parent = seal,
		})

		-- Pastille rouge "non lu"
		local dot = UIUtil.Label({
			Name = "UnreadDot",
			Text = "1",
			Font = Theme.Fonts.Number,
			TextColor3 = Color3.new(1, 1, 1),
			BackgroundColor3 = Theme.Colors.Red,
			BackgroundTransparency = 0,
			Size = UDim2.fromOffset(22, 22),
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.new(1, -2, 0, 2),
			MaxTextSize = 14,
			ZIndex = 35,
			Parent = body,
		})
		UIUtil.Corner(dot, UDim.new(1, 0))
		UIUtil.Stroke(dot, Color3.new(1, 1, 1), 2, 0)

		-- Étiquette sous l'enveloppe
		local tag = UIUtil.Label({
			Name = "Tag",
			Text = "📩 " .. email.Sender,
			Font = Theme.Fonts.Title,
			TextColor3 = Theme.Colors.TextDark,
			BackgroundColor3 = Color3.new(1, 1, 1),
			BackgroundTransparency = 0,
			Size = UDim2.fromOffset(128, 22),
			AnchorPoint = Vector2.new(0.5, 0),
			Position = UDim2.new(0.5, 0, 0, 76),
			MaxTextSize = 13,
			ZIndex = 35,
			Parent = root,
		})
		UIUtil.Corner(tag, UDim.new(1, 0))
		UIUtil.Stroke(tag, border, 1.5, 0.2)
		UIUtil.Create("UIPadding", {
			PaddingLeft = UDim.new(0, 6),
			PaddingRight = UDim.new(0, 6),
			Parent = tag,
		})

		local envelope = {
			Id = info.Id,
			Email = email,
			Root = root,
			Scale = scale,
			Body = body,
			Dot = dot,
			Tag = tag,
			Target = target,
			X = x,
			Y = y,
			Born = os.clock(),
			Lifetime = lifetime,
			Phase = random:NextNumber(0, math.pi * 2),
			Hurry = false,
			Done = false,
		}
		envelopes[info.Id] = envelope
		envelopeCount += 1
		refreshCounter()

		-- Arrivée en vol plané
		UIUtil.Tween(root, 0.75, { Position = target, Rotation = 0 }, Enum.EasingStyle.Back)
		UIUtil.Tween(scale, 0.75, { Scale = 1 }, Enum.EasingStyle.Back)
		ctx.Sound.Play("Mail", 1 + random:NextNumber() * 0.15)

		-- Clic : on ouvre le mail
		ctx.Connect(root.Activated, function()
			if envelope.Done or not ctx.IsAlive() then
				return
			end
			local position = root.Position
			positions[envelope.Id] = position
			lastPosition = position
			ctx.ClaimSpawn(envelope.Id)
			ctx.Sound.Play("Mail", 1.4)
			if effectsOn() then
				ctx.Effects.Burst(container, position, blue, 10)
				ctx.Effects.Burst(container, position, nil, 6)
			end
			removeEnvelope(envelope, true)
			openPopup(envelope.Email, envelope.X, envelope.Y)
			local id = envelope.Id
			task.delay(6, function()
				positions[id] = nil
			end)
		end)
	end

	-- Animation de toutes les enveloppes (une seule connexion)
	ctx.OnRender(function()
		if envelopeCount <= 0 then
			return
		end
		local now = os.clock()
		for _, envelope in pairs(envelopes) do
			local age = now - envelope.Born
			local left = envelope.Lifetime - age
			if left <= 0 then
				removeEnvelope(envelope, false)
			else
				local t = now + envelope.Phase
				if left < HURRY_TIME then
					-- Pressée : elle s'agite et l'étiquette vire au rouge
					if not envelope.Hurry then
						envelope.Hurry = true
						envelope.Tag.Text = "📩 Vite, lis-moi !"
						envelope.Tag.BackgroundColor3 = Theme.Colors.Red
						envelope.Tag.TextColor3 = Color3.new(1, 1, 1)
					end
					envelope.Body.Rotation = math.sin(t * 24) * 10
					envelope.Dot.Size = UDim2.fromOffset(22, 22) + UDim2.fromOffset(math.sin(t * 16) * 4, math.sin(t * 16) * 4)
				else
					envelope.Body.Rotation = math.sin(t * 3) * 6
				end
				-- Flotte doucement une fois arrivée
				if age > 0.8 then
					envelope.Root.Position = envelope.Target + UDim2.fromOffset(0, math.sin(t * 2.2) * 5)
				end
			end
		end
	end)

	ctx.OnSpawn("Email", spawnEmail)

	-- Bonus confirmé : "+X" à côté du mail
	ctx.OnBonus("Email", function(payload)
		if not ctx.IsAlive() then
			return
		end
		local position = (payload.SpawnId and positions[payload.SpawnId]) or lastPosition
		ctx.FloatText(container, position, "+" .. ctx.Format.Format(tonumber(payload.Amount) or 0), blue, 40)
	end)
end

function Email.Stop(_ctx)
	-- Enveloppes, fenêtre et compteur vivent dans ctx.Container
	-- (détruit par le StimulusManager)
end

return Email
