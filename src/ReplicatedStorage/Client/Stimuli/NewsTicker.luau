--[[
	NewsTicker (ModuleScript - stimulus)
	Emplacement : ReplicatedStorage > Client > Stimuli > NewsTicker

	Bandeau rouge "FLASH INFO" tout en haut de l'écran : des titres
	absurdes (en majuscules, gras, italique) défilent de droite à gauche,
	à l'infini, séparés par des "•". Survoler le bandeau le ralentit (pour
	lire tranquillement). Cliquer sur un titre = Interact("Headline") : le
	serveur limite les récompenses (Config.Interactions.Headline) et le
	"+X" confirmé (OnBonus "Headline") s'affiche juste sous le bandeau.
]]

local Players = game:GetService("Players")
local TextService = game:GetService("TextService")

local NewsTicker = {}
NewsTicker.Slot = "Ticker"

local HEIGHT = 30 -- hauteur du slot (pixels "design")
local LEFT_W = 136 -- bloc "FLASH INFO"
local RIGHT_W = 62 -- bloc horloge
local TEXT_SIZE = 19
local SEPARATOR_W = 46
local SPEED = 95 -- pixels "design" par seconde
local SLOW_SPEED = 28 -- vitesse quand la souris survole le bandeau
local MAX_ITEMS = 14 -- sécurité : titres vivants au maximum
local URGENT_CHANCE = 1 / 7

-- Titres absurdes (déjà en majuscules)
local HEADLINES = {
	"LES GRENOUILLES ONT DISPARU... OU PAS, IL N'EST PAS SÛR",
	"UN HOMME CLIQUE DEPUIS 3 JOURS, IL VA BIEN",
	"LES DOUCHES FROIDES SONT-ELLES LE FUTUR ?",
	"UN PIGEON ÉLU MAIRE D'UN PETIT VILLAGE, IL PROMET PLUS DE MIETTES",
	"ALERTE : LE LUNDI ARRIVE ENCORE CETTE SEMAINE",
	"DES SCIENTIFIQUES CONFIRMENT QUE LE CANAPÉ EST TRÈS CONFORTABLE",
	"UNE CHAUSSETTE RETROUVÉE APRÈS 12 ANS DE CAVALE",
	"LE WIFI TOMBE EN PANNE, UNE FAMILLE DÉCOUVRE QU'ELLE A UN JARDIN",
	"UN CHAT REFUSE DE DESCENDRE DU CLAVIER, LES NÉGOCIATIONS ÉCHOUENT",
	"LA LUNE ANNONCE UNE PAUSE CARRIÈRE, LES MARÉES INQUIÈTES",
	"UN ESCARGOT BAT LE RECORD DU MONDE DE LENTEUR... POUR LA 3E FOIS",
	"LES NUAGES EN GRÈVE : SOLEIL PAR DÉFAUT TOUTE LA SEMAINE",
	"UN BOUTON A ÉTÉ CLIQUÉ, PERSONNE NE SAIT POURQUOI",
	"LA DOPAMINE ATTEINT UN NIVEAU HISTORIQUE, LES ÉCONOMISTES APPLAUDISSENT",
	"UNE BAGUETTE DE PAIN ÉLUE MEILLEUR ACCESSOIRE DE L'ANNÉE",
	"UN POISSON ROUGE OUBLIE SON PROPRE ANNIVERSAIRE, ENCORE",
	"LES CHERCHEURS SONT FORMELS : IL FAUT BOIRE DE L'EAU",
	"UN PAPY INVENTE LE CLIC À DEUX DOIGTS, LE MONDE S'INCLINE",
	"LA MACHINE À CAFÉ DU BUREAU PORTE PLAINTE POUR SURMENAGE",
	"UN CANARD TRAVERSE LA ROUTE : ON NE SAIT TOUJOURS PAS POURQUOI",
	"LES HARICOTS VERTS SE PLAIGNENT D'ÊTRE LAISSÉS DANS L'ASSIETTE",
	"UN NUAGE EN FORME DE HAMSTER APERÇU AU-DESSUS DE LA VILLE",
	"UN EXPERT : « CLIQUER, C'EST COMME RESPIRER, MAIS AVEC LE DOIGT »",
	"UN ENFANT DEMANDE « POURQUOI ? » 400 FOIS, SES PARENTS PARTENT EN VACANCES",
	"UNE PLANTE VERTE ARROSÉE DEUX FOIS LE MÊME JOUR, ELLE EST SOUS LE CHOC",
	"LE SOLEIL SE LÈVE À L'EST, PERSONNE N'EST SURPRIS",
	"UN LOGO QUI REBONDIT FRÔLE LE COIN, LE PAYS RETIENT SON SOUFFLE",
	"RECORD : 47 ONGLETS OUVERTS, L'ORDINATEUR DEMANDE PITIÉ",
	"UNE PIZZA À L'ANANAS DIVISE UN VILLAGE, LE CONSEIL MUNICIPAL SE RÉUNIT",
	"LES ÉTOILES DORÉES SONT ÉPHÉMÈRES, RAPPELLENT LES PHILOSOPHES",
	"UN HAMSTER COURT 30 KM DANS SA ROUE, IL N'EST TOUJOURS ARRIVÉ NULLE PART",
	"LA SIESTE RECONNUE SPORT OLYMPIQUE, LA FRANCE GRANDE FAVORITE",
	"UNE MOUCHE ENTRE DANS LE SALON : PANIQUE GÉNÉRALE",
	"LE PAPIER BULLE ENFIN RECONNU COMME THÉRAPIE",
	"UN ROBOT ASPIRATEUR DEVIENT CONSCIENT, IL VEUT JUSTE ÊTRE AIMÉ",
	"SONDAGE : 100 % DES PERSONNES INTERROGÉES ONT RÉPONDU AU SONDAGE",
	"LES GRENOUILLES SONT REVENUES, ELLES ÉTAIENT JUSTE EN VACANCES",
	"UNE TARTINE TOMBE CÔTÉ BEURRE, LES SCIENTIFIQUES N'EN REVIENNENT PAS",
	"MÉTÉO : 100 % DE CHANCES QU'IL FASSE UN TEMPS",
	"UN GARÇON DIT « ENCORE 5 MINUTES », IL EST 3 HEURES DU MATIN",
	"LES CHAUSSONS EN GRÈVE : ILS EXIGENT DES PIEDS PLUS PROPRES",
	"LA BOURSE DE LA DOPAMINE MONTE, DESCEND, PUIS REMONTE. AFFAIRE À SUIVRE",
	"UN TOURNESOL SE TROMPE ET FIXE LA LAMPE DU SALON DEPUIS MARDI",
	"L'OCÉAN RAPPELLE QU'IL EST TOUJOURS LÀ, SI JAMAIS",
	"UN MOUTON COMPTE DES HUMAINS POUR S'ENDORMIR, IL EN EST À 8 MILLIARDS",
	"UNE LICORNE APERÇUE EN BANLIEUE, C'ÉTAIT UN CHEVAL AVEC UN CORNET DE GLACE",
}

-- Petites réactions quand on clique sur un titre
local REACTIONS = { "😂", "🤯", "😱", "🤔", "👀", "🙃", "😮", "🧐", "📰", "😳" }

function NewsTicker.Start(ctx)
	local UIUtil = ctx.UIUtil
	local Theme = ctx.Theme
	local container: Frame = ctx.Container
	local overlay: Frame = ctx.Overlay
	local random = Random.new()

	local red = Theme.Colors.Red
	local darkRed = Color3.fromRGB(150, 12, 18)
	local yellow = Theme.Colors.Yellow
	local white = Color3.new(1, 1, 1)

	-- Police gras + italique (BuilderSans)
	local italicFont = Font.new("rbxasset://fonts/families/BuilderSans.json", Enum.FontWeight.Bold, Enum.FontStyle.Italic)

	------------------------------------------------------------------
	-- Titres "dynamiques" (utilisent l'état du joueur)
	------------------------------------------------------------------
	local function stat(name: string): number
		local data = ctx.State.Data
		local stats = data and data.Stats
		return (stats and tonumber(stats[name])) or 0
	end

	local function playerName(): string
		local player = Players.LocalPlayer
		local name = player and player.DisplayName or "QUELQU'UN"
		return string.upper(name)
	end

	local DYNAMIC = {
		function()
			local data = ctx.State.Data
			local amount = data and tonumber(data.Dopamine) or 0
			return "RECORD : UN JOUEUR POSSÈDE " .. ctx.Format.Format(amount) .. " DOPAMINE, SES VOISINS INQUIETS"
		end,
		function()
			return "LE BOUTON « CLIQUE-MOI » A ÉTÉ CLIQUÉ " .. ctx.Format.WithSpaces(stat("TotalClicks")) .. " FOIS, IL DEMANDE DES VACANCES"
		end,
		function()
			return "EXCLUSIF : " .. playerName() .. " N'A PAS CLIGNÉ DES YEUX DEPUIS 20 MINUTES"
		end,
		function()
			return "INTERVIEW : " .. playerName() .. " AFFIRME POUVOIR « ARRÊTER QUAND IL VEUT »"
		end,
	}

	-- Paquet mélangé : chaque titre passe une fois avant de revenir
	local deck: { any } = {}
	local function refillDeck()
		table.clear(deck)
		for _, text in ipairs(HEADLINES) do
			table.insert(deck, text)
		end
		for _, generator in ipairs(DYNAMIC) do
			table.insert(deck, generator)
		end
		for i = #deck, 2, -1 do
			local j = random:NextInteger(1, i)
			deck[i], deck[j] = deck[j], deck[i]
		end
	end

	local function nextHeadline(): string
		if #deck == 0 then
			refillDeck()
		end
		local entry = table.remove(deck)
		if type(entry) == "function" then
			local ok, text = pcall(entry)
			if ok and type(text) == "string" then
				return text
			end
			return HEADLINES[random:NextInteger(1, #HEADLINES)]
		end
		return entry
	end

	------------------------------------------------------------------
	-- Construction du bandeau
	------------------------------------------------------------------
	local strip = UIUtil.Create("Frame", {
		Name = "Strip",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = red,
		BorderSizePixel = 0,
		ZIndex = 1,
		Parent = container,
	})
	UIUtil.Gradient(strip, ColorSequence.new(Color3.new(1, 1, 1), Color3.fromRGB(200, 200, 200)), 90)
	-- Liseré sombre en bas
	UIUtil.Create("Frame", {
		Name = "BottomLine",
		Size = UDim2.new(1, 0, 0, 2),
		Position = UDim2.new(0, 0, 1, -2),
		BackgroundColor3 = darkRed,
		BorderSizePixel = 0,
		ZIndex = 6,
		Parent = container,
	})

	-- Zone de défilement
	local clip = UIUtil.Create("Frame", {
		Name = "Clip",
		Size = UDim2.new(1, -(LEFT_W + RIGHT_W), 1, 0),
		Position = UDim2.fromOffset(LEFT_W, 0),
		BackgroundTransparency = 1,
		ClipsDescendants = true,
		ZIndex = 2,
		Parent = container,
	})

	-- Bloc gauche "FLASH INFO" (blanc, bord en biais)
	local left = UIUtil.Create("Frame", {
		Name = "FlashInfo",
		Size = UDim2.new(0, LEFT_W - 12, 1, 0),
		BackgroundColor3 = white,
		BorderSizePixel = 0,
		ZIndex = 4,
		Parent = container,
	})
	local slant = UIUtil.Create("Frame", {
		Name = "Slant",
		Size = UDim2.fromOffset(22, HEIGHT + 20),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(1, 0, 0.5, 0),
		Rotation = 18,
		BackgroundColor3 = white,
		BorderSizePixel = 0,
		ZIndex = 4,
		Parent = left,
	})
	local liveDot = UIUtil.Create("Frame", {
		Name = "LiveDot",
		Size = UDim2.fromOffset(10, 10),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0, 14, 0.5, 0),
		BackgroundColor3 = red,
		BorderSizePixel = 0,
		ZIndex = 5,
		Parent = left,
	})
	UIUtil.Corner(liveDot, UDim.new(1, 0))
	local flashLabel = UIUtil.Create("TextLabel", {
		Name = "Title",
		Size = UDim2.new(1, -24, 1, 0),
		Position = UDim2.fromOffset(24, 0),
		BackgroundTransparency = 1,
		Text = "FLASH INFO",
		TextColor3 = red,
		TextSize = 18,
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = 5,
		Parent = left,
	})
	flashLabel.FontFace = italicFont

	-- Bloc droit : horloge
	local right = UIUtil.Create("Frame", {
		Name = "Clock",
		Size = UDim2.new(0, RIGHT_W, 1, 0),
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.fromScale(1, 0),
		BackgroundColor3 = darkRed,
		BorderSizePixel = 0,
		ZIndex = 4,
		Parent = container,
	})
	local clockLabel = UIUtil.Create("TextLabel", {
		Name = "Time",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Font = Theme.Fonts.Mono,
		Text = "--:--",
		TextColor3 = white,
		TextSize = 16,
		ZIndex = 5,
		Parent = right,
	})

	-- Bouton invisible qui couvre tout le bandeau (clic / survol)
	local button = UIUtil.Create("TextButton", {
		Name = "HitArea",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		AutoButtonColor = false,
		Text = "",
		ZIndex = 10,
		Parent = container,
	})

	------------------------------------------------------------------
	-- Titres qui défilent
	------------------------------------------------------------------
	local items: { any } = {}

	-- Pixels réels par pixel "design" (la toile est mise à l'échelle)
	local function designWidth(guiObject: GuiObject): number
		local absHeight = container.AbsoluteSize.Y
		if absHeight <= 0 then
			return 1280
		end
		return guiObject.AbsoluteSize.X * (HEIGHT / absHeight)
	end

	local function measure(text: string): number
		local ok, size = pcall(function()
			return TextService:GetTextSize(text, TEXT_SIZE, Enum.Font.BuilderSansBold, Vector2.new(10000, HEIGHT))
		end)
		if ok and size then
			return size.X + 8 -- un peu de marge pour l'italique
		end
		return #text * 11
	end

	local function addItem(x: number)
		local urgent = random:NextNumber() < URGENT_CHANCE
		local text = nextHeadline()
		if urgent then
			text = "🚨 URGENT : " .. text
		end
		local textWidth = measure(text)
		local width = textWidth + SEPARATOR_W

		local frame = UIUtil.Create("Frame", {
			Name = "Headline",
			Size = UDim2.fromOffset(width, HEIGHT),
			Position = UDim2.fromOffset(x, 0),
			BackgroundTransparency = 1,
			ZIndex = 2,
			Parent = clip,
		})
		local label = UIUtil.Create("TextLabel", {
			Name = "Text",
			Size = UDim2.fromOffset(textWidth, HEIGHT - 2),
			Position = UDim2.fromOffset(0, 0),
			BackgroundTransparency = 1,
			Text = text,
			TextColor3 = urgent and yellow or white,
			TextSize = TEXT_SIZE,
			TextXAlignment = Enum.TextXAlignment.Left,
			ZIndex = 3,
			Parent = frame,
		})
		label.FontFace = italicFont
		UIUtil.Create("TextLabel", {
			Name = "Separator",
			Size = UDim2.fromOffset(SEPARATOR_W, HEIGHT - 2),
			Position = UDim2.fromOffset(textWidth, 0),
			BackgroundTransparency = 1,
			Font = Theme.Fonts.Title,
			Text = "•",
			TextColor3 = yellow,
			TextSize = 22,
			ZIndex = 3,
			Parent = frame,
		})

		table.insert(items, {
			Frame = frame,
			Label = label,
			Width = width,
			X = x,
			Urgent = urgent,
			Alerted = false,
			BaseColor = urgent and yellow or white,
		})
	end

	-- Alerte "URGENT" : le bloc gauche clignote en jaune
	local alertUntil = 0
	local function triggerAlert()
		alertUntil = os.clock() + 2.5
		flashLabel.Text = "URGENT !"
		ctx.Sound.Play("Notif", 0.8)
	end

	local speed = SPEED
	local targetSpeed = SPEED

	ctx.Connect(button.MouseEnter, function()
		targetSpeed = SLOW_SPEED
	end)
	ctx.Connect(button.MouseLeave, function()
		targetSpeed = SPEED
	end)

	ctx.OnRender(function(dt: number)
		dt = math.min(dt, 0.1)
		speed += (targetSpeed - speed) * math.min(1, dt * 6)
		local clipWidth = designWidth(clip)

		-- Déplacement + suppression des titres sortis à gauche
		local i = 1
		while i <= #items do
			local item = items[i]
			item.X -= speed * dt
			if item.X + item.Width < -4 then
				item.Frame:Destroy()
				table.remove(items, i)
			else
				item.Frame.Position = UDim2.fromOffset(item.X, 0)
				if item.Urgent and not item.Alerted and item.X < clipWidth * 0.6 then
					item.Alerted = true
					triggerAlert()
				end
				i += 1
			end
		end

		-- Ajout de nouveaux titres à droite
		local guard = 0
		while guard < 4 and #items < MAX_ITEMS do
			local last = items[#items]
			local edge = last and (last.X + last.Width) or clipWidth * 0.3
			if last and edge > clipWidth + 30 then
				break
			end
			addItem(edge)
			guard += 1
		end

		-- Bloc gauche : point "en direct" qui clignote, alerte urgente
		local now = os.clock()
		liveDot.BackgroundTransparency = (math.floor(now * 2) % 2 == 0) and 0 or 0.7
		if now < alertUntil then
			local blink = math.floor(now * 6) % 2 == 0
			left.BackgroundColor3 = blink and yellow or white
			slant.BackgroundColor3 = left.BackgroundColor3
			flashLabel.TextColor3 = blink and Theme.Colors.TextDark or red
		elseif flashLabel.Text ~= "FLASH INFO" then
			flashLabel.Text = "FLASH INFO"
			left.BackgroundColor3 = white
			slant.BackgroundColor3 = white
			flashLabel.TextColor3 = red
		end
	end)

	-- Horloge (heure locale)
	task.spawn(function()
		while ctx.IsAlive() do
			local now = os.date("*t")
			if now and now.hour and now.min then
				clockLabel.Text = string.format("%02d:%02d", now.hour, now.min)
			end
			task.wait(5)
		end
	end)

	------------------------------------------------------------------
	-- Clic sur un titre
	------------------------------------------------------------------
	local interaction = ctx.Config.Interactions and ctx.Config.Interactions.Headline
	local cooldown = (interaction and tonumber(interaction.Cooldown)) or 8
	local lastInteract = -math.huge
	local lastScaleX = 0.5

	local function effectsOn(): boolean
		local data = ctx.State.Data
		return not (data and data.Settings and data.Settings.Effects == false)
	end

	ctx.Connect(button.Activated, function(input)
		-- Position X du clic (pixels réels ; milieu du bandeau par défaut)
		local px: number = clip.AbsolutePosition.X + clip.AbsoluteSize.X * 0.5
		if typeof(input) == "Instance" and input:IsA("InputObject") then
			px = input.Position.X
		end

		-- Titre sous le curseur (ou le plus proche)
		local hit, bestDistance = nil, math.huge
		for _, item in ipairs(items) do
			local absX = item.Frame.AbsolutePosition.X
			local absW = item.Frame.AbsoluteSize.X
			local distance = 0
			if px < absX then
				distance = absX - px
			elseif px > absX + absW then
				distance = px - (absX + absW)
			end
			if distance < bestDistance then
				hit, bestDistance = item, distance
			end
		end

		-- Position du clic sur la toile (échelle 0..1 de l'overlay)
		local overlayWidth = overlay.AbsoluteSize.X
		if overlayWidth > 0 then
			lastScaleX = math.clamp((px - overlay.AbsolutePosition.X) / overlayWidth, 0.05, 0.95)
		end

		ctx.Sound.Play("Click", 1.3 + random:NextNumber() * 0.2)
		if hit then
			local label = hit.Label
			label.TextColor3 = Theme.Colors.TextDark
			label.BackgroundTransparency = 0
			label.BackgroundColor3 = yellow
			label.Position = UDim2.fromOffset(0, -3)
			UIUtil.Tween(label, 0.35, { Position = UDim2.fromOffset(0, 0) }, Enum.EasingStyle.Bounce)
			task.delay(0.7, function()
				if label.Parent then
					label.TextColor3 = hit.BaseColor
					UIUtil.Tween(label, 0.25, { BackgroundTransparency = 1 })
				end
			end)
		end

		-- Petite réaction sous le bandeau
		if effectsOn() then
			ctx.FloatText(overlay, UDim2.new(lastScaleX, 0, 0, 52), REACTIONS[random:NextInteger(1, #REACTIONS)], white, 30)
		end

		-- Récompense (le serveur a son propre délai ; on évite juste de spammer)
		local now = os.clock()
		if now - lastInteract >= cooldown then
			lastInteract = now
			ctx.Interact("Headline")
		end
	end)

	-- Bonus confirmé par le serveur
	ctx.OnBonus("Headline", function(payload)
		if not ctx.IsAlive() then
			return
		end
		local amount = tonumber(payload.Amount) or 0
		ctx.FloatText(overlay, UDim2.new(lastScaleX, 0, 0, 84), "+" .. ctx.Format.Format(amount), Theme.Colors.Gold, 34)
	end)
end

function NewsTicker.Stop(_ctx)
	-- Tout vit dans ctx.Container (détruit par le StimulusManager) ;
	-- les textes flottants de l'overlay se détruisent tout seuls.
end

return NewsTicker
