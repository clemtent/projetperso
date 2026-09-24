--[[
	Background (ModuleScript)
	Emplacement : ReplicatedStorage > Client > Components > Background

	Fond "basique" : dégradé vertical blanc -> gris clair, comme au tout
	début d'un jeu qui ne paie pas de mine.
	- Mode sombre (néon) : le fond passe au noir (le stimulus NeonMode
	  dessine son propre fond animé par-dessus, dans le calque Background).
	- Dopamine Rush : une lueur jaune pulse doucement en bas de l'écran.
]]

local RunService = game:GetService("RunService")

local Client = script.Parent.Parent
local Theme = require(Client.Theme)
local UIUtil = require(Client.UIUtil)
local ClientState = require(Client.ClientState)

local Background = {}

local frame: Frame? = nil
local glow: Frame? = nil
local rushActive = false

local LIGHT = ColorSequence.new(Theme.Colors.Background, Theme.Colors.BackgroundBottom)

local function applyDarkMode(dark: boolean)
	local target = frame
	if not target then
		return
	end
	-- Le fond clair s'estompe au profit d'un fond presque noir
	UIUtil.Tween(target, 0.6, {
		BackgroundColor3 = dark and Theme.DarkColors.Background or Color3.new(1, 1, 1),
	})
	local gradient = target:FindFirstChild("Gradient") :: UIGradient?
	if gradient then
		gradient.Enabled = not dark
	end
end

-- `parent` = calque Background de l'Interface (ou la ScreenGui en secours)
function Background.Build(parent: Instance)
	local bg = UIUtil.Create("Frame", {
		Name = "LightBackground",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.new(1, 1, 1), -- blanc : le dégradé donne les couleurs
		BorderSizePixel = 0,
		ZIndex = 0, -- sous les fonds des stimuli (ZIndex >= 1)
		Parent = parent,
	})
	local gradient = UIUtil.Gradient(bg, LIGHT, 90)
	gradient.Name = "Gradient"
	frame = bg

	-- Lueur du Rush (invisible par défaut)
	local rushGlow = UIUtil.Create("Frame", {
		Name = "RushGlow",
		Size = UDim2.new(1, 0, 0.45, 0),
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.fromScale(0, 1),
		BackgroundColor3 = Theme.Colors.Yellow,
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ZIndex = 1,
		Parent = bg,
	})
	UIUtil.Create("UIGradient", {
		Rotation = 90,
		Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 1),
			NumberSequenceKeypoint.new(1, 0.3),
		}),
		Parent = rushGlow,
	})
	glow = rushGlow

	RunService.Heartbeat:Connect(function()
		local g = glow
		if not g then
			return
		end
		if rushActive then
			g.BackgroundTransparency = 0.55 + math.sin(os.clock() * 3) * 0.2
		elseif g.BackgroundTransparency < 1 then
			g.BackgroundTransparency = math.min(1, g.BackgroundTransparency + 0.02)
		end
	end)

	ClientState.DarkModeChanged:Connect(applyDarkMode)
	applyDarkMode(ClientState.DarkMode)
	return bg
end

function Background.SetRush(active: boolean)
	rushActive = active
end

return Background
