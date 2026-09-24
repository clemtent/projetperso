--[[
	PanelManager (ModuleScript)
	Emplacement : ReplicatedStorage > Client > Components > PanelManager

	Fenêtres "pop-up" (boutique, succès, quêtes, classement...). Une seule
	ouverte à la fois, avec animation d'ouverture et fond assombri (clic
	dehors = fermer). Style clair : fenêtre blanche, contour noir fin.
	Chaque panneau est un module dans Components > Panels avec :
	  Title, Color, Build(content), Update(data) (optionnel),
	  OnOpen() (optionnel), Size (Vector2, optionnel : taille de la fenêtre)
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Client = script.Parent.Parent
local Theme = require(Client.Theme)
local UIUtil = require(Client.UIUtil)
local ClientState = require(Client.ClientState)
local SoundManager = require(Client.SoundManager)
local Signal = require(ReplicatedStorage.Shared.Signal)

local PanelManager = {}

PanelManager.Opened = Signal.new() -- (name)
PanelManager.Closed = Signal.new() -- (name)

local DEFAULT_SIZE = Vector2.new(640, 500)

local overlay: Frame
local window: Frame
local windowScale: UIScale
local titleLabel: TextLabel
local titleBar: Frame
local panels = {} -- [nom] = { Module, Content }
local openName: string? = nil

local function callOnClose(name: string)
	local panel = panels[name]
	if panel and panel.Module.OnClose then
		pcall(panel.Module.OnClose)
	end
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
	local dimmer = UIUtil.Create("TextButton", {
		Name = "Dimmer",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.new(0, 0, 0),
		BackgroundTransparency = 0.5,
		AutoButtonColor = false,
		Text = "",
		ZIndex = 1,
		Parent = overlay,
	})
	dimmer.Activated:Connect(function()
		PanelManager.Close()
	end)

	window = UIUtil.Create("Frame", {
		Name = "Window",
		Size = UDim2.fromOffset(DEFAULT_SIZE.X, DEFAULT_SIZE.Y),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		BackgroundColor3 = Theme.Colors.Panel,
		Active = true, -- bloque les clics pour qu'ils n'atteignent pas le fond sombre
		ZIndex = 2,
		Parent = overlay,
	})
	UIUtil.Corner(window, 20)
	UIUtil.Stroke(window, Theme.Colors.CardBorder, 2)
	windowScale = UIUtil.Create("UIScale", { Parent = window })

	-- Bandeau de titre (petite barre de couleur à gauche du titre)
	titleBar = UIUtil.Create("Frame", {
		Name = "TitleAccent",
		Size = UDim2.fromOffset(8, 30),
		Position = UDim2.fromOffset(22, 21),
		BackgroundColor3 = Theme.Colors.Blue,
		BorderSizePixel = 0,
		Parent = window,
	})
	UIUtil.Corner(titleBar, 4)

	titleLabel = UIUtil.Label({
		Font = Theme.Fonts.Title,
		TextColor3 = Theme.Colors.Text,
		Size = UDim2.new(1, -130, 0, 36),
		Position = UDim2.fromOffset(40, 18),
		TextXAlignment = Enum.TextXAlignment.Left,
		MaxTextSize = 28,
		Parent = window,
	})

	local closeButton = UIUtil.BasicButton({
		Name = "Close",
		Text = "✕",
		Font = Theme.Fonts.Title,
		TextSize = 22,
		Size = UDim2.fromOffset(44, 44),
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -14, 0, 14),
		CornerRadius = 22,
		Parent = window,
	})
	closeButton.Activated:Connect(function()
		PanelManager.Close()
	end)

	-- Séparateur
	UIUtil.Create("Frame", {
		Size = UDim2.new(1, -40, 0, 1),
		Position = UDim2.fromOffset(20, 64),
		BackgroundColor3 = Theme.Colors.Disabled,
		BorderSizePixel = 0,
		Parent = window,
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
	local content = UIUtil.Create("Frame", {
		Name = name,
		Size = UDim2.new(1, -40, 1, -88),
		Position = UDim2.fromOffset(20, 74),
		BackgroundTransparency = 1,
		Visible = false,
		Parent = window,
	})
	local ok, err = pcall(module.Build, content)
	if not ok then
		warn("[PanelManager] Erreur dans " .. name .. ".Build : " .. tostring(err))
	end
	panels[name] = { Module = module, Content = content }
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
	for otherName, other in pairs(panels) do
		other.Content.Visible = otherName == name
	end
	openName = name
	titleLabel.Text = panel.Module.Title or name
	titleBar.BackgroundColor3 = panel.Module.Color or Theme.Colors.Blue
	local size = panel.Module.Size or DEFAULT_SIZE
	window.Size = UDim2.fromOffset(size.X, size.Y)

	if panel.Module.Update and ClientState.Data then
		pcall(panel.Module.Update, ClientState.Data)
	end
	if panel.Module.OnOpen then
		pcall(panel.Module.OnOpen)
	end

	overlay.Visible = true
	windowScale.Scale = 0.6
	UIUtil.Tween(windowScale, 0.35, { Scale = 1 }, Enum.EasingStyle.Back)
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
	UIUtil.Tween(windowScale, 0.15, { Scale = 0.7 }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
	task.delay(0.15, function()
		if not openName then
			overlay.Visible = false
		end
	end)
	PanelManager.Closed:Fire(name)
end

function PanelManager.Toggle(name: string)
	if openName == name then
		PanelManager.Close()
	else
		PanelManager.Open(name)
	end
end

return PanelManager
