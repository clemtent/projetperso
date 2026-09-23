--[[
	HUD (ModuleScript)
	Emplacement : ReplicatedStorage > Client > Components > HUD

	Compteurs en haut de l'écran : Dopamine (lissée à chaque image),
	Dopamine par clic, par seconde, multiplicateur total, bannière du Rush.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Client = script.Parent.Parent
local Theme = require(Client.Theme)
local UIUtil = require(Client.UIUtil)
local ClientState = require(Client.ClientState)
local NumberFormatter = require(ReplicatedStorage.Shared.NumberFormatter)

local HUD = {}

local counterScale: UIScale
local rushBanner: Frame
local rushLabel: TextLabel

function HUD.Build(parent: Frame)
	local frame = UIUtil.Create("Frame", {
		Name = "HUD",
		Size = UDim2.fromOffset(520, 130),
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, -125, 0, 10),
		BackgroundColor3 = Theme.Colors.Panel,
		BackgroundTransparency = 0.25,
		Parent = parent,
	})
	UIUtil.Corner(frame, 20)
	local stroke = UIUtil.Stroke(frame, Color3.new(1, 1, 1), 3)
	UIUtil.Gradient(stroke, nil, 0)

	UIUtil.Label({
		Text = "🧠 DOPAMINE",
		Font = Theme.Fonts.Title,
		TextColor3 = Theme.Colors.Cyan,
		Size = UDim2.new(1, 0, 0, 22),
		Position = UDim2.fromOffset(0, 8),
		MaxTextSize = 20,
		Parent = frame,
	})

	local counter = UIUtil.Label({
		Name = "Counter",
		Text = "0",
		Font = Theme.Fonts.Number,
		Size = UDim2.new(1, -20, 0, 58),
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 30),
		MaxTextSize = 58,
		Parent = frame,
	})
	UIUtil.Gradient(counter, ColorSequence.new(Theme.Colors.Text, Theme.Colors.Yellow), 90)
	counterScale = UIUtil.Create("UIScale", { Parent = counter })

	-- Ligne de statistiques
	local statsRow = UIUtil.Create("Frame", {
		Size = UDim2.new(1, -24, 0, 28),
		Position = UDim2.new(0, 12, 0, 94),
		BackgroundTransparency = 1,
		Parent = frame,
	})
	UIUtil.Create("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		VerticalAlignment = Enum.VerticalAlignment.Center,
		Padding = UDim.new(0, 10),
		Parent = statsRow,
	})

	local function chip(order: number, width: number, color: Color3): TextLabel
		local label = UIUtil.Label({
			Size = UDim2.fromOffset(width, 28),
			BackgroundTransparency = 0.2,
			BackgroundColor3 = Theme.Colors.PanelLight,
			TextColor3 = color,
			LayoutOrder = order,
			MaxTextSize = 18,
			Parent = statsRow,
		})
		UIUtil.Corner(label, 14)
		UIUtil.Stroke(label, color, 1.5, 0.3)
		return label
	end

	local perClick = chip(1, 180, Theme.Colors.Pink)
	local perSecond = chip(2, 180, Theme.Colors.Cyan)
	local multiplier = chip(3, 110, Theme.Colors.Yellow)

	-- Bannière Dopamine Rush (cachée par défaut)
	rushBanner = UIUtil.Create("Frame", {
		Name = "RushBanner",
		Size = UDim2.fromOffset(440, 44),
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, -125, 0, 150),
		BackgroundColor3 = Color3.new(1, 1, 1), -- couleurs données par le UIGradient
		Visible = false,
		Parent = parent,
	})
	UIUtil.Corner(rushBanner, 22)
	UIUtil.Stroke(rushBanner, Theme.Colors.Pink, 3)
	UIUtil.Gradient(rushBanner, ColorSequence.new(Theme.Colors.Yellow, Theme.Colors.Orange), 0)
	rushLabel = UIUtil.Label({
		Font = Theme.Fonts.Title,
		TextColor3 = Theme.Colors.TextDark,
		Size = UDim2.new(1, -20, 1, -8),
		Position = UDim2.fromOffset(10, 4),
		MaxTextSize = 22,
		Parent = rushBanner,
	})

	-- Mise à jour des statistiques quand le serveur envoie un nouvel état
	ClientState.Changed:Connect(function(data)
		perClick.Text = "👆 +" .. NumberFormatter.Format(data.ClickValue) .. " / clic"
		perSecond.Text = "⏱️ +" .. NumberFormatter.Format(data.PerSecond) .. " / s"
		multiplier.Text = "🔥 " .. NumberFormatter.Multiplier(data.GlobalMultiplier)
	end)

	-- Compteur lissé + compte à rebours du Rush, à chaque image
	RunService.RenderStepped:Connect(function(dt)
		counter.Text = NumberFormatter.Format(ClientState.UpdateDisplay(dt))

		local rush = ClientState.Rush
		local remaining = rush.EndsAt - workspace:GetServerTimeNow()
		local active = rush.Active and remaining > 0
		rushBanner.Visible = active
		if active then
			rushLabel.Text = string.format("⚡ %s x%s — %ds", rush.Name, tostring(rush.Multiplier), math.ceil(remaining))
			rushBanner.Rotation = math.sin(os.clock() * 8) * 2
		end
	end)
end

-- Petit "pop" du compteur (appelé à chaque clic)
function HUD.Pop()
	counterScale.Scale = 1.12
	UIUtil.Tween(counterScale, 0.2, { Scale = 1 }, Enum.EasingStyle.Back)
end

return HUD
