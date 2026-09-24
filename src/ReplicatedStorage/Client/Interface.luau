--[[
	Interface (ModuleScript)
	Emplacement : ReplicatedStorage > Client > Interface

	Crée la ScreenGui et la "toile virtuelle" responsive :
	  - toute l'interface est pensée pour un écran de 1280x720 ;
	  - un UIScale agrandit / réduit l'ensemble selon l'écran réel
	    (PC, mobile, tablette) ;
	  - le cadre "Root" s'étire pour toujours couvrir tout l'écran
	    (sa taille en pixels "design" est donc >= 1280x720 dans un sens).

	Calques (du plus bas au plus haut), tous plein écran, transparents et
	non "Active" (les clics passent à travers) :
	  Background < Slots < Main < Overlay < Panels < Toasts < Effects < Cinematic
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Theme = require(script.Parent.Theme)
local UIUtil = require(script.Parent.UIUtil)
local Signal = require(ReplicatedStorage.Shared.Signal)

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

	local old = playerGui:FindFirstChild("DopamineGui")
	if old then
		old:Destroy()
	end

	local screenGui = UIUtil.Create("ScreenGui", {
		Name = "DopamineGui",
		ResetOnSpawn = false,
		IgnoreGuiInset = true,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		Parent = playerGui,
	})

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

	-- Recalcule l'échelle quand la taille de l'écran change
	local function updateScale()
		local camera = workspace.CurrentCamera
		if not camera then
			return
		end
		local viewport = camera.ViewportSize
		if viewport.X < 1 or viewport.Y < 1 then
			return
		end
		local design = Theme.DesignResolution
		local scale = math.clamp(math.min(viewport.X / design.X, viewport.Y / design.Y), Theme.MinScale, Theme.MaxScale)
		local canvas = Vector2.new(viewport.X / scale, viewport.Y / scale)
		Interface.Scale = scale
		Interface.CanvasSize = canvas
		uiScale.Scale = scale
		-- Root fait (écran / échelle) pour couvrir exactement l'écran une fois agrandi
		root.Size = UDim2.fromOffset(canvas.X, canvas.Y)
		Interface.ScaleChanged:Fire(scale, canvas)
	end

	local cameraConnection: RBXScriptConnection? = nil
	local function watchCamera()
		if cameraConnection then
			cameraConnection:Disconnect()
			cameraConnection = nil
		end
		local camera = workspace.CurrentCamera
		if camera then
			cameraConnection = camera:GetPropertyChangedSignal("ViewportSize"):Connect(updateScale)
		end
		updateScale()
	end
	workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(watchCamera)
	watchCamera()

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
