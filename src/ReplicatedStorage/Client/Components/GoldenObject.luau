--[[
	GoldenObject (ModuleScript)
	Emplacement : ReplicatedStorage > Client > Components > GoldenObject

	Objet doré qui apparaît au hasard (décidé par le serveur), tourne,
	brille... et disparaît vite. Le cliquer donne un gros bonus (validé
	par le serveur grâce à un identifiant unique).
]]

local Debris = game:GetService("Debris")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Client = script.Parent.Parent
local Theme = require(Client.Theme)
local UIUtil = require(Client.UIUtil)
local Effects = require(Client.Effects)
local SoundManager = require(Client.SoundManager)
local Notifications = require(script.Parent.Notifications)

local Config = require(ReplicatedStorage.Shared.Config)
local NumberFormatter = require(ReplicatedStorage.Shared.NumberFormatter)
local Net = require(ReplicatedStorage.Shared.Net)

local GoldenObject = {}

local lastPosition = UDim2.fromScale(0.5, 0.5)

local function spawnGolden(layer: Frame, info)
	local settings = Config.Events.Golden
	local position = UDim2.fromScale(info.X, info.Y)
	lastPosition = position

	local button = UIUtil.Create("ImageButton", {
		Name = "Golden",
		Size = UDim2.fromOffset(110, 110),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = position,
		BackgroundColor3 = Color3.new(1, 1, 1), -- couleurs données par le UIGradient
		BackgroundTransparency = settings.Image == "" and 0 or 1,
		Image = settings.Image,
		AutoButtonColor = false,
		Parent = layer,
	})
	UIUtil.Create("UIAspectRatioConstraint", { AspectRatio = 1, Parent = button })
	if settings.Image == "" then
		UIUtil.Corner(button, UDim.new(1, 0))
		UIUtil.Stroke(button, Theme.Colors.Yellow, 4)
		UIUtil.Gradient(button, ColorSequence.new(Theme.Colors.Yellow, Theme.Colors.Orange), 45)
		UIUtil.Label({
			Text = "🌟",
			Size = UDim2.fromScale(0.7, 0.7),
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			MaxTextSize = 70,
			Parent = button,
		})
	end

	-- Apparition
	local scale = UIUtil.Create("UIScale", { Scale = 0, Parent = button })
	UIUtil.Tween(scale, 0.4, { Scale = 1 }, Enum.EasingStyle.Back)
	SoundManager.Play("Golden", 1.4)

	-- Rotation + pulsation tant qu'il est là
	local spawnTime = os.clock()
	local connection = RunService.RenderStepped:Connect(function()
		local t = os.clock()
		button.Rotation = math.sin(t * 3) * 15
		-- On attend la fin de l'animation d'apparition avant de pulser
		if t - spawnTime > 0.4 then
			scale.Scale = 1 + math.sin(t * 10) * 0.08
		end
	end)

	local clicked = false
	button.Activated:Connect(function()
		if clicked then
			return
		end
		clicked = true
		connection:Disconnect()
		Net.Event("GoldenClick"):FireServer(info.Id)
		Effects.Burst(layer, position, Theme.Colors.Gold, 24)
		Effects.Flash(Theme.Colors.Gold, 0.35)
		UIUtil.Tween(scale, 0.25, { Scale = 1.6 })
		UIUtil.Tween(button, 0.25, { BackgroundTransparency = 1, ImageTransparency = 1 })
		Debris:AddItem(button, 0.3)
	end)

	-- Disparition automatique
	task.delay(info.Lifetime, function()
		if not clicked and button.Parent then
			clicked = true
			connection:Disconnect()
			UIUtil.Tween(scale, 0.3, { Scale = 0 }, Enum.EasingStyle.Back, Enum.EasingDirection.In)
			Debris:AddItem(button, 0.35)
		end
	end)
end

function GoldenObject.Build(layer: Frame)
	Net.Event("GoldenSpawn").OnClientEvent:Connect(function(info)
		spawnGolden(layer, info)
	end)

	-- Le serveur confirme : "+X" à l'endroit où était l'objet
	Notifications.BonusHandlers.Golden = function(amount: number)
		Effects.FloatingText(layer, lastPosition, "+" .. NumberFormatter.Format(amount), Theme.Colors.Gold, 48)
	end
end

return GoldenObject
