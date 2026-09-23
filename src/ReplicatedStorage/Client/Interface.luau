--[[
	Interface (ModuleScript)
	Emplacement : ReplicatedStorage > Client > Interface

	Crée la ScreenGui et la "toile virtuelle" responsive :
	  - toute l'interface est pensée pour un écran de 1280x720 ;
	  - un UIScale agrandit / réduit l'ensemble selon l'écran réel
	    (PC, mobile, tablette) ;
	  - le cadre "Root" s'étire pour toujours couvrir tout l'écran.

	Calques (du plus bas au plus haut) :
	  Main (HUD, bouton, boutique, menu) < DVD < Golden < Panels < Toasts < Effects
]]

local Players = game:GetService("Players")

local Theme = require(script.Parent.Theme)
local UIUtil = require(script.Parent.UIUtil)

local Interface = {}

Interface.ScreenGui = nil :: ScreenGui?
Interface.Root = nil :: Frame?
Interface.Layers = {} :: { [string]: Frame }
Interface.Scale = 1

local LAYER_ORDER = { "Main", "DVD", "Golden", "Panels", "Toasts", "Effects" }

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
		Size = UDim2.fromScale(1, 1),
		ZIndex = 2,
		Parent = screenGui,
	})
	local uiScale = UIUtil.Create("UIScale", { Parent = root })

	for index, name in ipairs(LAYER_ORDER) do
		Interface.Layers[name] = UIUtil.Create("Frame", {
			Name = name,
			BackgroundTransparency = 1,
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
		Interface.Scale = scale
		uiScale.Scale = scale
		-- Root fait (écran / échelle) pour couvrir exactement l'écran une fois agrandi
		root.Size = UDim2.fromOffset(viewport.X / scale, viewport.Y / scale)
	end

	local function watchCamera()
		local camera = workspace.CurrentCamera
		if camera then
			camera:GetPropertyChangedSignal("ViewportSize"):Connect(updateScale)
		end
		updateScale()
	end
	workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(watchCamera)
	watchCamera()

	Interface.ScreenGui = screenGui
	Interface.Root = root
	return screenGui
end

return Interface
