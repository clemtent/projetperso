--[[
	Clicker (ModuleScript)
	Emplacement : ReplicatedStorage > Client > Components > Clicker

	Le GROS bouton "CLIQUE-MOI" + la barre de combo.
	À chaque clic : squish/rebond, texte "+X" flottant, particules, son dont
	la hauteur monte avec le combo. Le gain réel est calculé par le serveur.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Client = script.Parent.Parent
local Theme = require(Client.Theme)
local UIUtil = require(Client.UIUtil)
local ClientState = require(Client.ClientState)
local Effects = require(Client.Effects)
local SoundManager = require(Client.SoundManager)
local HUD = require(script.Parent.HUD)
local NumberFormatter = require(ReplicatedStorage.Shared.NumberFormatter)

local Clicker = {}

local random = Random.new()

function Clicker.Build(parent: Frame)
	-- Conteneur carré (UIAspectRatioConstraint = toujours un cercle parfait)
	local container = UIUtil.Create("Frame", {
		Name = "Clicker",
		Size = UDim2.fromOffset(300, 300),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, -125, 0.5, 30),
		BackgroundTransparency = 1,
		Parent = parent,
	})
	UIUtil.Create("UIAspectRatioConstraint", { AspectRatio = 1, Parent = container })

	-- Halo qui pulse derrière le bouton
	local halo = UIUtil.Create("Frame", {
		Size = UDim2.fromScale(1.35, 1.35),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		BackgroundColor3 = Theme.Colors.Pink,
		BackgroundTransparency = 0.75,
		ZIndex = 1,
		Parent = container,
	})
	UIUtil.Corner(halo, UDim.new(1, 0))
	UIUtil.Create("UIGradient", {
		Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.2),
			NumberSequenceKeypoint.new(1, 1),
		}),
		Rotation = 90,
		Parent = halo,
	})
	local haloScale = UIUtil.Create("UIScale", { Parent = halo })

	-- Anneau néon qui tourne
	local ring = UIUtil.Create("Frame", {
		Size = UDim2.fromScale(1.12, 1.12),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		BackgroundTransparency = 1,
		ZIndex = 2,
		Parent = container,
	})
	UIUtil.Corner(ring, UDim.new(1, 0))
	local ringStroke = UIUtil.Stroke(ring, Color3.new(1, 1, 1), 5)
	local ringGradient = UIUtil.Gradient(ringStroke)

	-- Le bouton lui-même
	local button = UIUtil.Create("TextButton", {
		Name = "ClickButton",
		Size = UDim2.fromScale(1, 1),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		BackgroundColor3 = Color3.new(1, 1, 1),
		AutoButtonColor = false,
		Text = "",
		ZIndex = 3,
		Parent = container,
	})
	UIUtil.Corner(button, UDim.new(1, 0))
	local buttonGradient = UIUtil.Gradient(button, nil, 45)
	UIUtil.Stroke(button, Color3.new(1, 1, 1), 4, 0.2)

	UIUtil.Label({
		Text = "🧠",
		Size = UDim2.fromScale(0.5, 0.36),
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromScale(0.5, 0.14),
		ZIndex = 4,
		MaxTextSize = 100,
		Parent = button,
	})
	local title = UIUtil.Label({
		Text = "CLIQUE-MOI",
		Font = Theme.Fonts.Title,
		Size = UDim2.fromScale(0.8, 0.16),
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromScale(0.5, 0.56),
		ZIndex = 4,
		MaxTextSize = 34,
		Parent = button,
	})
	UIUtil.Stroke(title, Theme.Colors.TextDark, 2).ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual

	-- Barre de combo
	local comboBar = UIUtil.Create("Frame", {
		Name = "ComboBar",
		Size = UDim2.fromOffset(320, 30),
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, -125, 0.5, 215),
		BackgroundColor3 = Theme.Colors.Panel,
		BackgroundTransparency = 0.2,
		ClipsDescendants = true,
		Parent = parent,
	})
	UIUtil.Corner(comboBar, 15)
	UIUtil.Stroke(comboBar, Theme.Colors.Cyan, 2, 0.3)
	local comboFill = UIUtil.Create("Frame", {
		Size = UDim2.fromScale(0, 1),
		BackgroundColor3 = Color3.new(1, 1, 1),
		Parent = comboBar,
	})
	UIUtil.Corner(comboFill, 15)
	UIUtil.Gradient(comboFill, ColorSequence.new(Theme.Colors.Cyan, Theme.Colors.Pink), 0)
	local comboLabel = UIUtil.Label({
		Text = "COMBO x1",
		Font = Theme.Fonts.Title,
		Size = UDim2.new(1, -10, 1, -6),
		Position = UDim2.fromOffset(5, 3),
		ZIndex = 2,
		MaxTextSize = 18,
		Parent = comboBar,
	})
	UIUtil.Stroke(comboLabel, Theme.Colors.TextDark, 1.5).ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual

	-- Animation continue : rotation, halo, barre de combo
	local wasMax = false
	RunService.RenderStepped:Connect(function()
		local t = os.clock()
		local meter = ClientState.GetComboMeter()
		local ratio = meter / 100

		ringGradient.Rotation = (t * 90) % 360
		buttonGradient.Rotation = (45 + t * 20) % 360
		haloScale.Scale = 1 + math.sin(t * (3 + ratio * 8)) * (0.03 + ratio * 0.06)
		halo.BackgroundTransparency = 0.75 - ratio * 0.35

		comboFill.Size = UDim2.fromScale(ratio, 1)
		comboLabel.Text = "COMBO " .. NumberFormatter.Multiplier(ClientState.GetComboMultiplier())

		local isMax = meter >= 99.5
		if isMax and not wasMax then
			Effects.FloatingText(container, UDim2.fromScale(0.5, -0.05), "COMBO MAX !", Theme.Colors.Yellow, 44)
			Effects.Burst(container, UDim2.fromScale(0.5, 0.5), Theme.Colors.Yellow, 20)
		end
		wasMax = isMax
		comboBar.Rotation = isMax and math.sin(t * 30) * 1.5 or 0
	end)

	-- Gestion du clic (souris ET tactile, multi-touch compris)
	local function onClick()
		local gain = ClientState.Click()
		if not gain then
			return
		end

		-- Squish : on écrase le bouton puis il rebondit
		button.Size = UDim2.fromScale(1.12, 0.86)
		UIUtil.Tween(button, 0.45, { Size = UDim2.fromScale(1, 1) }, Enum.EasingStyle.Elastic)

		-- Couleur du texte selon le combo
		local ratio = ClientState.GetComboMeter() / 100
		local color = Theme.Colors.Text:Lerp(Theme.Colors.Yellow, math.min(1, ratio * 2))
		if ratio > 0.75 then
			color = Theme.Colors.Pink
		end

		local position = UDim2.fromScale(0.5 + random:NextNumber(-0.3, 0.3), 0.3 + random:NextNumber(-0.15, 0.1))
		Effects.FloatingText(container, position, "+" .. NumberFormatter.Format(gain), color, 34 + ratio * 14)
		Effects.Burst(container, UDim2.fromScale(random:NextNumber(0.3, 0.7), random:NextNumber(0.3, 0.7)), nil, 5)

		-- Le son monte dans les aigus avec le combo : effet "dopamine" garanti
		SoundManager.Play("Click", 0.9 + ratio * 0.6 + random:NextNumber(0, 0.08))
		HUD.Pop()
	end

	button.InputBegan:Connect(function(input: InputObject)
		local inputType = input.UserInputType
		if inputType == Enum.UserInputType.MouseButton1 or inputType == Enum.UserInputType.Touch then
			onClick()
		end
	end)

	-- Petit rappel au joueur tant qu'il n'a jamais cliqué
	task.spawn(function()
		while button.Parent do
			local data = ClientState.Data
			if data and data.Stats.TotalClicks == 0 then
				UIUtil.Tween(container, 0.3, { Rotation = 6 }, Enum.EasingStyle.Sine)
				task.wait(0.3)
				UIUtil.Tween(container, 0.3, { Rotation = -6 }, Enum.EasingStyle.Sine)
				task.wait(0.3)
				UIUtil.Tween(container, 0.3, { Rotation = 0 }, Enum.EasingStyle.Sine)
			end
			task.wait(2)
		end
	end)

	return container
end

return Clicker
