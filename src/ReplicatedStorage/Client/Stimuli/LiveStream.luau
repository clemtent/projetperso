--[[
	LiveStream (ModuleScript - stimulus)
	Emplacement : ReplicatedStorage > Client > Stimuli > LiveStream

	Faux live "ASMR mukbang" (slot L1, 288x190) : badge "🔴 EN DIRECT",
	compteur de spectateurs (qui grimpe avec l'amélioration "Abonnés"),
	un gourmand 😋 qui mange une assiette d'emojis un par un avec des
	"CRUNCH !" / "MIAM" qui éclatent, des miettes, des cœurs qui montent,
	et un bouton "Suivre" pour le plaisir.

	Avec la Feature "LiveChat", une colonne de chat apparaît à droite :
	pseudos rigolos, messages absurdes, dons... plus il y a d'abonnés,
	plus le chat s'emballe.

	Purement visuel : aucune récompense ici (la production est dans la
	Dopamine par seconde).
]]

local Debris = game:GetService("Debris")

local LiveStream = {}
LiveStream.Slot = "L1"

-- Disposition (pixels "design", carte rentrée de 2 px)
local CARD_W, CARD_H = 284, 186
local VIDEO_X, VIDEO_Y = 6, 6
local VIDEO_H = 146
local CHAT_W = 100
local GAP = 4
local TABLE_Y = 110 -- haut de la table dans la vidéo
local PLATE_Y = 116
local MOUTH_Y = 84
local MAX_CHAT = 10
local MAX_HEARTS = 6

local FOODS = { "🥪", "🍟", "🍔", "🌭", "🍕", "🥓", "🍗", "🌮", "🍩", "🥐", "🍪", "🌯" }
local FOOD_OFFSETS = { -44, -22, 0, 22, 44 }

local CRUNCH_WORDS = { "CRUNCH !", "MIAM", "CROC !", "*crounch*", "SLURP", "CRAC !", "NOM NOM", "CRISP !", "MMMH", "SCROUNCH" }
local CRUNCH_COLORS = {
	Color3.fromRGB(255, 214, 40),
	Color3.fromRGB(255, 80, 150),
	Color3.fromRGB(0, 210, 255),
	Color3.fromRGB(255, 255, 255),
	Color3.fromRGB(130, 255, 120),
}

local HEARTS = { "❤️", "💜", "💖", "😍", "🔥", "👏" }

local NAMES = {
	"Kevin_du_75", "xX_Nugget_Xx", "Mamie_Gaming", "LeChatDuVoisin", "BaguetteMan", "Tartiflette99",
	"MrPatate", "Choupette", "DarkSasuke42", "Poulet_Braisé", "Zinzin_78", "Croquette", "SushiLover",
	"Tonton_Jean", "Lulu_ASMR", "PatateDouce", "Bichon_Fou", "Crêpe_Party", "Moustache_Pro",
	"Raclette4Life", "Gratin2Pâtes", "Ninja_du_Dimanche", "Fromage_Fou", "LaTeteDansLeFrigo",
}
local NAME_COLORS = { "#FF6B9A", "#6BD5FF", "#FFD34D", "#9DFF6B", "#C38BFF", "#FF9F45", "#5CFFD1" }

local MESSAGES = {
	"W", "+1", "incroyable", "🔥🔥", "c'est quoi ce live", "le crunch était parfait", "encore !!",
	"j'ai faim maintenant", "il mange à 3h du mat ?", "premier", "ASMR de qualité", "MIAM",
	"c'est tellement satisfaisant", "je regarde au lieu de réviser", "mdr", "😭😭", "le son 🤤",
	"abonné !", "maman si tu vois ça coucou", "il a même pas mâché", "CRUNCH", "trop bien", "respect",
	"et la sauce ??", "GG", "🥪🥪🥪", "qui est là depuis le début ?", "j'ai lâché mon goûter",
	"5 étoiles", "mon moment préféré", "L", "il va finir l'assiette ??", "trop fort le monsieur",
	"je suis au régime 😭", "le micro 😳", "c'est l'heure du goûter", "on veut des frites !", "👀",
	"j'entends le crunch d'ici", "reviens manger chez moi", "ratio", "💯", "je m'endors 😴",
}
local REACTIONS = { "CRUNCH 🔥", "le son 🤤🤤", "OUIIII", "MIAM", "encore une !", "🔥🔥🔥", "W crunch" }
local DONATION_AMOUNTS = { 5, 10, 20, 50, 100, 500 }

function LiveStream.Start(ctx)
	local UI = ctx.UIUtil
	local Theme = ctx.Theme
	local Format = ctx.Format
	local random = Random.new()

	local function effectsOn(): boolean
		local data = ctx.State.Data
		return not (data and data.Settings and data.Settings.Effects == false)
	end

	local function followers(): number
		return ctx.GetLevel("Followers") or 0
	end

	local function hasChat(): boolean
		return ctx.HasFeature("LiveChat") == true
	end

	------------------------------------------------------------------
	-- Carte
	------------------------------------------------------------------
	local card = UI.Create("Frame", {
		Name = "Card",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.new(1, -4, 1, -4),
		BackgroundColor3 = Color3.fromRGB(24, 21, 32),
		BorderSizePixel = 0,
		Parent = ctx.Container,
	})
	UI.Corner(card, 14)
	UI.Stroke(card, Theme.Colors.CardBorder, 2)

	local function videoWidth(chat: boolean): number
		if chat then
			return CARD_W - VIDEO_X * 2 - CHAT_W - GAP
		end
		return CARD_W - VIDEO_X * 2
	end

	------------------------------------------------------------------
	-- Vidéo
	------------------------------------------------------------------
	local video = UI.Create("Frame", {
		Name = "Video",
		Position = UDim2.fromOffset(VIDEO_X, VIDEO_Y),
		Size = UDim2.fromOffset(videoWidth(hasChat()), VIDEO_H),
		BackgroundColor3 = Color3.new(1, 1, 1),
		BorderSizePixel = 0,
		ClipsDescendants = true,
		Parent = card,
	})
	UI.Corner(video, 10)
	UI.Gradient(video, ColorSequence.new(Color3.fromRGB(255, 222, 186), Color3.fromRGB(255, 160, 118)), 90)

	-- Guirlande lumineuse en haut du mur
	local bulbs: { Frame } = {}
	local BULB_COLORS = {
		Color3.fromRGB(255, 90, 120),
		Color3.fromRGB(255, 210, 60),
		Color3.fromRGB(90, 220, 255),
		Color3.fromRGB(150, 255, 120),
		Color3.fromRGB(200, 120, 255),
	}
	for i = 1, 9 do
		local x = (i - 0.5) / 9
		local bulb = UI.Create("Frame", {
			Name = "Bulb",
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.new(x, 0, 0, 30 + math.sin(x * math.pi) * 6),
			Size = UDim2.fromOffset(6, 6),
			BackgroundColor3 = BULB_COLORS[(i - 1) % #BULB_COLORS + 1],
			BorderSizePixel = 0,
			ZIndex = 1,
			Parent = video,
		})
		UI.Corner(bulb, UDim.new(1, 0))
		table.insert(bulbs, bulb)
	end

	-- Enseigne néon "MIAM" sur le mur
	local neonSign = UI.Label({
		Name = "Neon",
		Text = "MIAM ✨",
		Font = Theme.Fonts.Title,
		TextColor3 = Color3.fromRGB(255, 70, 160),
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -10, 0, 40),
		Size = UDim2.fromOffset(60, 16),
		MaxTextSize = 14,
		Rotation = 6,
		ZIndex = 1,
		Parent = video,
	})
	local neonStroke = UI.Stroke(neonSign, Color3.fromRGB(255, 190, 230), 1.5, 0.3)
	neonStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual

	-- Le gourmand (derrière la table)
	local face = UI.Create("TextLabel", {
		Name = "Face",
		Text = "😋",
		TextSize = 58,
		Font = Theme.Fonts.Body,
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 0, TABLE_Y + 16),
		Size = UDim2.fromOffset(70, 70),
		ZIndex = 2,
		Parent = video,
	})

	-- Table
	local tableFrame = UI.Create("Frame", {
		Name = "Table",
		Position = UDim2.fromOffset(0, TABLE_Y),
		Size = UDim2.new(1, 0, 0, VIDEO_H - TABLE_Y),
		BackgroundColor3 = Color3.fromRGB(150, 96, 62),
		BorderSizePixel = 0,
		ZIndex = 3,
		Parent = video,
	})
	UI.Create("Frame", {
		Name = "Edge",
		Size = UDim2.new(1, 0, 0, 4),
		BackgroundColor3 = Color3.fromRGB(186, 128, 84),
		BorderSizePixel = 0,
		ZIndex = 3,
		Parent = tableFrame,
	})

	-- Micro ASMR
	UI.Create("TextLabel", {
		Name = "Mic",
		Text = "🎙️",
		TextSize = 26,
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.13, 0, 0, TABLE_Y + 8),
		Size = UDim2.fromOffset(30, 30),
		ZIndex = 5,
		Parent = video,
	})

	-- Assiette
	local plate = UI.Create("Frame", {
		Name = "Plate",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 0, PLATE_Y),
		Size = UDim2.fromOffset(122, 22),
		BackgroundColor3 = Color3.fromRGB(252, 252, 252),
		BorderSizePixel = 0,
		ZIndex = 4,
		Parent = video,
	})
	UI.Corner(plate, UDim.new(1, 0))
	UI.Stroke(plate, Color3.fromRGB(190, 190, 200), 1.5)
	local rim = UI.Create("Frame", {
		Name = "Rim",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.new(1, -24, 1, -8),
		BackgroundColor3 = Color3.fromRGB(236, 236, 242),
		BorderSizePixel = 0,
		ZIndex = 4,
		Parent = plate,
	})
	UI.Corner(rim, UDim.new(1, 0))

	-- Aliments (réutilisés à chaque nouvelle assiette)
	local foods: { TextLabel } = {}
	local foodScales: { UIScale } = {}
	local function foodHome(index: number): UDim2
		return UDim2.new(0.5, FOOD_OFFSETS[index], 0, PLATE_Y - 6)
	end
	for i = 1, #FOOD_OFFSETS do
		local food = UI.Create("TextLabel", {
			Name = "Food",
			Text = FOODS[random:NextInteger(1, #FOODS)],
			TextSize = 26,
			BackgroundTransparency = 1,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = foodHome(i),
			Size = UDim2.fromOffset(30, 30),
			Rotation = random:NextNumber(-12, 12),
			ZIndex = 5 + i % 2,
			Parent = video,
		})
		foods[i] = food
		foodScales[i] = UI.Create("UIScale", { Parent = food })
	end

	-- Bandeau "EN DIRECT" + spectateurs
	local liveBadge = UI.Create("TextLabel", {
		Name = "Live",
		Text = "🔴 EN DIRECT",
		Font = Theme.Fonts.Title,
		TextSize = 11,
		TextColor3 = Color3.new(1, 1, 1),
		BackgroundColor3 = Color3.fromRGB(230, 30, 45),
		AutomaticSize = Enum.AutomaticSize.X,
		Size = UDim2.fromOffset(0, 18),
		Position = UDim2.fromOffset(6, 6),
		BorderSizePixel = 0,
		ZIndex = 8,
		Parent = video,
	})
	UI.Corner(liveBadge, 5)
	UI.Create("UIPadding", { PaddingLeft = UDim.new(0, 5), PaddingRight = UDim.new(0, 6), Parent = liveBadge })
	local liveScale = UI.Create("UIScale", { Parent = liveBadge })

	local viewersLabel = UI.Create("TextLabel", {
		Name = "Viewers",
		Text = "👁 0",
		Font = Theme.Fonts.Number,
		TextSize = 11,
		TextColor3 = Color3.new(1, 1, 1),
		BackgroundColor3 = Color3.new(0, 0, 0),
		BackgroundTransparency = 0.45,
		AutomaticSize = Enum.AutomaticSize.X,
		Size = UDim2.fromOffset(0, 18),
		Position = UDim2.fromOffset(94, 6),
		BorderSizePixel = 0,
		ZIndex = 8,
		Parent = video,
	})
	UI.Corner(viewersLabel, 5)
	UI.Create("UIPadding", { PaddingLeft = UDim.new(0, 5), PaddingRight = UDim.new(0, 6), Parent = viewersLabel })

	-- Réserve de mots "CRUNCH" (réutilisés)
	local popLabels: { TextLabel } = {}
	local popIndex = 0
	for i = 1, 3 do
		local label = UI.Create("TextLabel", {
			Name = "Pop" .. i,
			Text = "",
			Font = Theme.Fonts.Title,
			TextSize = 20,
			TextColor3 = Color3.new(1, 1, 1),
			TextTransparency = 1,
			BackgroundTransparency = 1,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Size = UDim2.fromOffset(110, 26),
			ZIndex = 9,
			Parent = video,
		})
		local stroke = UI.Stroke(label, Color3.fromRGB(40, 20, 30), 2, 1)
		stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
		UI.Create("UIScale", { Parent = label })
		popLabels[i] = label
	end

	local function popWord(text: string?)
		popIndex = popIndex % #popLabels + 1
		local label = popLabels[popIndex]
		local stroke = label:FindFirstChildOfClass("UIStroke")
		local scale = label:FindFirstChildOfClass("UIScale")
		local side = random:NextNumber() < 0.5 and -1 or 1
		local start = UDim2.new(0.5, side * random:NextInteger(28, 46), 0, MOUTH_Y - 8)
		label.Text = text or CRUNCH_WORDS[random:NextInteger(1, #CRUNCH_WORDS)]
		label.TextColor3 = CRUNCH_COLORS[random:NextInteger(1, #CRUNCH_COLORS)]
		label.Position = start
		label.Rotation = random:NextNumber(-16, 16)
		label.TextTransparency = 0
		if stroke then
			stroke.Transparency = 0
			UI.Tween(stroke, 0.5, { Transparency = 1 }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		end
		if scale then
			scale.Scale = 0.3
			UI.Tween(scale, 0.22, { Scale = 1.15 }, Enum.EasingStyle.Back)
		end
		UI.Tween(label, 0.75, {
			Position = start + UDim2.fromOffset(side * 12, -26),
			TextTransparency = 1,
		}, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
	end

	-- Miettes (petits carrés qui tombent, détruits automatiquement)
	local function crumbs()
		if not effectsOn() then
			return
		end
		for _ = 1, 4 do
			local size = random:NextInteger(3, 5)
			local crumb = UI.Create("Frame", {
				Name = "Crumb",
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.new(0.5, random:NextInteger(-8, 8), 0, MOUTH_Y + 4),
				Size = UDim2.fromOffset(size, size),
				BackgroundColor3 = Color3.fromRGB(220, 160, 80),
				BorderSizePixel = 0,
				Rotation = random:NextNumber(0, 90),
				ZIndex = 7,
				Parent = video,
			})
			UI.Tween(crumb, 0.55, {
				Position = UDim2.new(0.5, random:NextInteger(-36, 36), 0, PLATE_Y - 4),
				Rotation = random:NextNumber(90, 360),
				BackgroundTransparency = 0.3,
			}, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
			Debris:AddItem(crumb, 0.6)
		end
	end

	-- Cœurs qui montent (réserve réutilisée)
	local hearts: { { Label: TextLabel, Start: number, Life: number, X: number, Sway: number } } = {}
	for i = 1, MAX_HEARTS do
		local label = UI.Create("TextLabel", {
			Name = "Heart" .. i,
			Text = "❤️",
			TextSize = 16,
			BackgroundTransparency = 1,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Size = UDim2.fromOffset(20, 20),
			Visible = false,
			ZIndex = 8,
			Parent = video,
		})
		hearts[i] = { Label = label, Start = -math.huge, Life = 1.6, X = 0, Sway = 0 }
	end
	local function spawnHeart(emoji: string?)
		for _, heart in ipairs(hearts) do
			if not heart.Label.Visible then
				heart.Label.Text = emoji or HEARTS[random:NextInteger(1, #HEARTS)]
				heart.Start = os.clock()
				heart.Life = random:NextNumber(1.3, 2)
				heart.X = random:NextNumber(-14, 4)
				heart.Sway = random:NextNumber(0, math.pi * 2)
				heart.Label.Visible = true
				return
			end
		end
	end

	------------------------------------------------------------------
	-- Barre d'infos sous la vidéo : avatar, pseudo, bouton "Suivre"
	------------------------------------------------------------------
	local infoBar = UI.Create("Frame", {
		Name = "Info",
		Position = UDim2.fromOffset(VIDEO_X, VIDEO_Y + VIDEO_H + 4),
		Size = UDim2.new(1, -VIDEO_X * 2, 0, CARD_H - VIDEO_Y - VIDEO_H - 8),
		BackgroundTransparency = 1,
		Parent = card,
	})
	local avatar = UI.Create("TextLabel", {
		Name = "Avatar",
		Text = "🍔",
		TextSize = 14,
		BackgroundColor3 = Color3.fromRGB(255, 200, 90),
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.fromScale(0, 0.5),
		Size = UDim2.fromOffset(22, 22),
		BorderSizePixel = 0,
		Parent = infoBar,
	})
	UI.Corner(avatar, UDim.new(1, 0))
	UI.Stroke(avatar, Color3.fromRGB(145, 70, 255), 1.5)
	UI.Label({
		Name = "Streamer",
		Text = '<b>MangeTout_ASMR</b> <font color="#A8A2C0">· mukbang</font>',
		RichText = true,
		TextColor3 = Color3.new(1, 1, 1),
		TextXAlignment = Enum.TextXAlignment.Left,
		Position = UDim2.fromOffset(28, 2),
		Size = UDim2.new(1, -110, 1, -4),
		MaxTextSize = 12,
		Parent = infoBar,
	})
	local followButton = UI.Create("TextButton", {
		Name = "Follow",
		Text = "❤️ Suivre",
		Font = Theme.Fonts.Title,
		TextSize = 12,
		TextColor3 = Color3.new(1, 1, 1),
		BackgroundColor3 = Color3.fromRGB(145, 70, 255),
		AutoButtonColor = false,
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.fromScale(1, 0.5),
		Size = UDim2.fromOffset(76, 20),
		BorderSizePixel = 0,
		Parent = infoBar,
	})
	UI.Corner(followButton, UDim.new(1, 0))
	UI.AnimateButton(followButton, 1.06, 0.9)

	------------------------------------------------------------------
	-- Chat (Feature "LiveChat")
	------------------------------------------------------------------
	local chat = UI.Create("Frame", {
		Name = "Chat",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -VIDEO_X, 0, VIDEO_Y),
		Size = UDim2.fromOffset(CHAT_W, VIDEO_H),
		BackgroundColor3 = Color3.fromRGB(34, 30, 46),
		BorderSizePixel = 0,
		ClipsDescendants = true,
		Visible = hasChat(),
		Parent = card,
	})
	UI.Corner(chat, 10)
	UI.Label({
		Name = "Header",
		Text = "💬 CHAT",
		Font = Theme.Fonts.Title,
		TextColor3 = Color3.fromRGB(200, 190, 230),
		Position = UDim2.fromOffset(0, 2),
		Size = UDim2.new(1, 0, 0, 14),
		MaxTextSize = 11,
		ZIndex = 3,
		Parent = chat,
	})
	UI.Create("Frame", {
		Name = "HeaderLine",
		Position = UDim2.fromOffset(6, 17),
		Size = UDim2.new(1, -12, 0, 1),
		BackgroundColor3 = Color3.fromRGB(80, 70, 110),
		BorderSizePixel = 0,
		ZIndex = 3,
		Parent = chat,
	})
	local chatList = UI.Create("Frame", {
		Name = "Messages",
		Position = UDim2.fromOffset(0, 19),
		Size = UDim2.new(1, 0, 1, -21),
		BackgroundTransparency = 1,
		ClipsDescendants = true,
		Parent = chat,
	})
	UI.Create("UIListLayout", {
		SortOrder = Enum.SortOrder.LayoutOrder,
		VerticalAlignment = Enum.VerticalAlignment.Bottom,
		Padding = UDim.new(0, 2),
		Parent = chatList,
	})
	UI.Create("UIPadding", {
		PaddingLeft = UDim.new(0, 4),
		PaddingRight = UDim.new(0, 3),
		PaddingBottom = UDim.new(0, 2),
		Parent = chatList,
	})

	local chatMessages: { TextLabel } = {}
	local chatOrder = 0

	local function escape(text: string): string
		text = string.gsub(text, "&", "&amp;")
		text = string.gsub(text, "<", "&lt;")
		text = string.gsub(text, ">", "&gt;")
		return text
	end

	local function pushChat(name: string, message: string, highlight: Color3?)
		if not chat.Visible then
			return
		end
		chatOrder += 1
		local color = NAME_COLORS[random:NextInteger(1, #NAME_COLORS)]
		local label = UI.Create("TextLabel", {
			Name = "Msg",
			Text = '<font color="' .. color .. '"><b>' .. escape(name) .. "</b></font> " .. escape(message),
			RichText = true,
			Font = Theme.Fonts.Body,
			TextSize = 11,
			TextColor3 = Color3.new(1, 1, 1),
			TextWrapped = true,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextTransparency = 1,
			BackgroundColor3 = highlight or Color3.new(0, 0, 0),
			BackgroundTransparency = highlight and 0.55 or 1,
			BorderSizePixel = 0,
			AutomaticSize = Enum.AutomaticSize.Y,
			Size = UDim2.new(1, 0, 0, 0),
			LayoutOrder = chatOrder,
			Parent = chatList,
		})
		if highlight then
			UI.Corner(label, 4)
		end
		UI.Tween(label, 0.2, { TextTransparency = 0 })
		table.insert(chatMessages, label)
		while #chatMessages > MAX_CHAT do
			local old = table.remove(chatMessages, 1)
			if old then
				old:Destroy()
			end
		end
	end

	local function randomName(): string
		return NAMES[random:NextInteger(1, #NAMES)]
	end

	local function randomChat()
		local roll = random:NextNumber()
		if roll < 0.06 then
			local amount = DONATION_AMOUNTS[random:NextInteger(1, #DONATION_AMOUNTS)]
			pushChat("💸 " .. randomName(), "a donné " .. amount .. " Dopamine !", Color3.fromRGB(255, 190, 0))
			spawnHeart("💸")
		else
			pushChat(randomName(), MESSAGES[random:NextInteger(1, #MESSAGES)])
		end
	end

	-- Affiche / cache le chat quand la Feature change
	local chatShown = chat.Visible
	local function applyChatVisibility()
		local shown = hasChat()
		if shown == chatShown then
			return
		end
		chatShown = shown
		UI.Tween(video, 0.35, { Size = UDim2.fromOffset(videoWidth(shown), VIDEO_H) }, Enum.EasingStyle.Back)
		if shown then
			chat.Visible = true
			chat.Position = UDim2.new(1, CHAT_W, 0, VIDEO_Y)
			UI.Tween(chat, 0.35, { Position = UDim2.new(1, -VIDEO_X, 0, VIDEO_Y) }, Enum.EasingStyle.Back)
			pushChat("MangeTout_ASMR", "le chat est ouvert !! 🎉", Color3.fromRGB(145, 70, 255))
		else
			chat.Visible = false
		end
	end
	ctx.Connect(ctx.State.FeaturesChanged, applyChatVisibility)

	------------------------------------------------------------------
	-- Spectateurs : grimpent avec le niveau "Abonnés"
	------------------------------------------------------------------
	local function targetViewers(): number
		local base = 40 * (1.9 ^ followers())
		if hasChat() then
			base *= 1.5
		end
		return base
	end
	local viewers = targetViewers() * random:NextNumber(0.9, 1.1)
	local shownViewers = viewers

	local function formatViewers(value: number): string
		if value < 1e5 then
			return Format.WithSpaces(value)
		end
		return Format.Format(value)
	end

	------------------------------------------------------------------
	-- Bouton "Suivre" (juste pour le plaisir)
	------------------------------------------------------------------
	local followLock = false
	ctx.Connect(followButton.Activated, function()
		if followLock then
			return
		end
		followLock = true
		ctx.Sound.Play("Pop", 1.3)
		followButton.Text = "✅ Suivi !"
		followButton.BackgroundColor3 = Color3.fromRGB(70, 60, 90)
		for _ = 1, 4 do
			spawnHeart("💜")
		end
		viewers += 1
		pushChat("MangeTout_ASMR", "merci pour le follow !! 💜", Color3.fromRGB(145, 70, 255))
		task.delay(3, function()
			if ctx.IsAlive() and followButton.Parent then
				followButton.Text = "❤️ Suivre"
				followButton.BackgroundColor3 = Color3.fromRGB(145, 70, 255)
			end
			followLock = false
		end)
	end)

	------------------------------------------------------------------
	-- Animation continue
	------------------------------------------------------------------
	local clock = 0
	local chewUntil = 0
	local nextHeart = 0.5
	local viewersTimer = 0
	ctx.OnRender(function(dt: number)
		clock += dt
		local now = os.clock()

		-- Tête : balancement tranquille, ou mastication rapide
		local chewing = now < chewUntil
		if chewing then
			face.Position = UDim2.new(0.5, 0, 0, TABLE_Y + 16 + math.abs(math.sin(clock * 18)) * 3)
			face.Rotation = math.sin(clock * 14) * 6
		else
			face.Position = UDim2.new(0.5, 0, 0, TABLE_Y + 16 + math.sin(clock * 2) * 2)
			face.Rotation = math.sin(clock * 1.3) * 3
		end

		-- Badge "EN DIRECT" qui pulse, guirlande qui clignote, néon qui grésille
		liveScale.Scale = 1 + math.max(0, math.sin(clock * 4)) * 0.06
		for i, bulb in ipairs(bulbs) do
			bulb.BackgroundTransparency = 0.15 + 0.6 * (0.5 + 0.5 * math.sin(clock * 3 + i * 1.7))
		end
		neonSign.TextTransparency = (math.sin(clock * 23) > 0.93) and 0.6 or 0

		-- Cœurs
		for _, heart in ipairs(hearts) do
			local label = heart.Label
			if label.Visible then
				local t = (now - heart.Start) / heart.Life
				if t >= 1 then
					label.Visible = false
				else
					label.Position = UDim2.new(1, -18 + heart.X + math.sin(heart.Sway + t * 6) * 6, 0, TABLE_Y - 4 - t * 80)
					label.TextTransparency = t * t
					label.Rotation = math.sin(heart.Sway + t * 4) * 15
				end
			end
		end
		nextHeart -= dt
		if nextHeart <= 0 then
			nextHeart = random:NextNumber(0.5, 1.6) / (1 + followers() * 0.12)
			if effectsOn() or random:NextNumber() < 0.3 then
				spawnHeart()
			end
		end

		-- Spectateurs : marche aléatoire autour de la cible
		viewersTimer -= dt
		if viewersTimer <= 0 then
			viewersTimer = 0.6
			local target = targetViewers()
			viewers += (target - viewers) * 0.25 + target * random:NextNumber(-0.03, 0.03)
			viewers = math.max(1, viewers)
		end
		shownViewers += (viewers - shownViewers) * math.min(1, dt * 4)
		viewersLabel.Text = "👁 " .. formatViewers(math.floor(shownViewers + 0.5))
	end)

	------------------------------------------------------------------
	-- Boucle de repas : un aliment à la fois
	------------------------------------------------------------------
	local function refillPlate()
		for i, food in ipairs(foods) do
			food.Text = FOODS[random:NextInteger(1, #FOODS)]
			food.Rotation = random:NextNumber(-12, 12)
			foodScales[i].Scale = 1
			food.Position = foodHome(i) - UDim2.fromOffset(0, 70)
			food.Visible = true
			task.delay((i - 1) * 0.08, function()
				if ctx.IsAlive() and food.Parent then
					UI.Tween(food, 0.45, { Position = foodHome(i) }, Enum.EasingStyle.Bounce)
				end
			end)
		end
	end

	task.spawn(function()
		task.wait(1)
		while ctx.IsAlive() do
			task.wait(random:NextNumber(1.1, 1.9) / (1 + math.min(followers(), 15) * 0.02))
			if not ctx.IsAlive() then
				break
			end

			-- Prochain aliment encore dans l'assiette
			local index = nil
			for i, food in ipairs(foods) do
				if food.Visible then
					index = i
					break
				end
			end

			if not index then
				-- Assiette vide : on ressert !
				face.Text = "🥺"
				popWord("RESSERVI !")
				task.wait(0.5)
				if not ctx.IsAlive() then
					break
				end
				refillPlate()
				pushChat(randomName(), "IL RESSERT 😭🔥")
				task.wait(0.7)
				face.Text = "😋"
			else
				local food = foods[index]
				local scale = foodScales[index]
				-- Regard gourmand, bouche ouverte, puis croc !
				face.Text = "🤤"
				task.wait(0.35)
				if not ctx.IsAlive() then
					break
				end
				face.Text = "😮"
				UI.Tween(food, 0.25, { Position = UDim2.new(0.5, 0, 0, MOUTH_Y), Rotation = 0 }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
				UI.Tween(scale, 0.25, { Scale = 0.35 }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
				task.wait(0.25)
				if not ctx.IsAlive() then
					break
				end
				food.Visible = false
				face.Text = "😋"
				chewUntil = os.clock() + 0.9
				popWord()
				crumbs()
				ctx.Sound.Play("Pop", random:NextNumber(0.55, 0.75))
				if random:NextNumber() < 0.5 then
					pushChat(randomName(), REACTIONS[random:NextInteger(1, #REACTIONS)])
				end
			end
		end
	end)

	------------------------------------------------------------------
	-- Boucle du chat : de plus en plus rapide avec les abonnés
	------------------------------------------------------------------
	task.spawn(function()
		while ctx.IsAlive() do
			local interval = math.clamp(1.4 / (1 + followers() * 0.15), 0.25, 1.4)
			task.wait(random:NextNumber(0.6, 1.3) * interval)
			if not ctx.IsAlive() then
				break
			end
			if chat.Visible then
				randomChat()
			end
		end
	end)
end

return LiveStream
