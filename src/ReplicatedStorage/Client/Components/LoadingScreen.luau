--[[
	LoadingScreen (ModuleScript)
	Emplacement : ReplicatedStorage > Client > Components > LoadingScreen

	Écran d'intro affiché pendant le chargement : logo "DOPAMINE CLICKER"
	avec le cerveau 🧠 qui pulse, dégradé doux qui tourne, points animés,
	barre de progression et petites astuces. Il couvre tout l'écran (même
	sous l'encoche) dans sa propre ScreenGui, au-dessus du jeu.
	Il disparaît en fondu au premier état reçu du serveur
	(ClientState.Loaded), ou au bout de 8 secondes au plus tard.

	API : LoadingScreen.Show() puis LoadingScreen.Hide() (appelé tout seul).
	v5 : textes traduits (Locale ; mis à jour si la langue est choisie
	pendant le chargement), toile à la taille de l'écran (téléphone), mode
	sombre (DarkSkin).
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Client = script.Parent.Parent
local Theme = require(Client.Theme)
local UIUtil = require(Client.UIUtil)
local Interface = require(Client.Interface)
local ClientState = require(Client.ClientState)
local DarkSkin = require(Client.DarkSkin)
local Locale = require(ReplicatedStorage.Shared.Locale)

local LoadingScreen = {}

local TIMEOUT = 8 -- secondes max d'affichage
local MIN_TIME = 1.2 -- durée minimale (pour que l'animation se voie)
local FADE_TIME = 0.6

-- Astuces (une liste par langue, même nombre d'éléments)
local TIPS = {
	en = {
		"Tip: every upgrade adds something new to the screen.",
		"Tip: click fast to fill the combo meter 🔥",
		"Tip: the DVD logo hitting a corner is the jackpot 📀",
		"Tip: the ocean 🌊 resets everything… but multiplies your gains.",
		"Tip: change the background in 🎨 Themes.",
		"Preparing your dose of dopamine…",
	},
	fr = {
		"Astuce : chaque amélioration ajoute quelque chose à l'écran.",
		"Astuce : clique vite pour remplir la jauge de combo 🔥",
		"Astuce : le logo DVD qui touche un coin, c'est le jackpot 📀",
		"Astuce : l'océan 🌊 remet tout à zéro… mais multiplie tes gains.",
		"Astuce : change de fond dans 🎨 Thèmes.",
		"Préparation de ta dose de dopamine…",
	},
}

local function getTips(): { string }
	return Locale.Pick(TIPS)
end

local gui: ScreenGui? = nil
local renderConnection: RBXScriptConnection? = nil
local hiding = false
local shownAt = 0
local loaded = false

-- Fondu de tous les éléments visibles d'un cadre
local function fadeOut(root: Instance, duration: number)
	for _, item in ipairs(root:GetDescendants()) do
		if item:IsA("TextLabel") or item:IsA("TextButton") then
			UIUtil.Tween(item, duration, { TextTransparency = 1, BackgroundTransparency = 1 })
		elseif item:IsA("Frame") then
			UIUtil.Tween(item, duration, { BackgroundTransparency = 1 })
		elseif item:IsA("UIStroke") then
			UIUtil.Tween(item, duration, { Transparency = 1 })
		end
	end
end

function LoadingScreen.Show()
	if gui then
		return
	end
	local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")
	local old = playerGui:FindFirstChild("DopamineLoading")
	if old then
		old:Destroy()
	end
	hiding = false
	loaded = false
	shownAt = os.clock()

	local screen = UIUtil.Create("ScreenGui", {
		Name = "DopamineLoading",
		ResetOnSpawn = false,
		IgnoreGuiInset = true,
		DisplayOrder = 50,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		Parent = playerGui,
	}) :: ScreenGui
	gui = screen

	-- Fond : dégradé doux qui tourne lentement (bloque les clics)
	local background = UIUtil.Create("TextButton", {
		Name = "Background",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.new(1, 1, 1),
		AutoButtonColor = false,
		Text = "",
		BorderSizePixel = 0,
		Parent = screen,
	})
	local gradient = UIUtil.Gradient(background, ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 255, 255)),
		ColorSequenceKeypoint.new(0.55, Color3.fromRGB(246, 240, 255)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(255, 232, 244)),
	}), 90)

	-- Toile centrée à la taille de celle du jeu, mise à l'échelle comme lui
	local canvasSize = Interface.CanvasSize
	local canvas = UIUtil.Create("Frame", {
		Name = "Canvas",
		Size = UDim2.fromOffset(canvasSize.X, canvasSize.Y),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		BackgroundTransparency = 1,
		ZIndex = 2,
		Parent = screen,
	})
	local canvasScale = UIUtil.Create("UIScale", { Scale = Interface.Scale, Parent = canvas })
	local scaleConnection = Interface.ScaleChanged:Connect(function(scale: number, size: Vector2)
		canvasScale.Scale = scale
		canvas.Size = UDim2.fromOffset(size.X, size.Y)
	end)
	screen.Destroying:Connect(function()
		scaleConnection:Disconnect()
	end)

	-- Halo coloré derrière le logo
	local halo = UIUtil.Create("Frame", {
		Name = "Halo",
		Size = UDim2.fromOffset(260, 260),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 0.5, -70),
		BackgroundColor3 = Theme.Colors.Pink,
		BackgroundTransparency = 0.88,
		BorderSizePixel = 0,
		ZIndex = 2,
		Parent = canvas,
	})
	UIUtil.Corner(halo, UDim.new(1, 0))
	UIUtil.Gradient(halo, ColorSequence.new(Theme.Colors.Pink, Theme.Colors.Purple), 45)

	-- Cerveau dans une pastille blanche avec ombre
	local brainHolder = UIUtil.Create("Frame", {
		Name = "BrainHolder",
		Size = UDim2.fromOffset(132, 132),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 0.5, -70),
		BackgroundTransparency = 1,
		ZIndex = 3,
		Parent = canvas,
	})
	local brainScale = UIUtil.Create("UIScale", { Scale = 0.4, Parent = brainHolder })
	local brainCircle = UIUtil.Create("Frame", {
		Name = "Circle",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.new(1, 1, 1),
		ZIndex = 4,
		Parent = brainHolder,
	})
	UIUtil.Corner(brainCircle, UDim.new(1, 0))
	UIUtil.Stroke(brainCircle, Theme.Colors.Border, 2)
	UIUtil.Shadow(brainCircle, 6, 0.8, 4)
	local brain = UIUtil.Label({
		Text = "🧠",
		Size = UDim2.new(1, -30, 1, -30),
		Position = UDim2.fromOffset(15, 15),
		MaxTextSize = 84,
		ZIndex = 5,
		Parent = brainCircle,
	})

	-- Logo
	local title = UIUtil.Label({
		Name = "Title",
		Text = "DOPAMINE",
		Font = Theme.Fonts.Title,
		TextColor3 = Theme.Colors.Text,
		Size = UDim2.fromOffset(640, 76),
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0.5, 14),
		MaxTextSize = 72,
		ZIndex = 3,
		Parent = canvas,
	})
	local titleGradient = UIUtil.Gradient(title, ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 62, 138)),
		ColorSequenceKeypoint.new(0.5, Color3.fromRGB(139, 50, 224)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(0, 170, 220)),
	}), 0)
	title.TextColor3 = Color3.new(1, 1, 1) -- couleurs données par le dégradé
	local subtitle = UIUtil.Label({
		Name = "Subtitle",
		Text = "C  L  I  C  K  E  R",
		Font = Theme.Fonts.Title,
		TextColor3 = Theme.Colors.TextDim,
		Size = UDim2.fromOffset(400, 30),
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0.5, 88),
		MaxTextSize = 26,
		ZIndex = 3,
		Parent = canvas,
	})

	-- Barre de progression
	local bar = UIUtil.Create("Frame", {
		Name = "Bar",
		Size = UDim2.fromOffset(300, 10),
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0.5, 142),
		BackgroundColor3 = Color3.fromRGB(232, 228, 240),
		BorderSizePixel = 0,
		ClipsDescendants = true,
		ZIndex = 3,
		Parent = canvas,
	})
	UIUtil.Corner(bar, UDim.new(1, 0))
	local fill = UIUtil.Create("Frame", {
		Name = "Fill",
		Size = UDim2.fromScale(0, 1),
		BackgroundColor3 = Color3.new(1, 1, 1),
		BorderSizePixel = 0,
		ZIndex = 4,
		Parent = bar,
	})
	UIUtil.Corner(fill, UDim.new(1, 0))
	UIUtil.Gradient(fill, ColorSequence.new(Theme.Colors.Pink, Theme.Colors.Purple), 0)

	local status = UIUtil.Label({
		Name = "Status",
		Text = Locale.T("Loading"),
		Font = Theme.Fonts.Title,
		TextColor3 = Theme.Colors.TextDim,
		Size = UDim2.fromOffset(300, 22),
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0.5, 160),
		MaxTextSize = 17,
		ZIndex = 3,
		Parent = canvas,
	})
	local tip = UIUtil.Label({
		Name = "Tip",
		Text = getTips()[1],
		TextColor3 = Theme.Colors.TextDim,
		Size = UDim2.fromOffset(620, 22),
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -40),
		MaxTextSize = 16,
		ZIndex = 3,
		Parent = canvas,
	})

	-- Entrée : le cerveau rebondit, le titre glisse
	UIUtil.Tween(brainScale, 0.7, { Scale = 1 }, Enum.EasingStyle.Elastic)
	title.Position = UDim2.new(0.5, 0, 0.5, 40)
	title.TextTransparency = 1
	UIUtil.Tween(title, 0.6, { Position = UDim2.new(0.5, 0, 0.5, 14), TextTransparency = 0 }, Enum.EasingStyle.Quint)
	subtitle.TextTransparency = 1
	task.delay(0.2, function()
		if subtitle.Parent and not hiding then
			UIUtil.Tween(subtitle, 0.6, { TextTransparency = 0 })
		end
	end)

	-- Animation continue
	local progress = 0
	local elapsed = 0
	local tipClock = 0
	local tipIndex = math.random(1, #getTips())
	tip.Text = getTips()[tipIndex]
	-- Langue choisie pendant le chargement : l'astuce change tout de suite
	Locale.OnChanged(function()
		if tip.Parent and not hiding then
			local tips = getTips()
			tipIndex = math.clamp(tipIndex, 1, #tips)
			tip.Text = tips[tipIndex]
		end
	end)
	DarkSkin.Register(screen)
	renderConnection = RunService.RenderStepped:Connect(function(dt: number)
		elapsed += dt
		gradient.Rotation = 90 + math.sin(elapsed * 0.6) * 25
		titleGradient.Offset = Vector2.new(math.sin(elapsed * 1.2) * 0.25, 0)
		brain.Rotation = math.sin(elapsed * 2.2) * 6
		halo.Size = UDim2.fromOffset(250 + math.sin(elapsed * 2) * 14, 250 + math.sin(elapsed * 2) * 14)

		-- Progression "réaliste" : file vers 90 % puis 100 % une fois chargé
		local target = loaded and 1 or 0.9
		local speed = loaded and 6 or 0.55
		progress += (target - progress) * math.min(1, dt * speed)
		fill.Size = UDim2.fromScale(progress, 1)

		if not hiding then
			local dots = string.rep(".", math.floor(elapsed * 3) % 4)
			status.Text = (loaded and Locale.T("Let's go") or Locale.T("Loading")) .. dots
		end

		tipClock += dt
		if tipClock > 2.6 and not hiding then
			tipClock = 0
			local tips = getTips()
			tipIndex = tipIndex % #tips + 1
			tip.Text = tips[tipIndex]
		end
	end)

	-- Fermeture : premier état reçu ou délai dépassé
	if ClientState.IsLoaded then
		task.delay(MIN_TIME, LoadingScreen.Hide)
	else
		local connection
		connection = ClientState.Loaded:Connect(function()
			connection:Disconnect()
			local remaining = math.max(0, MIN_TIME - (os.clock() - shownAt))
			task.delay(remaining, LoadingScreen.Hide)
		end)
	end
	task.delay(TIMEOUT, LoadingScreen.Hide)
end

function LoadingScreen.Hide()
	local screen = gui
	if not screen or hiding then
		return
	end
	hiding = true
	loaded = true
	-- On laisse la barre se remplir un instant, puis fondu général
	task.delay(0.35, function()
		if not screen.Parent then
			return
		end
		local canvas = screen:FindFirstChild("Canvas")
		local canvasScale = canvas and canvas:FindFirstChildOfClass("UIScale")
		if canvasScale then
			UIUtil.Tween(canvasScale, FADE_TIME, { Scale = canvasScale.Scale * 1.06 }, Enum.EasingStyle.Quad)
		end
		fadeOut(screen, FADE_TIME)
		local background = screen:FindFirstChild("Background")
		if background and background:IsA("GuiObject") then
			UIUtil.Tween(background, FADE_TIME, { BackgroundTransparency = 1 })
			if background:IsA("GuiButton") then
				background.Active = false
			end
		end
		task.delay(FADE_TIME + 0.05, function()
			if renderConnection then
				renderConnection:Disconnect()
				renderConnection = nil
			end
			screen:Destroy()
			if gui == screen then
				gui = nil
			end
		end)
	end)
end

-- Vrai tant que l'écran de chargement est affiché
function LoadingScreen.IsVisible(): boolean
	return gui ~= nil and not hiding
end

return LoadingScreen
