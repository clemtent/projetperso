--[[
	Hud (ModuleScript)
	Emplacement : ReplicatedStorage > Client > Stimuli > Live > Hud

	v9.1 : habillage du live POSÉ SUR LA VIDÉO (façon appli de live sur
	téléphone), utilisé par Stimuli > LiveStream :
	  - ombrages haut / bas (les textes restent lisibles sur l'image) ;
	  - pastille de la streameuse en haut à gauche : avatar dessiné dans un
	    anneau dégradé qui tourne, étiquette "LIVE", couronne (studio 9),
	    pseudo certifié, titre + durée, bouton "Suivre" (reflet qui passe tant
	    qu'on n'est pas abonné) ;
	  - en haut à droite : "● LIVE" rouge qui clignote + spectateurs, et les
	    likes en dessous (petit rebond quand ils montent) ;
	  - sous la pastille : objectif d'abonnés (barre qui se remplit, alterne
	    avec "Nouvel abonné : X").
	Mode compact (téléphone) : pastilles agrandies, textes secondaires cachés.
	Rien ne tourne ici : LiveStream appelle Step(clock) depuis SA boucle (≤ 30 Hz).
]]

local Locale = require(game:GetService("ReplicatedStorage").Shared.Locale)

local Hud = {}

local WHITE = Color3.new(1, 1, 1)
local SKIN = Color3.fromRGB(255, 220, 196)
local HAIR = Color3.fromRGB(70, 46, 96)
local INK = Color3.fromRGB(46, 28, 52)
local PHONES_GLOW = Color3.fromRGB(255, 130, 210)
local PILL = Color3.fromRGB(14, 9, 26)
local FOLLOW_COLOR = Color3.fromRGB(255, 60, 120)
local FOLLOWED_COLOR = Color3.fromRGB(70, 62, 96)

local MARGIN = 6 -- marge avec les bords de la vidéo
local HOST_H = 36 -- pastille de la streameuse
local HOST_W = 238
local AVATAR = 36 -- dessin de l'avatar (réduit par un UIScale)
local AVATAR_SHOWN = 30
local FOLLOW_W, FOLLOW_H = 64, 26
local GOAL_W, GOAL_H = 184, 17
local RIGHT_H = 20 -- pastilles de droite

export type Options = {
	Parent: GuiObject, -- la vidéo
	ZIndex: number,
	Host: string, -- pseudo de la streameuse
}

function Hud.new(ctx: any, options: Options)
	local UI = ctx.UIUtil
	local Theme = ctx.Theme
	local z = options.ZIndex

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
		props.TextColor3 = props.TextColor3 or WHITE
		return UI.Create("TextLabel", props)
	end
	local function at(props: { [string]: any }, x: number, y: number, w: number, h: number): { [string]: any }
		props.AnchorPoint = Vector2.new(0.5, 0.5)
		props.Position = UDim2.fromOffset(x, y)
		props.Size = UDim2.fromOffset(w, h)
		return props
	end
	-- Ombre de texte (contour sombre, lisible sur n'importe quelle image)
	local function shadow(label: TextLabel, transparency: number?)
		label.TextStrokeColor3 = Color3.fromRGB(12, 6, 22)
		label.TextStrokeTransparency = transparency or 0.55
	end

	local root = box({ Name = "Hud", Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, ZIndex = z, Parent = options.Parent })

	-- Ombrages : haut (pastilles) et bas (saisie)
	local topShade = box({ Name = "TopShade", Size = UDim2.new(1, 0, 0, 70), BackgroundColor3 = Color3.fromRGB(10, 6, 20), ZIndex = 1, Parent = root })
	UI.Gradient(topShade, ColorSequence.new(WHITE), 90).Transparency = NumberSequence.new(0.35, 1)
	local bottomShade = box({ Name = "BottomShade", AnchorPoint = Vector2.new(0, 1), Position = UDim2.fromScale(0, 1), Size = UDim2.new(1, 0, 0, 44), BackgroundColor3 = Color3.fromRGB(10, 6, 20), ZIndex = 1, Parent = root })
	-- (léger : les bulles du chat ont leur propre fond, la table reste bien visible)
	UI.Gradient(bottomShade, ColorSequence.new(WHITE), 90).Transparency = NumberSequence.new(1, 0.5)

	------------------------------------------------------------------
	-- Pastille de la streameuse
	------------------------------------------------------------------
	local host = box({
		Name = "Host",
		Position = UDim2.fromOffset(MARGIN, MARGIN),
		Size = UDim2.fromOffset(HOST_W, HOST_H),
		BackgroundColor3 = PILL,
		BackgroundTransparency = 0.28,
		ZIndex = 3,
		Parent = root,
	}, UDim.new(1, 0))
	UI.Stroke(host, WHITE, 1, 0.82)
	local hostScale = UI.Create("UIScale", { Parent = host })

	-- Avatar : anneau dégradé qui tourne + mini portrait dessiné
	local avatarRing = box(at({ Name = "Avatar", BackgroundColor3 = WHITE, ZIndex = 4, Parent = host }, HOST_H / 2, HOST_H / 2, AVATAR, AVATAR), UDim.new(1, 0))
	UI.Create("UIScale", { Scale = AVATAR_SHOWN / AVATAR, Parent = avatarRing })
	local ringGradient = UI.Gradient(avatarRing, ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 60, 90)),
		ColorSequenceKeypoint.new(0.5, Color3.fromRGB(255, 120, 200)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(255, 180, 60)),
	}), 45)
	do
		local gap = box(at({ BackgroundColor3 = Color3.fromRGB(30, 24, 44), ZIndex = 5, Parent = avatarRing }, AVATAR / 2, AVATAR / 2, AVATAR - 4, AVATAR - 4), UDim.new(1, 0))
		local s = AVATAR - 7
		local face = box(at({ BackgroundColor3 = Color3.fromRGB(255, 196, 222), ZIndex = 6, ClipsDescendants = true, Parent = gap }, (AVATAR - 4) / 2, (AVATAR - 4) / 2, s, s), UDim.new(1, 0))
		UI.Gradient(face, ColorSequence.new(Color3.fromRGB(255, 214, 234), Color3.fromRGB(250, 160, 200)), 90)
		box(at({ BackgroundColor3 = HAIR, ZIndex = 6, Parent = face }, s / 2, s / 2 + 3, 22, 26), 9)
		box(at({ BackgroundColor3 = SKIN, ZIndex = 7, Parent = face }, s / 2, s / 2 + 5, 16, 16), UDim.new(0.48, 0))
		box(at({ BackgroundColor3 = HAIR, ZIndex = 8, Parent = face }, s / 2, s / 2 - 3, 20, 8), 4)
		for _, x in ipairs({ -3.5, 3.5 }) do
			box(at({ BackgroundColor3 = INK, ZIndex = 9, Parent = face }, s / 2 + x, s / 2 + 5, 2.5, 3), UDim.new(1, 0))
			box(at({ BackgroundColor3 = Color3.fromRGB(255, 120, 150), BackgroundTransparency = 0.4, ZIndex = 9, Parent = face }, s / 2 + x * 1.6, s / 2 + 8, 4, 2), UDim.new(1, 0))
		end
		box(at({ BackgroundColor3 = Color3.fromRGB(190, 70, 100), ZIndex = 9, Parent = face }, s / 2, s / 2 + 9.5, 4, 2), UDim.new(1, 0))
		for _, x in ipairs({ -9, 9 }) do
			box(at({ BackgroundColor3 = PHONES_GLOW, ZIndex = 9, Parent = face }, s / 2 + x, s / 2 + 4, 4, 8), 2)
		end
	end
	local liveTag = text({
		Name = "LiveTag",
		Text = "LIVE",
		Font = Theme.Fonts.Title,
		TextSize = 8,
		BackgroundColor3 = Color3.fromRGB(235, 35, 60),
		BackgroundTransparency = 0,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromOffset(HOST_H / 2, HOST_H - 3),
		Size = UDim2.fromOffset(24, 10),
		ZIndex = 10,
		Parent = host,
	})
	UI.Corner(liveTag, 3)
	UI.Stroke(liveTag, Color3.fromRGB(30, 24, 44), 1.5)
	local crown = text({
		Name = "Crown",
		Text = "👑",
		TextSize = 15,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromOffset(HOST_H / 2 + 11, 1),
		Size = UDim2.fromOffset(20, 20),
		Rotation = 22,
		Visible = false,
		ZIndex = 11,
		Parent = host,
	})

	local nameX = HOST_H + 3
	local textW = HOST_W - nameX - FOLLOW_W - 8
	local nameLabel = text({
		Name = "Streamer",
		Text = "<b>" .. options.Host .. '</b> <font color="#5CC8FF">✔</font>',
		RichText = true,
		Font = Theme.Fonts.Title,
		TextSize = 12,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextTruncate = Enum.TextTruncate.AtEnd,
		Position = UDim2.fromOffset(nameX, 3),
		Size = UDim2.fromOffset(textW, 17),
		ZIndex = 4,
		Parent = host,
	})
	local subtitle = text({
		Name = "Title",
		Text = "",
		RichText = true,
		TextSize = 10,
		TextColor3 = Color3.fromRGB(214, 204, 240),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextTruncate = Enum.TextTruncate.AtEnd,
		Position = UDim2.fromOffset(nameX, 19),
		Size = UDim2.fromOffset(textW, 13),
		ZIndex = 4,
		Parent = host,
	})

	-- Bouton Suivre (dans la pastille, à droite)
	local follow = UI.Create("TextButton", {
		Name = "Follow",
		Text = Locale.T("💜 Follow"),
		Font = Theme.Fonts.Title,
		TextSize = 12,
		TextColor3 = WHITE,
		BackgroundColor3 = FOLLOW_COLOR,
		AutoButtonColor = false,
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -5, 0.5, 0),
		Size = UDim2.fromOffset(FOLLOW_W, FOLLOW_H),
		BorderSizePixel = 0,
		ZIndex = 5,
		Parent = host,
	})
	UI.Corner(follow, UDim.new(1, 0))
	local followGradient = UI.Gradient(follow, ColorSequence.new(WHITE, Color3.fromRGB(215, 190, 230)), 90)
	local followStroke = UI.Stroke(follow, Color3.fromRGB(255, 190, 220), 1.5, 0.2)
	UI.AnimateButton(follow, 1.06, 0.9)
	local shine = box({ Name = "Shine", Size = UDim2.fromScale(1, 1), BackgroundColor3 = WHITE, BackgroundTransparency = 0.5, ZIndex = 6, Parent = follow }, UDim.new(1, 0))
	local shineGradient = UI.Create("UIGradient", {
		Rotation = 20,
		Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 1),
			NumberSequenceKeypoint.new(0.42, 1),
			NumberSequenceKeypoint.new(0.5, 0.2),
			NumberSequenceKeypoint.new(0.58, 1),
			NumberSequenceKeypoint.new(1, 1),
		}),
		Offset = Vector2.new(-1, 0),
		Parent = shine,
	})

	------------------------------------------------------------------
	-- En haut à droite : LIVE + spectateurs, likes
	------------------------------------------------------------------
	local right = box({
		Name = "Stats",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -MARGIN, 0, MARGIN + (HOST_H - RIGHT_H) / 2),
		Size = UDim2.fromOffset(120, RIGHT_H * 2 + 4),
		BackgroundTransparency = 1,
		ZIndex = 3,
		Parent = root,
	})
	local rightScale = UI.Create("UIScale", { Parent = right })
	local live = box({ Name = "Live", AnchorPoint = Vector2.new(1, 0), Size = UDim2.fromOffset(112, RIGHT_H), BackgroundColor3 = PILL, BackgroundTransparency = 0.28, Position = UDim2.fromScale(1, 0), ZIndex = 3, Parent = right }, 6)
	local liveBadge = box({ Name = "Badge", Size = UDim2.new(0, 44, 1, 0), BackgroundColor3 = WHITE, ZIndex = 4, Parent = live }, 6)
	UI.Gradient(liveBadge, ColorSequence.new(Color3.fromRGB(255, 70, 90), Color3.fromRGB(215, 20, 50)), 90)
	local liveDot = box(at({ BackgroundColor3 = WHITE, ZIndex = 5, Parent = liveBadge }, 9, RIGHT_H / 2, 6, 6), UDim.new(1, 0))
	local liveText = text({ Text = "LIVE", Font = Theme.Fonts.Title, TextSize = 12, Position = UDim2.fromOffset(14, 0), Size = UDim2.new(1, -15, 1, 0), ZIndex = 5, Parent = liveBadge })
	-- Petit bonhomme (icône "spectateurs")
	local viewerIcon = box(at({ BackgroundTransparency = 1, ZIndex = 4, Parent = live }, 53, RIGHT_H / 2, 10, 11))
	box(at({ BackgroundColor3 = Color3.fromRGB(255, 130, 140), ZIndex = 4, Parent = viewerIcon }, 5, 2.5, 5, 5), UDim.new(1, 0))
	box(at({ BackgroundColor3 = Color3.fromRGB(255, 130, 140), ZIndex = 4, Parent = viewerIcon }, 5, 8.5, 9, 5), 2)
	local viewers = text({
		Name = "Count",
		Text = "0",
		Font = Theme.Fonts.Number,
		TextSize = 13,
		TextXAlignment = Enum.TextXAlignment.Left,
		Position = UDim2.fromOffset(61, 0),
		Size = UDim2.new(1, -62, 1, 0),
		ZIndex = 4,
		Parent = live,
	})
	local likesPill = box({ Name = "Likes", AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, 0, 0, RIGHT_H + 4), Size = UDim2.fromOffset(64, RIGHT_H), BackgroundColor3 = PILL, BackgroundTransparency = 0.28, ZIndex = 3, Parent = right }, 6)
	local likes = text({ Name = "Count", Text = "❤ 0", Font = Theme.Fonts.Number, TextSize = 12, TextColor3 = Color3.fromRGB(255, 176, 206), Size = UDim2.fromScale(1, 1), ZIndex = 4, Parent = likesPill })
	local likesScale = UI.Create("UIScale", { Parent = likesPill })

	------------------------------------------------------------------
	-- Objectif d'abonnés (sous la pastille)
	------------------------------------------------------------------
	local goal = box({
		Name = "Goal",
		Position = UDim2.fromOffset(MARGIN, MARGIN + HOST_H + 5),
		Size = UDim2.fromOffset(GOAL_W, GOAL_H),
		BackgroundColor3 = PILL,
		BackgroundTransparency = 0.25,
		ClipsDescendants = true,
		ZIndex = 3,
		Parent = root,
	}, UDim.new(1, 0))
	UI.Stroke(goal, Color3.fromRGB(210, 160, 255), 1, 0.5)
	local goalFill = box({ Name = "Fill", Size = UDim2.fromScale(0.5, 1), BackgroundColor3 = WHITE, BackgroundTransparency = 0.1, ZIndex = 3, Parent = goal }, UDim.new(1, 0))
	local goalGradient = UI.Gradient(goalFill, ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(150, 80, 255)),
		ColorSequenceKeypoint.new(0.5, Color3.fromRGB(255, 90, 180)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(150, 80, 255)),
	}), 0)
	local goalLabel = text({
		Name = "Label",
		Text = Locale.T("💜 Follower goal"),
		RichText = true,
		Font = Theme.Fonts.Title,
		TextSize = 11,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextTruncate = Enum.TextTruncate.AtEnd,
		Position = UDim2.fromOffset(8, 0),
		Size = UDim2.new(0.55, -8, 1, 0),
		ZIndex = 4,
		Parent = goal,
	})
	local goalCount = text({
		Name = "Count",
		Text = "",
		Font = Theme.Fonts.Number,
		TextSize = 11,
		TextXAlignment = Enum.TextXAlignment.Right,
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -8, 0, 0),
		Size = UDim2.new(0.45, -4, 1, 0),
		ZIndex = 4,
		Parent = goal,
	})
	for _, label in ipairs({ nameLabel, subtitle, viewers, likes, goalLabel, goalCount, liveText }) do
		shadow(label)
	end

	------------------------------------------------------------------
	-- API
	------------------------------------------------------------------
	local hud = { Root = root, Follow = follow, Crown = crown }
	local compact = false
	local shownViewers, shownLikes, shownRising = "", "", false

	function hud.SetFollowed(followed: boolean)
		shine.Visible = not followed
		if followed then
			follow.Text = Locale.T("✔ Following")
			follow.BackgroundColor3 = FOLLOWED_COLOR
			followGradient.Color = ColorSequence.new(WHITE, Color3.fromRGB(220, 220, 230))
			followStroke.Color = Color3.fromRGB(140, 130, 170)
			followStroke.Transparency = 0.5
		else
			follow.Text = Locale.T("💜 Follow")
			follow.BackgroundColor3 = FOLLOW_COLOR
			followGradient.Color = ColorSequence.new(WHITE, Color3.fromRGB(215, 190, 230))
			followStroke.Color = Color3.fromRGB(255, 190, 220)
			followStroke.Transparency = 0.2
		end
	end

	function hud.SetViewers(value: string, rising: boolean)
		if value ~= shownViewers then
			shownViewers = value
			viewers.Text = value
			live.Size = UDim2.fromOffset(66 + #value * 7, RIGHT_H)
		end
		if rising ~= shownRising then
			shownRising = rising
			viewers.TextColor3 = rising and Color3.fromRGB(150, 255, 180) or WHITE
		end
	end

	function hud.SetLikes(value: string)
		if value ~= shownLikes then
			shownLikes = value
			likes.Text = value
			likesPill.Size = UDim2.fromOffset(24 + #value * 6, RIGHT_H)
		end
	end

	function hud.BumpLikes()
		likesScale.Scale = 1.25
		UI.Tween(likesScale, 0.3, { Scale = 1 }, Enum.EasingStyle.Back)
	end

	function hud.SetSubtitle(rich: string)
		subtitle.Text = rich
	end

	-- ratio 0..1 ; countText "5 802 / 6 000"
	function hud.SetGoal(ratio: number, countText: string)
		goalFill.Size = UDim2.fromScale(ratio, 1)
		goalCount.Text = countText
	end

	-- follower (texte riche) : "Nouvel abonné : X" ; nil : l'objectif
	function hud.ShowFollower(rich: string?)
		if rich then
			goalLabel.Text = rich
			goalLabel.Size = UDim2.new(1, -16, 1, 0)
			goalCount.Visible = false
		else
			goalLabel.Text = Locale.T("💜 Follower goal")
			goalLabel.Size = UDim2.new(0.55, -8, 1, 0)
			goalCount.Visible = true
		end
	end

	function hud.ResetGoalShine()
		goalGradient.Offset = Vector2.new(0, 0)
	end

	-- Centre du bouton Suivre, en pixels de la vidéo (effets de gain)
	function hud.FollowCenter(): Vector2
		local scale = hostScale.Scale
		local width = compact and (HOST_H + FOLLOW_W + 10) or HOST_W
		return Vector2.new(MARGIN + (width - 5 - FOLLOW_W / 2) * scale, MARGIN + HOST_H / 2 * scale)
	end

	-- Téléphone : pastilles agrandies, seulement l'essentiel
	function hud.SetCompact(on: boolean)
		compact = on
		hostScale.Scale = on and 1.45 or 1
		rightScale.Scale = on and 1.45 or 1
		nameLabel.Visible = not on
		subtitle.Visible = not on
		likesPill.Visible = not on
		goal.Visible = not on
		host.Size = UDim2.fromOffset(on and (HOST_H + FOLLOW_W + 10) or HOST_W, HOST_H)
		topShade.Size = UDim2.new(1, 0, 0, on and 84 or 70)
	end

	-- Animations (appelé par la boucle de LiveStream, ≤ 30 Hz)
	function hud.Step(clock: number)
		local blink = math.sin(clock * 5) > 0
		liveDot.BackgroundTransparency = blink and 0 or 0.7
		liveTag.BackgroundTransparency = blink and 0 or 0.2
		ringGradient.Rotation = (clock * 60) % 360
		goalGradient.Offset = Vector2.new((clock * 0.25) % 1 - 0.5, 0)
		if shine.Visible then
			shineGradient.Offset = Vector2.new(((clock * 0.5) % 2) - 1, 0)
		end
	end

	return hud
end

return Hud
