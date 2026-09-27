--[[
	ChatPanel (ModuleScript)
	Emplacement : ReplicatedStorage > Client > Stimuli > Live > ChatPanel

	v9.1 : le chat du live POSÉ SUR LA VIDÉO, en bas à gauche (façon appli de
	live sur téléphone), utilisé par Stimuli > LiveStream :
	  - chaque message est une "bulle" sombre translucide À LA LARGEUR DU
	    TEXTE (TextService), avatar rond à initiale, pseudo en couleur, texte
	    blanc ombré : lisible sur l'image, même sur une petite carte ;
	  - styles : "you" (ton message : doré + ta photo), "mention" (on te
	    parle : rose), "host" (la streameuse : violet), messages système
	    (raid, don...) teintés ;
	  - le message arrive en glissant ; les plus anciens s'estompent vers le
	    haut (réserve FIXE de lignes recyclées, aucun objet créé ensuite) ;
	  - message épinglé (invitation à écrire) au-dessus, bandeau "RAID !" ;
	  - champ de saisie (Live > ChatInput) en bas ; toucher les messages
	    ouvre le clavier.
	Mode compact (téléphone) : texte bien plus gros, moins de lignes.
]]

local TextService = game:GetService("TextService")
local ChatInput = require(script.Parent.ChatInput)

local ChatPanel = {}

local WHITE = Color3.new(1, 1, 1)
local POOL = 10 -- lignes recyclées
local YOU_GOLD = Color3.fromRGB(255, 211, 77)
local MENTION_PINK = Color3.fromRGB(255, 84, 150)
local HOST_PURPLE = Color3.fromRGB(150, 80, 255)
local BUBBLE = Color3.fromRGB(12, 8, 24)

-- Tailles : normal / compact (téléphone)
local SIZES = {
	normal = { Text = 13, Avatar = 18, Pinned = 11, PinnedH = 30, Gap = 3, Visible = 6 },
	compact = { Text = 20, Avatar = 26, Pinned = 16, PinnedH = 0, Gap = 4, Visible = 3 },
}

export type Options = {
	Parent: GuiObject, -- la vidéo
	Position: UDim2,
	Size: UDim2,
	ZIndex: number,
	KnownTopics: { [string]: boolean }?,
	Headshot: string, -- photo du joueur ("" si aucune)
	OnMessage: (text: string, topics: { string }) -> (),
	OnFocus: ((focused: boolean) -> ())?,
}

type Line = {
	Frame: Frame,
	Bubble: Frame,
	Stroke: UIStroke,
	Gradient: UIGradient,
	Avatar: Frame,
	Initial: TextLabel,
	Photo: ImageLabel,
	Label: TextLabel,
	Plain: string,
	HasAvatar: boolean,
	Order: number,
}

function ChatPanel.new(ctx: any, options: Options)
	local UI = ctx.UIUtil
	local Theme = ctx.Theme
	local z = options.ZIndex
	local size = SIZES.normal
	local compact = false

	local panel = UI.Create("Frame", {
		Name = "Chat",
		Position = options.Position,
		Size = options.Size,
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ZIndex = z,
		Parent = options.Parent,
	})

	-- Message épinglé (en haut de la colonne)
	local pinned = UI.Create("Frame", {
		Name = "Pinned",
		Size = UDim2.new(1, 0, 0, size.PinnedH),
		BackgroundColor3 = WHITE,
		BorderSizePixel = 0,
		ZIndex = z,
		Parent = panel,
	})
	UI.Corner(pinned, 9)
	UI.Gradient(pinned, ColorSequence.new(Color3.fromRGB(120, 60, 200), Color3.fromRGB(70, 40, 130)), 0)
	pinned.BackgroundTransparency = 0.15
	UI.Stroke(pinned, Color3.fromRGB(200, 160, 255), 1, 0.35)
	local pinnedLabel = UI.Create("TextLabel", {
		Text = "",
		RichText = true,
		Font = Theme.Fonts.Body,
		TextSize = size.Pinned,
		TextWrapped = true,
		TextColor3 = Color3.fromRGB(248, 242, 255),
		TextXAlignment = Enum.TextXAlignment.Left,
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Position = UDim2.fromOffset(7, 1),
		Size = UDim2.new(1, -12, 1, -2),
		ZIndex = z + 1,
		Parent = pinned,
	})

	-- Bandeau "RAID !" (caché hors raid)
	local banner = UI.Create("TextLabel", {
		Name = "Banner",
		Text = "",
		RichText = true,
		Font = Theme.Fonts.Title,
		TextSize = 14,
		TextColor3 = WHITE,
		BackgroundColor3 = Color3.fromRGB(230, 110, 20),
		BorderSizePixel = 0,
		Size = UDim2.new(1, 0, 0, 24),
		Visible = false,
		ZIndex = z + 2,
		Parent = panel,
	})
	UI.Corner(banner, 9)
	UI.Stroke(banner, Color3.fromRGB(255, 220, 150), 1.5, 0).ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	local bannerScale = UI.Create("UIScale", { Parent = banner })

	-- Liste : "rouleau" accroché en bas qui grandit vers le haut
	local list = UI.Create("Frame", {
		Name = "Messages",
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ClipsDescendants = true,
		ZIndex = z,
		Parent = panel,
	})
	local scroller = UI.Create("Frame", {
		Name = "Scroller",
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.fromScale(0, 1),
		Size = UDim2.fromScale(1, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ZIndex = z,
		Parent = list,
	})
	local listLayout = UI.Create("UIListLayout", {
		SortOrder = Enum.SortOrder.LayoutOrder,
		Padding = UDim.new(0, size.Gap),
		Parent = scroller,
	})

	local input = ChatInput.new(ctx, {
		Parent = panel,
		TapArea = list,
		ZIndex = z + 2,
		Inset = 0,
		KnownTopics = options.KnownTopics,
		OnMessage = options.OnMessage,
		OnFocus = options.OnFocus,
	})

	local lines: { Line } = {}
	for i = 1, POOL do
		local frame = UI.Create("Frame", {
			Name = "Line" .. i,
			Size = UDim2.fromScale(1, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			Visible = false,
			ZIndex = z,
			Parent = scroller,
		})
		UI.Create("UIPadding", { PaddingBottom = UDim.new(0, 3), Parent = frame })
		-- Bulle à la largeur du texte (hauteur = celle de la ligne)
		local bubble = UI.Create("Frame", {
			Name = "Bubble",
			Size = UDim2.new(0, 60, 1, 0),
			BackgroundColor3 = BUBBLE,
			BackgroundTransparency = 0.42,
			BorderSizePixel = 0,
			ZIndex = z,
			Parent = frame,
		})
		UI.Corner(bubble, 10)
		local stroke = UI.Stroke(bubble, YOU_GOLD, 1.5, 0.1)
		stroke.Enabled = false
		local gradient = UI.Gradient(bubble, ColorSequence.new(Color3.fromRGB(255, 196, 70), Color3.fromRGB(255, 104, 170)), 0)
		gradient.Enabled = false
		local avatar = UI.Create("Frame", {
			Name = "Avatar",
			Position = UDim2.fromOffset(3, 3),
			Size = UDim2.fromOffset(size.Avatar, size.Avatar),
			BackgroundColor3 = WHITE,
			BorderSizePixel = 0,
			ZIndex = z + 1,
			Parent = frame,
		})
		UI.Corner(avatar, UDim.new(1, 0))
		local initial = UI.Create("TextLabel", {
			Text = "",
			Font = Theme.Fonts.Title,
			TextSize = 11,
			TextColor3 = Color3.fromRGB(30, 20, 40),
			BackgroundTransparency = 1,
			Size = UDim2.fromScale(1, 1),
			ZIndex = z + 2,
			Parent = avatar,
		})
		local photo = UI.Create("ImageLabel", { Name = "Photo", Image = "", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), Visible = false, ZIndex = z + 3, Parent = avatar })
		UI.Corner(photo, UDim.new(1, 0))
		local label = UI.Create("TextLabel", {
			Name = "Msg",
			Text = "",
			RichText = true,
			Font = Theme.Fonts.Body,
			TextSize = size.Text,
			TextWrapped = true,
			TextColor3 = WHITE,
			TextStrokeColor3 = Color3.fromRGB(10, 6, 20),
			TextStrokeTransparency = 0.6,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextYAlignment = Enum.TextYAlignment.Top,
			AutomaticSize = Enum.AutomaticSize.Y,
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			ZIndex = z + 1,
			Parent = frame,
		})
		lines[i] = { Frame = frame, Bubble = bubble, Stroke = stroke, Gradient = gradient, Avatar = avatar, Initial = initial, Photo = photo, Label = label, Plain = "", HasAvatar = false, Order = 0 }
	end
	local nextLine, order = 0, 0

	-- Largeur utile d'une ligne (pixels "design" de la carte)
	local function columnWidth(): number
		local width = panel.Size.X.Offset
		return width > 0 and width or 180
	end

	local function textLeft(line: Line): number
		return line.HasAvatar and (size.Avatar + 8) or 8
	end

	-- Texte brut d'un texte riche (balises retirées, entités décodées)
	local function plainOf(rich: string): string
		local plain = string.gsub(rich, "<[^>]*>", "")
		plain = string.gsub(plain, "&lt;", "<")
		plain = string.gsub(plain, "&gt;", ">")
		plain = string.gsub(plain, "&amp;", "&")
		return plain
	end

	-- Mesure du texte (police grasse : un peu plus large que le vrai rendu)
	local function measure(plain: string): number
		local ok, bounds = pcall(function()
			return TextService:GetTextSize(plain, size.Text, Theme.Fonts.Title, Vector2.new(4000, 200))
		end)
		if ok and typeof(bounds) == "Vector2" then
			return bounds.X
		end
		return 4000
	end

	local function layoutLine(line: Line)
		local left = textLeft(line)
		local labelWidth = columnWidth() - left - 6
		line.Label.Position = UDim2.fromOffset(left, 3)
		line.Label.Size = UDim2.new(0, labelWidth, 0, 0)
		line.Avatar.Size = UDim2.fromOffset(size.Avatar, size.Avatar)
		line.Initial.TextSize = compact and 16 or 11
		line.Label.TextSize = size.Text
		local textWidth = measure(line.Plain)
		if string.find(line.Label.Text, '<font size="', 1, true) then
			textWidth *= 1.45 -- (emotes affichées en plus gros)
		end
		local width = math.min(columnWidth(), left + textWidth + 10)
		line.Bubble.Size = UDim2.new(0, math.max(width, left + 24), 1, 0)
	end

	-- Estompe les plus anciens (seulement les `Visible` plus récents bien lisibles)
	local function refreshFade()
		local ranked = {}
		for _, line in ipairs(lines) do
			if line.Frame.Visible then
				table.insert(ranked, line)
			end
		end
		table.sort(ranked, function(a, b)
			return a.Order > b.Order
		end)
		for rank, line in ipairs(ranked) do
			local fade = rank <= size.Visible - 1 and 0 or (rank == size.Visible and 0.45 or 0.8)
			line.Label.TextTransparency = fade
			line.Label.TextStrokeTransparency = 0.6 + fade * 0.4
			line.Initial.TextTransparency = fade
			line.Avatar.BackgroundTransparency = fade
			line.Photo.ImageTransparency = fade
			local base = line.Gradient.Enabled and 0.3 or (line.Stroke.Enabled and 0.35 or 0.42)
			line.Bubble.BackgroundTransparency = base + (1 - base) * fade
			line.Stroke.Transparency = line.Stroke.Enabled and (0.1 + 0.9 * fade) or 1
			-- (une ligne qui a quitté la zone visible est recyclée plus tard)
		end
	end

	local api = { Frame = panel, Input = input }

	-- Écrit une ligne (réserve recyclée). rich : texte riche déjà échappé ;
	-- avatarName : initiale (nil = message système) ; style.Kind : "you" |
	-- "mention" | "host" ; style.Tint : couleur d'un message système.
	function api.Write(rich: string, avatarName: string?, avatarColor: Color3?, style: { Kind: string?, Tint: Color3? }?)
		nextLine = nextLine % POOL + 1
		local line = lines[nextLine]
		order += 1
		line.Order = order
		line.Frame.LayoutOrder = order
		line.Frame.Visible = true
		line.Label.Text = rich
		line.Plain = plainOf(rich)
		local kind = style and style.Kind
		local tint = style and style.Tint
		local you, mention, host = kind == "you", kind == "mention", kind == "host"
		line.HasAvatar = avatarName ~= nil
		line.Avatar.Visible = line.HasAvatar
		if avatarName then
			line.Avatar.BackgroundColor3 = you and YOU_GOLD or (avatarColor or WHITE)
			line.Initial.Text = string.upper(string.sub(avatarName, 1, 1))
		end
		local showPhoto = you and options.Headshot ~= ""
		line.Photo.Visible = showPhoto
		if showPhoto and line.Photo.Image ~= options.Headshot then
			line.Photo.Image = options.Headshot
		end
		line.Gradient.Enabled = you
		line.Stroke.Enabled = you or mention or host
		if you then
			line.Bubble.BackgroundColor3 = Color3.fromRGB(190, 120, 40)
			line.Stroke.Color = YOU_GOLD
		elseif mention then
			line.Bubble.BackgroundColor3 = Color3.fromRGB(120, 20, 70)
			line.Stroke.Color = MENTION_PINK
		elseif host then
			line.Bubble.BackgroundColor3 = Color3.fromRGB(70, 30, 140)
			line.Stroke.Color = HOST_PURPLE
		else
			line.Bubble.BackgroundColor3 = tint and tint:Lerp(BUBBLE, 0.35) or BUBBLE
		end
		layoutLine(line)
		refreshFade()
		-- Arrivée : glisse depuis la gauche + petit flash
		line.Label.Position = UDim2.fromOffset(textLeft(line) - 14, 3)
		UI.Tween(line.Label, 0.25, { Position = UDim2.fromOffset(textLeft(line), 3) }, Enum.EasingStyle.Back)
		if you or mention then
			line.Bubble.BackgroundTransparency = 0
			UI.Tween(line.Bubble, 0.8, { BackgroundTransparency = you and 0.3 or 0.35 })
		end
	end

	function api.SetPinned(rich: string?)
		if rich then
			pinnedLabel.Text = rich
		end
		pinned.Visible = rich ~= nil and not compact
		api.Layout()
	end

	function api.SetBanner(rich: string?)
		banner.Visible = rich ~= nil
		if rich then
			banner.Text = rich
			bannerScale.Scale = 0.4
			UI.Tween(bannerScale, 0.35, { Scale = 1 }, Enum.EasingStyle.Back)
		end
	end

	-- Replace la liste entre l'épinglé et la saisie
	function api.Layout()
		local top = pinned.Visible and (size.PinnedH + 4) or 0
		local bottom = input.Height + 5
		list.Position = UDim2.fromOffset(0, top)
		list.Size = UDim2.new(1, 0, 1, -(top + bottom))
		pinned.Size = UDim2.new(1, 0, 0, size.PinnedH)
	end

	function api.SetCompact(on: boolean)
		if on == compact then
			return
		end
		compact = on
		size = on and SIZES.compact or SIZES.normal
		input.SetCompact(on)
		pinnedLabel.TextSize = size.Pinned
		banner.TextSize = on and 20 or 14
		banner.Size = UDim2.new(1, 0, 0, on and 32 or 24)
		listLayout.Padding = UDim.new(0, size.Gap)
		pinned.Visible = pinned.Visible and not on
		for _, line in ipairs(lines) do
			layoutLine(line)
		end
		refreshFade()
		api.Layout()
	end

	function api.SetFrame(position: UDim2, frameSize: UDim2)
		panel.Position = position
		panel.Size = frameSize
		for _, line in ipairs(lines) do
			if line.Frame.Visible then
				layoutLine(line)
			end
		end
	end

	function api.IsCompact(): boolean
		return compact
	end

	function api.Step(now: number)
		input.Step(now)
	end

	api.Layout()
	return api
end

return ChatPanel
