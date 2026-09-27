--[[
	HouseButtons (ModuleScript)
	Emplacement : ReplicatedStorage > Client > Components > House > HouseButtons

	Boutons "bonbons" de la maison (plus de boutons plats basiques) :
	  - Candy : bouton-outil carré (barre d'outils de l'éditeur) : face
	    brillante en dégradé + reflet, "lèvre" plus foncée dessous (effet 3D
	    qui s'enfonce quand on appuie), icône + légende, survol qui soulève
	    le bouton, état désactivé grisé ;
	  - Tip : petite bulle sombre au survol (nom + raccourci clavier).
	Tout est construit une fois ; les animations sont de simples Tweens.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Client = script.Parent.Parent.Parent
local Theme = require(Client.Theme)
local UIUtil = require(Client.UIUtil)
local Interface = require(Client.Interface)
local Locale = require(ReplicatedStorage.Shared.Locale)
local HouseCommon = require(script.Parent.HouseCommon)

local HouseButtons = {}

local WHITE = Color3.new(1, 1, 1)
local C = HouseCommon.Colors
local LIP = 4 -- (px) épaisseur de la "lèvre" sous la face

-- Couleurs des familles d'outils (face) : exposées pour l'éditeur / la fenêtre
HouseButtons.Palette = {
	Lilac = Color3.fromRGB(200, 176, 255),
	Mint = Color3.fromRGB(128, 222, 190),
	Sky = Color3.fromRGB(140, 200, 255),
	Butter = Color3.fromRGB(255, 214, 110),
	Peach = Color3.fromRGB(255, 176, 140),
	Pink = Color3.fromRGB(255, 132, 186),
	Red = Color3.fromRGB(255, 88, 118),
	White = Color3.fromRGB(255, 252, 254),
	Green = Color3.fromRGB(96, 206, 128),
}

local function lipOf(color: Color3): Color3
	return color:Lerp(C.Ink, 0.42)
end

local function outlineOf(color: Color3): Color3
	return color:Lerp(C.Ink, 0.55)
end

-- Texte clair ou foncé selon la face
local function inkFor(color: Color3): Color3
	local luminance = 0.3 * color.R + 0.59 * color.G + 0.11 * color.B
	return luminance > 0.72 and C.Ink or WHITE
end

----------------------------------------------------------------------
-- Bulle d'aide (une seule, déplacée de bouton en bouton)
----------------------------------------------------------------------

local tip: Frame? = nil
local tipLabel: TextLabel? = nil
local tipOwner: GuiObject? = nil

local function ensureTip(): (Frame, TextLabel)
	local frame = tip
	local label = tipLabel
	if frame and label then
		return frame, label
	end
	local newTip = UIUtil.Create("Frame", {
		Name = "HouseTip",
		AnchorPoint = Vector2.new(0.5, 1),
		Size = UDim2.fromOffset(0, 26),
		AutomaticSize = Enum.AutomaticSize.X,
		BackgroundColor3 = C.Ink,
		BackgroundTransparency = 0.04,
		Visible = false,
		ZIndex = 60,
	})
	UIUtil.Corner(newTip, UDim.new(0, 9))
	UIUtil.Stroke(newTip, WHITE, 1.5, 0.35)
	UIUtil.Create("UIPadding", { PaddingLeft = UDim.new(0, 10), PaddingRight = UDim.new(0, 10), Parent = newTip })
	local newLabel = UIUtil.Create("TextLabel", {
		Name = "Label",
		Size = UDim2.fromScale(0, 1),
		AutomaticSize = Enum.AutomaticSize.X,
		BackgroundTransparency = 1,
		Font = Theme.Fonts.Title,
		Text = "",
		TextColor3 = WHITE,
		TextSize = 14,
		ZIndex = 62,
		Parent = newTip,
	})
	-- petite pointe
	local pointer = UIUtil.Create("Frame", {
		Name = "Pointer",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 1, 0),
		Size = UDim2.fromOffset(10, 10),
		Rotation = 45,
		BackgroundColor3 = C.Ink,
		BackgroundTransparency = 0.04,
		BorderSizePixel = 0,
		ZIndex = 61,
		Parent = newTip,
	})
	pointer:SetAttribute("DarkSkinIgnore", true)
	newTip:SetAttribute("DarkSkinIgnore", true)
	tip = newTip
	tipLabel = newLabel
	return newTip, newLabel
end

-- Affiche la bulle au-dessus de `owner` (nil = cache)
function HouseButtons.ShowTip(owner: GuiObject?, text: string?)
	local frame, label = ensureTip()
	if not owner or not text or text == "" then
		tipOwner = nil
		frame.Visible = false
		frame.Parent = nil
		return
	end
	tipOwner = owner
	label.Text = text
	frame.Position = UDim2.new(0.5, 0, 0, -8)
	-- (bulle détruite avec un ancien bouton : on en refait une)
	if not pcall(function()
		frame.Parent = owner
	end) then
		tip, tipLabel = nil, nil
		frame, label = ensureTip()
		label.Text = text
		frame.Position = UDim2.new(0.5, 0, 0, -8)
		frame.Parent = owner
	end
	frame.Visible = true
	UIUtil.Pop(frame, 0.7, 0.2)
end

-- Bulle au survol (souris seulement) ; `getText` peut changer (état du bouton)
function HouseButtons.Tip(button: GuiButton, getText: () -> string)
	button.MouseEnter:Connect(function()
		if not Interface.IsTouch() then
			HouseButtons.ShowTip(button, getText())
		end
	end)
	button.MouseLeave:Connect(function()
		if tipOwner == button then
			HouseButtons.ShowTip(nil)
		end
	end)
	button.Activated:Connect(function()
		if tipOwner == button then
			-- (le texte peut changer après un clic : ex. aimant oui / non)
			task.defer(function()
				if tipOwner == button then
					HouseButtons.ShowTip(button, getText())
				end
			end)
		end
	end)
end

-- Cache la bulle si elle est sur ce bouton (bouton qui disparaît)
function HouseButtons.HideTipOf(owner: GuiObject)
	if tipOwner == owner or (tipOwner and tipOwner:IsDescendantOf(owner)) then
		HouseButtons.ShowTip(nil)
	end
end

----------------------------------------------------------------------
-- Bouton-outil "bonbon"
----------------------------------------------------------------------

export type Candy = {
	Button: TextButton,
	Face: Frame,
	Icon: TextLabel,
	Caption: TextLabel?,
	SetEnabled: (enabled: boolean) -> (),
	IsEnabled: () -> boolean,
	SetColor: (color: Color3) -> (),
	SetIcon: (text: string) -> (),
	SetCaption: (text: string) -> (),
	SetSize: (width: number, height: number) -> (),
}

-- props : Name, Icon, Caption?, Color, TextColor?, Width, Height, Radius?,
-- IconSize?, LayoutOrder?, ZIndex?, Parent?
function HouseButtons.Candy(props: { [string]: any }): Candy
	local color: Color3 = props.Color or HouseButtons.Palette.White
	local z = props.ZIndex or 1
	local radius = props.Radius or 14
	local enabled = true
	local hovering = false

	local button = UIUtil.Create("TextButton", {
		Name = props.Name or "Candy",
		Size = UDim2.fromOffset(props.Width or 48, props.Height or 52),
		BackgroundTransparency = 1,
		AutoButtonColor = false,
		Text = "",
		LayoutOrder = props.LayoutOrder or 0,
		ZIndex = z,
		Parent = props.Parent,
	})
	local lip = UIUtil.Create("Frame", {
		Name = "Lip",
		Position = UDim2.fromOffset(0, LIP),
		Size = UDim2.new(1, 0, 1, -LIP),
		BackgroundColor3 = lipOf(color),
		ZIndex = z,
		Parent = button,
	})
	UIUtil.Corner(lip, radius)
	local lipStroke = UIUtil.Stroke(lip, outlineOf(color), 1.5, 0.25)
	local face = UIUtil.Create("Frame", {
		Name = "Face",
		Size = UDim2.new(1, 0, 1, -LIP),
		BackgroundColor3 = color,
		ZIndex = z + 1,
		Parent = button,
	})
	UIUtil.Corner(face, radius)
	local faceStroke = UIUtil.Stroke(face, outlineOf(color), 1.5, 0.25)
	UIUtil.Gradient(face, ColorSequence.new(WHITE, Color3.fromRGB(226, 226, 232)), 90)
	local gloss = UIUtil.Create("Frame", {
		Name = "Gloss",
		Position = UDim2.new(0, 4, 0, 3),
		Size = UDim2.new(1, -8, 0.4, 0),
		BackgroundColor3 = WHITE,
		BackgroundTransparency = 0.35,
		ZIndex = z + 2,
		Parent = face,
	})
	UIUtil.Corner(gloss, math.max(4, radius - 4))
	UIUtil.Create("UIGradient", {
		Rotation = 90,
		Transparency = NumberSequence.new(0.25, 1),
		Parent = gloss,
	})
	local hasCaption = props.Caption ~= nil and props.Caption ~= ""
	local textColor = props.TextColor or inkFor(color)
	local icon = UIUtil.Create("TextLabel", {
		Name = "Icon",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = hasCaption and UDim2.new(0.5, 0, 0.38, 0) or UDim2.fromScale(0.5, 0.5),
		Size = UDim2.new(1, 0, hasCaption and 0.6 or 1, 0),
		BackgroundTransparency = 1,
		Font = Theme.Fonts.Title,
		Text = props.Icon or "",
		TextColor3 = textColor,
		TextSize = props.IconSize or 22,
		ZIndex = z + 3,
		Parent = face,
	})
	local caption: TextLabel? = nil
	if hasCaption then
		local label = UIUtil.Create("TextLabel", {
			Name = "Caption",
			AnchorPoint = Vector2.new(0.5, 1),
			Position = UDim2.new(0.5, 0, 1, -3),
			Size = UDim2.new(1, -4, 0, 13),
			BackgroundTransparency = 1,
			Font = Theme.Fonts.Title,
			Text = props.Caption,
			TextColor3 = textColor,
			TextSize = 12,
			TextScaled = true,
			ZIndex = z + 3,
			Parent = face,
		})
		UIUtil.Create("UITextSizeConstraint", { MaxTextSize = 12, MinTextSize = 7, Parent = label })
		caption = label
	end

	local function setFace(offset: number, time: number)
		UIUtil.Tween(face, time, { Position = UDim2.fromOffset(0, offset) }, Enum.EasingStyle.Quad)
	end
	button.MouseEnter:Connect(function()
		hovering = true
		if enabled then
			setFace(-1.5, 0.1)
		end
	end)
	button.MouseLeave:Connect(function()
		hovering = false
		setFace(0, 0.12)
	end)
	button.MouseButton1Down:Connect(function()
		setFace(LIP - 1, 0.06)
	end)
	button.MouseButton1Up:Connect(function()
		setFace(hovering and enabled and -1.5 or 0, 0.14)
	end)

	local candy: Candy
	local function paint()
		local shown = enabled and color or color:Lerp(Color3.fromRGB(214, 210, 222), 0.65)
		face.BackgroundColor3 = shown
		lip.BackgroundColor3 = lipOf(shown)
		lipStroke.Color = outlineOf(shown)
		faceStroke.Color = outlineOf(shown)
		gloss.BackgroundTransparency = enabled and 0.35 or 0.6
		local ink = props.TextColor or inkFor(color)
		icon.TextColor3 = ink
		icon.TextTransparency = enabled and 0 or 0.5
		local label = candy and candy.Caption
		if label then
			label.TextColor3 = ink
			label.TextTransparency = enabled and 0 or 0.45
		end
	end
	candy = {
		Button = button,
		Face = face,
		Icon = icon,
		Caption = caption,
		SetEnabled = function(value: boolean)
			if enabled == value then
				return
			end
			enabled = value
			paint()
		end,
		IsEnabled = function(): boolean
			return enabled
		end,
		SetColor = function(value: Color3)
			color = value
			paint()
		end,
		SetIcon = function(text: string)
			if icon.Text ~= text then
				icon.Text = text
			end
		end,
		SetCaption = function(text: string)
			local label = caption
			if label and label.Text ~= text then
				label.Text = text
			end
		end,
		SetSize = function(width: number, height: number)
			button.Size = UDim2.fromOffset(width, height)
		end,
	}
	paint()
	return candy
end

----------------------------------------------------------------------
-- Cadres qui "avalent" les clics
----------------------------------------------------------------------

-- Conteneur visible (pastille, capsule, bandeau...) fait avec un TextButton
-- sans action : sur Roblox une Frame laisse passer le clic vers un bouton
-- placé derrière (la pièce désélectionnerait l'objet, une case de la maison
-- s'ouvrirait...). À utiliser à la place d'une Frame quand le cadre a un
-- UIListLayout / UIPadding (UIUtil.SinkClicks y ajouterait un enfant rangé
-- par la liste). props : mêmes propriétés qu'une Frame.
function HouseButtons.Container(props: { [string]: any }): TextButton
	local finalProps: { [string]: any } = {
		AutoButtonColor = false,
		Text = "",
		Selectable = false,
	}
	for key, value in pairs(props) do
		finalProps[key] = value
	end
	return UIUtil.Create("TextButton", finalProps)
end

-- Bouton invisible sous tout le contenu d'un cadre SANS liste (comme
-- UIUtil.SinkClicks) qui couvre aussi ses marges internes (UIPadding)
function HouseButtons.Sink(frame: GuiObject): TextButton
	local existing = frame:FindFirstChild("ClickSink")
	if existing and existing:IsA("TextButton") then
		return existing
	end
	local padding = frame:FindFirstChildOfClass("UIPadding")
	local padL = padding and padding.PaddingLeft.Offset or 0
	local padR = padding and padding.PaddingRight.Offset or 0
	local padT = padding and padding.PaddingTop.Offset or 0
	local padB = padding and padding.PaddingBottom.Offset or 0
	local sink = UIUtil.Create("TextButton", {
		Name = "ClickSink",
		Position = UDim2.fromOffset(-padL, -padT),
		Size = UDim2.new(1, padL + padR, 1, padT + padB),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		AutoButtonColor = false,
		Text = "",
		Selectable = false,
		ZIndex = 0,
		Parent = frame,
	})
	return sink
end

-- Texte localisé d'une bulle "Nom  (raccourci)"
function HouseButtons.TipText(name: string, shortcut: string?): string
	if shortcut and shortcut ~= "" and not Interface.IsTouch() then
		return Locale.T(name) .. "   " .. shortcut
	end
	return Locale.T(name)
end

return HouseButtons
