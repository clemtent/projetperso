--[[
	PanelManager (ModuleScript)
	Emplacement : ReplicatedStorage > Client > Components > PanelManager

	Fenêtres "pop-up" (boutique, succès, quêtes, classement...). Une seule
	ouverte à la fois, avec fond assombri (clic dehors = fermer) et
	transitions douces (fondu du fond + glissement / zoom de la fenêtre).
	Style clair : fenêtre blanche, contour fin, ombre douce, en-tête avec
	pastille d'icône colorée, titre, sous-titre optionnel et bouton ✕.

	Chaque panneau est un module dans Components > Panels avec :
	  Title, Color, Build(content), Update(data) (optionnel),
	  OnOpen() / OnClose() (optionnels), Size (Vector2, optionnel),
	  Icon (optionnel : sinon le 1er emoji du titre), Subtitle (optionnel).
	v5 : Title / Subtitle sont écrits en ANGLAIS dans les modules et traduits
	ici (Locale.T) à l'ouverture. La fenêtre tient toujours dans 94 % de
	l'écran (ex. téléphone) : un peu réduite (jusqu'à 90 %), puis moins
	haute ; le contenu est alors raccourci (ses listes défilent déjà) ou,
	pour un panneau à mise en page fixe (Module.FixedLayout = true), il
	défile dans la fenêtre. Le mode sombre est appliqué par DarkSkin.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Client = script.Parent.Parent
local Theme = require(Client.Theme)
local UIUtil = require(Client.UIUtil)
local Interface = require(Client.Interface)
local ClientState = require(Client.ClientState)
local SoundManager = require(Client.SoundManager)
local Signal = require(ReplicatedStorage.Shared.Signal)
local Locale = require(ReplicatedStorage.Shared.Locale)

local PanelManager = {}

PanelManager.Opened = Signal.new() -- (name)
PanelManager.Closed = Signal.new() -- (name)

local DEFAULT_SIZE = Vector2.new(640, 500)
local HEADER_HEIGHT = 66
local DIM_TRANSPARENCY = 0.45
local SCREEN_FIT = 0.94 -- la fenêtre occupe au plus 94 % de l'écran
local MIN_FIT_SCALE = 0.9 -- réduction max avant de raccourcir la fenêtre

local overlay: Frame
local dimmer: TextButton
local holder: Frame -- support (taille de la fenêtre) : porte l'ombre et l'animation
local holderScale: UIScale
local window: Frame
local iconBadge: Frame
local iconLabel: TextLabel
local titleLabel: TextLabel
local subtitleLabel: TextLabel
local accentLine: Frame
local panels = {} -- [nom] = { Module, Content, Viewport }
local openName: string? = nil
local closeToken = 0
local fitScale = 1 -- réduction pour tenir dans l'écran (1 = taille normale)
local currentSize = DEFAULT_SIZE

-- Place de la fenêtre dans 94 % de la toile : (échelle, hauteur visible).
-- Trop large : on réduit (UIScale). Trop haute : petite réduction si l'écart
-- est faible, sinon la fenêtre est moins haute et son contenu défile.
local function computeFit(size: Vector2): (number, number)
	local canvas = Interface.CanvasSize
	if canvas.X < 1 or canvas.Y < 1 then
		return 1, size.Y
	end
	local scale = math.min(1, canvas.X * SCREEN_FIT / size.X)
	local ratio = canvas.Y * SCREEN_FIT / (size.Y * scale)
	if ratio >= 1 then
		return scale, size.Y
	end
	scale *= math.max(ratio, MIN_FIT_SCALE)
	return scale, math.min(size.Y, math.floor(canvas.Y * SCREEN_FIT / scale))
end

-- Taille de la fenêtre + zone de défilement du contenu du panneau `name`
local function applyFit(name: string?)
	local visibleHeight
	fitScale, visibleHeight = computeFit(currentSize)
	holder.Size = UDim2.fromOffset(currentSize.X, visibleHeight)
	local panel = name and panels[name]
	if panel then
		local shortened = visibleHeight < currentSize.Y
		-- Mise en page fixe : le contenu garde sa hauteur et défile ;
		-- sinon il est raccourci (ses propres listes défilent)
		local scrolls = shortened and panel.Module.FixedLayout == true
		local contentHeight = (scrolls and currentSize.Y or visibleHeight) - (HEADER_HEIGHT + 22)
		panel.Content.Size = UDim2.new(1, 0, 0, contentHeight)
		local viewport = panel.Viewport :: ScrollingFrame
		viewport.CanvasSize = UDim2.fromOffset(0, contentHeight)
		viewport.ScrollingEnabled = scrolls
		viewport.ScrollBarThickness = scrolls and 6 or 0
		if not scrolls then
			viewport.CanvasPosition = Vector2.zero
		end
	end
end

local function callOnClose(name: string)
	local panel = panels[name]
	if panel and panel.Module.OnClose then
		pcall(panel.Module.OnClose)
	end
end

-- "🏆 Succès" -> ("🏆", "Succès") ; "Classement" -> (nil, "Classement")
local function splitTitle(title: string): (string?, string)
	local first, rest = string.match(title, "^(%S+)%s+(.+)$")
	if first and rest and not string.find(first, "%w") then
		return first, rest
	end
	return nil, title
end

-- Met l'en-tête aux couleurs du panneau
local function applyHeader(module, name: string)
	local icon, text = splitTitle(Locale.T(tostring(module.Title or name)))
	icon = module.Icon or icon
	local color: Color3 = module.Color or Theme.Colors.Blue

	iconBadge.Visible = icon ~= nil
	iconLabel.Text = icon or ""
	iconBadge.BackgroundColor3 = color
	titleLabel.Text = text

	local left = icon and 76 or 26
	local subtitle = module.Subtitle
	if type(subtitle) == "string" and subtitle ~= "" then
		subtitleLabel.Visible = true
		subtitleLabel.Text = Locale.T(subtitle)
		titleLabel.Position = UDim2.fromOffset(left, 12)
		titleLabel.Size = UDim2.new(1, -(left + 70), 0, 28)
		subtitleLabel.Position = UDim2.fromOffset(left, 40)
		subtitleLabel.Size = UDim2.new(1, -(left + 70), 0, 18)
	else
		subtitleLabel.Visible = false
		titleLabel.Position = UDim2.fromOffset(left, 17)
		titleLabel.Size = UDim2.new(1, -(left + 70), 0, 32)
	end

	-- Liseré sous l'en-tête : couleur du panneau qui s'estompe sur les côtés
	accentLine.BackgroundColor3 = color
end

function PanelManager.Build(layer: Frame)
	overlay = UIUtil.Create("Frame", {
		Name = "PanelOverlay",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Visible = false,
		ZIndex = 10,
		Parent = layer,
	})

	-- Fond sombre plein écran (bouton : un clic dehors ferme la fenêtre)
	dimmer = UIUtil.Create("TextButton", {
		Name = "Dimmer",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.fromRGB(10, 10, 20),
		BackgroundTransparency = 1,
		AutoButtonColor = false,
		Text = "",
		ZIndex = 1,
		Parent = overlay,
	})
	dimmer.Activated:Connect(function()
		PanelManager.Close()
	end)

	holder = UIUtil.Create("Frame", {
		Name = "WindowHolder",
		Size = UDim2.fromOffset(DEFAULT_SIZE.X, DEFAULT_SIZE.Y),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		BackgroundTransparency = 1,
		ZIndex = 2,
		Parent = overlay,
	})
	holderScale = UIUtil.Create("UIScale", { Parent = holder })

	window = UIUtil.Create("Frame", {
		Name = "Window",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Theme.Colors.Panel,
		Active = true, -- bloque les clics pour qu'ils n'atteignent pas le fond sombre
		ZIndex = 3,
		Parent = holder,
	})
	UIUtil.Corner(window, Theme.Radius.XL)
	UIUtil.Stroke(window, Theme.Colors.CardBorder, 1.5, 0.1)
	UIUtil.Shadow(window, 10, 0.72, 6)

	-- En-tête : pastille d'icône, titre, sous-titre
	iconBadge = UIUtil.Create("Frame", {
		Name = "IconBadge",
		Size = UDim2.fromOffset(42, 42),
		Position = UDim2.fromOffset(22, 12),
		BackgroundColor3 = Theme.Colors.Blue,
		ZIndex = 4,
		Parent = window,
	})
	UIUtil.Corner(iconBadge, Theme.Radius.M)
	UIUtil.Stroke(iconBadge, Theme.Colors.Border, 1.5, 0.2)
	UIUtil.Gradient(iconBadge, ColorSequence.new(Color3.new(1, 1, 1), Color3.fromRGB(205, 205, 205)), 90)
	iconLabel = UIUtil.Label({
		Size = UDim2.new(1, -8, 1, -8),
		Position = UDim2.fromOffset(4, 4),
		MaxTextSize = 26,
		ZIndex = 5,
		Parent = iconBadge,
	})

	titleLabel = UIUtil.Label({
		Name = "Title",
		Font = Theme.Fonts.Title,
		TextColor3 = Theme.Colors.Text,
		Size = UDim2.new(1, -146, 0, 32),
		Position = UDim2.fromOffset(76, 17),
		TextXAlignment = Enum.TextXAlignment.Left,
		MaxTextSize = Theme.TextSize.Title,
		ZIndex = 4,
		Parent = window,
	})
	subtitleLabel = UIUtil.Label({
		Name = "Subtitle",
		TextColor3 = Theme.Colors.TextDim,
		Size = UDim2.new(1, -146, 0, 18),
		Position = UDim2.fromOffset(76, 40),
		TextXAlignment = Enum.TextXAlignment.Left,
		MaxTextSize = Theme.TextSize.Caption + 1,
		Visible = false,
		ZIndex = 4,
		Parent = window,
	})

	local closeButton = UIUtil.BasicButton({
		Name = "Close",
		Text = "✕",
		Font = Theme.Fonts.Title,
		TextSize = 20,
		Size = UDim2.fromOffset(40, 40),
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -16, 0, 13),
		CornerRadius = 20,
		ZIndex = 4,
		Parent = window,
	})
	closeButton.Activated:Connect(function()
		PanelManager.Close()
	end)
	-- Zone tactile agrandie (bouton invisible autour du ✕) sur téléphone / tablette
	local closeHitbox = UIUtil.Create("TextButton", {
		Name = "CloseHitbox",
		Text = "",
		BackgroundTransparency = 1,
		AutoButtonColor = false,
		Size = UDim2.fromOffset(64, 64),
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -4, 0, 1),
		ZIndex = 3,
		Visible = Interface.IsTouch(),
		Parent = window,
	})
	closeHitbox.Activated:Connect(function()
		PanelManager.Close()
	end)

	-- L'écran change (rotation, fenêtre redimensionnée) : la fenêtre ouverte se réajuste
	Interface.ScaleChanged:Connect(function()
		closeHitbox.Visible = Interface.IsTouch()
		if openName then
			applyFit(openName)
			holderScale.Scale = fitScale
		end
	end)

	-- Séparateur + liseré de couleur
	UIUtil.Create("Frame", {
		Name = "Divider",
		Size = UDim2.new(1, -40, 0, 1),
		Position = UDim2.fromOffset(20, HEADER_HEIGHT),
		BackgroundColor3 = Theme.Colors.Divider,
		BorderSizePixel = 0,
		ZIndex = 4,
		Parent = window,
	})
	accentLine = UIUtil.Create("Frame", {
		Name = "Accent",
		Size = UDim2.new(0, 120, 0, 3),
		Position = UDim2.fromOffset(22, HEADER_HEIGHT - 1),
		BackgroundColor3 = Theme.Colors.Blue,
		BorderSizePixel = 0,
		ZIndex = 5,
		Parent = window,
	})
	UIUtil.Corner(accentLine, 2)
	UIUtil.Create("UIGradient", {
		Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0),
			NumberSequenceKeypoint.new(0.6, 0.2),
			NumberSequenceKeypoint.new(1, 1),
		}),
		Parent = accentLine,
	})

	ClientState.Changed:Connect(function(data)
		for name, panel in pairs(panels) do
			if panel.Module.Update then
				local ok, err = pcall(panel.Module.Update, data)
				if not ok then
					warn("[PanelManager] Erreur dans " .. name .. ".Update : " .. tostring(err))
				end
			end
		end
	end)
end

function PanelManager.Register(name: string, module)
	if type(module) ~= "table" or type(module.Build) ~= "function" then
		warn("[PanelManager] Panneau invalide : " .. tostring(name))
		return
	end
	-- Zone de défilement (utile seulement quand la fenêtre est moins haute
	-- que prévu, ex. téléphone) ; le contenu garde sa taille normale
	local size: Vector2 = module.Size or DEFAULT_SIZE
	local viewport = UIUtil.Create("ScrollingFrame", {
		Name = name .. "Viewport",
		Size = UDim2.new(1, -40, 1, -(HEADER_HEIGHT + 22)),
		Position = UDim2.fromOffset(20, HEADER_HEIGHT + 10),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollingDirection = Enum.ScrollingDirection.Y,
		ScrollingEnabled = false,
		ScrollBarThickness = 0,
		ScrollBarImageColor3 = Theme.Colors.Dark,
		CanvasSize = UDim2.fromOffset(0, size.Y - (HEADER_HEIGHT + 22)),
		ElasticBehavior = Enum.ElasticBehavior.WhenScrollable,
		Visible = false,
		ZIndex = 4,
		Parent = window,
	})
	local content = UIUtil.Create("Frame", {
		Name = name,
		Size = UDim2.new(1, 0, 0, size.Y - (HEADER_HEIGHT + 22)),
		BackgroundTransparency = 1,
		Visible = false,
		ZIndex = 4,
		Parent = viewport,
	})
	local ok, err = pcall(module.Build, content)
	if not ok then
		warn("[PanelManager] Erreur dans " .. name .. ".Build : " .. tostring(err))
	end
	panels[name] = { Module = module, Content = content, Viewport = viewport }
	-- Première mise à jour si l'état est déjà là
	if module.Update and ClientState.Data then
		pcall(module.Update, ClientState.Data)
	end
end

function PanelManager.IsRegistered(name: string): boolean
	return panels[name] ~= nil
end

function PanelManager.IsOpen(name: string?): boolean
	if name then
		return openName == name
	end
	return openName ~= nil
end

function PanelManager.Open(name: string)
	local panel = panels[name]
	if not panel then
		return
	end
	local previous = openName
	local wasVisible = overlay.Visible and previous ~= nil
	for otherName, other in pairs(panels) do
		other.Content.Visible = otherName == name
		other.Viewport.Visible = otherName == name
	end
	openName = name
	closeToken += 1
	applyHeader(panel.Module, name)
	currentSize = panel.Module.Size or DEFAULT_SIZE
	applyFit(name)
	panel.Viewport.CanvasPosition = Vector2.zero

	if panel.Module.Update and ClientState.Data then
		pcall(panel.Module.Update, ClientState.Data)
	end
	if panel.Module.OnOpen then
		pcall(panel.Module.OnOpen)
	end

	overlay.Visible = true
	if wasVisible then
		-- Changement de panneau : petit "pop" seulement
		holderScale.Scale = 0.97 * fitScale
		UIUtil.Tween(holderScale, 0.2, { Scale = fitScale }, Enum.EasingStyle.Back)
	else
		dimmer.BackgroundTransparency = 1
		UIUtil.Tween(dimmer, 0.25, { BackgroundTransparency = DIM_TRANSPARENCY })
		holderScale.Scale = 0.88 * fitScale
		holder.Position = UDim2.new(0.5, 0, 0.5, 26)
		UIUtil.Tween(holderScale, 0.32, { Scale = fitScale }, Enum.EasingStyle.Back)
		UIUtil.Tween(holder, 0.32, { Position = UDim2.fromScale(0.5, 0.5) }, Enum.EasingStyle.Quint)
	end
	SoundManager.Play("Open", 1)
	if previous and previous ~= name then
		callOnClose(previous)
		PanelManager.Closed:Fire(previous)
	end
	PanelManager.Opened:Fire(name)
end

function PanelManager.Close()
	local name = openName
	if not name then
		return
	end
	openName = nil
	callOnClose(name)
	closeToken += 1
	local token = closeToken
	UIUtil.Tween(dimmer, 0.18, { BackgroundTransparency = 1 })
	UIUtil.Tween(holderScale, 0.18, { Scale = 0.9 * fitScale }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
	UIUtil.Tween(holder, 0.18, { Position = UDim2.new(0.5, 0, 0.5, 18) }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
	task.delay(0.19, function()
		-- Rouvert entre-temps : on ne cache rien
		if token == closeToken and not openName then
			overlay.Visible = false
		end
	end)
	PanelManager.Closed:Fire(name)
end

-- Échelle actuelle de la fenêtre (1 = taille normale ; < 1 si réduite pour tenir à l'écran)
function PanelManager.GetFitScale(): number
	return fitScale
end

function PanelManager.Toggle(name: string)
	if openName == name then
		PanelManager.Close()
	else
		PanelManager.Open(name)
	end
end

return PanelManager
