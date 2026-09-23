--[[
	PanelManager (ModuleScript)
	Emplacement : ReplicatedStorage > Client > Components > PanelManager

	Fenêtres "pop-up" (quêtes, succès, rebirth...). Une seule ouverte à la
	fois, avec animation d'ouverture et fond assombri (clic dehors = fermer).
	Chaque panneau est un module dans Components > Panels avec :
	  Title, Color, Build(content), Update(data) (optionnel)
]]

local Client = script.Parent.Parent
local Theme = require(Client.Theme)
local UIUtil = require(Client.UIUtil)
local ClientState = require(Client.ClientState)
local SoundManager = require(Client.SoundManager)

local PanelManager = {}

local overlay: Frame
local window: Frame
local windowScale: UIScale
local titleLabel: TextLabel
local windowStroke: UIStroke
local panels = {} -- [nom] = { Module, Content }
local openName: string? = nil

function PanelManager.Build(layer: Frame)
	overlay = UIUtil.Create("Frame", {
		Name = "Overlay",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Visible = false,
		Parent = layer,
	})

	-- Fond sombre plein écran (bouton : un clic dehors ferme la fenêtre)
	local dimmer = UIUtil.Create("TextButton", {
		Name = "Dimmer",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.new(0, 0, 0),
		BackgroundTransparency = 0.45,
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
		Size = UDim2.fromOffset(640, 500),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		BackgroundColor3 = Color3.new(1, 1, 1), -- blanc : le UIGradient donne les vraies couleurs
		Active = true, -- bloque les clics pour qu'ils n'atteignent pas le fond sombre
		ZIndex = 2,
		Parent = overlay,
	})
	UIUtil.Corner(window, 24)
	windowStroke = UIUtil.Stroke(window, Theme.Colors.Cyan, 3)
	UIUtil.Gradient(window, ColorSequence.new(Theme.Colors.PanelLight, Theme.Colors.Panel), 90)
	windowScale = UIUtil.Create("UIScale", { Parent = window })

	titleLabel = UIUtil.Label({
		Font = Theme.Fonts.Title,
		TextColor3 = Theme.Colors.Cyan,
		Size = UDim2.new(1, -120, 0, 40),
		Position = UDim2.fromOffset(24, 16),
		TextXAlignment = Enum.TextXAlignment.Left,
		MaxTextSize = 28,
		Parent = window,
	})

	local closeButton = UIUtil.NeonButton({
		Text = "✕",
		Size = UDim2.fromOffset(48, 48),
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -14, 0, 12),
		Color = Theme.Colors.Red,
		MaxTextSize = 26,
		Parent = window,
	})
	closeButton.Activated:Connect(function()
		PanelManager.Close()
	end)

	ClientState.Changed:Connect(function(data)
		for _, panel in pairs(panels) do
			if panel.Module.Update then
				panel.Module.Update(data)
			end
		end
	end)
end

function PanelManager.Register(name: string, module)
	local content = UIUtil.Create("Frame", {
		Name = name,
		Size = UDim2.new(1, -40, 1, -84),
		Position = UDim2.fromOffset(20, 70),
		BackgroundTransparency = 1,
		Visible = false,
		Parent = window,
	})
	module.Build(content)
	panels[name] = { Module = module, Content = content }
end

function PanelManager.Open(name: string)
	local panel = panels[name]
	if not panel then
		return
	end
	for otherName, other in pairs(panels) do
		other.Content.Visible = otherName == name
	end
	openName = name
	titleLabel.Text = panel.Module.Title
	local color = panel.Module.Color or Theme.Colors.Cyan
	titleLabel.TextColor3 = color
	windowStroke.Color = color

	if panel.Module.Update and ClientState.Data then
		panel.Module.Update(ClientState.Data)
	end
	if panel.Module.OnOpen then
		panel.Module.OnOpen()
	end

	overlay.Visible = true
	windowScale.Scale = 0.6
	UIUtil.Tween(windowScale, 0.35, { Scale = 1 }, Enum.EasingStyle.Back)
	SoundManager.Play("Open", 1)
end

function PanelManager.Close()
	if not openName then
		return
	end
	openName = nil
	UIUtil.Tween(windowScale, 0.15, { Scale = 0.7 }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
	task.delay(0.15, function()
		if not openName then
			overlay.Visible = false
		end
	end)
end

function PanelManager.Toggle(name: string)
	if openName == name then
		PanelManager.Close()
	else
		PanelManager.Open(name)
	end
end

return PanelManager
