--[[
	TownHud (ModuleScript)
	Emplacement : ReplicatedStorage > Client > World > TownHud

	🚶 Dopamine Town : l'interface compacte pendant la promenade (le clicker
	est masqué). ScreenGui "TownHud" dans la zone sûre (CoreUISafeInsets :
	jamais sous les boutons Roblox ni l'encoche), mise à l'échelle comme le
	jeu (PC / tablette / téléphone ; boutons tactiles >= 44 px) :
	  - en haut à gauche : "⬅ Clicker" (retour au jeu) ;
	  - en haut au milieu : compteur de Dopamine (+ par seconde), bandeau de
	    la maison où l'on est (propriétaire, ❤️, 👀, accès : le propriétaire
	    le change d'un appui : Tout le monde -> Amis -> Personne) ;
	  - en haut à droite : "🏠 Ma maison", "👥 Visiter" ;
	  - colonne à droite (au-dessus du bouton "sauter" des mobiles) : 👆 clic
	    (gagne comme le gros bouton), 😀 émotes (roue : salut, danse, youpi,
	    assis, montrer), ✏️ déplacer les meubles (dans SA maison), ❤️ j'aime
	    (maison d'un autre) ;
	  - barre d'édition (en bas) : 🔄 tourner (R), 🧲 grille, 📦 ranger,
	    ✅ poser, ❌ annuler ;
	  - fenêtre "👥 Visiter" : joueurs du serveur, leur maison, ❤️, accès ;
	  - petits messages (toasts) et écran de chargement de la ville.
	v9.4 (ENTRY94) :
	  - "🏠 Rentrer" (téléportation devant sa porte) + 🧭 boussole sous
	    "Retour" (flèche vers sa maison + distance, un appui = Rentrer) ;
	  - pastille d'action en bas au milieu (entre le joystick et "sauter"
	    sur mobile) : "■ Arrêter" pendant une émote, "Se lever" assis ;
	  - voile plein écran à part (ScreenGui "TownOverlay", sous les
	    encoches aussi, reste actif quand le HUD est masqué) : écran de
	    chargement (ciel, silhouette de la ville, barre, astuces), bandes
	    cinéma + titre + "Passer" du survol d'arrivée, fondus d'entrée /
	    de sortie ;
	  - liste des visites plus claire (anneau vert = en ville, pastilles).
	Aucune logique de jeu ici : tout passe par les rappels (callbacks).
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")

local Client = script.Parent.Parent
local Theme = require(Client.Theme)
local UIUtil = require(Client.UIUtil)
local ClientState = require(Client.ClientState)
local Locale = require(ReplicatedStorage.Shared.Locale)
local Config = require(ReplicatedStorage.Shared.Config)
local NumberFormatter = require(ReplicatedStorage.Shared.NumberFormatter)
local WorldLayout = require(ReplicatedStorage.Shared.WorldLayout)

local TownHud = {}
TownHud.__index = TownHud

local PINK = Color3.fromRGB(255, 110, 170)
local PINK_DEEP = Color3.fromRGB(236, 72, 140)
local LILAC = Color3.fromRGB(170, 140, 245)
local MINT = Color3.fromRGB(80, 200, 160)
local SKY = Color3.fromRGB(96, 170, 245)
local INK = Color3.fromRGB(92, 58, 96)
local CARD = Color3.fromRGB(255, 250, 253)
local WHITE = Color3.new(1, 1, 1)

export type Callbacks = {
	Back: () -> (),
	Home: () -> (),
	OpenVisit: () -> (),
	Visit: (userId: number) -> (),
	Emote: (name: string) -> (),
	ToggleEdit: () -> (),
	Rotate: () -> (),
	Snap: () -> (),
	PutAway: () -> (),
	Drop: () -> (),
	Cancel: () -> (),
	Like: () -> (),
	Click: () -> number?,
	CycleOpen: () -> (),
	StopEmote: () -> (),
	GetUp: () -> (),
	SkipIntro: () -> (),
}

export type Context = {
	Snapshot: any?, -- maison où l'on est (ou devant laquelle on est)
	IsOwner: boolean,
	Locked: boolean,
	InHouse: boolean,
}

local EMOTES = {
	{ Id = "wave", Icon = "👋", Text = "Wave" },
	{ Id = "dance", Icon = "💃", Text = "Dance" },
	{ Id = "cheer", Icon = "🎉", Text = "Cheer" },
	{ Id = "sit", Icon = "🪑", Text = "Sit" },
	{ Id = "point", Icon = "👉", Text = "Point" },
}

local OPEN_TEXT = {
	Everyone = "🔓 Open to everyone",
	Friends = "👥 Friends only",
	Nobody = "🔒 Closed",
}

----------------------------------------------------------------------
-- Petits constructeurs
----------------------------------------------------------------------

local TextService = game:GetService("TextService")

-- Largeur d'un texte (px) : les tailles sont calculées, pas "automatiques"
local function textWidth(text: string, size: number, font: Enum.Font?): number
	local ok, bounds = pcall(function()
		return TextService:GetTextSize(text, size, font or Theme.Fonts.Title, Vector2.new(4000, 200))
	end)
	if ok and typeof(bounds) == "Vector2" then
		return bounds.X
	end
	local length = utf8.len(text) or #text
	return length * size * 0.55
end

local function label(props: { [string]: any }): TextLabel
	local l = UIUtil.Create("TextLabel", {
		BackgroundTransparency = 1,
		Font = props.Font or Theme.Fonts.Title,
		TextColor3 = props.Color or INK,
		TextSize = props.TextSize or 18,
		TextXAlignment = props.XAlign or Enum.TextXAlignment.Center,
		TextYAlignment = Enum.TextYAlignment.Center,
		Text = props.Text or "",
		Size = props.Size or UDim2.fromScale(1, 1),
		Position = props.Position or UDim2.new(),
		AnchorPoint = props.AnchorPoint or Vector2.zero,
		AutomaticSize = props.AutomaticSize or Enum.AutomaticSize.None,
		TextTruncate = Enum.TextTruncate.AtEnd,
		ZIndex = props.ZIndex or 2,
		Name = props.Name or "Label",
		LayoutOrder = props.LayoutOrder or 0,
		Parent = props.Parent,
	})
	return l
end

local function roundButton(parent: Instance, name: string, icon: string, color: Color3, diameter: number, order: number): TextButton
	local button = UIUtil.PillButton({
		Name = name,
		Text = icon,
		Color = color,
		Height = diameter,
		Round = true,
		TextSize = math.floor(diameter * 0.46),
		LayoutOrder = order,
		Parent = parent,
	})
	return button
end

----------------------------------------------------------------------

function TownHud.new(callbacks: Callbacks)
	local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")
	local old = playerGui:FindFirstChild("TownHud")
	if old then
		old:Destroy()
	end
	local gui = Instance.new("ScreenGui")
	gui.Name = "TownHud"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = false
	gui.ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.DisplayOrder = 20
	gui.Enabled = false
	gui.Parent = playerGui

	local root = UIUtil.Create("Frame", {
		Name = "Root",
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(1100, 620),
		Parent = gui,
	})
	local scale = UIUtil.Create("UIScale", { Parent = root })

	local self = setmetatable({
		Gui = gui,
		Root = root,
		Scale = scale,
		Callbacks = callbacks,
		Phone = false,
		Toasts = {} :: { Frame },
		ToastCount = 0,
		Context = nil :: Context?,
		Editing = false,
		Holding = false,
		Snap = true,
		EmoteOpen = false,
		Parts = {} :: { [string]: any },
	}, TownHud)
	self:Build()
	gui:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
		self:Layout()
	end)
	self:Layout()
	return self
end

function TownHud.Build(self: any)
	local root: Frame = self.Root
	local cb: Callbacks = self.Callbacks
	local parts = self.Parts

	-- ⬅ retour au clicker (flèche dessinée à gauche, texte à droite)
	local back = UIUtil.PillButton({
		Name = "BackToClicker",
		Text = Locale.T("Back to clicker"),
		Color = WHITE,
		TextColor3 = INK,
		Height = 46,
		TextSize = 19,
		Parent = root,
	})
	back.AutomaticSize = Enum.AutomaticSize.None
	back.TextXAlignment = Enum.TextXAlignment.Right
	back.Position = UDim2.fromOffset(10, 8)
	local backPad = back:FindFirstChildOfClass("UIPadding")
	if backPad then
		backPad.PaddingLeft = UDim.new(0, 44)
		backPad.PaddingRight = UDim.new(0, 16)
	end
	UIUtil.Icon("ArrowLeft", { Size = 20, Thickness = 3, Color = PINK_DEEP, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0, -22, 0.5, 0), ZIndex = 4, Parent = back })
	back.Activated:Connect(function()
		cb.Back()
	end)
	parts.Back = back

	-- Compteur de Dopamine
	local counter = UIUtil.Create("Frame", {
		Name = "Counter",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 8),
		Size = UDim2.fromOffset(260, 58),
		BackgroundColor3 = CARD,
		Parent = root,
	})
	UIUtil.Corner(counter, 18)
	UIUtil.Stroke(counter, PINK, 2, 0.2)
	UIUtil.Shadow(counter, 3, 0.8)
	UIUtil.Gradient(counter, ColorSequence.new(Color3.fromRGB(255, 255, 255), Color3.fromRGB(255, 226, 240)), 90)
	parts.Amount = label({ Name = "Amount", Text = "0", Color = PINK_DEEP, TextSize = 30, Font = Theme.Fonts.Number, Size = UDim2.new(1, -20, 0, 34),
		Position = UDim2.fromOffset(10, 3), Parent = counter })
	parts.Rate = label({ Name = "Rate", Text = "", Color = INK, TextSize = 15, Font = Theme.Fonts.Body, Size = UDim2.new(1, -20, 0, 18),
		Position = UDim2.fromOffset(10, 36), Parent = counter })
	parts.Counter = counter

	-- Bandeau de la maison
	local banner = UIUtil.Create("Frame", {
		Name = "HouseBanner",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 72),
		Size = UDim2.fromOffset(300, 34),
		BackgroundColor3 = Color3.fromRGB(92, 58, 120),
		BackgroundTransparency = 0.12,
		Visible = false,
		Parent = root,
	})
	UIUtil.Corner(banner, UDim.new(1, 0))
	UIUtil.Create("UIPadding", { PaddingLeft = UDim.new(0, 14), PaddingRight = UDim.new(0, 6), Parent = banner })
	UIUtil.Create("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		VerticalAlignment = Enum.VerticalAlignment.Center,
		Padding = UDim.new(0, 10),
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = banner,
	})
	parts.BannerText = label({ Name = "Text", Text = "", Color = WHITE, TextSize = 17, Size = UDim2.fromOffset(200, 34), LayoutOrder = 1, Parent = banner })
	local openButton = UIUtil.PillButton({ Name = "OpenMode", Text = "", Color = MINT, Height = 26, TextSize = 14, LayoutOrder = 2, Parent = banner })
	openButton.AutomaticSize = Enum.AutomaticSize.None
	openButton.Activated:Connect(function()
		cb.CycleOpen()
	end)
	parts.OpenButton = openButton
	parts.Banner = banner

	-- En haut à droite : ma maison, visiter
	local topRight = UIUtil.Create("Frame", {
		Name = "TopRight",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -10, 0, 8),
		Size = UDim2.fromOffset(0, 50),
		AutomaticSize = Enum.AutomaticSize.X,
		BackgroundTransparency = 1,
		Parent = root,
	})
	UIUtil.Create("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		HorizontalAlignment = Enum.HorizontalAlignment.Right,
		VerticalAlignment = Enum.VerticalAlignment.Top,
		Padding = UDim.new(0, 8),
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = topRight,
	})
	local home = UIUtil.PillButton({ Name = "MyHouse", Text = Locale.T("🏠 Go home"), Color = PINK, Height = 46, TextSize = 19, LayoutOrder = 1, Parent = topRight })
	home.Activated:Connect(function()
		cb.Home()
	end)
	local visit = UIUtil.PillButton({ Name = "VisitButton", Text = Locale.T("👥 Visit…"), Color = LILAC, Height = 46, TextSize = 19, LayoutOrder = 2, Parent = topRight })
	visit.Activated:Connect(function()
		cb.OpenVisit()
	end)
	parts.Home = home
	parts.VisitButton = visit
	parts.TopRight = topRight

	-- Colonne de droite
	local column = UIUtil.Create("Frame", {
		Name = "Actions",
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -12, 0.46, 0),
		Size = UDim2.fromOffset(76, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
		Parent = root,
	})
	UIUtil.Create("UIListLayout", {
		FillDirection = Enum.FillDirection.Vertical,
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		Padding = UDim.new(0, 24),
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = column,
	})
	local click = roundButton(column, "TownClick", "👆", PINK_DEEP, 70, 1)
	click.Activated:Connect(function()
		local gain = cb.Click()
		if gain and gain > 0 then
			self:Pop(click, "+" .. NumberFormatter.Format(gain))
		end
	end)
	local emote = roundButton(column, "Emotes", "😀", Color3.fromRGB(255, 196, 70), 56, 2)
	emote.Activated:Connect(function()
		self:SetEmoteWheel(not self.EmoteOpen)
	end)
	local edit = roundButton(column, "EditFurniture", "✏️", SKY, 56, 3)
	edit.Visible = false
	edit.Activated:Connect(function()
		cb.ToggleEdit()
	end)
	local like = roundButton(column, "LikeHouse", "❤️", Color3.fromRGB(255, 90, 120), 56, 4)
	like.Visible = false
	like.Activated:Connect(function()
		cb.Like()
	end)
	parts.Column = column
	parts.Click = click
	parts.Emote = emote
	parts.Edit = edit
	parts.Like = like
	-- petites étiquettes sous les boutons (PC / tablette)
	for _, spec in ipairs({ { click, "Click" }, { emote, "Emotes" }, { edit, "Move furniture" }, { like, "Like" } }) do
		local tag = label({ Name = "Tag", Text = Locale.T(spec[2]), Color = WHITE, TextSize = 13, Size = UDim2.fromOffset(110, 16),
			AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 1, 1), ZIndex = 5, Parent = spec[1] })
		UIUtil.Create("UIStroke", { Color = INK, Thickness = 1.5, Transparency = 0.2, Parent = tag })
	end

	-- Roue des émotes (à gauche du bouton)
	local wheel = UIUtil.Create("Frame", {
		Name = "EmoteWheel",
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(0, -10, 0.5, 0),
		Size = UDim2.fromOffset(#EMOTES * 54 + 10, 60),
		BackgroundColor3 = CARD,
		Visible = false,
		ZIndex = 6,
		Parent = emote,
	})
	UIUtil.Corner(wheel, UDim.new(1, 0))
	UIUtil.Stroke(wheel, Color3.fromRGB(255, 196, 70), 2, 0.1)
	-- (le "puits à clics" reste HORS de la rangée : une UIListLayout le placerait comme un bouton)
	UIUtil.SinkClicks(wheel)
	local wheelRow = UIUtil.Create("Frame", { Name = "Row", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), ZIndex = 6, Parent = wheel })
	UIUtil.Create("UIPadding", { PaddingLeft = UDim.new(0, 8), PaddingRight = UDim.new(0, 8), Parent = wheelRow })
	UIUtil.Create("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		VerticalAlignment = Enum.VerticalAlignment.Center,
		Padding = UDim.new(0, 6),
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = wheelRow,
	})
	for index, spec in ipairs(EMOTES) do
		local b = UIUtil.PillButton({ Name = "Emote_" .. spec.Id, Text = spec.Icon, Color = Color3.fromRGB(255, 240, 200), Height = 48, Round = true,
			TextSize = 24, LayoutOrder = index, ZIndex = 7, Parent = wheelRow })
		local tag = label({ Name = "Tag", Text = Locale.T(spec.Text), Color = INK, TextSize = 11, Size = UDim2.fromOffset(60, 12),
			AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, 2), ZIndex = 9, Parent = b })
		tag.Font = Theme.Fonts.Title
		b.Activated:Connect(function()
			self:SetEmoteWheel(false)
			cb.Emote(spec.Id)
		end)
	end
	parts.Wheel = wheel

	-- Barre d'édition des meubles
	local editBar = UIUtil.Create("Frame", {
		Name = "EditBar",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -12),
		Size = UDim2.fromOffset(600, 64),
		BackgroundColor3 = CARD,
		Visible = false,
		Parent = root,
	})
	UIUtil.Corner(editBar, 22)
	UIUtil.Stroke(editBar, SKY, 2, 0.1)
	UIUtil.Shadow(editBar, 3, 0.8)
	UIUtil.SinkClicks(editBar)
	local editRow = UIUtil.Create("Frame", { Name = "Row", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), Parent = editBar })
	UIUtil.Create("UIPadding", { PaddingLeft = UDim.new(0, 12), PaddingRight = UDim.new(0, 12), Parent = editRow })
	UIUtil.Create("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		VerticalAlignment = Enum.VerticalAlignment.Center,
		Padding = UDim.new(0, 8),
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = editRow,
	})
	parts.EditHint = label({ Name = "Hint", Text = "", Color = INK, TextSize = 17, Size = UDim2.fromOffset(240, 60), LayoutOrder = 0, Parent = editRow })
	parts.EditHint.TextWrapped = true
	parts.EditHint.TextTruncate = Enum.TextTruncate.None
	local function editButton(name: string, text: string, color: Color3, order: number, fn: () -> ()): TextButton
		local b = UIUtil.PillButton({ Name = name, Text = text, Color = color, Height = 44, TextSize = 17, LayoutOrder = order, Parent = editRow })
		b.AutomaticSize = Enum.AutomaticSize.None
		b.Size = UDim2.fromOffset(textWidth(text, 17) + 36, 44)
		b.Activated:Connect(fn)
		return b
	end
	parts.Rotate = editButton("Rotate", Locale.T("🔄 Rotate"), LILAC, 1, cb.Rotate)
	parts.SnapButton = editButton("Snap", "", Color3.fromRGB(255, 200, 90), 2, cb.Snap)
	parts.PutAway = editButton("PutAway", Locale.T("📦 Put away"), Color3.fromRGB(255, 150, 120), 3, cb.PutAway)
	parts.Drop = editButton("Drop", Locale.T("✅ Drop"), MINT, 4, cb.Drop)
	parts.CancelMove = editButton("CancelMove", Locale.T("❌ Cancel"), Color3.fromRGB(236, 236, 244), 5, cb.Cancel)
	parts.Done = editButton("DoneEditing", Locale.T("✅ Done"), MINT, 6, cb.ToggleEdit)
	parts.EditBar = editBar

	-- Toasts
	local toasts = UIUtil.Create("Frame", {
		Name = "Toasts",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 114),
		Size = UDim2.fromOffset(660, 140),
		BackgroundTransparency = 1,
		Parent = root,
	})
	UIUtil.Create("UIListLayout", {
		FillDirection = Enum.FillDirection.Vertical,
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		Padding = UDim.new(0, 6),
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = toasts,
	})
	parts.ToastHolder = toasts

	-- Fenêtre "Visiter"
	local dimmer = UIUtil.Create("TextButton", {
		Name = "VisitDimmer",
		Size = UDim2.new(1, 400, 1, 400),
		Position = UDim2.fromOffset(-200, -200),
		BackgroundColor3 = Color3.new(0, 0, 0),
		BackgroundTransparency = 0.45,
		AutoButtonColor = false,
		Text = "",
		Visible = false,
		ZIndex = 20,
		Parent = root,
	})
	dimmer.Activated:Connect(function()
		self:CloseVisit()
	end)
	local card = UIUtil.Create("Frame", {
		Name = "VisitCard",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.52),
		Size = UDim2.fromOffset(520, 440),
		BackgroundColor3 = CARD,
		ZIndex = 21,
		Visible = false,
		Parent = root,
	})
	UIUtil.Corner(card, 24)
	UIUtil.Stroke(card, LILAC, 2.5, 0)
	UIUtil.SinkClicks(card)
	UIUtil.Gradient(card, ColorSequence.new(Color3.fromRGB(255, 255, 255), Color3.fromRGB(246, 236, 255)), 90)
	label({ Name = "Title", Text = Locale.T("👥 Visit a house"), Color = PINK_DEEP, TextSize = 26, Size = UDim2.new(1, -80, 0, 40),
		Position = UDim2.fromOffset(20, 12), XAlign = Enum.TextXAlignment.Left, ZIndex = 22, Parent = card })
	local count = label({ Name = "Count", Text = "", Color = WHITE, TextSize = 14, Size = UDim2.fromOffset(80, 24), AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -62, 0, 20), ZIndex = 22, Parent = card })
	count.BackgroundColor3 = LILAC
	count.BackgroundTransparency = 0
	UIUtil.Corner(count, UDim.new(1, 0))
	parts.VisitCount = count
	parts.VisitSub = label({ Name = "Subtitle", Text = Locale.T("Walk to their door, sit on their sofa and leave a ❤️"), Color = INK, TextSize = 15,
		Font = Theme.Fonts.Body, Size = UDim2.new(1, -80, 0, 20), Position = UDim2.fromOffset(20, 50), XAlign = Enum.TextXAlignment.Left, ZIndex = 22, Parent = card })
	local close = UIUtil.CloseButton({ Name = "CloseVisit", Size = 40, AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -12, 0, 12), ZIndex = 23 })
	close.Parent = card
	close.Activated:Connect(function()
		self:CloseVisit()
	end)
	local list = UIUtil.Create("ScrollingFrame", {
		Name = "List",
		Position = UDim2.fromOffset(14, 80),
		Size = UDim2.new(1, -28, 1, -94),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 6,
		ScrollBarImageColor3 = LILAC,
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollingDirection = Enum.ScrollingDirection.Y,
		ZIndex = 22,
		Parent = card,
	})
	UIUtil.Create("UIListLayout", {
		FillDirection = Enum.FillDirection.Vertical,
		Padding = UDim.new(0, 8),
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = list,
	})
	UIUtil.Create("UIPadding", { PaddingRight = UDim.new(0, 8), PaddingTop = UDim.new(0, 2), Parent = list })
	parts.VisitDimmer = dimmer
	parts.VisitCard = card
	parts.VisitList = list

	-- 🧭 Boussole vers sa maison (sous "Retour") : flèche qui tourne + distance ;
	-- un appui = "Rentrer" (téléportation devant sa porte). v9.6 : PETITE et
	-- discrète (plus aucune ligne / arc dans le monde vers la maison)
	local compass = UIUtil.Create("TextButton", {
		Name = "HomeCompass",
		Position = UDim2.fromOffset(10, 62),
		Size = UDim2.fromOffset(96, 32),
		BackgroundColor3 = Color3.fromRGB(92, 58, 120),
		BackgroundTransparency = 0.4,
		AutoButtonColor = false,
		Text = "",
		Visible = false,
		Parent = root,
	})
	UIUtil.Corner(compass, UDim.new(1, 0))
	UIUtil.Stroke(compass, WHITE, 1, 0.6)
	local dial = UIUtil.Create("Frame", {
		Name = "Dial",
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 4, 0.5, 0),
		Size = UDim2.fromOffset(24, 24),
		BackgroundColor3 = WHITE,
		Parent = compass,
	})
	UIUtil.Corner(dial, UDim.new(1, 0))
	UIUtil.Stroke(dial, PINK, 1, 0)
	-- (flèche en traits : pas de ClipsDescendants, elle peut tourner)
	local needle = UIUtil.Create("Frame", { Name = "Needle", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(20, 20), BackgroundTransparency = 1, ZIndex = 3, Parent = dial })
	local function bar(x1: number, y1: number, x2: number, y2: number)
		local dx, dy = x2 - x1, y2 - y1
		local b = UIUtil.Create("Frame", {
			Name = "Bar",
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromOffset((x1 + x2) / 2, (y1 + y2) / 2),
			Size = UDim2.fromOffset(math.sqrt(dx * dx + dy * dy) + 3, 3),
			Rotation = math.deg(math.atan2(dy, dx)),
			BackgroundColor3 = PINK_DEEP,
			BorderSizePixel = 0,
			ZIndex = 3,
			Parent = needle,
		})
		UIUtil.Corner(b, UDim.new(1, 0))
	end
	bar(10, 3, 10, 17)
	bar(10, 3, 5, 8)
	bar(10, 3, 15, 8)
	parts.CompassText = label({ Name = "Text", Text = "", Color = WHITE, TextSize = 14, Size = UDim2.new(1, -38, 1, 0), Position = UDim2.fromOffset(32, 0),
		XAlign = Enum.TextXAlignment.Left, Parent = compass })
	compass.Activated:Connect(function()
		cb.Home()
	end)
	parts.Compass = compass
	parts.Needle = needle

	-- Pastille d'action en bas au milieu (entre joystick et "sauter" sur
	-- mobile) : "■ Arrêter" pendant une émote, "Se lever" quand on est assis
	local action = UIUtil.PillButton({ Name = "StopEmote", Text = "", Color = Color3.fromRGB(255, 92, 120), Height = 50, TextSize = 20, Parent = root })
	action.AutomaticSize = Enum.AutomaticSize.None
	action.AnchorPoint = Vector2.new(0.5, 1)
	action.Position = UDim2.new(0.5, 0, 1, -18)
	action.Visible = false
	action.TextXAlignment = Enum.TextXAlignment.Right
	local actionPad = action:FindFirstChildOfClass("UIPadding")
	if actionPad then
		actionPad.PaddingLeft = UDim.new(0, 50)
		actionPad.PaddingRight = UDim.new(0, 20)
	end
	-- icône : carré "stop" ou flèche "se lever"
	local stopIcon = UIUtil.Create("Frame", { Name = "StopIcon", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0, -26, 0.5, 0),
		Size = UDim2.fromOffset(16, 16), BackgroundColor3 = WHITE, BorderSizePixel = 0, ZIndex = 4, Parent = action })
	UIUtil.Corner(stopIcon, 3)
	local upIcon = UIUtil.Icon("Up", { Size = 20, Color = WHITE, Position = UDim2.new(0, -26, 0.5, 0), ZIndex = 4, Parent = action })
	upIcon.Name = "UpIcon"
	action.Activated:Connect(function()
		if self.ActionState == "Sit" then
			cb.GetUp()
		else
			cb.StopEmote()
		end
	end)
	parts.Action = action
	parts.StopIcon = stopIcon
	parts.UpIcon = upIcon
	self.ActionState = nil

	-- Écran de chargement (plein écran, sous les encoches aussi)
	self:BuildOverlay()

	self:SetSnap(true)
	self:SetEditing(false, false)
end

----------------------------------------------------------------------
-- Mise en page (échelle, téléphone)
----------------------------------------------------------------------

function TownHud.Layout(self: any)
	local size = self.Gui.AbsoluteSize
	if size.X < 10 or size.Y < 10 then
		return
	end
	local touch = UserInputService.TouchEnabled and not UserInputService.MouseEnabled
	local phone = touch and math.min(size.X, size.Y) < 500
	self.Phone = phone
	-- (téléphone : toile de 820 x 430 -> tout est plus gros ; PC : 1100 x 620)
	local designW, designH = phone and 820 or 1100, phone and 430 or 620
	local scale = math.clamp(math.min(size.X / designW, size.Y / designH), 0.45, 1.35)
	self.Scale.Scale = scale
	self.Root.Size = UDim2.fromOffset(size.X / scale, size.Y / scale)
	local parts = self.Parts
	local backText = phone and Locale.T("Clicker") or Locale.T("Back to clicker")
	parts.Back.Text = backText
	parts.Back.Size = UDim2.fromOffset(textWidth(backText, 19) + 64, 46)
	for _, spec in ipairs({ { parts.Home, phone and "🏠" or Locale.T("🏠 Go home") }, { parts.VisitButton, phone and "👥" or Locale.T("👥 Visit…") } }) do
		local button, text = spec[1], spec[2]
		button.Text = text
		button.AutomaticSize = Enum.AutomaticSize.None
		local padding = button:FindFirstChildOfClass("UIPadding")
		local pad = phone and 12 or 18
		if padding then
			padding.PaddingLeft = UDim.new(0, pad)
			padding.PaddingRight = UDim.new(0, pad)
		end
		button.Size = UDim2.fromOffset(phone and 52 or textWidth(text, 19) + pad * 2 + 6, phone and 52 or 46)
	end
	parts.Counter.Size = UDim2.fromOffset(phone and 220 or 260, 58)
	-- téléphone : colonne compacte sous les boutons du haut (le bouton
	-- "sauter" de Roblox est en bas à droite, plus à gauche que la colonne)
	if phone then
		parts.Column.AnchorPoint = Vector2.new(1, 0)
		parts.Column.Position = UDim2.new(1, -8, 0, 66)
	else
		parts.Column.AnchorPoint = Vector2.new(1, 0.5)
		parts.Column.Position = UDim2.new(1, -12, 0.46, 0)
	end
	local layout = parts.Column:FindFirstChildOfClass("UIListLayout")
	if layout then
		layout.Padding = UDim.new(0, phone and 16 or 24)
	end
	for _, spec in ipairs({ { parts.Click, 70, 58 }, { parts.Emote, 56, 46 }, { parts.Edit, 56, 46 }, { parts.Like, 56, 46 } }) do
		local d = phone and spec[3] or spec[2]
		spec[1].Size = UDim2.fromOffset(d, d)
		spec[1].TextSize = math.floor(d * 0.46)
		local tag = spec[1]:FindFirstChild("Tag")
		if tag then
			tag.Visible = not phone
		end
	end
	-- voile plein écran (chargement, survol) : même échelle que le reste
	local overlay = self.Overlay
	local full = overlay and overlay.AbsoluteSize or size
	if full.X < 10 or full.Y < 10 then
		full = size
	end
	local overlayScale = math.clamp(math.min(full.X / 860, full.Y / 520), 0.45, 1.3)
	parts.LoadingScale.Scale = overlayScale
	parts.CinemaScale.Scale = overlayScale
	-- bandes cinéma : 11 % de l'écran, jamais moins de 56 px (bouton "Passer" dedans)
	local barH = math.max(math.floor(full.Y * 0.11), 56)
	parts.TopBar.Size = UDim2.new(1, 0, 0, barH)
	parts.BottomBar.Size = UDim2.new(1, 0, 0, barH)
	parts.Skip.Position = UDim2.new(1, phone and -64 or -40, 0, barH / 2)
	parts.SkipScale.Scale = math.clamp(overlayScale, 0.8, 1.2)
	local card = parts.VisitCard
	local rootSize = Vector2.new(size.X / scale, size.Y / scale)
	card.Size = UDim2.fromOffset(math.min(520, rootSize.X - 30), math.min(440, rootSize.Y - 30))
end

----------------------------------------------------------------------
-- Mises à jour
----------------------------------------------------------------------

function TownHud.SetVisible(self: any, visible: boolean)
	self.Gui.Enabled = visible
	if not visible then
		self:CloseVisit()
		self:SetEmoteWheel(false)
		self:SetCinematic(false)
		self:SetAction(nil)
		self:SetCompass(false)
	end
end

-- Compteur (appelé ~10 fois par seconde)
function TownHud.UpdateCounter(self: any)
	local data = ClientState.Data
	local value = ClientState.GetDisplayDopamine()
	if value <= 0 then
		value = ClientState.GetTargetDopamine()
	end
	self.Parts.Amount.Text = "🧠 " .. NumberFormatter.Format(value)
	local rate = data and tonumber(data.PerSecond) or 0
	self.Parts.Rate.Text = Locale.T("+%s / sec", NumberFormatter.Format(rate))
end

function TownHud.SetContext(self: any, context: Context?)
	self.Context = context
	local parts = self.Parts
	local snapshot = context and context.Snapshot
	parts.Banner.Visible = snapshot ~= nil and not self.DeskActive
	parts.Edit.Visible = context ~= nil and context.IsOwner and context.InHouse and not self.DeskActive
	parts.Like.Visible = snapshot ~= nil and not (context and context.IsOwner)
	if not snapshot or not context then
		return
	end
	local size = Config.HouseSizesById[snapshot.Size] or Config.House.Sizes[1]
	local name = tostring(snapshot.DisplayName or snapshot.Name or "?")
	local title = context.IsOwner and Locale.T("🏠 Your %s", Locale.T(size.Name)) or Locale.T("🏠 %s's %s", name, Locale.T(size.Name))
	local text = string.format("%s   ❤️ %s   👀 %s%s", title, NumberFormatter.Format(tonumber(snapshot.Likes) or 0),
		NumberFormatter.Format(tonumber(snapshot.Visits) or 0), context.Locked and ("   " .. Locale.T("🔒 Closed to you")) or "")
	parts.BannerText.Text = text
	local textW = math.min(textWidth(text, 17), self.Phone and 360 or 560)
	parts.BannerText.Size = UDim2.fromOffset(textW + 4, 34)
	local open = WorldLayout.NormalizeOpen(snapshot.Open)
	local openText = Locale.T(OPEN_TEXT[open])
	parts.OpenButton.Visible = context.IsOwner
	parts.OpenButton.Text = openText
	local openW = textWidth(openText, 14) + 28
	parts.OpenButton.Size = UDim2.fromOffset(openW, 26)
	parts.Banner.Size = UDim2.fromOffset(textW + 4 + 20 + (context.IsOwner and openW + 10 or 0), 34)
end

function TownHud.SetSnap(self: any, on: boolean)
	self.Snap = on
	local text = on and Locale.T("🧲 Grid: on") or Locale.T("🧲 Grid: off")
	local button = self.Parts.SnapButton
	button.Text = text
	button.Size = UDim2.fromOffset(textWidth(text, 17) + 36, 44)
end

-- Mode édition (barre du bas) : `holding` = un meuble est en main
function TownHud.SetEditing(self: any, editing: boolean, holding: boolean, itemName: string?)
	self.Editing = editing
	self.Holding = holding
	local parts = self.Parts
	parts.EditBar.Visible = editing
	parts.Edit.Text = editing and "✅" or "✏️"
	local touch = UserInputService.TouchEnabled and not UserInputService.MouseEnabled
	if holding then
		parts.EditHint.Text = (itemName and (itemName .. " · ") or "") .. (touch and Locale.T("drag to move") or Locale.T("move the mouse · R to rotate"))
	else
		parts.EditHint.Text = touch and Locale.T("✏️ Tap a piece of furniture to pick it up") or Locale.T("✏️ Click a piece of furniture to pick it up")
	end
	local width = 24 + (self.Phone and 0 or 248)
	parts.EditHint.Visible = not self.Phone
	for _, name in ipairs({ "Rotate", "SnapButton", "PutAway", "Drop", "CancelMove" }) do
		parts[name].Visible = holding
		if holding then
			width += parts[name].Size.X.Offset + 8
		end
	end
	parts.Done.Visible = not holding
	if not holding then
		width += parts.Done.Size.X.Offset + 8
		if self.Phone then
			-- (téléphone : l'indice passe dans la barre à la place des boutons)
			parts.EditHint.Visible = true
			width += 248
		end
	end
	parts.EditBar.Size = UDim2.fromOffset(width, 64)
	if parts.Action then
		self:PlaceAction()
	end
end

-- "+123" qui s'envole au-dessus d'un bouton
function TownHud.Pop(self: any, anchor: GuiObject, text: string)
	local pop = label({ Name = "Pop", Text = text, Color = PINK_DEEP, TextSize = 22, Size = UDim2.fromOffset(160, 26), AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, -40, 0, 0), ZIndex = 30, Parent = anchor })
	UIUtil.Create("UIStroke", { Color = WHITE, Thickness = 2, Parent = pop })
	local ok = pcall(function()
		TweenService:Create(pop, TweenInfo.new(0.7, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			Position = UDim2.new(0.5, -40, 0, -46),
			TextTransparency = 1,
		}):Play()
	end)
	task.delay(ok and 0.75 or 0.4, function()
		pop:Destroy()
	end)
end

function TownHud.Toast(self: any, text: string, color: Color3?)
	local parts = self.Parts
	local holder: Frame = parts.ToastHolder
	self.ToastCount += 1
	local width = math.min(textWidth(text, 18) + 40, 640)
	local toast = UIUtil.Create("Frame", {
		Name = "Toast",
		Size = UDim2.fromOffset(width, 40),
		BackgroundColor3 = color or Color3.fromRGB(92, 58, 120),
		BackgroundTransparency = 0.08,
		LayoutOrder = self.ToastCount,
		Parent = holder,
	})
	UIUtil.Corner(toast, UDim.new(1, 0))
	label({ Name = "Text", Text = text, Color = WHITE, TextSize = 18, Size = UDim2.new(1, -24, 1, 0), Position = UDim2.fromOffset(12, 0), Parent = toast })
	table.insert(self.Toasts, toast)
	while #self.Toasts > 3 do
		local oldest = table.remove(self.Toasts, 1)
		if oldest then
			oldest:Destroy()
		end
	end
	task.delay(3.6, function()
		local index = table.find(self.Toasts, toast)
		if index then
			table.remove(self.Toasts, index)
		end
		toast:Destroy()
	end)
end

function TownHud.SetEmoteWheel(self: any, open: boolean)
	self.EmoteOpen = open
	self.Parts.Wheel.Visible = open
end

----------------------------------------------------------------------
-- Voile plein écran : chargement, fondus, survol (ScreenGui à part,
-- sous les encoches aussi ; reste actif quand le HUD est masqué)
----------------------------------------------------------------------

local LOADING_TIPS = {
	"Tip: follow the glowing arc to find your house",
	"Tip: tap 😀 to dance, wave or sit — walk or jump to stop",
	"Tip: leave a ❤️ at a friend's house: you both earn Dopamine",
	"Tip: sit on any sofa, chair or bench",
	"Tip: ✏️ moves your furniture inside your house",
	"Tip: your Dopamine keeps growing while you walk around",
}

local SKYLINE = { -- (x en échelle, largeur px, hauteur px, couleur)
	{ 0.03, 70, 90, 1 }, { 0.1, 56, 130, 2 }, { 0.17, 84, 70, 1 }, { 0.26, 60, 110, 2 }, { 0.33, 90, 84, 1 },
	{ 0.62, 80, 96, 1 }, { 0.7, 58, 140, 2 }, { 0.78, 92, 76, 1 }, { 0.87, 64, 118, 2 }, { 0.95, 78, 88, 1 },
}

function TownHud.BuildOverlay(self: any)
	local playerGui = self.Gui.Parent
	local old = playerGui and playerGui:FindFirstChild("TownOverlay")
	if old then
		old:Destroy()
	end
	local overlay = Instance.new("ScreenGui")
	overlay.Name = "TownOverlay"
	overlay.ResetOnSpawn = false
	overlay.IgnoreGuiInset = true
	overlay.ScreenInsets = Enum.ScreenInsets.None
	overlay.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	overlay.DisplayOrder = 45
	overlay.Enabled = true
	overlay.Parent = playerGui
	self.Overlay = overlay
	local parts = self.Parts

	-- Chargement : ciel rose -> lilas, soleil, silhouette de la ville
	local loading = UIUtil.Create("Frame", {
		Name = "Loading",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = WHITE,
		BorderSizePixel = 0,
		Visible = false,
		ZIndex = 40,
		Parent = overlay,
	})
	UIUtil.Gradient(loading, ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(176, 160, 255)),
		ColorSequenceKeypoint.new(0.55, Color3.fromRGB(255, 176, 214)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(255, 222, 196)),
	}), 90)
	local sun = UIUtil.Create("Frame", { Name = "Sun", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.62),
		Size = UDim2.fromOffset(300, 300), BackgroundColor3 = Color3.fromRGB(255, 244, 214), BackgroundTransparency = 0.35, ZIndex = 41, Parent = loading })
	UIUtil.Corner(sun, UDim.new(1, 0))
	local halo = UIUtil.Create("Frame", { Name = "Halo", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(1.5, 1.5), BackgroundColor3 = WHITE, BackgroundTransparency = 0.82, ZIndex = 41, Parent = sun })
	UIUtil.Corner(halo, UDim.new(1, 0))
	-- silhouette : maisons (corps + toit en carré tourné) sur une colline
	UIUtil.Create("Frame", { Name = "Ground", AnchorPoint = Vector2.new(0, 1), Position = UDim2.fromScale(0, 1),
		Size = UDim2.new(1, 0, 0.16, 0), BackgroundColor3 = Color3.fromRGB(150, 118, 196), BorderSizePixel = 0, ZIndex = 43, Parent = loading })
	local tones = { Color3.fromRGB(170, 136, 214), Color3.fromRGB(196, 160, 236) }
	for _, spec in ipairs(SKYLINE) do
		local color = tones[spec[4]]
		local body = UIUtil.Create("Frame", { Name = "House", AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(spec[1], 0, 0.84, 1),
			Size = UDim2.fromOffset(spec[2], spec[3]), BackgroundColor3 = color, BorderSizePixel = 0, ZIndex = 42, Parent = loading })
		local roofSide = spec[2] / math.sqrt(2)
		UIUtil.Create("Frame", { Name = "Roof", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0), Rotation = 45,
			Size = UDim2.fromOffset(roofSide, roofSide), BackgroundColor3 = color, BorderSizePixel = 0, ZIndex = 42, Parent = body })
		for w = 0, 1 do
			local window = UIUtil.Create("Frame", { Name = "Window", AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.3 + w * 0.4, 0, 0, spec[3] * 0.3),
				Size = UDim2.fromOffset(12, 14), BackgroundColor3 = Color3.fromRGB(255, 236, 170), BorderSizePixel = 0, ZIndex = 42, Parent = body })
			UIUtil.Corner(window, 3)
		end
	end
	-- centre : titre, état, barre, astuce (mis à l'échelle dans Layout)
	local center = UIUtil.Create("Frame", { Name = "Center", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.4),
		Size = UDim2.fromOffset(760, 260), BackgroundTransparency = 1, ZIndex = 44, Parent = loading })
	parts.LoadingScale = UIUtil.Create("UIScale", { Parent = center })
	label({ Name = "Welcome", Text = Locale.T("Welcome to"), Color = WHITE, TextSize = 26, Size = UDim2.new(1, 0, 0, 34), ZIndex = 45, Parent = center })
	local title = label({ Name = "Title", Text = "DOPAMINE TOWN", Color = WHITE, TextSize = 78, Size = UDim2.new(1, 0, 0, 90),
		Position = UDim2.fromOffset(0, 30), ZIndex = 45, Parent = center })
	UIUtil.Create("UIStroke", { Color = PINK_DEEP, Thickness = 5, Parent = title })
	parts.LoadingText = label({ Name = "Text", Text = "", Color = INK, TextSize = 22, Font = Theme.Fonts.Title, Size = UDim2.new(1, 0, 0, 30),
		Position = UDim2.fromOffset(0, 136), ZIndex = 45, Parent = center })
	local track = UIUtil.Create("Frame", { Name = "Progress", AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 176),
		Size = UDim2.fromOffset(420, 18), BackgroundColor3 = WHITE, BackgroundTransparency = 0.25, ZIndex = 45, Parent = center })
	UIUtil.Corner(track, UDim.new(1, 0))
	UIUtil.Stroke(track, WHITE, 2, 0)
	local fill = UIUtil.Create("Frame", { Name = "Fill", Size = UDim2.fromScale(0.05, 1), BackgroundColor3 = PINK, ZIndex = 46, Parent = track })
	UIUtil.Corner(fill, UDim.new(1, 0))
	UIUtil.Gradient(fill, ColorSequence.new(Color3.fromRGB(255, 120, 190), Color3.fromRGB(255, 190, 110)), 0)
	parts.LoadingFill = fill
	parts.LoadingTip = label({ Name = "Tip", Text = "", Color = INK, TextSize = 18, Font = Theme.Fonts.Body, Size = UDim2.new(1, 0, 0, 26),
		Position = UDim2.fromOffset(0, 208), ZIndex = 45, Parent = center })
	parts.Loading = loading

	-- Survol : bandes cinéma, titre, "Passer"
	local cinema = UIUtil.Create("Frame", { Name = "Cinematic", Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Visible = false, ZIndex = 30, Parent = overlay })
	for _, spec in ipairs({ { "TopBar", 0 }, { "BottomBar", 1 } }) do
		parts[spec[1]] = UIUtil.Create("Frame", { Name = spec[1], AnchorPoint = Vector2.new(0, spec[2]), Position = UDim2.fromScale(0, spec[2]), Size = UDim2.fromScale(1, 0.11),
			BackgroundColor3 = Color3.fromRGB(12, 8, 20), BorderSizePixel = 0, ZIndex = 31, Parent = cinema })
	end
	local cinemaCenter = UIUtil.Create("Frame", { Name = "Titles", AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.fromScale(0.5, 0.86),
		Size = UDim2.fromOffset(760, 130), BackgroundTransparency = 1, ZIndex = 32, Parent = cinema })
	parts.CinemaScale = UIUtil.Create("UIScale", { Parent = cinemaCenter })
	local cTitle = label({ Name = "Title", Text = "DOPAMINE TOWN", Color = WHITE, TextSize = 64, Size = UDim2.new(1, 0, 0, 74), ZIndex = 33, Parent = cinemaCenter })
	local cStroke = UIUtil.Create("UIStroke", { Color = PINK_DEEP, Thickness = 4, Parent = cTitle })
	local cSub = label({ Name = "Subtitle", Text = "", Color = WHITE, TextSize = 24, Size = UDim2.new(1, 0, 0, 32), Position = UDim2.fromOffset(0, 78), ZIndex = 33, Parent = cinemaCenter })
	local cSubStroke = UIUtil.Create("UIStroke", { Color = INK, Thickness = 2, Transparency = 0.2, Parent = cSub })
	parts.CinemaTitle, parts.CinemaSub, parts.CinemaStroke, parts.CinemaSubStroke = cTitle, cSub, cStroke, cSubStroke
	local skip = UIUtil.PillButton({ Name = "SkipIntro", Text = Locale.T("Skip"), Color = WHITE, TextColor3 = INK, Height = 40, TextSize = 18, ZIndex = 34, Parent = cinema })
	skip.AutomaticSize = Enum.AutomaticSize.None
	skip.TextXAlignment = Enum.TextXAlignment.Left
	skip.AnchorPoint = Vector2.new(1, 0.5)
	skip.Position = UDim2.new(1, -40, 0.055, 0)
	skip.Size = UDim2.fromOffset(textWidth(Locale.T("Skip"), 18) + 62, 40)
	local skipPad = skip:FindFirstChildOfClass("UIPadding")
	if skipPad then
		skipPad.PaddingLeft = UDim.new(0, 18)
		skipPad.PaddingRight = UDim.new(0, 40)
	end
	UIUtil.Icon("Next", { Size = 18, Color = PINK_DEEP, Position = UDim2.new(1, 20, 0.5, 0), ZIndex = 35, Parent = skip })
	parts.SkipScale = UIUtil.Create("UIScale", { Parent = skip })
	skip.Activated:Connect(function()
		self.Callbacks.SkipIntro()
	end)
	parts.Cinema = cinema
	parts.Skip = skip

	-- Fondu (sortie, fin du chargement)
	parts.Fade = UIUtil.Create("Frame", { Name = "Fade", Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.fromRGB(255, 190, 220),
		BackgroundTransparency = 1, BorderSizePixel = 0, Visible = false, ZIndex = 60, Parent = overlay })
end

-- Écran de chargement ; `progress` 0..1 (barre)
function TownHud.ShowLoading(self: any, visible: boolean, text: string?, progress: number?)
	local parts = self.Parts
	local wasVisible = parts.Loading.Visible
	parts.Loading.Visible = visible
	if text then
		parts.LoadingText.Text = text
	end
	if progress then
		self:SetLoadingProgress(progress)
	end
	if visible and not wasVisible then
		-- astuces qui défilent tant que l'écran est là
		self.TipToken = (self.TipToken or 0) + 1
		local token = self.TipToken
		local index = math.random(1, #LOADING_TIPS)
		parts.LoadingTip.Text = Locale.T(LOADING_TIPS[index])
		task.spawn(function()
			while self.TipToken == token and parts.Loading.Visible do
				task.wait(2.6)
				if self.TipToken ~= token or not parts.Loading.Visible then
					break
				end
				index = index % #LOADING_TIPS + 1
				parts.LoadingTip.Text = Locale.T(LOADING_TIPS[index])
			end
		end)
	elseif not visible and wasVisible then
		self.TipToken = (self.TipToken or 0) + 1
		-- (le chargement s'efface en douceur : voile de la même couleur)
		self:Fade(0, 0, Color3.fromRGB(255, 186, 214))
		self:Fade(1, 0.6)
	end
end

function TownHud.SetLoadingProgress(self: any, progress: number)
	local p = math.clamp(progress, 0.03, 1)
	self.Parts.LoadingFill.Size = UDim2.fromScale(p, 1)
end

-- Voile plein écran : `alpha` 0 = couvert, 1 = transparent
function TownHud.Fade(self: any, alpha: number, duration: number, color: Color3?)
	local fade: Frame = self.Parts.Fade
	if color then
		fade.BackgroundColor3 = color
	end
	if self.FadeTween then
		pcall(function()
			self.FadeTween:Cancel()
		end)
		self.FadeTween = nil
	end
	fade.Visible = true
	if duration <= 0 then
		fade.BackgroundTransparency = alpha
		fade.Visible = alpha < 1
		return
	end
	local ok, tween = pcall(function()
		return TweenService:Create(fade, TweenInfo.new(duration, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut), { BackgroundTransparency = alpha })
	end)
	if ok and tween then
		self.FadeTween = tween
		tween.Completed:Connect(function()
			if self.FadeTween == tween then
				self.FadeTween = nil
				fade.Visible = fade.BackgroundTransparency < 0.999
			end
		end)
		tween:Play()
	else
		fade.BackgroundTransparency = alpha
		fade.Visible = alpha < 1
	end
end

-- Survol : bandes + titre ; le HUD normal est caché pendant ce temps
function TownHud.SetCinematic(self: any, on: boolean, subtitle: string?)
	local parts = self.Parts
	parts.Cinema.Visible = on
	self.Root.Visible = not on
	if subtitle then
		parts.CinemaSub.Text = subtitle
	end
	if on then
		self:SetIntroProgress(0)
	end
end

-- Titre du survol : apparaît puis s'efface (t = 0..1)
function TownHud.SetIntroProgress(self: any, t: number)
	local parts = self.Parts
	local alpha
	if t < 0.12 then
		alpha = 1 - t / 0.12
	elseif t < 0.7 then
		alpha = 0
	else
		alpha = math.clamp((t - 0.7) / 0.2, 0, 1)
	end
	parts.CinemaTitle.TextTransparency = alpha
	parts.CinemaSub.TextTransparency = alpha
	parts.CinemaStroke.Transparency = alpha
	parts.CinemaSubStroke.Transparency = 0.2 + 0.8 * alpha
end

-- 🖥️ Au bureau (DeskMode) : pas d'émotes ni de meubles, pas de pastille
-- (DeskMode montre son propre "Se lever")
function TownHud.SetDeskMode(self: any, active: boolean)
	self.DeskActive = active
	local parts = self.Parts
	parts.Emote.Visible = not active
	-- (au bureau, la bannière de la maison cacherait les écrans du haut)
	parts.Banner.Visible = not active and self.Context ~= nil and self.Context.Snapshot ~= nil
	if active then
		self:SetEmoteWheel(false)
		parts.Edit.Visible = false
		self:SetAction(nil)
	else
		local context = self.Context
		parts.Edit.Visible = context ~= nil and context.IsOwner and context.InHouse
	end
end

-- Pastille d'action : "Emote" -> ■ Arrêter, "Sit" -> Se lever, nil -> cachée
function TownHud.SetAction(self: any, state: string?)
	if self.DeskActive then
		state = nil
	end
	self.ActionState = state
	local parts = self.Parts
	local action: TextButton = parts.Action
	action.Visible = state ~= nil
	if not state then
		return
	end
	local text = state == "Sit" and Locale.T("Get up") or Locale.T("Stop")
	action.Text = text
	action.BackgroundColor3 = state == "Sit" and MINT or Color3.fromRGB(255, 92, 120)
	action:SetAttribute("BaseColor", action.BackgroundColor3)
	action.Size = UDim2.fromOffset(textWidth(text, 20) + 76, 50)
	parts.StopIcon.Visible = state ~= "Sit"
	parts.UpIcon.Visible = state == "Sit"
	self:PlaceAction()
end

-- (au-dessus de la barre d'édition si elle est ouverte)
function TownHud.PlaceAction(self: any)
	local parts = self.Parts
	local lift = parts.EditBar.Visible and 86 or 18
	parts.Action.Position = UDim2.new(0.5, 0, 1, -lift)
end

-- Boussole : `bearing` en degrés (0 = devant), `distance` en studs
function TownHud.SetCompass(self: any, visible: boolean, bearing: number?, distance: number?)
	local parts = self.Parts
	parts.Compass.Visible = visible
	if not visible then
		return
	end
	parts.Needle.Rotation = math.floor((bearing or 0) + 0.5)
	-- (1 stud = 0,28 m)
	local meters = math.floor((distance or 0) * 0.28 + 0.5)
	local text = Locale.T("🏠 %s m", tostring(meters))
	if parts.CompassText.Text ~= text then
		parts.CompassText.Text = text
		parts.Compass.Size = UDim2.fromOffset(math.max(84, textWidth(text, 14) + 44), 32)
	end
end

----------------------------------------------------------------------
-- Fenêtre "Visiter"
----------------------------------------------------------------------

export type VisitRow = { Snapshot: any, IsSelf: boolean, Locked: boolean }

function TownHud.OpenVisit(self: any, rows: { VisitRow })
	local parts = self.Parts
	local list: ScrollingFrame = parts.VisitList
	for _, child in ipairs(list:GetChildren()) do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end
	if #rows == 0 then
		label({ Name = "Empty", Text = Locale.T("Nobody else is here yet… invite a friend!"), Color = INK, TextSize = 17, Size = UDim2.new(1, 0, 0, 60),
			ZIndex = 23, Parent = list })
	end
	-- petite pastille (taille, ❤️, 👀, 🔒…)
	local function chip(parent: Instance, text: string, color: Color3, textColor: Color3, order: number)
		local width = textWidth(text, 13, Theme.Fonts.Title) + 16
		local c = UIUtil.Create("Frame", { Name = "Chip", Size = UDim2.fromOffset(width, 22), BackgroundColor3 = color, LayoutOrder = order, ZIndex = 24, Parent = parent })
		UIUtil.Corner(c, UDim.new(1, 0))
		label({ Name = "Text", Text = text, Color = textColor, TextSize = 13, Size = UDim2.fromScale(1, 1), ZIndex = 25, Parent = c })
	end
	for index, row in ipairs(rows) do
		local snapshot = row.Snapshot
		local inTown = snapshot.InTown == true
		local item = UIUtil.Create("Frame", {
			Name = "Row_" .. tostring(snapshot.UserId),
			Size = UDim2.new(1, 0, 0, 78),
			BackgroundColor3 = WHITE,
			LayoutOrder = index,
			ZIndex = 23,
			Parent = list,
		})
		UIUtil.Corner(item, 18)
		UIUtil.Stroke(item, row.IsSelf and PINK or Color3.fromRGB(226, 212, 250), row.IsSelf and 2 or 1.5, 0)
		UIUtil.Gradient(item, ColorSequence.new(row.IsSelf and Color3.fromRGB(255, 236, 246) or Color3.fromRGB(250, 246, 255), WHITE), 0)
		-- avatar dans un anneau (vert : en ville)
		local ring = UIUtil.Create("Frame", { Name = "Ring", Size = UDim2.fromOffset(60, 60), Position = UDim2.fromOffset(9, 9),
			BackgroundColor3 = inTown and MINT or Color3.fromRGB(214, 200, 240), ZIndex = 24, Parent = item })
		UIUtil.Corner(ring, UDim.new(1, 0))
		local head = UIUtil.Create("ImageLabel", {
			Name = "Head",
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromOffset(52, 52),
			BackgroundColor3 = Color3.fromRGB(255, 226, 240),
			Image = UIUtil.HeadshotUrl(tonumber(snapshot.UserId) or 1, 60),
			ZIndex = 25,
			Parent = ring,
		})
		UIUtil.Corner(head, UDim.new(1, 0))
		local dot = UIUtil.Create("Frame", { Name = "Status", AnchorPoint = Vector2.new(1, 1), Position = UDim2.fromScale(1, 1), Size = UDim2.fromOffset(16, 16),
			BackgroundColor3 = inTown and Color3.fromRGB(60, 210, 130) or Color3.fromRGB(190, 180, 200), ZIndex = 26, Parent = ring })
		UIUtil.Corner(dot, UDim.new(1, 0))
		UIUtil.Stroke(dot, WHITE, 2, 0)
		local size = Config.HouseSizesById[snapshot.Size] or Config.House.Sizes[1]
		local name = tostring(snapshot.DisplayName or snapshot.Name or "?")
		-- nom, puis l'état (en ville / clique, 🔒) juste après
		local nameText = row.IsSelf and Locale.T("%s (you)", name) or name
		local nameW = math.min(textWidth(nameText, 19) + 10, 190)
		label({ Name = "Name", Text = nameText, Color = INK, TextSize = 19, Size = UDim2.fromOffset(nameW + 4, 24),
			Position = UDim2.fromOffset(80, 10), XAlign = Enum.TextXAlignment.Left, ZIndex = 24, Parent = item })
		local status = (inTown and Locale.T("🚶 in town") or Locale.T("💤 clicking")) .. (row.Locked and "  🔒" or "")
		label({ Name = "Status", Text = status, Color = inTown and Color3.fromRGB(40, 160, 100) or Color3.fromRGB(150, 130, 170), TextSize = 13, Font = Theme.Fonts.Body,
			Size = UDim2.fromOffset(textWidth(status, 13, Theme.Fonts.Body) + 6, 24), Position = UDim2.fromOffset(80 + nameW + 10, 10), XAlign = Enum.TextXAlignment.Left,
			ZIndex = 24, Parent = item })
		local chips = UIUtil.Create("Frame", { Name = "Chips", BackgroundTransparency = 1, Position = UDim2.fromOffset(80, 42), Size = UDim2.new(1, -240, 0, 22),
			ClipsDescendants = true, ZIndex = 24, Parent = item })
		UIUtil.Create("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 5), SortOrder = Enum.SortOrder.LayoutOrder, Parent = chips })
		chip(chips, string.format("%s %s", tostring(size.Icon or "🏠"), Locale.T(size.Name)), Color3.fromRGB(240, 232, 255), INK, 1)
		chip(chips, string.format("❤️ %s  👀 %s", NumberFormatter.Format(tonumber(snapshot.Likes) or 0), NumberFormatter.Format(tonumber(snapshot.Visits) or 0)),
			Color3.fromRGB(255, 228, 238), PINK_DEEP, 2)
		local go = UIUtil.PillButton({ Name = "Go", Text = row.IsSelf and Locale.T("🏠 Home") or Locale.T("🚶 Visit"), Color = row.IsSelf and PINK or LILAC,
			Height = 44, TextSize = 17, ZIndex = 24, AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -12, 0.5, 0), Parent = item })
		go.AutomaticSize = Enum.AutomaticSize.None
		go.Size = UDim2.fromOffset(textWidth(go.Text, 17) + 44, 44)
		go.Activated:Connect(function()
			self:CloseVisit()
			if row.IsSelf then
				self.Callbacks.Home()
			else
				self.Callbacks.Visit(tonumber(snapshot.UserId) or 0)
			end
		end)
	end
	parts.VisitCount.Text = Locale.T("%s houses", tostring(#rows))
	parts.VisitCount.Size = UDim2.fromOffset(textWidth(parts.VisitCount.Text, 14) + 20, 24)
	parts.VisitDimmer.Visible = true
	parts.VisitCard.Visible = true
	UIUtil.Pop(parts.VisitCard, 0.9, 0.2)
end

function TownHud.CloseVisit(self: any)
	self.Parts.VisitDimmer.Visible = false
	self.Parts.VisitCard.Visible = false
end

function TownHud.IsVisitOpen(self: any): boolean
	return self.Parts.VisitCard.Visible
end

function TownHud.Destroy(self: any)
	self.Gui:Destroy()
	if self.Overlay then
		self.Overlay:Destroy()
	end
end

return TownHud
