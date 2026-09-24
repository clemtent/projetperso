--[[
	LiveStream (ModuleScript - stimulus)
	Emplacement : ReplicatedStorage > Client > Stimuli > LiveStream

	Faux live "ASMR mukbang" (slot L1, 288x190), façon appli de streaming :
	  - en-tête : avatar dessiné, pseudo certifié, badge "● LIVE" qui pulse,
	    spectateurs (animés, montent avec l'amélioration "Abonnés"), likes ;
	  - la vidéo : une streameuse DESSINÉE en formes (cheveux, casque
	    lumineux, sweat, bras qui portent la nourriture à la bouche, yeux
	    qui clignent, joues roses, bouche qui mâche), un ring light, un
	    micro ASMR "moumoute" avec ondes sonores, une assiette d'aliments
	    mangés un par un ("CRUNCH !", miettes, cœurs qui montent) ;
	  - bouton "Suivre" : si ClientState.Data.LiveFollowed est faux,
	    Interact("Follow") (récompense unique par partie), puis "✔ Abonné"
	    et les dons commencent ;
	  - dons : OnSpawn("Donation") affiche une carte dorée (dans le chat ou
	    en haut de la vidéo), cliquable -> ClaimSpawn ; OnBonus("Donation" /
	    "Follow") fait flotter le gain ;
	  - Feature "LiveChat" : colonne de chat vivante (50 pseudos colorés,
	    rôles 🛡️ modo / 💎 abonné / 👑 VIP, 150+ messages, messages
	    d'emotes en gros, message épinglé, défilement fluide avec fondu en
	    haut, "raids" de temps en temps) qui réagit aux aliments mangés,
	    au beurre, aux dons, à l'abonnement et aux gros gains du joueur ;
	  - Feature "Butter" : un gros bloc de beurre brillant sur une coupelle.
	    Clic = son "Crunch", traces de dents, éclats (il se fait manger
	    petit à petit puis revient), "+X" = gain par clic x ClickFraction,
	    Interact("Butter") limité côté client à MaxPerSecond.
]]

local Debris = game:GetService("Debris")
local TweenService = game:GetService("TweenService")

local LiveStream = {}
LiveStream.Slot = "L1"

----------------------------------------------------------------------
-- Disposition (pixels "design", carte 284 x 186 rentrée de 2 px)
----------------------------------------------------------------------
local CARD_W = 284
local VIDEO_X, VIDEO_Y = 6, 34
local VIDEO_H = 146
local CHAT_W = 100
local GAP = 4
local TABLE_Y = 104 -- haut de la table dans la vidéo
local PLATE_Y = 114 -- centre de l'assiette
local MOUTH_Y = TABLE_Y - 36 -- bouche de la streameuse (vidéo)
local BUTTER_X = 0.85 -- position (Scale) du beurre sur la table
local MIC_X = 0.12
local MAX_CHAT = 16 -- messages gardés (les plus vieux sont hors champ, en haut)
local MAX_HEARTS = 6
local BUTTER_BITES = 8 -- bouchées avant qu'il ne reste plus rien

local FOODS = { "🥪", "🍟", "🍔", "🌭", "🍕", "🥓", "🍗", "🌮", "🍩", "🥐", "🍪", "🌯", "🍙", "🧁" }
local FOOD_OFFSETS = { -22, -8, 8, 22 }

local CRUNCH_WORDS = { "CRUNCH !", "MIAM", "CROC !", "*crounch*", "SLURP", "CRAC !", "NOM NOM", "CRISP !", "MMMH", "SCROUNCH" }
local BUTTER_WORDS = { "CROUNCH !", "*CROUNCH*", "CRAC !", "SCRONCH", "CRUNCH !!" }
local POP_COLORS = {
	Color3.fromRGB(255, 214, 40),
	Color3.fromRGB(255, 90, 160),
	Color3.fromRGB(0, 210, 255),
	Color3.fromRGB(255, 255, 255),
	Color3.fromRGB(130, 255, 120),
}
local HEARTS = { "❤️", "💜", "💖", "😍", "🔥", "👏", "✨" }

local HOST = "MangeTout_ASMR"

----------------------------------------------------------------------
-- Chat : pseudos, rôles et messages (tout est inventé)
----------------------------------------------------------------------
local NAMES = {
	"Kevin_du_75", "xX_Nugget_Xx", "Mamie_Gaming", "LeChatDuVoisin", "BaguetteMan", "Tartiflette99",
	"MrPatate", "Choupette", "DarkSasuke42", "Poulet_Braisé", "Zinzin_78", "Croquette", "SushiLover",
	"Tonton_Jean", "Lulu_ASMR", "PatateDouce", "Bichon_Fou", "Crêpe_Party", "Moustache_Pro",
	"Raclette4Life", "Gratin2Pâtes", "Ninja_du_Dimanche", "Fromage_Fou", "LaTeteDansLeFrigo",
	"Pépito_Gamer", "Mimi_Chaussette", "Cornichon_Royal", "Tata_Brioche", "Loulou_Pixel", "CaptainKebab",
	"Nuage_Rose", "Petit_Pois", "Madeleine_Proust", "Framboise_Zen", "Cacahuète42", "Le_Roi_du_Gouda",
	"Pingouin_Timide", "Chocapic_Fan", "Sardine_Club", "Biscotte_Ninja", "Yaourt_Nature", "Mister_Frites",
	"Poney_Magique", "Tomate_Cerise", "Kiwi_Sauvage", "Doudou_77", "Licorne_Fatiguée", "Bretzel_Boss",
	"Céleri_Rave", "Nutella_Addict",
}
-- Modérateurs (badge 🛡️) : toujours les mêmes, comme sur un vrai live
local MODS = { Tonton_Jean = true, Lulu_ASMR = true, Moustache_Pro = true, Madeleine_Proust = true }
local NAME_COLORS = { "#FF6B9A", "#6BD5FF", "#FFD34D", "#9DFF6B", "#C38BFF", "#FF9F45", "#5CFFD1", "#FF7AF0", "#7AA2FF", "#FFB3C7" }

local MESSAGES = {
	"W", "+1", "incroyable", "c'est quoi ce live", "le crunch était parfait", "encore !!",
	"j'ai faim maintenant", "elle mange à 3h du mat ?", "premier", "ASMR de qualité", "MIAM",
	"c'est tellement satisfaisant", "je regarde au lieu de réviser", "mdr", "le son 🤤",
	"maman si tu vois ça coucou", "elle a même pas mâché", "trop bien", "respect",
	"et la sauce ??", "GG", "qui est là depuis le début ?", "j'ai lâché mon goûter",
	"5 étoiles", "mon moment préféré", "L", "elle va finir l'assiette ??", "le casque est trop beau",
	"je suis au régime 😭", "le micro 😳", "c'est l'heure du goûter", "on veut des frites !",
	"j'entends le crunch d'ici", "reviens manger chez moi", "ratio", "je m'endors 😴",
	"le ring light 😍", "trop chou le sweat", "quelqu'un a vu mes lunettes ?", "je devais dormir il y a 2h",
	"c'est mieux qu'un film", "ma prof regarde aussi je crois", "on est combien là ?", "le chat est chaud ce soir",
	"bonjour de Marseille ☀️", "coucou de Lyon 👋", "salut de Montréal ❄️", "bisous de Bordeaux 🍷",
	"je mange des chips en même temps", "on peut avoir un mukbang raclette ?", "prochain live : fondue 🧀",
	"c'est mon rituel du soir", "elle est trop forte", "comment elle a pas mal au ventre ??",
	"moi aussi je veux un micro moumoute", "ça me détend trop", "mon chat regarde avec moi 🐈",
	"je suis en cours chut 🤫", "lol", "ptdr", "j'avoue", "grave", "je like chaque crunch",
	"qui mange devant l'écran aussi ?", "le bruit est hypnotisant", "je reste jusqu'à la fin",
	"on est bien là", "vivement demain", "je partage à mes potes", "c'est ma dose de dopamine",
	"clique clique clique", "j'ai oublié pourquoi j'étais là", "encore une assiette !!",
	"c'est quoi la musique ?", "le son est parfait", "vous entendez ça ??", "jsuis pas prêt",
	"trop mims", "elle a des goûts de luxe", "c'est la meilleure streameuse", "notif activée 🔔",
	"je devrais faire mes devoirs...", "t'as essayé les cornichons ?", "team frites 🍟", "team nuggets",
	"il est quelle heure chez vous ?", "10 minutes que je souris devant mon écran", "ça sent bon d'ici",
	"le chat va trop vite 😵", "qui veut un bout ?", "c'est mon anniv aujourd'hui 🎂", "joyeux anniv !!",
	"j'ai mis le son à fond", "mes voisins entendent le crunch", "live de l'année", "je suis addict",
}
-- Messages uniquement composés d'emotes (affichés en plus gros)
local EMOTE_MESSAGES = {
	"🔥🔥🔥", "😭😭😭", "🤤🤤🤤", "💜💜💜", "👏👏👏", "😂😂", "🥪🥪🥪", "🍟🍟", "👀", "💯💯",
	"😍😍", "🤯", "🙌🙌", "✨✨✨", "🎉🎉🎉", "🧈🧈", "🍔🍕🌭", "😋😋", "💖", "🥺👉👈",
}
local EAT_REACTIONS = {
	"CRUNCH 🔥", "le son 🤤🤤", "OUIIII", "MIAM", "encore une !", "W crunch", "ASMR 🔊",
	"cette bouchée 😳", "elle a tout mangé d'un coup", "le crunch m'a traversé", "croustillant validé ✅",
	"10/10 le bruit", "j'ai frissonné", "encore encore encore", "ce son devrait être interdit",
}
local BUTTER_REACTIONS = {
	"*CROUNCH*", "le beurre 😭😭", "CROUNCH 🧈", "ASMR BEURRE 🔊", "qui croque du beurre ??",
	"le son du beurre 🤤", "c'est illégal ça", "BEURRE CROUSTILLANT", "*crounch crounch*",
	"le beurre a crié", "BEURRE > tout", "qui a eu l'idée du beurre 😭", "demi-sel ou doux ??", "encore le beurre !!",
}
local DONATION_REACTIONS = {
	"MERCI POUR LE DON 💸", "le boss 🤑", "GG le don !!", "quel généreux", "W donateur",
	"moi aussi je veux donner", "c'est la fête 🎉", "le mécène du live", "pluie de billets 💵",
	"t'es le meilleur", "respect au donateur 🙏", "💸💸💸",
}
local FOLLOW_REACTIONS = {
	"bienvenue !! 💜", "un nouvel abonné 🎉", "W follow", "bienvenue dans la team",
	"on est une famille ici", "enfin abonné 😤", "les dons sont ouverts !!", "💜💜💜",
}
local BIG_GAIN_REACTIONS = {
	"GROS GAIN 🤑", "t'es riche maintenant", "prête-moi de la dopamine stp", "les chiffres montent 📈",
	"c'est énorme", "💰💰💰", "quelle chance 🍀", "on fête ça 🎉", "le compteur s'affole", "t'arrêtes plus",
}
local RAID_MESSAGES = {
	"RAID 🎉🎉", "on vient en raid !!", "💜 RAID 💜", "bonjour le chat !!", "coucou tout le monde 👋",
	"on a entendu parler du crunch", "c'est ici le beurre ?", "RAIDDDD 🚨", "on débarque 🏃", "salut la team !!",
}
local MOD_MESSAGES = {
	"restez gentils svp 🛡️", "pas de spam dans le chat !", "on respecte la streameuse 💜",
	"hydratez-vous 💧", "pensez à suivre la chaîne 💜", "on parle pas la bouche pleine... ah si en fait",
}
local HOST_MESSAGES = {
	"merci d'être là 💜", "vous voulez que je goûte quoi ?", "le son est bon ?", "chut... ASMR 🤫",
	"abonnez-vous 💜", "j'ai encore faim", "qui mange avec moi ?", "coucou les nouveaux 👋",
}
local DONATION_LINES = { "a fait un don !", "t'envoie un pourboire !", "offre une tournée !", "a lâché un billet !" }

----------------------------------------------------------------------
-- Petites fonctions utilitaires
----------------------------------------------------------------------
local function escape(text: string): string
	text = string.gsub(text, "&", "&amp;")
	text = string.gsub(text, "<", "&lt;")
	text = string.gsub(text, ">", "&gt;")
	return text
end

local function pick<T>(list: { T }, random: Random): T
	return list[random:NextInteger(1, #list)]
end

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

	local function hasButter(): boolean
		return ctx.HasFeature("Butter") == true
	end

	local function isFollowedOnServer(): boolean
		local data = ctx.State.Data
		return data ~= nil and data.LiveFollowed == true
	end

	-- Cadre sans bordure (+ coin arrondi optionnel)
	local function box(props: { [string]: any }, radius: (number | UDim)?): Frame
		props.BorderSizePixel = 0
		local frame = UI.Create("Frame", props)
		if radius then
			UI.Corner(frame, radius)
		end
		return frame
	end

	local function text(props: { [string]: any }): TextLabel
		props.BackgroundTransparency = props.BackgroundTransparency or 1
		props.BorderSizePixel = 0
		props.Font = props.Font or Theme.Fonts.Body
		props.TextColor3 = props.TextColor3 or Color3.new(1, 1, 1)
		return UI.Create("TextLabel", props)
	end

	------------------------------------------------------------------
	-- Carte
	------------------------------------------------------------------
	local card = box({
		Name = "Card",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.new(1, -4, 1, -4),
		BackgroundColor3 = Color3.fromRGB(24, 20, 34),
		Parent = ctx.Container,
	}, 14)
	UI.Gradient(card, ColorSequence.new(Color3.fromRGB(46, 36, 66), Color3.fromRGB(20, 17, 28)), 90)
	local cardStroke = UI.Stroke(card, Color3.fromRGB(150, 90, 255), 2)
	UI.Gradient(cardStroke, ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 90, 170)),
		ColorSequenceKeypoint.new(0.5, Color3.fromRGB(150, 90, 255)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(80, 200, 255)),
	}), 0)
	local strokeGradient = cardStroke:FindFirstChildOfClass("UIGradient")

	local function videoWidth(chat: boolean): number
		if chat then
			return CARD_W - VIDEO_X * 2 - CHAT_W - GAP
		end
		return CARD_W - VIDEO_X * 2
	end

	------------------------------------------------------------------
	-- En-tête : avatar, pseudo, LIVE, spectateurs, likes, Suivre
	------------------------------------------------------------------
	local header = box({
		Name = "Header",
		Position = UDim2.fromOffset(0, 0),
		Size = UDim2.new(1, 0, 0, VIDEO_Y),
		BackgroundTransparency = 1,
		ZIndex = 5,
		Parent = card,
	})

	-- Avatar : mini portrait dessiné (anneau dégradé + visage + cheveux)
	local avatarRing = box({
		Name = "Avatar",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromOffset(19, 18),
		Size = UDim2.fromOffset(26, 26),
		BackgroundColor3 = Color3.new(1, 1, 1),
		ZIndex = 5,
		Parent = header,
	}, UDim.new(1, 0))
	local ringGradient = UI.Gradient(avatarRing, ColorSequence.new(Color3.fromRGB(255, 80, 160), Color3.fromRGB(120, 90, 255)), 45)
	local avatarFace = box({
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(21, 21),
		BackgroundColor3 = Color3.fromRGB(255, 214, 186),
		ZIndex = 6,
		Parent = avatarRing,
	}, UDim.new(1, 0))
	box({ Position = UDim2.fromOffset(0, -1), Size = UDim2.fromOffset(21, 10), BackgroundColor3 = Color3.fromRGB(74, 52, 94), ZIndex = 7, Parent = avatarFace }, 5)
	for _, x in ipairs({ 7, 14 }) do
		box({ AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromOffset(x, 12), Size = UDim2.fromOffset(3, 3), BackgroundColor3 = Color3.fromRGB(40, 30, 50), ZIndex = 7, Parent = avatarFace }, UDim.new(1, 0))
	end
	box({ AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromOffset(10.5, 16), Size = UDim2.fromOffset(5, 2), BackgroundColor3 = Color3.fromRGB(190, 70, 100), ZIndex = 7, Parent = avatarFace }, UDim.new(1, 0))

	text({
		Name = "Streamer",
		Text = "<b>" .. HOST .. '</b> <font color="#5CC8FF">✔</font>',
		RichText = true,
		Font = Theme.Fonts.Title,
		TextSize = 12,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextTruncate = Enum.TextTruncate.AtEnd,
		Position = UDim2.fromOffset(36, 4),
		Size = UDim2.fromOffset(108, 14),
		ZIndex = 5,
		Parent = header,
	})
	local viewersLabel = text({
		Name = "Viewers",
		Text = "👁 0",
		Font = Theme.Fonts.Number,
		TextSize = 10,
		TextColor3 = Color3.fromRGB(200, 192, 230),
		TextXAlignment = Enum.TextXAlignment.Left,
		Position = UDim2.fromOffset(36, 18),
		Size = UDim2.fromOffset(56, 12),
		ZIndex = 5,
		Parent = header,
	})
	local likesLabel = text({
		Name = "Likes",
		Text = "❤ 0",
		Font = Theme.Fonts.Number,
		TextSize = 10,
		TextColor3 = Color3.fromRGB(255, 150, 190),
		TextXAlignment = Enum.TextXAlignment.Left,
		Position = UDim2.fromOffset(94, 18),
		Size = UDim2.fromOffset(52, 12),
		ZIndex = 5,
		Parent = header,
	})
	local likesScale = UI.Create("UIScale", { Parent = likesLabel })

	-- Badge LIVE (point blanc qui pulse)
	local liveBadge = box({
		Name = "Live",
		Position = UDim2.fromOffset(148, 9),
		Size = UDim2.fromOffset(42, 17),
		BackgroundColor3 = Color3.fromRGB(235, 35, 60),
		ZIndex = 5,
		Parent = header,
	}, 5)
	UI.Gradient(liveBadge, ColorSequence.new(Color3.new(1, 1, 1), Color3.fromRGB(200, 200, 200)), 90)
	local liveDot = box({
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromOffset(8, 8.5),
		Size = UDim2.fromOffset(6, 6),
		BackgroundColor3 = Color3.new(1, 1, 1),
		ZIndex = 6,
		Parent = liveBadge,
	}, UDim.new(1, 0))
	text({
		Text = "LIVE",
		Font = Theme.Fonts.Title,
		TextSize = 11,
		Position = UDim2.fromOffset(13, 0),
		Size = UDim2.new(1, -14, 1, 0),
		ZIndex = 6,
		Parent = liveBadge,
	})
	local liveScale = UI.Create("UIScale", { Parent = liveBadge })

	-- Bouton Suivre
	local FOLLOW_COLOR = Color3.fromRGB(145, 70, 255)
	local FOLLOWED_COLOR = Color3.fromRGB(62, 56, 84)
	local followButton = UI.Create("TextButton", {
		Name = "Follow",
		Text = "💜 Suivre",
		Font = Theme.Fonts.Title,
		TextSize = 12,
		TextColor3 = Color3.new(1, 1, 1),
		BackgroundColor3 = FOLLOW_COLOR,
		AutoButtonColor = false,
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -7, 0, 18),
		Size = UDim2.fromOffset(74, 22),
		BorderSizePixel = 0,
		ZIndex = 5,
		Parent = header,
	})
	UI.Corner(followButton, UDim.new(1, 0))
	local followGradient = UI.Gradient(followButton, ColorSequence.new(Color3.new(1, 1, 1), Color3.fromRGB(205, 190, 230)), 90)
	local followStroke = UI.Stroke(followButton, Color3.fromRGB(210, 180, 255), 1.5, 0.3)
	UI.AnimateButton(followButton, 1.06, 0.9)

	------------------------------------------------------------------
	-- Vidéo : la pièce
	------------------------------------------------------------------
	local video = box({
		Name = "Video",
		Position = UDim2.fromOffset(VIDEO_X, VIDEO_Y),
		Size = UDim2.fromOffset(videoWidth(hasChat()), VIDEO_H),
		BackgroundColor3 = Color3.new(1, 1, 1),
		ClipsDescendants = true,
		ZIndex = 2,
		Parent = card,
	}, 10)
	UI.Gradient(video, ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(96, 74, 150)),
		ColorSequenceKeypoint.new(0.55, Color3.fromRGB(178, 112, 176)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(240, 150, 150)),
	}), 90)

	-- Ruban LED en haut du mur (arc-en-ciel qui défile) + halo
	local led = box({
		Name = "LED",
		Position = UDim2.fromOffset(0, 6),
		Size = UDim2.new(1, 0, 0, 3),
		BackgroundColor3 = Color3.new(1, 1, 1),
		ZIndex = 1,
		Parent = video,
	})
	local ledGradient = UI.Gradient(led, ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 80, 160)),
		ColorSequenceKeypoint.new(0.25, Color3.fromRGB(255, 200, 60)),
		ColorSequenceKeypoint.new(0.5, Color3.fromRGB(80, 220, 255)),
		ColorSequenceKeypoint.new(0.75, Color3.fromRGB(160, 100, 255)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(255, 80, 160)),
	}), 0)
	local ledGlow = box({
		Position = UDim2.fromOffset(0, 9),
		Size = UDim2.new(1, 0, 0, 22),
		BackgroundColor3 = Color3.fromRGB(255, 170, 230),
		BackgroundTransparency = 0.2,
		ZIndex = 1,
		Parent = video,
	})
	local glowGradient = UI.Gradient(ledGlow, ColorSequence.new(Color3.fromRGB(255, 190, 240), Color3.fromRGB(255, 190, 240)), 90)
	glowGradient.Transparency = NumberSequence.new(0.55, 1)

	-- Étagère + plante (à gauche)
	local shelf = box({
		Position = UDim2.new(0.03, 0, 0, 42),
		Size = UDim2.fromOffset(40, 4),
		BackgroundColor3 = Color3.fromRGB(120, 78, 60),
		ZIndex = 2,
		Parent = video,
	}, 2)
	local pot = box({
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.fromOffset(12, 0),
		Size = UDim2.fromOffset(12, 10),
		BackgroundColor3 = Color3.fromRGB(240, 130, 110),
		ZIndex = 3,
		Parent = shelf,
	}, 3)
	for i, rotation in ipairs({ -30, 0, 30 }) do
		box({
			AnchorPoint = Vector2.new(0.5, 1),
			Position = UDim2.new(0.5, (i - 2) * 3, 0, 1),
			Size = UDim2.fromOffset(5, 13),
			Rotation = rotation,
			BackgroundColor3 = Color3.fromRGB(90, 200, 120),
			ZIndex = 2,
			Parent = pot,
		}, UDim.new(1, 0))
	end
	-- Petit cadre photo
	local frameArt = box({
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.fromOffset(30, 0),
		Size = UDim2.fromOffset(12, 14),
		BackgroundColor3 = Color3.fromRGB(255, 240, 220),
		ZIndex = 3,
		Parent = shelf,
	}, 2)
	UI.Gradient(frameArt, ColorSequence.new(Color3.fromRGB(255, 220, 120), Color3.fromRGB(130, 200, 255)), 90)

	-- Enseigne néon "MIAM" (à droite, grésille)
	local neonSign = text({
		Name = "Neon",
		Text = "miam ♥",
		Font = Enum.Font.FredokaOne,
		TextSize = 13,
		TextColor3 = Color3.fromRGB(255, 120, 200),
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(0.97, 0, 0, 16),
		Size = UDim2.fromOffset(52, 16),
		Rotation = 5,
		ZIndex = 2,
		Parent = video,
	})
	local neonStroke = UI.Stroke(neonSign, Color3.fromRGB(255, 200, 240), 1.2, 0.35)
	neonStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual

	-- Ring light derrière la tête
	local ringLight = box({
		Name = "RingLight",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 0, TABLE_Y - 50),
		Size = UDim2.fromOffset(78, 78),
		BackgroundColor3 = Color3.fromRGB(255, 245, 250),
		BackgroundTransparency = 0.82,
		ZIndex = 2,
		Parent = video,
	}, UDim.new(1, 0))
	local ringStroke = UI.Stroke(ringLight, Color3.fromRGB(255, 250, 255), 4, 0.1)

	------------------------------------------------------------------
	-- La streameuse (dessinée en formes)
	------------------------------------------------------------------
	local SKIN = Color3.fromRGB(255, 214, 186)
	local SKIN_SHADE = Color3.fromRGB(240, 178, 150)
	local HAIR = Color3.fromRGB(74, 52, 94)
	local HOODIE = Color3.fromRGB(255, 150, 185)
	local HOODIE_DARK = Color3.fromRGB(226, 104, 150)
	local INK = Color3.fromRGB(44, 30, 52)

	local streamerY = TABLE_Y + 6
	local streamer = box({
		Name = "Streamer",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 0, streamerY),
		Size = UDim2.fromOffset(80, 80),
		BackgroundTransparency = 1,
		ZIndex = 4,
		Parent = video,
	})

	-- Cheveux (arrière) : longs, tombent sur les épaules
	box({ Position = UDim2.fromOffset(13, 6), Size = UDim2.fromOffset(54, 48), BackgroundColor3 = HAIR, ZIndex = 1, Parent = streamer }, 20)

	-- Corps : sweat à capuche
	local body = box({ Position = UDim2.fromOffset(8, 46), Size = UDim2.fromOffset(64, 44), BackgroundColor3 = HOODIE, ZIndex = 2, Parent = streamer }, 20)
	UI.Gradient(body, ColorSequence.new(Color3.new(1, 1, 1), Color3.fromRGB(215, 200, 210)), 90)
	box({ AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromOffset(40, 36), Size = UDim2.fromOffset(12, 14), BackgroundColor3 = SKIN_SHADE, ZIndex = 2, Parent = streamer }, 4)
	box({ AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.fromOffset(40, 43), Size = UDim2.fromOffset(34, 9), BackgroundColor3 = HOODIE_DARK, ZIndex = 3, Parent = streamer }, 5)
	for _, x in ipairs({ 35, 45 }) do
		box({ AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.fromOffset(x, 50), Size = UDim2.fromOffset(2, 11), BackgroundColor3 = Color3.new(1, 1, 1), ZIndex = 4, Parent = streamer }, 1)
	end
	text({
		Text = "♥",
		Font = Theme.Fonts.Title,
		TextSize = 11,
		TextColor3 = Color3.new(1, 1, 1),
		TextTransparency = 0.15,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromOffset(40, 66),
		Size = UDim2.fromOffset(12, 12),
		ZIndex = 4,
		Parent = streamer,
	})

	-- Bras (support qui tourne autour de l'épaule, bras dans la moitié basse)
	local function makeArm(x: number, restRotation: number): Frame
		local holder = box({
			Name = "Arm",
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromOffset(x, 54),
			Size = UDim2.fromOffset(12, 52),
			BackgroundTransparency = 1,
			Rotation = restRotation,
			ZIndex = 5,
			Parent = streamer,
		})
		local arm = box({
			AnchorPoint = Vector2.new(0.5, 0),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromOffset(11, 24),
			BackgroundColor3 = HOODIE,
			ZIndex = 5,
			Parent = holder,
		}, 5)
		UI.Stroke(arm, HOODIE_DARK, 1, 0.3)
		box({
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.new(0.5, 0, 1, 0),
			Size = UDim2.fromOffset(10, 10),
			BackgroundColor3 = SKIN,
			ZIndex = 6,
			Parent = arm,
		}, UDim.new(1, 0))
		return holder
	end
	local ARM_REST_L, ARM_REST_R, ARM_EAT = -28, 28, 124
	makeArm(16, ARM_REST_L)
	local armRight = makeArm(64, ARM_REST_R)

	-- Tête
	local head = box({ Name = "Head", Position = UDim2.fromOffset(18, 8), Size = UDim2.fromOffset(44, 40), BackgroundColor3 = SKIN, ZIndex = 6, Parent = streamer }, UDim.new(0.5, 0))
	UI.Gradient(head, ColorSequence.new(Color3.new(1, 1, 1), Color3.fromRGB(240, 222, 214)), 90)
	-- Frange + mèches
	box({ Position = UDim2.fromOffset(-2, -4), Size = UDim2.fromOffset(48, 17), BackgroundColor3 = HAIR, ZIndex = 7, Parent = head }, 10)
	box({ AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromOffset(13, 12), Size = UDim2.fromOffset(12, 9), Rotation = 30, BackgroundColor3 = HAIR, ZIndex = 7, Parent = head }, 4)
	box({ AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromOffset(31, 12), Size = UDim2.fromOffset(12, 9), Rotation = -30, BackgroundColor3 = HAIR, ZIndex = 7, Parent = head }, 4)
	-- Reflet dans les cheveux
	box({ Position = UDim2.fromOffset(8, -1), Size = UDim2.fromOffset(12, 3), BackgroundColor3 = Color3.fromRGB(160, 130, 190), BackgroundTransparency = 0.3, Rotation = -8, ZIndex = 8, Parent = head }, 2)

	-- Yeux (clignent / se ferment quand elle mâche) + reflets
	local eyes: { Frame } = {}
	for _, x in ipairs({ 15, 29 }) do
		local eye = box({ AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromOffset(x, 22), Size = UDim2.fromOffset(6, 7), BackgroundColor3 = INK, ZIndex = 8, Parent = head }, UDim.new(1, 0))
		box({ Position = UDim2.fromScale(0.5, 0.1), Size = UDim2.fromOffset(2, 2), BackgroundColor3 = Color3.new(1, 1, 1), ZIndex = 9, Parent = eye }, UDim.new(1, 0))
		table.insert(eyes, eye)
	end
	-- Sourcils
	local brows: { Frame } = {}
	for _, x in ipairs({ 15, 29 }) do
		table.insert(brows, box({ AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromOffset(x, 16), Size = UDim2.fromOffset(7, 2), BackgroundColor3 = HAIR, ZIndex = 8, Parent = head }, 1))
	end
	-- Joues roses
	for _, x in ipairs({ 10, 34 }) do
		box({ AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromOffset(x, 28), Size = UDim2.fromOffset(8, 4), BackgroundColor3 = Color3.fromRGB(255, 120, 150), BackgroundTransparency = 0.4, ZIndex = 8, Parent = head }, UDim.new(1, 0))
	end
	-- Bouche (+ langue quand elle est grande ouverte)
	local mouth = box({ AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromOffset(22, 31), Size = UDim2.fromOffset(8, 3), BackgroundColor3 = Color3.fromRGB(120, 36, 60), ZIndex = 8, Parent = head }, UDim.new(1, 0))
	local tongue = box({ AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.fromScale(0.5, 1), Size = UDim2.fromScale(0.7, 0.45), BackgroundColor3 = Color3.fromRGB(255, 120, 140), Visible = false, ZIndex = 9, Parent = mouth }, UDim.new(1, 0))

	-- Casque (arceau + écouteurs lumineux). La moitié basse de l'arceau est
	-- cachée par un dégradé de transparence (pas de ClipsDescendants : la
	-- tête tourne, et le découpage ne marche pas sur un objet tourné)
	local band = box({ Position = UDim2.fromOffset(-6, -8), Size = UDim2.fromOffset(56, 48), BackgroundTransparency = 1, ZIndex = 10, Parent = head }, UDim.new(1, 0))
	local bandStroke = UI.Stroke(band, Color3.fromRGB(46, 42, 64), 4)
	local bandGradient = UI.Gradient(bandStroke, ColorSequence.new(Color3.new(1, 1, 1)), 90)
	bandGradient.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0),
		NumberSequenceKeypoint.new(0.46, 0),
		NumberSequenceKeypoint.new(0.5, 1),
		NumberSequenceKeypoint.new(1, 1),
	})
	local cupStrokes: { UIStroke } = {}
	for _, x in ipairs({ -3, 47 }) do
		local cup = box({ AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromOffset(x, 22), Size = UDim2.fromOffset(11, 17), BackgroundColor3 = Color3.fromRGB(46, 42, 64), ZIndex = 11, Parent = head }, 5)
		table.insert(cupStrokes, UI.Stroke(cup, Color3.fromRGB(255, 120, 210), 1.5, 0.1))
		box({ AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(4, 9), BackgroundColor3 = Color3.fromRGB(255, 150, 220), ZIndex = 12, Parent = cup }, 2)
	end

	------------------------------------------------------------------
	-- Table, assiette, micro
	------------------------------------------------------------------
	local tableFrame = box({
		Name = "Table",
		Position = UDim2.fromOffset(0, TABLE_Y),
		Size = UDim2.new(1, 0, 0, VIDEO_H - TABLE_Y),
		BackgroundColor3 = Color3.new(1, 1, 1),
		ZIndex = 10,
		Parent = video,
	})
	UI.Gradient(tableFrame, ColorSequence.new(Color3.fromRGB(196, 132, 90), Color3.fromRGB(120, 74, 48)), 90)
	box({ Size = UDim2.new(1, 0, 0, 3), BackgroundColor3 = Color3.fromRGB(230, 170, 120), ZIndex = 10, Parent = tableFrame })
	-- Veines du bois
	for i, y in ipairs({ 14, 26 }) do
		box({ Position = UDim2.new(0.1 * i, 0, 0, y), Size = UDim2.new(0.5, 0, 0, 1), BackgroundColor3 = Color3.fromRGB(110, 66, 40), BackgroundTransparency = 0.5, ZIndex = 10, Parent = tableFrame })
	end

	-- Assiette
	local plate = box({
		Name = "Plate",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 0, PLATE_Y),
		Size = UDim2.fromOffset(72, 16),
		BackgroundColor3 = Color3.fromRGB(252, 252, 255),
		ZIndex = 11,
		Parent = video,
	}, UDim.new(1, 0))
	UI.Stroke(plate, Color3.fromRGB(180, 180, 200), 1.5)
	box({ AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.new(1, -18, 1, -6), BackgroundColor3 = Color3.fromRGB(232, 232, 242), ZIndex = 11, Parent = plate }, UDim.new(1, 0))

	local foods: { TextLabel } = {}
	local foodScales: { UIScale } = {}
	local function foodHome(index: number): UDim2
		return UDim2.new(0.5, FOOD_OFFSETS[index], 0, PLATE_Y - 5)
	end
	for i = 1, #FOOD_OFFSETS do
		local food = text({
			Name = "Food",
			Text = pick(FOODS, random),
			TextSize = 18,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = foodHome(i),
			Size = UDim2.fromOffset(22, 22),
			Rotation = random:NextNumber(-12, 12),
			ZIndex = 12 + i % 2,
			Parent = video,
		})
		foods[i] = food
		foodScales[i] = UI.Create("UIScale", { Parent = food })
	end

	-- Micro ASMR "moumoute" sur pied + voyant ON
	local micStand = box({
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(MIC_X, 0, 0, TABLE_Y + 8),
		Size = UDim2.fromOffset(3, 26),
		BackgroundColor3 = Color3.fromRGB(60, 60, 70),
		ZIndex = 11,
		Parent = video,
	})
	box({ AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.fromScale(0.5, 1), Size = UDim2.fromOffset(18, 4), BackgroundColor3 = Color3.fromRGB(60, 60, 70), ZIndex = 11, Parent = micStand }, 2)
	local mic = box({
		Name = "Mic",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(MIC_X, 0, 0, TABLE_Y - 24),
		Size = UDim2.fromOffset(20, 24),
		BackgroundColor3 = Color3.fromRGB(150, 146, 160),
		ZIndex = 12,
		Parent = video,
	}, UDim.new(1, 0))
	UI.Gradient(mic, ColorSequence.new(Color3.new(1, 1, 1), Color3.fromRGB(170, 170, 180)), 60)
	-- Touffes de fourrure autour
	for i = 0, 5 do
		local angle = i / 6 * math.pi * 2
		box({
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.new(0.5, math.cos(angle) * 9, 0.5, math.sin(angle) * 11),
			Size = UDim2.fromOffset(9, 9),
			BackgroundColor3 = Color3.fromRGB(165, 160, 175),
			ZIndex = 11,
			Parent = mic,
		}, UDim.new(1, 0))
	end
	local micLed = box({ AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 1, 5), Size = UDim2.fromOffset(4, 4), BackgroundColor3 = Color3.fromRGB(255, 50, 70), ZIndex = 13, Parent = mic }, UDim.new(1, 0))

	-- Ondes sonores (réserve de 2 anneaux)
	local waves: { Frame } = {}
	for i = 1, 2 do
		local ring = box({ Name = "Wave" .. i, AnchorPoint = Vector2.new(0.5, 0.5), Position = mic.Position, Size = UDim2.fromOffset(20, 20), BackgroundTransparency = 1, ZIndex = 12, Parent = video }, UDim.new(1, 0))
		UI.Stroke(ring, Color3.fromRGB(255, 255, 255), 1.5, 1)
		waves[i] = ring
	end
	local waveIndex = 0
	local function soundWave(origin: UDim2?)
		if not effectsOn() then
			return
		end
		waveIndex = waveIndex % #waves + 1
		local ring = waves[waveIndex]
		local stroke = ring:FindFirstChildOfClass("UIStroke")
		ring.Position = origin or mic.Position
		ring.Size = UDim2.fromOffset(18, 18)
		UI.Tween(ring, 0.55, { Size = UDim2.fromOffset(54, 54) }, Enum.EasingStyle.Quad)
		if stroke then
			stroke.Transparency = 0.1
			UI.Tween(stroke, 0.55, { Transparency = 1 }, Enum.EasingStyle.Quad)
		end
	end

	------------------------------------------------------------------
	-- Le beurre croustillant (Feature "Butter")
	------------------------------------------------------------------
	local BUTTER_W, BUTTER_H = 34, 22
	local butterButton = UI.Create("TextButton", {
		Name = "Butter",
		Text = "",
		AutoButtonColor = false,
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(BUTTER_X, 0, 0, TABLE_Y + 20),
		Size = UDim2.fromOffset(48, 40),
		Visible = hasButter(),
		ZIndex = 14,
		Parent = video,
	})
	local butterScale = UI.Create("UIScale", { Parent = butterButton })
	-- Coupelle
	local dish = box({
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, 0),
		Size = UDim2.fromOffset(46, 11),
		BackgroundColor3 = Color3.new(1, 1, 1),
		ZIndex = 14,
		Parent = butterButton,
	}, UDim.new(1, 0))
	UI.Gradient(dish, ColorSequence.new(Color3.fromRGB(255, 255, 255), Color3.fromRGB(150, 190, 240)), 90)
	UI.Stroke(dish, Color3.fromRGB(90, 130, 200), 1.2)
	-- Bloc (les traces de dents sont dedans, coupées par ClipsDescendants)
	local block = box({
		Name = "Block",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -5),
		Size = UDim2.fromOffset(BUTTER_W, BUTTER_H),
		BackgroundColor3 = Color3.new(1, 1, 1),
		ClipsDescendants = true,
		ZIndex = 15,
		Parent = butterButton,
	}, 4)
	UI.Gradient(block, ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 244, 160)),
		ColorSequenceKeypoint.new(0.3, Color3.fromRGB(255, 226, 96)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(236, 184, 50)),
	}), 90)
	UI.Stroke(block, Color3.fromRGB(196, 140, 30), 1.5)
	-- Face du dessus (plus claire) + reflet brillant
	box({ Size = UDim2.new(1, 0, 0, 6), BackgroundColor3 = Color3.fromRGB(255, 250, 200), BackgroundTransparency = 0.2, ZIndex = 16, Parent = block })
	local shine = box({ Position = UDim2.fromOffset(4, 8), Size = UDim2.fromOffset(12, 3), BackgroundColor3 = Color3.new(1, 1, 1), BackgroundTransparency = 0.25, ZIndex = 17, Parent = block }, 2)
	local sparkle = text({
		Text = "✨",
		TextSize = 11,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 14, 0, 8),
		Size = UDim2.fromOffset(12, 12),
		TextTransparency = 1,
		ZIndex = 18,
		Parent = butterButton,
	})
	-- Indice "CROQUE !" tant qu'on ne l'a pas croqué
	local butterHint = text({
		Text = "CROQUE !",
		Font = Theme.Fonts.Title,
		TextSize = 9,
		TextColor3 = Color3.fromRGB(90, 50, 0),
		BackgroundColor3 = Color3.fromRGB(255, 226, 96),
		BackgroundTransparency = 0,
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 0, 2),
		Size = UDim2.fromOffset(46, 12),
		ZIndex = 18,
		Parent = butterButton,
	})
	UI.Corner(butterHint, UDim.new(1, 0))

	local bites: { Frame } = {}
	local regenerating = false

	-- Une trace de dents : demi-disque "intérieur" sur le bord du dessus
	local function addBite()
		local size = random:NextInteger(11, 15)
		local slot = #bites
		-- Les bouchées avancent de droite à gauche (puis au hasard)
		local x = slot < 5 and (1 - slot * 0.2 - 0.05) or random:NextNumber(0.1, 0.9)
		local bite = box({
			Name = "Bite",
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.new(x, 0, 0, random:NextInteger(-1, 2)),
			Size = UDim2.fromOffset(size, size),
			BackgroundColor3 = Color3.fromRGB(255, 246, 206),
			ZIndex = 19,
			Parent = block,
		}, UDim.new(1, 0))
		UI.Stroke(bite, Color3.fromRGB(214, 160, 48), 1)
		table.insert(bites, bite)
	end

	local function butterChunks(position: UDim2)
		if not effectsOn() then
			return
		end
		for _ = 1, 4 do
			local size = random:NextInteger(3, 6)
			local chunk = box({
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = position,
				Size = UDim2.fromOffset(size, size),
				BackgroundColor3 = random:NextNumber() < 0.5 and Color3.fromRGB(255, 226, 96) or Color3.fromRGB(255, 246, 190),
				Rotation = random:NextNumber(0, 90),
				ZIndex = 20,
				Parent = video,
			}, 1)
			local dx = random:NextNumber(-26, 26)
			UI.Tween(chunk, 0.18, { Position = position + UDim2.fromOffset(dx * 0.5, -random:NextNumber(8, 20)) }, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
			task.delay(0.18, function()
				if chunk.Parent then
					UI.Tween(chunk, 0.3, {
						Position = position + UDim2.fromOffset(dx, 18),
						Rotation = chunk.Rotation + 180,
						BackgroundTransparency = 1,
					}, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
				end
			end)
			Debris:AddItem(chunk, 0.55)
		end
	end

	-- Le beurre revient tout neuf
	local function regenerateButter()
		regenerating = true
		UI.Tween(butterScale, 0.18, { Scale = 0 }, Enum.EasingStyle.Back, Enum.EasingDirection.In)
		task.delay(1.1, function()
			if not ctx.IsAlive() or not block.Parent then
				return
			end
			for _, bite in ipairs(bites) do
				bite:Destroy()
			end
			table.clear(bites)
			block.Size = UDim2.fromOffset(BUTTER_W, BUTTER_H)
			butterScale.Scale = 0.2
			UI.Tween(butterScale, 0.45, { Scale = 1 }, Enum.EasingStyle.Back)
			regenerating = false
		end)
	end

	------------------------------------------------------------------
	-- Onomatopées, miettes, cœurs
	------------------------------------------------------------------
	local popLabels: { TextLabel } = {}
	local popIndex = 0
	for i = 1, 3 do
		local label = text({
			Name = "Pop" .. i,
			Text = "",
			Font = Enum.Font.LuckiestGuy,
			TextSize = 17,
			TextTransparency = 1,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Size = UDim2.fromOffset(110, 24),
			ZIndex = 22,
			Parent = video,
		})
		local stroke = UI.Stroke(label, Color3.fromRGB(40, 20, 30), 2, 1)
		stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
		UI.Create("UIScale", { Parent = label })
		popLabels[i] = label
	end

	local function popWord(word: string, position: UDim2, color: Color3?)
		popIndex = popIndex % #popLabels + 1
		local label = popLabels[popIndex]
		local stroke = label:FindFirstChildOfClass("UIStroke")
		local scale = label:FindFirstChildOfClass("UIScale")
		label.Text = word
		label.TextColor3 = color or pick(POP_COLORS, random)
		label.Position = position
		label.Rotation = random:NextNumber(-14, 14)
		label.TextTransparency = 0
		if stroke then
			stroke.Transparency = 0
			UI.Tween(stroke, 0.6, { Transparency = 1 }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		end
		if scale then
			scale.Scale = 0.3
			UI.Tween(scale, 0.22, { Scale = 1.15 }, Enum.EasingStyle.Back)
		end
		UI.Tween(label, 0.8, {
			Position = position + UDim2.fromOffset(random:NextInteger(-8, 8), -24),
			TextTransparency = 1,
		}, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
	end

	local function crumbs()
		if not effectsOn() then
			return
		end
		for _ = 1, 4 do
			local size = random:NextInteger(2, 4)
			local crumb = box({
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.new(0.5, random:NextInteger(-6, 6), 0, MOUTH_Y + 4),
				Size = UDim2.fromOffset(size, size),
				BackgroundColor3 = Color3.fromRGB(230, 170, 90),
				Rotation = random:NextNumber(0, 90),
				ZIndex = 13,
				Parent = video,
			})
			UI.Tween(crumb, 0.55, {
				Position = UDim2.new(0.5, random:NextInteger(-30, 30), 0, PLATE_Y - 4),
				Rotation = random:NextNumber(90, 360),
				BackgroundTransparency = 0.4,
			}, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
			Debris:AddItem(crumb, 0.6)
		end
	end

	local hearts: { { Label: TextLabel, Start: number, Life: number, X: number, Sway: number } } = {}
	for i = 1, MAX_HEARTS do
		local label = text({
			Name = "Heart" .. i,
			Text = "❤️",
			TextSize = 13,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Size = UDim2.fromOffset(16, 16),
			Visible = false,
			ZIndex = 21,
			Parent = video,
		})
		hearts[i] = { Label = label, Start = -math.huge, Life = 1.6, X = 0, Sway = 0 }
	end
	local function spawnHeart(emoji: string?)
		for _, heart in ipairs(hearts) do
			if not heart.Label.Visible then
				heart.Label.Text = emoji or pick(HEARTS, random)
				heart.Start = os.clock()
				heart.Life = random:NextNumber(1.3, 2)
				heart.X = random:NextNumber(-10, 4)
				heart.Sway = random:NextNumber(0, math.pi * 2)
				heart.Label.Visible = true
				return
			end
		end
	end

	-- Likes (compteur qui grimpe)
	local likes = random:NextInteger(120, 400) * (1 + followers())
	local function addLikes(amount: number, bump: boolean)
		likes += amount
		if bump then
			likesScale.Scale = 1.3
			UI.Tween(likesScale, 0.3, { Scale = 1 }, Enum.EasingStyle.Back)
		end
	end

	------------------------------------------------------------------
	-- Expressions (pilotées par OnRender)
	------------------------------------------------------------------
	local chewUntil = 0
	local openUntil = 0
	local wowUntil = 0
	local nextBlink = os.clock() + random:NextNumber(1.5, 4)
	local blinkUntil = 0

	local function wow(duration: number?)
		wowUntil = os.clock() + (duration or 0.6)
	end

	------------------------------------------------------------------
	-- Chat (Feature "LiveChat") : titre, message épinglé, liste qui défile
	-- en douceur (fondu en haut)
	------------------------------------------------------------------
	local CHAT_BG = Color3.fromRGB(32, 28, 46)
	local LIST_Y = 44
	local LIST_H = VIDEO_H - LIST_Y - 2
	local chat = box({
		Name = "Chat",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -VIDEO_X, 0, VIDEO_Y),
		Size = UDim2.fromOffset(CHAT_W, VIDEO_H),
		BackgroundColor3 = CHAT_BG,
		ClipsDescendants = true,
		Visible = hasChat(),
		ZIndex = 2,
		Parent = card,
	}, 10)
	UI.Stroke(chat, Color3.fromRGB(70, 60, 100), 1)
	local chatTitle = text({
		Name = "Title",
		Text = "💬 <b>Chat</b>",
		RichText = true,
		TextSize = 10,
		TextColor3 = Color3.fromRGB(220, 212, 245),
		TextXAlignment = Enum.TextXAlignment.Left,
		Position = UDim2.fromOffset(6, 2),
		Size = UDim2.new(1, -8, 0, 14),
		ZIndex = 3,
		Parent = chat,
	})
	box({ Position = UDim2.fromOffset(6, 17), Size = UDim2.new(1, -12, 0, 1), BackgroundColor3 = Color3.fromRGB(80, 70, 110), ZIndex = 3, Parent = chat })

	-- Message épinglé
	local pinned = box({
		Name = "Pinned",
		Position = UDim2.fromOffset(4, 20),
		Size = UDim2.new(1, -8, 0, 22),
		BackgroundColor3 = Color3.fromRGB(64, 50, 100),
		ZIndex = 3,
		Parent = chat,
	}, 5)
	UI.Stroke(pinned, Color3.fromRGB(150, 110, 230), 1, 0.4)
	local pinnedLabel = UI.Label({
		Text = "",
		RichText = true,
		Font = Theme.Fonts.Body,
		TextColor3 = Color3.fromRGB(235, 225, 255),
		TextXAlignment = Enum.TextXAlignment.Left,
		Position = UDim2.fromOffset(3, 1),
		Size = UDim2.new(1, -5, 1, -2),
		MaxTextSize = 9,
		ZIndex = 4,
		Parent = pinned,
	})

	local chatList = box({
		Name = "Messages",
		Position = UDim2.fromOffset(0, LIST_Y),
		Size = UDim2.new(1, 0, 0, LIST_H),
		BackgroundTransparency = 1,
		ClipsDescendants = true,
		ZIndex = 3,
		Parent = chat,
	})
	-- Le "rouleau" est accroché en bas et grandit vers le haut ; quand un
	-- message arrive, on le décale d'autant puis on le ramène en douceur
	local scroller = box({
		Name = "Scroller",
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.fromScale(0, 1),
		Size = UDim2.fromScale(1, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
		ZIndex = 3,
		Parent = chatList,
	})
	UI.Create("UIListLayout", {
		SortOrder = Enum.SortOrder.LayoutOrder,
		Padding = UDim.new(0, 2),
		Parent = scroller,
	})
	UI.Create("UIPadding", {
		PaddingLeft = UDim.new(0, 4),
		PaddingRight = UDim.new(0, 3),
		PaddingBottom = UDim.new(0, 2),
		Parent = scroller,
	})
	-- Fondu en haut de la liste
	local fade = box({
		Name = "Fade",
		Size = UDim2.new(1, 0, 0, 22),
		BackgroundColor3 = CHAT_BG,
		ZIndex = 8,
		Parent = chatList,
	})
	local fadeGradient = UI.Gradient(fade, ColorSequence.new(Color3.new(1, 1, 1)), 90)
	fadeGradient.Transparency = NumberSequence.new(0, 1)

	local lastScrollerHeight = 0
	local scrollTween: Tween? = nil
	ctx.Connect(scroller:GetPropertyChangedSignal("AbsoluteSize"), function()
		local height = scroller.AbsoluteSize.Y
		local delta = height - lastScrollerHeight
		lastScrollerHeight = height
		-- (les messages retirés sont en haut, hors champ : rien à animer)
		local ratio = chatList.AbsoluteSize.Y / LIST_H
		if delta <= 0 or ratio <= 0 then
			return
		end
		local offset = math.min(scroller.Position.Y.Offset + delta / ratio, 80)
		if scrollTween then
			scrollTween:Cancel()
		end
		scroller.Position = UDim2.new(0, 0, 1, offset)
		scrollTween = UI.Tween(scroller, 0.28, { Position = UDim2.fromScale(0, 1) }, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	end)

	-- Dons affichés en haut de la vidéo quand il n'y a pas de chat
	local donationStack = box({
		Name = "Donations",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 12),
		Size = UDim2.new(1, -14, 0, 100),
		BackgroundTransparency = 1,
		ZIndex = 24,
		Parent = video,
	})
	UI.Create("UIListLayout", {
		SortOrder = Enum.SortOrder.LayoutOrder,
		Padding = UDim.new(0, 3),
		Parent = donationStack,
	})

	-- Entrées du chat (messages + cartes de don épinglées tant qu'elles attendent)
	type ChatEntry = { Instance: GuiObject, Pinned: boolean }
	local chatEntries: { ChatEntry } = {}
	local chatOrder = 0

	-- Retire les plus vieux messages (appelé à part, pas dans la même image
	-- qu'un ajout, pour que le défilement reste fluide)
	local function trimChat()
		local index = 1
		while #chatEntries > MAX_CHAT and index <= #chatEntries do
			local entry = chatEntries[index]
			if entry.Pinned and entry.Instance.Parent then
				index += 1
			else
				table.remove(chatEntries, index)
				if entry.Instance.Parent then
					entry.Instance:Destroy()
				end
			end
		end
	end

	local function nameHash(name: string): number
		local sum = 0
		for i = 1, #name do
			sum += string.byte(name, i) * i
		end
		return sum
	end

	local function nameColor(name: string): string
		return NAME_COLORS[nameHash(name) % #NAME_COLORS + 1]
	end

	-- Rôle stable par pseudo : 🛡️ modo, 👑 VIP, 💎 abonné (ou rien)
	local function roleBadge(name: string): string
		if MODS[name] then
			return "🛡️"
		end
		local roll = nameHash(name) % 10
		if roll <= 1 then
			return "👑"
		elseif roll <= 5 then
			return "💎"
		end
		return ""
	end

	type ChatOptions = { Badge: string?, Highlight: Color3?, Emote: boolean? }

	local function addChatLabel(richText: string, highlight: Color3?)
		chatOrder += 1
		local label = text({
			Name = "Msg",
			Text = richText,
			RichText = true,
			TextSize = 10,
			TextWrapped = true,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextTransparency = 1,
			BackgroundColor3 = highlight or Color3.new(0, 0, 0),
			BackgroundTransparency = highlight and 0.55 or 1,
			AutomaticSize = Enum.AutomaticSize.Y,
			Size = UDim2.fromScale(1, 0),
			LayoutOrder = chatOrder,
			ZIndex = 4,
			Parent = scroller,
		})
		if highlight then
			UI.Corner(label, 4)
			UI.Create("UIPadding", {
				PaddingLeft = UDim.new(0, 2),
				PaddingRight = UDim.new(0, 2),
				PaddingTop = UDim.new(0, 1),
				PaddingBottom = UDim.new(0, 1),
				Parent = label,
			})
		end
		UI.Tween(label, 0.25, { TextTransparency = 0 })
		table.insert(chatEntries, { Instance = label, Pinned = false })
	end

	local function pushChat(name: string, message: string, options: ChatOptions?)
		if not chat.Visible then
			return
		end
		local badge = (options and options.Badge) or roleBadge(name)
		local prefix = badge ~= "" and (badge .. " ") or ""
		local body = escape(message)
		if options and options.Emote then
			body = '<font size="14">' .. body .. "</font>"
		end
		addChatLabel(prefix .. '<font color="' .. nameColor(name) .. '"><b>' .. escape(name) .. "</b></font> " .. body, options and options.Highlight)
	end

	-- Message système (raid, abonnement...) : sans pseudo, surligné
	local function systemMessage(richText: string, color: Color3)
		if not chat.Visible then
			return
		end
		addChatLabel("<i>" .. richText .. "</i>", color)
	end

	local HOST_OPTIONS: ChatOptions = { Badge = "🎙️", Highlight = Color3.fromRGB(145, 70, 255) }
	local function hostSays(message: string)
		pushChat(HOST, message, HOST_OPTIONS)
	end

	local function randomName(): string
		return pick(NAMES, random)
	end

	-- Réaction du chat limitée (pas plus d'une par `interval` pour une même clé)
	local lastReaction: { [string]: number } = {}
	local function react(key: string, interval: number, list: { string }, extra: number?)
		local now = os.clock()
		if now - (lastReaction[key] or 0) < interval then
			return
		end
		lastReaction[key] = now
		pushChat(randomName(), pick(list, random))
		-- Quelques messages de plus, un peu après (le chat s'emballe)
		for i = 1, extra or 0 do
			task.delay(0.25 * i + random:NextNumber(0, 0.2), function()
				if ctx.IsAlive() then
					pushChat(randomName(), pick(list, random))
				end
			end)
		end
	end

	-- Texte du message épinglé (dépend de l'abonnement et du beurre)
	local function refreshPinned(followed: boolean)
		if not followed then
			pinnedLabel.Text = "📌 <b>Suis</b> pour débloquer les dons 💸"
		elseif hasButter() then
			pinnedLabel.Text = "📌 Merci les abonnés 💜 Croquez le <b>beurre</b> !"
		else
			pinnedLabel.Text = "📌 Merci les abonnés 💜 Soyez gentils !"
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
			hostSays("le chat est ouvert !! 🎉")
		else
			chat.Visible = false
		end
	end

	-- Affiche / cache le beurre
	local butterShown = butterButton.Visible
	local function applyButterVisibility()
		local shown = hasButter()
		if shown == butterShown then
			return
		end
		butterShown = shown
		butterButton.Visible = shown
		if shown then
			butterScale.Scale = 0.2
			UI.Tween(butterScale, 0.5, { Scale = 1 }, Enum.EasingStyle.Back)
			hostSays("j'ai ramené du BEURRE 🧈")
		end
		refreshPinned(isFollowedOnServer())
	end

	ctx.Connect(ctx.State.FeaturesChanged, function()
		applyChatVisibility()
		applyButterVisibility()
	end)

	------------------------------------------------------------------
	-- Spectateurs : grimpent avec le niveau "Abonnés"
	------------------------------------------------------------------
	local followPendingUntil = 0
	local function isFollowed(): boolean
		return isFollowedOnServer() or os.clock() < followPendingUntil
	end

	local function targetViewers(): number
		local base = 40 * (1.9 ^ followers())
		if hasChat() then
			base *= 1.5
		end
		if isFollowed() then
			base *= 1.15
		end
		return base
	end
	local viewers = targetViewers() * random:NextNumber(0.9, 1.1)
	local shownViewers = viewers
	local shownLikes = likes

	local function formatCount(value: number): string
		if value < 1e4 then
			return Format.WithSpaces(value)
		end
		return Format.Format(value, 1)
	end

	------------------------------------------------------------------
	-- Bouton "Suivre" : récompense unique, puis "✔ Abonné" et les dons
	------------------------------------------------------------------
	local shownFollowed: boolean? = nil
	local function refreshFollow(announce: boolean)
		local followed = isFollowed()
		if followed == shownFollowed then
			return
		end
		local wasShown = shownFollowed
		shownFollowed = followed
		refreshPinned(followed)
		if followed then
			followButton.Text = "✔ Abonné"
			followButton.BackgroundColor3 = FOLLOWED_COLOR
			followGradient.Color = ColorSequence.new(Color3.new(1, 1, 1), Color3.fromRGB(220, 220, 230))
			followStroke.Color = Color3.fromRGB(120, 110, 150)
			if announce and wasShown == false then
				systemMessage("💜 Tu suis maintenant <b>" .. HOST .. "</b> !", Color3.fromRGB(120, 60, 200))
				hostSays("merci pour le follow !! les dons sont ouverts 💸")
			end
		else
			followButton.Text = "💜 Suivre"
			followButton.BackgroundColor3 = FOLLOW_COLOR
			followGradient.Color = ColorSequence.new(Color3.new(1, 1, 1), Color3.fromRGB(205, 190, 230))
			followStroke.Color = Color3.fromRGB(210, 180, 255)
		end
	end
	refreshFollow(false)
	ctx.Connect(ctx.State.Changed, function()
		refreshFollow(true)
	end)

	ctx.Connect(followButton.Activated, function()
		if isFollowed() then
			-- Déjà abonné : petit cœur pour le plaisir
			spawnHeart("💜")
			addLikes(1, true)
			return
		end
		followPendingUntil = os.clock() + 6 -- en attendant la confirmation du serveur
		ctx.Interact("Follow")
		ctx.Sound.Play("Pop", 1.3)
		for _ = 1, 4 do
			spawnHeart("💜")
		end
		viewers += 1
		addLikes(10, true)
		wow(0.8)
		refreshFollow(true)
		task.delay(0.6, function()
			if ctx.IsAlive() then
				react("follow", 0.5, FOLLOW_REACTIONS, 2)
			end
		end)
	end)

	ctx.OnBonus("Follow", function(payload)
		local amount = tonumber(payload.Amount)
		if amount then
			ctx.FloatText(card, UDim2.fromOffset(CARD_W - 44, 30), "+" .. Format.Format(amount), Theme.Colors.Gold, 22)
		end
		ctx.Effects.Burst(card, UDim2.fromOffset(CARD_W - 44, 18), Color3.fromRGB(190, 120, 255), 10)
		ctx.Sound.Play("Bonus", 1.1)
	end)

	------------------------------------------------------------------
	-- Dons (Spawner "Donation") : carte cliquable -> ClaimSpawn
	------------------------------------------------------------------
	type Donation = {
		Card: TextButton,
		Title: TextLabel,
		Sub: TextLabel,
		Name: string,
		Claimed: boolean,
		Done: boolean,
		ExpiresAt: number,
		Entry: ChatEntry?,
	}
	local donations: { [string]: Donation } = {}

	local function removeDonation(id: string, delay: number)
		local donation = donations[id]
		if not donation or donation.Done then
			return
		end
		donation.Done = true
		if donation.Entry then
			donation.Entry.Pinned = false
		end
		task.delay(delay, function()
			local cardFrame = donation.Card
			if cardFrame.Parent then
				-- Se replie en douceur (les messages au-dessus redescendent)
				cardFrame.ClipsDescendants = true
				UI.Tween(cardFrame, 0.3, { BackgroundTransparency = 1, Size = UDim2.fromScale(1, 0) }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
				UI.Tween(donation.Title, 0.2, { TextTransparency = 1 })
				UI.Tween(donation.Sub, 0.2, { TextTransparency = 1 })
				local stroke = cardFrame:FindFirstChildOfClass("UIStroke")
				if stroke then
					UI.Tween(stroke, 0.2, { Transparency = 1 })
				end
				Debris:AddItem(cardFrame, 0.35)
			end
			task.delay(0.4, function()
				if donations[id] == donation then
					donations[id] = nil
				end
			end)
		end)
	end

	local function createDonation(info: any)
		local id = info.Id
		if type(id) ~= "string" or donations[id] then
			return
		end
		local variant = math.floor(tonumber(info.Variant) or random:NextInteger(1, 1000))
		local name = NAMES[(variant - 1) % #NAMES + 1]
		local line = DONATION_LINES[(variant - 1) % #DONATION_LINES + 1]
		local lifetime = tonumber(info.Lifetime) or 10
		local inChat = chat.Visible
		local height = inChat and 34 or 28

		chatOrder += 1
		local button = UI.Create("TextButton", {
			Name = "Donation",
			Text = "",
			AutoButtonColor = false,
			BackgroundColor3 = Color3.new(1, 1, 1),
			BorderSizePixel = 0,
			Size = UDim2.new(1, 0, 0, height),
			LayoutOrder = chatOrder,
			ZIndex = 25,
			Parent = inChat and scroller or donationStack,
		})
		UI.Corner(button, 6)
		UI.Gradient(button, ColorSequence.new(Color3.fromRGB(255, 226, 110), Color3.fromRGB(255, 160, 50)), 20)
		UI.Stroke(button, Color3.fromRGB(190, 110, 0), 1.5)
		local icon = text({
			Text = "💸",
			TextSize = inChat and 13 or 15,
			AnchorPoint = Vector2.new(0, 0.5),
			Position = UDim2.new(0, 2, 0.5, 0),
			Size = UDim2.fromOffset(18, 18),
			ZIndex = 26,
			Parent = button,
		})
		local title = text({
			Text = "<b>" .. escape(name) .. "</b> " .. line,
			RichText = true,
			TextSize = inChat and 9 or 10,
			TextColor3 = Color3.fromRGB(70, 36, 0),
			TextXAlignment = Enum.TextXAlignment.Left,
			TextWrapped = inChat,
			TextTruncate = inChat and Enum.TextTruncate.None or Enum.TextTruncate.AtEnd,
			Position = UDim2.fromOffset(21, 2),
			Size = UDim2.new(1, -23, 0, inChat and 20 or 13),
			ZIndex = 26,
			Parent = button,
		})
		local sub = text({
			Text = "Clique pour récupérer ✨",
			Font = Theme.Fonts.Title,
			TextSize = 9,
			TextColor3 = Color3.fromRGB(140, 60, 0),
			TextXAlignment = Enum.TextXAlignment.Left,
			Position = UDim2.new(0, 21, 1, -13),
			Size = UDim2.new(1, -23, 0, 10),
			ZIndex = 26,
			Parent = button,
		})
		local timer = box({
			AnchorPoint = Vector2.new(0, 1),
			Position = UDim2.new(0, 4, 1, -1),
			Size = UDim2.new(1, -8, 0, 2),
			BackgroundColor3 = Color3.fromRGB(255, 255, 255),
			BackgroundTransparency = 0.2,
			ZIndex = 27,
			Parent = button,
		}, 1)
		TweenService:Create(timer, TweenInfo.new(lifetime, Enum.EasingStyle.Linear), { Size = UDim2.new(0, 0, 0, 2) }):Play()

		-- Pulsation pour attirer l'œil
		-- (nommé "PopScale" : UIUtil.Pop le réutilise au clic, un seul UIScale)
		local pulse = UI.Create("UIScale", { Name = "PopScale", Scale = 0.3, Parent = button })
		UI.Tween(pulse, 0.35, { Scale = 1 }, Enum.EasingStyle.Back)
		task.delay(0.36, function()
			local current = donations[id]
			if button.Parent and current and not current.Claimed then
				TweenService:Create(pulse, TweenInfo.new(0.45, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), { Scale = 1.05 }):Play()
			end
		end)

		local entry: ChatEntry? = nil
		if inChat then
			entry = { Instance = button, Pinned = true }
			table.insert(chatEntries, entry :: ChatEntry)
		end

		local donation: Donation = {
			Card = button,
			Title = title,
			Sub = sub,
			Name = name,
			Claimed = false,
			Done = false,
			ExpiresAt = os.clock() + lifetime,
			Entry = entry,
		}
		donations[id] = donation

		ctx.Sound.Play("Notif", 1.2)
		spawnHeart("💸")
		wow(0.7)

		ctx.Connect(button.Activated, function()
			if donation.Claimed or donation.Done then
				return
			end
			donation.Claimed = true
			ctx.ClaimSpawn(id)
			ctx.Sound.Play("Cash", 1)
			sub.Text = "⏳ ..."
			icon.Text = "🤑"
			UI.Pop(button, 1.15, 0.3)
			-- Sans réponse du serveur (don expiré), la carte s'efface quand même
			removeDonation(id, 2.5)
		end)
	end

	ctx.OnSpawn("Donation", createDonation)

	ctx.OnBonus("Donation", function(payload)
		local amount = tonumber(payload.Amount)
		local donation = type(payload.SpawnId) == "string" and donations[payload.SpawnId] or nil
		local amountText = amount and ("+" .. Format.Format(amount)) or ""
		if donation and donation.Card.Parent then
			donation.Title.Text = "✔ Merci <b>" .. escape(donation.Name) .. "</b> !"
			donation.Sub.Text = amountText ~= "" and (amountText .. " Dopamine 💜") or "Merci 💜"
			if amount then
				ctx.FloatText(donation.Card, UDim2.fromScale(0.5, 0.5), amountText, Theme.Colors.Gold, 22)
			end
			ctx.Effects.Burst(donation.Card, UDim2.fromScale(0.5, 0.5), Theme.Colors.Gold, 8)
		elseif amount then
			ctx.FloatText(video, UDim2.new(0.5, 0, 0, 40), amountText, Theme.Colors.Gold, 22)
		end
		for _ = 1, 3 do
			spawnHeart("💸")
		end
		addLikes(random:NextInteger(20, 60), true)
		wow(0.9)
		soundWave(nil)
		popWord("MERCI !!", UDim2.new(0.5, 0, 0, MOUTH_Y - 20), Color3.fromRGB(255, 214, 40))
		task.delay(0.4, function()
			if ctx.IsAlive() then
				react("donation", 0.8, DONATION_REACTIONS, 2)
			end
		end)
	end)

	------------------------------------------------------------------
	-- Clic sur le beurre : CROUNCH (limité à MaxPerSecond)
	------------------------------------------------------------------
	local butterConfig = ctx.Config.Interactions and ctx.Config.Interactions.Butter
	local butterMaxPerSecond = (butterConfig and tonumber(butterConfig.MaxPerSecond)) or 8
	local butterFraction = (butterConfig and tonumber(butterConfig.ClickFraction)) or 0.75
	local butterInterval = 1 / math.max(1, butterMaxPerSecond)
	local lastButter = -math.huge
	local butterCrunches = 0

	ctx.Connect(butterButton.Activated, function()
		if not hasButter() or regenerating then
			return
		end
		local now = os.clock()
		if now - lastButter < butterInterval then
			-- Trop rapide : petite secousse seulement (pas de rotation : le
			-- bloc découpe ses traces de dents avec ClipsDescendants)
			butterButton.Position = UDim2.new(BUTTER_X, random:NextInteger(-2, 2), 0, TABLE_Y + 20)
			UI.Tween(butterButton, 0.12, { Position = UDim2.new(BUTTER_X, 0, 0, TABLE_Y + 20) })
			return
		end
		lastButter = now
		butterCrunches += 1

		ctx.Interact("Butter")
		ctx.Sound.Play("Crunch", random:NextNumber(0.9, 1.15))

		-- Écrasement + trace de dents
		butterScale.Scale = 0.82
		UI.Tween(butterScale, 0.25, { Scale = 1 }, Enum.EasingStyle.Back)
		addBite()
		local eaten = #bites / BUTTER_BITES
		block.Size = UDim2.fromOffset(BUTTER_W * (1 - eaten * 0.25), BUTTER_H * (1 - eaten * 0.45))
		if butterHint.Visible then
			butterHint.Visible = false
		end

		local butterTop = UDim2.new(BUTTER_X, 0, 0, TABLE_Y + 2)
		butterChunks(butterTop)
		soundWave(butterTop)
		popWord(pick(BUTTER_WORDS, random), UDim2.new(BUTTER_X, -10, 0, TABLE_Y - 18), Color3.fromRGB(255, 226, 96))

		-- "+X" prédit (le serveur donne gain par clic x ClickFraction)
		local data = ctx.State.Data
		local value = (data and tonumber(data.ClickValue) or 0) * butterFraction
		if value > 0 then
			ctx.FloatText(video, UDim2.new(BUTTER_X, 0, 0, TABLE_Y - 6), "+" .. Format.Format(value), Theme.Colors.Gold, 18)
		end

		wow(0.4)
		addLikes(random:NextInteger(1, 4), butterCrunches % 3 == 0)
		react("butter", 1.2, BUTTER_REACTIONS)

		if #bites >= BUTTER_BITES then
			regenerateButter()
			task.delay(0.3, function()
				if ctx.IsAlive() then
					hostSays("plus de beurre... j'en ressers ! 🧈")
				end
			end)
		end
	end)

	------------------------------------------------------------------
	-- Animation continue
	------------------------------------------------------------------
	local clock = 0
	local nextHeart = 0.5
	local viewersTimer = 0
	local likesTimer = 0
	local followTimer = 0
	local trimTimer = 1
	local sparkleTimer = 2
	ctx.OnRender(function(dt: number)
		dt = math.min(dt, 0.1)
		clock += dt
		local now = os.clock()

		-- Balancement doux (plus rapide quand elle mâche)
		local chewing = now < chewUntil
		local bob = chewing and math.abs(math.sin(clock * 9)) * 2 or math.sin(clock * 2) * 1.5
		streamer.Position = UDim2.new(0.5, 0, 0, streamerY + bob)
		head.Rotation = chewing and math.sin(clock * 7) * 4 or math.sin(clock * 1.3) * 3

		-- Yeux : clignement, fermés (contente) quand elle mâche, grands ouverts si "wow"
		if now >= nextBlink then
			blinkUntil = now + 0.12
			nextBlink = now + random:NextNumber(2, 5)
		end
		local amazed = now < wowUntil
		local eyeHeight = 7
		if amazed then
			eyeHeight = 9
		elseif chewing or now < blinkUntil then
			eyeHeight = 2
		end
		for _, eye in ipairs(eyes) do
			eye.Size = UDim2.fromOffset(amazed and 7 or 6, eyeHeight)
		end
		for i, brow in ipairs(brows) do
			local x = i == 1 and 15 or 29
			brow.Position = UDim2.fromOffset(x, amazed and 13 or 16)
			brow.Rotation = amazed and (i == 1 and -12 or 12) or 0
		end

		-- Bouche
		local mouthW, mouthH = 8, 3
		if amazed then
			mouthW, mouthH = 8, 8
		elseif now < openUntil then
			mouthW, mouthH = 11, 9
		elseif chewing then
			mouthW, mouthH = 9, 3 + math.abs(math.sin(clock * 16)) * 5
		end
		mouth.Size = UDim2.fromOffset(mouthW, mouthH)
		tongue.Visible = mouthH >= 7

		-- Casque qui brille au rythme, badge LIVE, ruban LED, néon
		local glow = 0.5 + 0.5 * math.sin(clock * 3)
		for _, stroke in ipairs(cupStrokes) do
			stroke.Transparency = 0.05 + glow * 0.5
		end
		liveScale.Scale = 1 + math.max(0, math.sin(clock * 4)) * 0.05
		liveDot.BackgroundTransparency = math.sin(clock * 5) > 0 and 0 or 0.6
		micLed.BackgroundTransparency = math.sin(clock * 2.5) > -0.3 and 0 or 0.5
		ledGradient.Offset = Vector2.new((clock * 0.15) % 1 - 0.5, 0)
		ringGradient.Rotation = (clock * 60) % 360
		if strokeGradient then
			strokeGradient.Rotation = (clock * 30) % 360
		end
		ringStroke.Transparency = 0.1 + glow * 0.15
		neonSign.TextTransparency = (math.sin(clock * 23) > 0.94) and 0.6 or 0
		shine.BackgroundTransparency = 0.2 + glow * 0.3

		-- Scintillement du beurre
		if butterButton.Visible then
			sparkleTimer -= dt
			if sparkleTimer <= 0 then
				sparkleTimer = random:NextNumber(1.5, 3.5)
				sparkle.TextTransparency = 0
				sparkle.Position = UDim2.new(0.5, random:NextInteger(-12, 14), 0, random:NextInteger(6, 16))
				UI.Tween(sparkle, 0.6, { TextTransparency = 1 })
			end
			if butterHint.Visible then
				butterHint.Position = UDim2.new(0.5, 0, 0, 2 - math.abs(math.sin(clock * 4)) * 3)
			end
		end

		-- Cœurs qui montent à droite
		for _, heart in ipairs(hearts) do
			local label = heart.Label
			if label.Visible then
				local t = (now - heart.Start) / heart.Life
				if t >= 1 then
					label.Visible = false
				else
					label.Position = UDim2.new(1, -14 + heart.X + math.sin(heart.Sway + t * 6) * 5, 0, TABLE_Y - 20 - t * 70)
					label.TextTransparency = t * t
					label.Rotation = math.sin(heart.Sway + t * 4) * 15
				end
			end
		end
		nextHeart -= dt
		if nextHeart <= 0 then
			nextHeart = random:NextNumber(0.6, 1.8) / (1 + followers() * 0.12)
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
		local rising = viewers > shownViewers + 0.5
		viewersLabel.Text = (rising and "▲ " or "👁 ") .. formatCount(math.floor(shownViewers + 0.5))
		viewersLabel.TextColor3 = rising and Color3.fromRGB(120, 255, 150) or Color3.fromRGB(200, 192, 230)

		-- Likes : montent tout seuls avec les spectateurs
		likesTimer -= dt
		if likesTimer <= 0 then
			likesTimer = 0.5
			addLikes(math.max(0, math.floor(viewers * random:NextNumber(0, 0.004) + random:NextNumber(0, 1.2))), false)
		end
		shownLikes += (likes - shownLikes) * math.min(1, dt * 5)
		likesLabel.Text = "❤ " .. formatCount(math.floor(shownLikes + 0.5))

		-- Nettoyage des vieux messages du chat (hors champ)
		trimTimer -= dt
		if trimTimer <= 0 then
			trimTimer = 1.3
			trimChat()
		end

		-- Abonnement : suit l'état serveur (et annule une attente expirée)
		followTimer -= dt
		if followTimer <= 0 then
			followTimer = 0.5
			refreshFollow(true)
		end

		-- Dons non cliqués : disparaissent à la fin de leur durée
		for id, donation in pairs(donations) do
			if not donation.Done and now >= donation.ExpiresAt then
				if not donation.Claimed then
					donation.Sub.Text = "Trop tard 😢"
				end
				removeDonation(id, 0.4)
			end
		end
	end)

	------------------------------------------------------------------
	-- Boucle de repas : un aliment à la fois
	------------------------------------------------------------------
	local function refillPlate()
		for i, food in ipairs(foods) do
			food.Text = pick(FOODS, random)
			food.Rotation = random:NextNumber(-12, 12)
			foodScales[i].Scale = 1
			food.Position = foodHome(i) - UDim2.fromOffset(0, 60)
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
			task.wait(random:NextNumber(1.2, 2) / (1 + math.min(followers(), 15) * 0.02))
			if not ctx.IsAlive() then
				break
			end

			local index = nil
			for i, food in ipairs(foods) do
				if food.Visible then
					index = i
					break
				end
			end

			if not index then
				-- Assiette vide : on ressert !
				wow(0.8)
				popWord("RESSERVI !", UDim2.new(0.5, 0, 0, MOUTH_Y - 16), nil)
				task.wait(0.5)
				if not ctx.IsAlive() then
					break
				end
				refillPlate()
				pushChat(randomName(), "ELLE RESSERT 😭🔥")
				task.wait(0.7)
			else
				local food = foods[index]
				local scale = foodScales[index]
				-- Le bras apporte l'aliment à la bouche grande ouverte
				openUntil = os.clock() + 0.5
				UI.Tween(armRight, 0.3, { Rotation = ARM_EAT }, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
				UI.Tween(food, 0.3, { Position = UDim2.new(0.5, 4, 0, MOUTH_Y + 2), Rotation = 0 }, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
				UI.Tween(scale, 0.3, { Scale = 0.6 }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
				task.wait(0.32)
				if not ctx.IsAlive() then
					break
				end
				-- CROC !
				food.Visible = false
				openUntil = 0
				chewUntil = os.clock() + 1
				UI.Tween(armRight, 0.4, { Rotation = ARM_REST_R }, Enum.EasingStyle.Back)
				popWord(pick(CRUNCH_WORDS, random), UDim2.new(0.5, random:NextNumber() < 0.5 and -34 or 34, 0, MOUTH_Y - 6), nil)
				crumbs()
				soundWave(nil)
				ctx.Sound.Play("Pop", random:NextNumber(0.55, 0.75))
				addLikes(random:NextInteger(2, 8), true)
				if random:NextNumber() < 0.45 then
					react("eat", 0.5, EAT_REACTIONS)
				end
			end
		end
	end)

	------------------------------------------------------------------
	-- Gros gains du joueur : le chat s'enflamme
	------------------------------------------------------------------
	local BIG_SOURCES = { Golden = true, Lightning = true, DVD = true, Email = true }
	ctx.Connect(ctx.State.NotifyReceived, function(payload)
		if type(payload) ~= "table" or not chat.Visible then
			return
		end
		local kind = payload.Type
		if kind == "Jackpot" then
			react("big", 1, { "JACKPOT ?!", "JACKPOT 🤑🤑🤑", "le coin du DVD !!!" }, 3)
		elseif kind == "Rush" then
			react("big", 1, { "RUSH !!! 🚀", "tout le monde clique !!", "c'est le rush 🔥" }, 2)
		elseif kind == "Achievement" then
			react("achievement", 2, { "GG pour le succès 🏆", "succès débloqué 👏", "trop fort 🏆" }, 0)
		elseif kind == "Unlock" then
			react("unlock", 2, { "nouvelle amélioration 👀", "c'est quoi ce truc ??", "ça devient n'importe quoi 😂" }, 0)
		elseif kind == "Bonus" and BIG_SOURCES[payload.Source] then
			react("big", 1.5, BIG_GAIN_REACTIONS, 1)
		end
	end)

	------------------------------------------------------------------
	-- Raid : une autre chaîne débarque avec ses spectateurs
	------------------------------------------------------------------
	local raiding = false
	local function startRaid()
		if raiding or not chat.Visible then
			return
		end
		raiding = true
		local raider = randomName()
		local count = math.floor(random:NextInteger(40, 160) * (1 + followers() * 0.5))
		viewers += count
		addLikes(count, true)
		chatTitle.Text = '🚨 <b><font color="#FF9F45">RAID !</font></b>'
		systemMessage("🚨 RAID de <b>" .. escape(raider) .. "</b> avec " .. count .. " spectateurs !", Color3.fromRGB(230, 110, 20))
		popWord("RAID !", UDim2.new(0.5, 0, 0, 28), Color3.fromRGB(255, 159, 69))
		wow(1)
		for _ = 1, 3 do
			spawnHeart("🎉")
		end
		task.spawn(function()
			for _ = 1, random:NextInteger(6, 9) do
				task.wait(random:NextNumber(0.12, 0.3))
				if not ctx.IsAlive() then
					return
				end
				if random:NextNumber() < 0.3 then
					pushChat(randomName(), pick(EMOTE_MESSAGES, random), { Emote = true })
				else
					pushChat(randomName(), pick(RAID_MESSAGES, random))
				end
			end
			task.wait(0.6)
			if not ctx.IsAlive() then
				return
			end
			hostSays("merci pour le raid " .. raider .. " !! 💜")
			task.wait(2.5)
			chatTitle.Text = "💬 <b>Chat</b>"
			raiding = false
		end)
	end

	------------------------------------------------------------------
	-- Boucle du chat : de plus en plus rapide avec les abonnés
	------------------------------------------------------------------
	task.spawn(function()
		local nextRaid = os.clock() + random:NextNumber(45, 90)
		while ctx.IsAlive() do
			local interval = math.clamp(1.4 / (1 + followers() * 0.15), 0.25, 1.4)
			task.wait(random:NextNumber(0.6, 1.3) * interval)
			if not ctx.IsAlive() then
				break
			end
			if chat.Visible then
				local roll = random:NextNumber()
				if os.clock() >= nextRaid then
					nextRaid = os.clock() + random:NextNumber(70, 140)
					startRaid()
				elseif roll < 0.05 then
					hostSays(pick(HOST_MESSAGES, random))
				elseif roll < 0.09 then
					local mod = pick({ "Tonton_Jean", "Lulu_ASMR", "Moustache_Pro", "Madeleine_Proust" }, random)
					pushChat(mod, pick(MOD_MESSAGES, random))
				elseif roll < 0.15 and hasButter() then
					pushChat(randomName(), pick({ "croque le beurre !!", "LE BEURRE 🧈", "clique sur le beurre 👀", "il est où le beurre ?" }, random))
				elseif roll < 0.17 and not isFollowed() then
					pushChat(randomName(), pick({ "abonne-toi !!", "clique sur Suivre 💜", "pourquoi t'es pas abonné ?" }, random))
				elseif roll < 0.35 then
					pushChat(randomName(), pick(EMOTE_MESSAGES, random), { Emote = true })
				else
					pushChat(randomName(), pick(MESSAGES, random))
				end
			end
		end
	end)
end

function LiveStream.Stop(_ctx)
	-- Tout est dans ctx.Container (détruit par le StimulusManager)
end

return LiveStream
