--[[
	Background (ModuleScript)
	Emplacement : ReplicatedStorage > Client > Components > Background

	Fond dégradé animé (violet / rose / bleu nuit) + orbes néon qui flottent.
	Pendant un Dopamine Rush, le fond s'accélère et devient plus vif.
]]

local RunService = game:GetService("RunService")

local Theme = require(script.Parent.Parent.Theme)
local UIUtil = require(script.Parent.Parent.UIUtil)

local Background = {}

local rushActive = false
local random = Random.new()

local ORB_COLORS = { Theme.Colors.Pink, Theme.Colors.Cyan, Theme.Colors.Purple }

local function floatOrb(orb: Frame)
	task.spawn(function()
		while orb.Parent do
			local duration = random:NextNumber(6, 12) / (rushActive and 3 or 1)
			UIUtil.Tween(orb, duration, {
				Position = UDim2.fromScale(random:NextNumber(0, 1), random:NextNumber(0, 1)),
			}, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut)
			task.wait(duration)
		end
	end)
end

function Background.Build(screenGui: ScreenGui)
	local frame = UIUtil.Create("Frame", {
		Name = "Background",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.new(1, 1, 1),
		BorderSizePixel = 0,
		ZIndex = 1,
		Parent = screenGui,
	})
	local gradient = UIUtil.Gradient(frame, nil, 45)

	-- Orbes lumineux flous
	for _ = 1, 12 do
		local size = random:NextInteger(120, 320)
		local orb = UIUtil.Create("Frame", {
			Size = UDim2.fromOffset(size, size),
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(random:NextNumber(0, 1), random:NextNumber(0, 1)),
			BackgroundColor3 = ORB_COLORS[random:NextInteger(1, #ORB_COLORS)],
			BackgroundTransparency = 0.88,
			BorderSizePixel = 0,
			ZIndex = 1,
			Parent = frame,
		})
		UIUtil.Corner(orb, UDim.new(1, 0))
		-- Dégradé radial simulé : bord transparent
		UIUtil.Create("UIGradient", {
			Transparency = NumberSequence.new({
				NumberSequenceKeypoint.new(0, 0),
				NumberSequenceKeypoint.new(1, 1),
			}),
			Rotation = random:NextInteger(0, 360),
			Parent = orb,
		})
		floatOrb(orb)
	end

	-- Animation du dégradé à chaque image
	local time = 0
	RunService.RenderStepped:Connect(function(dt)
		local speed = rushActive and 4 or 1
		time += dt * speed
		gradient.Rotation = (45 + time * 8) % 360
		gradient.Offset = Vector2.new(math.sin(time * 0.3) * 0.25, math.cos(time * 0.2) * 0.25)

		local pulse = (math.sin(time * 0.5) + 1) / 2
		local top = Theme.Colors.BackgroundTop:Lerp(Theme.Colors.Pink, rushActive and 0.35 or pulse * 0.12)
		local mid = Theme.Colors.BackgroundMid:Lerp(Theme.Colors.Purple, pulse * 0.25)
		local bottom = Theme.Colors.BackgroundBottom:Lerp(Theme.Colors.Cyan, rushActive and 0.3 or (1 - pulse) * 0.12)
		gradient.Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, top),
			ColorSequenceKeypoint.new(0.5, mid),
			ColorSequenceKeypoint.new(1, bottom),
		})
	end)

	return frame
end

function Background.SetRush(active: boolean)
	rushActive = active
end

return Background
