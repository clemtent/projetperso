--[[
	KeyboardPanel (ModuleScript)
	Emplacement : ReplicatedStorage > Client > Stimuli > Gear > KeyboardPanel

	v9.1 : GRAND clavier flottant. Quand le clavier posé à l'écran est trop
	petit pour viser ses touches (téléphone, écran chargé), un appui dessus
	ouvre ce grand clavier en bas de l'écran (comme le clavier d'un
	téléphone) : vraies touches QWERTY bien grosses (≈ 40 px sur PC, 46 px
	en tactile), le même dessin que le clavier posé (niveau compris),
	un titre, une astuce et un gros bouton ✕.
	  - calque Overlay (au-dessus des cartes, sous les fenêtres et toasts) ;
	  - UIUtil.SinkClicks : un appui entre deux touches ne traverse pas ;
	  - un appui EN DEHORS du clavier le ferme (comme les autres fenêtres),
	    sans bloquer le reste de l'écran (pas de voile) ;
	  - fermé aussi quand une fenêtre s'ouvre / l'écran change ;
	  - un seul grand clavier ouvert à la fois (clavier mécanique OU corail) ;
	  - construit au premier affichage puis réutilisé (reconstruit seulement
	    si le niveau ou l'écran a changé).

	API : KeyboardPanel.new(ctx, options) -> panel
	  options = { Id, Title: () -> string, Tray: Color3?,
	              Build: (parent, step) -> (keys, largeur, hauteur),
	              OnKey: (key) -> () }
	  panel:Open(), panel:Close(), panel:IsOpen(), panel:MarkDirty(),
	  panel:FindKey(code), panel:KeyPoint(key) -> Vector2 (toile), panel:Destroy()
	  KeyboardPanel.CloseAll()
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Locale = require(ReplicatedStorage.Shared.Locale)
local KeyboardArt = require(script.Parent.KeyboardArt)

local KeyboardPanel = {}
KeyboardPanel.__index = KeyboardPanel

export type Options = {
	Id: string,
	Title: () -> string,
	Tray: Color3?,
	Build: (parent: Frame, step: number) -> ({ KeyboardArt.Key }, number, number),
	OnKey: (key: KeyboardArt.Key) -> (),
}

local PANEL_Z = 2000
local openPanel: any = nil

function KeyboardPanel.CloseAll()
	local panel = openPanel
	if panel then
		panel:Close()
	end
end

function KeyboardPanel.new(ctx: any, options: Options)
	local self = setmetatable({
		Ctx = ctx,
		Options = options,
		Frame = nil :: Frame?,
		Art = nil :: Frame?,
		Keys = {} :: { KeyboardArt.Key },
		Dirty = true,
		Opened = false,
		OpenedAt = 0,
		InsideAt = -1,
		Title = nil :: TextLabel?,
		Hint = nil :: TextLabel?,
		Scale = nil :: UIScale?,
		Token = 0,
		Alive = true,
	}, KeyboardPanel)

	-- Appui en dehors : on ferme (vérifié un peu après, quand les boutons du
	-- panneau ont eu le temps de signaler un appui "dedans")
	ctx.Connect(UserInputService.InputBegan, function(input: InputObject)
		if not self.Opened then
			return
		end
		local kind = input.UserInputType
		if kind ~= Enum.UserInputType.MouseButton1 and kind ~= Enum.UserInputType.Touch then
			return
		end
		local stamp = os.clock()
		if math.abs(stamp - self.OpenedAt) < 0.15 then
			return -- (l'appui qui vient d'ouvrir le panneau)
		end
		task.delay(0.1, function()
			if self.Opened and math.abs(self.InsideAt - stamp) > 0.08 and math.abs(stamp - self.OpenedAt) >= 0.15 then
				self:Close()
			end
		end)
	end)
	ctx.OnVisibilityChanged(function(visibility: string)
		if visibility ~= "Visible" then
			self:Close()
		end
	end)
	ctx.Connect(ctx.Interface.ScaleChanged, function()
		self.Dirty = true
		self:Close()
	end)
	return self
end

function KeyboardPanel.MarkInside(self: any)
	self.InsideAt = os.clock()
end

local function isPress(input: InputObject): boolean
	local kind = input.UserInputType
	return kind == Enum.UserInputType.MouseButton1 or kind == Enum.UserInputType.Touch
end

-- (Re)construit le panneau à la taille de l'écran
function KeyboardPanel._build(self: any)
	local ctx = self.Ctx
	local Theme = ctx.Theme
	local UIUtil = ctx.UIUtil
	if self.Frame then
		self.Frame:Destroy()
	end
	table.clear(self.Keys)
	local interface = ctx.Interface
	local canvas: Vector2 = interface.CanvasSize or Vector2.new(1280, 720)
	local scale = math.max(0.05, interface.Scale or 1)
	local touch = interface.Device ~= "Desktop"
	local unitsW, rows = KeyboardArt.LayoutUnits("Full")
	-- Pas d'une touche (touche + écart) : ≈ 40 px réels sur PC, 46 en tactile
	local header = touch and 50 or 42
	local pad = 10
	local step = (touch and 50 or 44) / scale
	-- ... sans dépasser l'écran (largeur, et ~64 % de la hauteur)
	step = math.min(step, (canvas.X - 24 - pad * 2) / (unitsW + 0.9), (canvas.Y * 0.64 - header - pad * 2) / (rows + 1.3))
	step = math.max(step, 18)

	local frame = Instance.new("Frame")
	frame.Name = "GearKeyboardPanel_" .. self.Options.Id
	frame.AnchorPoint = Vector2.new(0.5, 1)
	frame.Position = UDim2.new(0.5, 0, 1, -8)
	frame.BackgroundColor3 = self.Options.Tray or Color3.fromRGB(34, 28, 52)
	frame.BackgroundTransparency = 0.06
	frame.BorderSizePixel = 0
	frame.ZIndex = PANEL_Z
	frame.Visible = false
	frame.Active = true
	UIUtil.Corner(frame, 18)
	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.fromRGB(255, 255, 255)
	stroke.Transparency = 0.55
	stroke.Thickness = 2
	stroke.Parent = frame
	local uiScale = Instance.new("UIScale")
	uiScale.Parent = frame
	self.Scale = uiScale

	-- Un appui entre deux touches ne traverse pas le panneau
	local sink = UIUtil.SinkClicks(frame)
	sink.InputBegan:Connect(function(input: InputObject)
		if isPress(input) then
			self:MarkInside()
		end
	end)

	-- Dessin du clavier (même style que le clavier posé)
	local art = Instance.new("Frame")
	art.Name = "Art"
	art.BackgroundTransparency = 1
	art.ZIndex = 2
	local keys, artW, artH = self.Options.Build(art, step)
	art.Size = UDim2.fromOffset(artW, artH)
	art.Position = UDim2.fromOffset(pad, pad + header)
	art.Parent = frame
	self.Art = art
	self.Keys = keys
	for _, key in ipairs(keys) do
		key.Button.InputBegan:Connect(function(input: InputObject)
			if isPress(input) then
				self:MarkInside()
				self.Options.OnKey(key)
			end
		end)
	end
	local width, height = artW + pad * 2, artH + pad * 2 + header
	frame.Size = UDim2.fromOffset(width, height)

	-- Titre (niveau compris)
	local title = Instance.new("TextLabel")
	title.Name = "Title"
	title.BackgroundTransparency = 1
	title.Position = UDim2.fromOffset(pad + 6, pad)
	title.Size = UDim2.fromOffset(width * 0.5, header - 6)
	title.Font = Theme.Fonts.Title
	title.TextSize = touch and 24 or 21
	title.TextColor3 = Color3.fromRGB(255, 255, 255)
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.TextTruncate = Enum.TextTruncate.AtEnd
	title.Text = self.Options.Title()
	title.ZIndex = 3
	title.Parent = frame
	self.Title = title

	-- Astuce (à droite du titre, avant le ✕)
	local closeSize = header - 6
	local hint = Instance.new("TextLabel")
	hint.Name = "Hint"
	hint.BackgroundTransparency = 1
	hint.AnchorPoint = Vector2.new(1, 0)
	hint.Position = UDim2.new(1, -(pad + closeSize + 12), 0, pad)
	hint.Size = UDim2.fromOffset(width * 0.5 - closeSize - 30, header - 6)
	hint.Font = Theme.Fonts.Body
	hint.TextSize = touch and 19 or 17
	hint.TextColor3 = Color3.fromRGB(214, 206, 255)
	hint.TextXAlignment = Enum.TextXAlignment.Right
	hint.TextTruncate = Enum.TextTruncate.AtEnd
	hint.Text = touch and Locale.T("Tap the keys!") or Locale.T("Type on your keyboard too!")
	hint.ZIndex = 3
	hint.Parent = frame
	self.Hint = hint

	-- Gros bouton ✕
	local close = Instance.new("TextButton")
	close.Name = "KeyboardClose"
	close.AnchorPoint = Vector2.new(1, 0)
	close.Position = UDim2.new(1, -pad, 0, pad - 2)
	close.Size = UDim2.fromOffset(closeSize, closeSize)
	close.BackgroundColor3 = Color3.fromRGB(255, 86, 110)
	close.AutoButtonColor = true
	close.Selectable = false
	close.Font = Theme.Fonts.Title
	close.Text = "✕"
	close.TextSize = math.floor(closeSize * 0.55)
	close.TextColor3 = Color3.new(1, 1, 1)
	close.ZIndex = 4
	UIUtil.Corner(close, math.floor(closeSize / 2))
	local closeStroke = Instance.new("UIStroke")
	closeStroke.Color = Color3.new(1, 1, 1)
	closeStroke.Thickness = 2
	closeStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	closeStroke.Parent = close
	close.InputBegan:Connect(function(input: InputObject)
		if isPress(input) then
			self:MarkInside()
		end
	end)
	close.Activated:Connect(function()
		self:Close()
	end)
	close.Parent = frame

	frame.Parent = ctx.Overlay or ctx.Container
	self.Frame = frame
	self.Dirty = false
end

function KeyboardPanel.IsOpen(self: any): boolean
	return self.Opened == true
end

function KeyboardPanel.MarkDirty(self: any)
	self.Dirty = true
	if self.Opened then
		-- Niveau changé pendant qu'il est ouvert : on redessine sur place
		self:_build()
		local frame = self.Frame
		if frame then
			frame.Visible = true
		end
	end
end

function KeyboardPanel.Open(self: any)
	if not self.Alive or self.Opened then
		return
	end
	if openPanel and openPanel ~= self then
		openPanel:Close()
	end
	if self.Dirty or not self.Frame or not self.Frame.Parent then
		self:_build()
	end
	local frame = self.Frame :: Frame
	local title = self.Title
	if title then
		title.Text = self.Options.Title()
	end
	self.Opened = true
	self.OpenedAt = os.clock()
	openPanel = self
	self.Token += 1
	frame.Visible = true
	local uiScale = self.Scale
	if uiScale then
		uiScale.Scale = 0.86
		self.Ctx.UIUtil.Tween(uiScale, 0.28, { Scale = 1 }, Enum.EasingStyle.Back)
	end
	frame.Position = UDim2.new(0.5, 0, 1, 30)
	self.Ctx.UIUtil.Tween(frame, 0.25, { Position = UDim2.new(0.5, 0, 1, -8) }, Enum.EasingStyle.Quad)
end

function KeyboardPanel.Close(self: any)
	if not self.Opened then
		return
	end
	self.Opened = false
	if openPanel == self then
		openPanel = nil
	end
	self.Token += 1
	local token = self.Token
	local frame = self.Frame
	if frame and frame.Parent then
		self.Ctx.UIUtil.Tween(frame, 0.18, { Position = UDim2.new(0.5, 0, 1, 40) }, Enum.EasingStyle.Quad)
		task.delay(0.18, function()
			if self.Token == token and not self.Opened and frame.Parent then
				frame.Visible = false
			end
		end)
	end
end

function KeyboardPanel.FindKey(self: any, code: string): KeyboardArt.Key?
	return KeyboardArt.Find(self.Keys, code)
end

-- Haut d'une touche, en pixels "design" de la toile
function KeyboardPanel.KeyPoint(self: any, key: KeyboardArt.Key): Vector2?
	local ctx = self.Ctx
	local root = ctx.Interface.Root
	local scale = math.max(0.01, ctx.Interface.Scale or 1)
	local button = key.Button
	if not root or not button.Parent then
		return nil
	end
	local position = (button.AbsolutePosition - root.AbsolutePosition) / scale
	local size = button.AbsoluteSize / scale
	return Vector2.new(position.X + size.X / 2, position.Y)
end

function KeyboardPanel.Destroy(self: any)
	self.Alive = false
	self:Close()
	if self.Frame then
		self.Frame:Destroy()
		self.Frame = nil
	end
end

return KeyboardPanel
