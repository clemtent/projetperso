--[[
	Interface (ModuleScript)
	Emplacement : ReplicatedStorage > Client > Interface

	Crée la ScreenGui et la "toile virtuelle" responsive :
	  - toute l'interface est pensée pour un écran de 1280x720 ;
	  - un UIScale agrandit / réduit l'ensemble selon l'écran réel
	    (PC, mobile, tablette) ;
	  - le cadre "Root" s'étire pour toujours couvrir toute la zone sûre
	    (hors encoche et barre Roblox ; sa taille en pixels "design" est
	    donc >= 1280x720 dans un sens) ;
	  - une ScreenGui de fond séparée remplit tout l'écran (couleur seule).

	Calques (du plus bas au plus haut), tous plein écran, transparents et
	non "Active" (les clics passent à travers) :
	  Background < Slots < Main < Overlay < Panels < Toasts < Effects < Cinematic
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Theme = require(script.Parent.Theme)
local UIUtil = require(script.Parent.UIUtil)
local Signal = require(ReplicatedStorage.Shared.Signal)
local ClientState = require(script.Parent.ClientState)

local Interface = {}

Interface.ScreenGui = nil :: ScreenGui?
Interface.Root = nil :: Frame?
Interface.Layers = {} :: { [string]: Frame }
Interface.Scale = 1
Interface.CanvasSize = Theme.DesignResolution -- taille de la toile en pixels "design"
Interface.ScaleChanged = Signal.new() -- (scale, canvasSize)

Interface.LayerOrder = { "Background", "Slots", "Main", "Overlay", "Panels", "Toasts", "Effects", "Cinematic" }

function Interface.Build(): ScreenGui
	local player = Players.LocalPlayer
	local playerGui = player:WaitForChild("PlayerGui") :: PlayerGui
	-- Le jeu se joue en paysage sur mobile
	playerGui.ScreenOrientation = Enum.ScreenOrientation.LandscapeSensor

	for _, name in ipairs({ "DopamineGui", "DopamineBackdrop" }) do
		local old = playerGui:FindFirstChild(name)
		if old then
			old:Destroy()
		end
	end

	-- Fond plein écran (sous l'encoche / la barre Roblox) : simple couleur,
	-- pour ne jamais voir le monde 3D autour de la zone sûre
	local backdropGui = UIUtil.Create("ScreenGui", {
		Name = "DopamineBackdrop",
		ResetOnSpawn = false,
		IgnoreGuiInset = true,
		DisplayOrder = 0,
		Parent = playerGui,
	})
	local backdrop = UIUtil.Create("Frame", {
		Name = "Backdrop",
		BackgroundColor3 = Color3.new(1, 1, 1),
		BorderSizePixel = 0,
		Active = false,
		Size = UDim2.fromScale(1, 1),
		Parent = backdropGui,
	})
	local backdropGradient = UIUtil.Gradient(backdrop, ColorSequence.new(Theme.Colors.Background, Theme.Colors.BackgroundBottom), 90)
	local function applyBackdrop(dark: boolean)
		backdrop.BackgroundColor3 = dark and Theme.DarkColors.Background or Color3.new(1, 1, 1)
		backdropGradient.Enabled = not dark
	end
	ClientState.DarkModeChanged:Connect(applyBackdrop)
	applyBackdrop(ClientState.DarkMode)

	-- L'interface du jeu reste dans la zone sûre : ni sous l'encoche des
	-- téléphones, ni sous les boutons Roblox de la barre du haut
	local screenGui = UIUtil.Create("ScreenGui", {
		Name = "DopamineGui",
		ResetOnSpawn = false,
		ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets,
		DisplayOrder = 1,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		Parent = playerGui,
	}) :: ScreenGui

	-- Toile virtuelle mise à l'échelle
	local root = UIUtil.Create("Frame", {
		Name = "Root",
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(Theme.DesignResolution.X, Theme.DesignResolution.Y),
		ZIndex = 2,
		Parent = screenGui,
	})
	local uiScale = UIUtil.Create("UIScale", { Parent = root })

	for index, name in ipairs(Interface.LayerOrder) do
		Interface.Layers[name] = UIUtil.Create("Frame", {
			Name = name,
			BackgroundTransparency = 1,
			Active = false,
			Size = UDim2.fromScale(1, 1),
			ZIndex = index,
			Parent = root,
		})
	end

	-- Recalcule l'échelle quand la zone sûre (taille de la ScreenGui) change
	local function updateScale()
		local available = screenGui.AbsoluteSize
		if available.X < 1 or available.Y < 1 then
			return
		end
		local design = Theme.DesignResolution
		local scale = math.clamp(math.min(available.X / design.X, available.Y / design.Y), Theme.MinScale, Theme.MaxScale)
		local canvas = Vector2.new(available.X / scale, available.Y / scale)
		Interface.Scale = scale
		Interface.CanvasSize = canvas
		uiScale.Scale = scale
		-- Root fait (zone sûre / échelle) pour la couvrir exactement une fois agrandi
		root.Size = UDim2.fromOffset(canvas.X, canvas.Y)
		Interface.ScaleChanged:Fire(scale, canvas)
	end

	screenGui:GetPropertyChangedSignal("AbsoluteSize"):Connect(updateScale)
	updateScale()

	Interface.ScreenGui = screenGui
	Interface.Root = root
	return screenGui
end

-- Convertit une position écran (pixels réels, ex. AbsolutePosition) en
-- position sur la toile (pixels "design").
function Interface.ScreenToCanvas(point: Vector2): Vector2
	local root = Interface.Root
	if not root then
		return point
	end
	return (point - root.AbsolutePosition) / Interface.Scale
end

-- Centre d'un élément, en coordonnées de la toile (pour placer des effets
-- dans un calque plein écran, ex. Effects.Burst(layer, UDim2.fromOffset(...)))
function Interface.GetCanvasCenter(guiObject: GuiObject): Vector2
	return Interface.ScreenToCanvas(guiObject.AbsolutePosition + guiObject.AbsoluteSize / 2)
end

-- Même chose, mais sous forme de UDim2 prête à l'emploi
function Interface.CanvasPosition(guiObject: GuiObject, offset: Vector2?): UDim2
	local center = Interface.GetCanvasCenter(guiObject) + (offset or Vector2.zero)
	return UDim2.fromOffset(center.X, center.Y)
end

return Interface
