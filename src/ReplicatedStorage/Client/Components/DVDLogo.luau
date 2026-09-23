--[[
	DVDLogo (ModuleScript)
	Emplacement : ReplicatedStorage > Client > Components > DVDLogo

	Le logo qui rebondit comme l'écran de veille DVD.
	  - La trajectoire vient du SERVEUR (DVDSetup) et est calculée avec
	    DVDMath à partir de l'heure serveur : mouvement fluide et identique
	    quel que soit l'écran ou le nombre d'images par seconde.
	  - Change de couleur à chaque rebond.
	  - Cliquable (bonus, avec temps de recharge).
	  - Coin touché : le client prévient le serveur, qui VÉRIFIE puis
	    envoie le jackpot.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Client = script.Parent.Parent
local Theme = require(Client.Theme)
local UIUtil = require(Client.UIUtil)
local Effects = require(Client.Effects)
local SoundManager = require(Client.SoundManager)
local Notifications = require(script.Parent.Notifications)

local Config = require(ReplicatedStorage.Shared.Config)
local DVDMath = require(ReplicatedStorage.Shared.DVDMath)
local NumberFormatter = require(ReplicatedStorage.Shared.NumberFormatter)
local Net = require(ReplicatedStorage.Shared.Net)

local DVDLogo = {}

function DVDLogo.Build(layer: Frame)
	local settings = Config.DVD
	local params: DVDMath.Params? = nil
	local lastIndexX: number? = nil
	local lastIndexY: number? = nil
	local colorIndex = 1
	local cooldownUntil = 0

	-- Le logo : ImageButton (ton image) + texte de secours "DOPA / VIDEO"
	local logo = UIUtil.Create("ImageButton", {
		Name = "DVDLogo",
		Size = UDim2.fromOffset(settings.LogoSize.X, settings.LogoSize.Y),
		BackgroundTransparency = 1,
		Image = settings.LogoImage,
		ImageColor3 = settings.Colors[1],
		ScaleType = Enum.ScaleType.Fit,
		AutoButtonColor = false,
		Visible = false,
		Parent = layer,
	})
	UIUtil.Create("UIAspectRatioConstraint", {
		AspectRatio = settings.LogoSize.X / settings.LogoSize.Y,
		Parent = logo,
	})

	local fallbackLabels = {}
	if settings.LogoImage == "" then
		-- Logo "fait maison" si aucune image n'est fournie
		local title = UIUtil.Label({
			Text = "DOPA",
			Font = Theme.Fonts.Number,
			TextColor3 = settings.Colors[1],
			Size = UDim2.fromScale(1, 0.62),
			MaxTextSize = 60,
			Parent = logo,
		})
		local disc = UIUtil.Create("Frame", {
			Size = UDim2.fromScale(0.8, 0.3),
			AnchorPoint = Vector2.new(0.5, 0),
			Position = UDim2.fromScale(0.5, 0.64),
			BackgroundColor3 = settings.Colors[1],
			Parent = logo,
		})
		UIUtil.Corner(disc, UDim.new(1, 0))
		local sub = UIUtil.Label({
			Text = "VIDEO",
			Font = Theme.Fonts.Title,
			TextColor3 = Theme.Colors.TextDark,
			Size = UDim2.fromScale(0.8, 0.8),
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			MaxTextSize = 20,
			Parent = disc,
		})
		fallbackLabels = { Title = title, Disc = disc, Sub = sub }
	end

	local function applyColor(color: Color3)
		logo.ImageColor3 = color
		if fallbackLabels.Title then
			fallbackLabels.Title.TextColor3 = color
			fallbackLabels.Disc.BackgroundColor3 = color
		end
	end

	local function nextColor()
		colorIndex = colorIndex % #settings.Colors + 1
		applyColor(settings.Colors[colorIndex])
	end

	-- Envoie la taille du logo (en fraction de l'écran) au serveur
	local lastSentW, lastSentH = 0, 0
	local function reportSize()
		local parentSize = layer.AbsoluteSize
		if parentSize.X < 1 or parentSize.Y < 1 then
			return
		end
		local w = logo.AbsoluteSize.X / parentSize.X
		local h = logo.AbsoluteSize.Y / parentSize.Y
		if math.abs(w - lastSentW) > 0.002 or math.abs(h - lastSentH) > 0.002 then
			lastSentW, lastSentH = w, h
			Net.Event("DVDResize"):FireServer(w, h)
		end
	end
	layer:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
		task.delay(0.6, reportSize) -- le serveur limite à 2 envois / seconde
	end)

	Net.Event("DVDSetup").OnClientEvent:Connect(function(newParams)
		params = newParams
		lastIndexX, lastIndexY = nil, nil
		logo.Visible = true
		task.defer(reportSize)
	end)

	-- Mouvement : recalculé à chaque image depuis l'heure serveur
	RunService.RenderStepped:Connect(function()
		local current = params
		if not current then
			return
		end
		local t = workspace:GetServerTimeNow()
		local x, y = DVDMath.Position(current, t)
		logo.Position = UDim2.fromScale(x, y)

		local indexX, indexY = DVDMath.BounceIndex(current, t)
		local bouncedX = lastIndexX ~= nil and indexX ~= lastIndexX
		local bouncedY = lastIndexY ~= nil and indexY ~= lastIndexY

		if bouncedX or bouncedY then
			nextColor()
			SoundManager.Play("Bounce", 1.5)
		end

		if bouncedX then
			-- Numéro du bord touché = le plus grand des deux segments
			local k = math.max(indexX, lastIndexX :: number)
			if DVDMath.IsCornerAtBounceX(current, k, settings.CornerTolerance) then
				Net.Event("DVDCorner"):FireServer(k)
			end
		end

		lastIndexX, lastIndexY = indexX, indexY

		-- Le logo est un peu transparent pendant le temps de recharge
		local ready = os.clock() >= cooldownUntil
		logo.ImageTransparency = ready and 0 or 0.6
		if fallbackLabels.Title then
			fallbackLabels.Title.TextTransparency = ready and 0 or 0.6
			fallbackLabels.Disc.BackgroundTransparency = ready and 0 or 0.6
		end
	end)

	-- Clic sur le logo
	logo.Activated:Connect(function()
		if os.clock() < cooldownUntil then
			return
		end
		cooldownUntil = os.clock() + settings.ClickCooldown
		Net.Event("DVDClick"):FireServer()
		-- Centre du logo, en fraction de l'écran
		local position = logo.Position
		local w = logo.AbsoluteSize.X / math.max(1, layer.AbsoluteSize.X)
		local h = logo.AbsoluteSize.Y / math.max(1, layer.AbsoluteSize.Y)
		Effects.Burst(layer, UDim2.fromScale(position.X.Scale + w / 2, position.Y.Scale + h / 2), nil, 12)
	end)

	-- Le serveur confirme le bonus : "+X" au niveau du logo
	Notifications.BonusHandlers.DVD = function(amount: number)
		Effects.FloatingText(logo, UDim2.fromScale(0.5, 0), "+" .. NumberFormatter.Format(amount), Theme.Colors.Yellow, 38)
	end

	return logo
end

return DVDLogo
