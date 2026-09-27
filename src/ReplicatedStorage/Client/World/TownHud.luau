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

	-- ⬅ retour au clicker
	local back = UIUtil.PillButton({
		Name = "BackToClicker",
		Text = "",
		Color = WHITE,
		Height = 46,
		TextSize = 20,
		Parent = root,
	})
	back.Position = UDim2.fromOffset(10, 8)
	local backRow = UIUtil.Create("Frame", {
		Name = "Content",
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(0, 1),
		AutomaticSize = Enum.AutomaticSize.X,
		ZIndex = 3,
		Parent = back,
	})
	UIUtil.Create("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		VerticalAlignment = Enum.VerticalAlignment.Center,
		Padding = UDim.new(0, 8),
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = backRow,
	})
	local arrowHolder = UIUtil.Create("Frame", { Name = "Arrow", BackgroundTransparency = 1, Size = UDim2.fromOffset(20, 20), LayoutOrder = 1, ZIndex = 3, Parent = backRow })
	UIUtil.Icon("ArrowLeft", { Size = 20, Thickness = 3, Color = PINK_DEEP, ZIndex = 4, Parent = arrowHolder })
	parts.BackText = label({ Name = "Text", Text = Locale.T("Back to clicker"), Color = INK, TextSize = 19, Size = UDim2.fromScale(0, 1),
		AutomaticSize = Enum.AutomaticSize.X, LayoutOrder = 2, ZIndex = 3, Parent = backRow })
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
		Size = UDim2.fromOffset(0, 34),
		AutomaticSize = Enum.AutomaticSize.X,
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
	parts.BannerText = label({ Name = "Text", Text = "", Color = WHITE, TextSize = 17, Size = UDim2.fromScale(0, 1), AutomaticSize = Enum.AutomaticSize.X,
		LayoutOrder = 1, Parent = banner })
	local openButton = UIUtil.PillButton({ Name = "OpenMode", Text = "", Color = MINT, Height = 26, TextSize = 14, LayoutOrder = 2, Parent = banner })
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
	local home = UIUtil.PillButton({ Name = "MyHouse", Text = Locale.T("🏠 My house"), Color = PINK, Height = 46, TextSize = 19, LayoutOrder = 1, Parent = topRight })
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
		Padding = UDim.new(0, 10),
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
		Size = UDim2.fromOffset(0, 60),
		AutomaticSize = Enum.AutomaticSize.X,
		BackgroundColor3 = CARD,
		Visible = false,
		ZIndex = 6,
		Parent = emote,
	})
	UIUtil.Corner(wheel, UDim.new(1, 0))
	UIUtil.Stroke(wheel, Color3.fromRGB(255, 196, 70), 2, 0.1)
	UIUtil.SinkClicks(wheel)
	UIUtil.Create("UIPadding", { PaddingLeft = UDim.new(0, 8), PaddingRight = UDim.new(0, 8), Parent = wheel })
	UIUtil.Create("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		VerticalAlignment = Enum.VerticalAlignment.Center,
		Padding = UDim.new(0, 6),
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = wheel,
	})
	for index, spec in ipairs(EMOTES) do
		local b = UIUtil.PillButton({ Name = "Emote_" .. spec.Id, Text = spec.Icon, Color = Color3.fromRGB(255, 240, 200), Height = 48, Round = true,
			TextSize = 24, LayoutOrder = index, ZIndex = 7, Parent = wheel })
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
		Size = UDim2.fromOffset(0, 64),
		AutomaticSize = Enum.AutomaticSize.X,
		BackgroundColor3 = CARD,
		Visible = false,
		Parent = root,
	})
	UIUtil.Corner(editBar, 22)
	UIUtil.Stroke(editBar, SKY, 2, 0.1)
	UIUtil.Shadow(editBar, 3, 0.8)
	UIUtil.SinkClicks(editBar)
	UIUtil.Create("UIPadding", { PaddingLeft = UDim.new(0, 12), PaddingRight = UDim.new(0, 12), Parent = editBar })
	UIUtil.Create("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		VerticalAlignment = Enum.VerticalAlignment.Center,
		Padding = UDim.new(0, 8),
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = editBar,
	})
	parts.EditHint = label({ Name = "Hint", Text = "", Color = INK, TextSize = 17, Size = UDim2.fromScale(0, 1), AutomaticSize = Enum.AutomaticSize.X,
		LayoutOrder = 0, Parent = editBar })
	local function editButton(name: string, text: string, color: Color3, order: number, fn: () -> ()): TextButton
		local b = UIUtil.PillButton({ Name = name, Text = text, Color = color, Height = 44, TextSize = 17, LayoutOrder = order, Parent = editBar })
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
		Size = UDim2.fromOffset(520, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
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
		Size = UDim2.fromScale(1, 1),
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

	-- Écran de chargement
	local loading = UIUtil.Create("Frame", {
		Name = "Loading",
		Size = UDim2.new(1, 400, 1, 400),
		Position = UDim2.fromOffset(-200, -200),
		BackgroundColor3 = Color3.fromRGB(255, 214, 236),
		Visible = false,
		ZIndex = 40,
		Parent = root,
	})
	UIUtil.Gradient(loading, ColorSequence.new(Color3.fromRGB(255, 226, 240), Color3.fromRGB(214, 226, 255)), 90)
	label({ Name = "Title", Text = "🚶 Dopamine Town", Color = PINK_DEEP, TextSize = 46, Size = UDim2.fromOffset(700, 60),
		AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.44), ZIndex = 41, Parent = loading })
	parts.LoadingText = label({ Name = "Text", Text = "", Color = INK, TextSize = 20, Font = Theme.Fonts.Body, Size = UDim2.fromOffset(700, 30),
		AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.53), ZIndex = 41, Parent = loading })
	parts.Loading = loading

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
	parts.BackText.Text = phone and Locale.T("Clicker") or Locale.T("Back to clicker")
	parts.Home.Text = phone and "🏠" or Locale.T("🏠 My house")
	parts.VisitButton.Text = phone and "👥" or Locale.T("👥 Visit…")
	for _, button in ipairs({ parts.Home, parts.VisitButton }) do
		local padding = button:FindFirstChildOfClass("UIPadding")
		if padding then
			padding.PaddingLeft = UDim.new(0, phone and 12 or 20)
			padding.PaddingRight = UDim.new(0, phone and 12 or 20)
		end
	end
	parts.Counter.Size = UDim2.fromOffset(phone and 220 or 260, 58)
	-- téléphone : colonne un peu plus haute (le bouton "sauter" est en bas à droite)
	parts.Column.Position = UDim2.new(1, -12, phone and 0.4 or 0.46, 0)
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
	parts.Banner.Visible = snapshot ~= nil
	parts.Edit.Visible = context ~= nil and context.IsOwner and context.InHouse
	parts.Like.Visible = snapshot ~= nil and not (context and context.IsOwner)
	if not snapshot or not context then
		return
	end
	local size = Config.HouseSizesById[snapshot.Size] or Config.House.Sizes[1]
	local name = tostring(snapshot.DisplayName or snapshot.Name or "?")
	local title = context.IsOwner and Locale.T("🏠 Your %s", Locale.T(size.Name)) or Locale.T("🏠 %s's %s", name, Locale.T(size.Name))
	parts.BannerText.Text = string.format("%s   ❤️ %s   👀 %s%s", title, NumberFormatter.Format(tonumber(snapshot.Likes) or 0),
		NumberFormatter.Format(tonumber(snapshot.Visits) or 0), context.Locked and ("   " .. Locale.T("🔒 Closed to you")) or "")
	local open = WorldLayout.NormalizeOpen(snapshot.Open)
	parts.OpenButton.Visible = context.IsOwner
	parts.OpenButton.Text = Locale.T(OPEN_TEXT[open])
end

function TownHud.SetSnap(self: any, on: boolean)
	self.Snap = on
	self.Parts.SnapButton.Text = on and Locale.T("🧲 Grid: on") or Locale.T("🧲 Grid: off")
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
	for _, name in ipairs({ "Rotate", "SnapButton", "PutAway", "Drop", "CancelMove" }) do
		parts[name].Visible = holding
	end
	parts.Done.Visible = not holding
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
	local toast = UIUtil.Create("Frame", {
		Name = "Toast",
		Size = UDim2.fromOffset(0, 40),
		AutomaticSize = Enum.AutomaticSize.X,
		BackgroundColor3 = color or Color3.fromRGB(92, 58, 120),
		BackgroundTransparency = 0.08,
		LayoutOrder = os.clock() * 1000 // 1,
		Parent = holder,
	})
	UIUtil.Corner(toast, UDim.new(1, 0))
	UIUtil.Create("UIPadding", { PaddingLeft = UDim.new(0, 18), PaddingRight = UDim.new(0, 18), Parent = toast })
	label({ Name = "Text", Text = text, Color = WHITE, TextSize = 18, Size = UDim2.fromScale(0, 1), AutomaticSize = Enum.AutomaticSize.X, Parent = toast })
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

function TownHud.ShowLoading(self: any, visible: boolean, text: string?)
	self.Parts.Loading.Visible = visible
	if text then
		self.Parts.LoadingText.Text = text
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
	for index, row in ipairs(rows) do
		local snapshot = row.Snapshot
		local item = UIUtil.Create("Frame", {
			Name = "Row_" .. tostring(snapshot.UserId),
			Size = UDim2.new(1, 0, 0, 64),
			BackgroundColor3 = row.IsSelf and Color3.fromRGB(255, 236, 246) or WHITE,
			LayoutOrder = index,
			ZIndex = 23,
			Parent = list,
		})
		UIUtil.Corner(item, 16)
		UIUtil.Stroke(item, Color3.fromRGB(230, 214, 250), 1.5, 0)
		local head = UIUtil.Create("ImageLabel", {
			Name = "Head",
			Size = UDim2.fromOffset(48, 48),
			Position = UDim2.fromOffset(8, 8),
			BackgroundColor3 = Color3.fromRGB(255, 226, 240),
			Image = UIUtil.HeadshotUrl(tonumber(snapshot.UserId) or 1, 60),
			ZIndex = 24,
			Parent = item,
		})
		UIUtil.Corner(head, UDim.new(1, 0))
		local size = Config.HouseSizesById[snapshot.Size] or Config.House.Sizes[1]
		local name = tostring(snapshot.DisplayName or snapshot.Name or "?")
		label({ Name = "Name", Text = row.IsSelf and Locale.T("%s (you)", name) or name, Color = INK, TextSize = 18, Size = UDim2.new(1, -200, 0, 24),
			Position = UDim2.fromOffset(66, 8), XAlign = Enum.TextXAlignment.Left, ZIndex = 24, Parent = item })
		local status = snapshot.InTown and Locale.T("🚶 in town") or Locale.T("💤 clicking")
		label({ Name = "House", Text = string.format("%s %s · ❤️ %s · %s%s", tostring(size.Icon or "🏠"), Locale.T(size.Name), NumberFormatter.Format(tonumber(snapshot.Likes) or 0),
			status, row.Locked and " · 🔒" or ""), Color = Color3.fromRGB(130, 100, 150), TextSize = 14, Font = Theme.Fonts.Body, Size = UDim2.new(1, -200, 0, 20),
			Position = UDim2.fromOffset(66, 34), XAlign = Enum.TextXAlignment.Left, ZIndex = 24, Parent = item })
		local go = UIUtil.PillButton({ Name = "Go", Text = row.IsSelf and Locale.T("🏠 Home") or Locale.T("🚶 Visit"), Color = row.IsSelf and PINK or LILAC,
			Height = 42, TextSize = 17, ZIndex = 24, Parent = item })
		go.AnchorPoint = Vector2.new(1, 0.5)
		go.Position = UDim2.new(1, -10, 0.5, 0)
		go.Activated:Connect(function()
			self:CloseVisit()
			if row.IsSelf then
				self.Callbacks.Home()
			else
				self.Callbacks.Visit(tonumber(snapshot.UserId) or 0)
			end
		end)
	end
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
end

return TownHud
