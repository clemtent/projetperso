--[[
	Effects (ModuleScript)
	Emplacement : ReplicatedStorage > Client > Effects

	Effets visuels 2D : textes flottants "+X", particules, confettis,
	flash d'écran, gros messages. (Les ParticleEmitter ne fonctionnent pas
	dans les interfaces, on anime donc de petits Frames.)
]]

local Debris = game:GetService("Debris")

local Theme = require(script.Parent.Theme)
local UIUtil = require(script.Parent.UIUtil)

local Effects = {}

local layer: Frame? = nil -- calque plein écran pour les effets
local enabled = true -- paramètre "Effets" (particules / confettis)
local random = Random.new()
local activeParticles = 0
local MAX_PARTICLES = 160 -- limite pour les petits appareils

local CONFETTI_COLORS = {
	Theme.Colors.Pink,
	Theme.Colors.Cyan,
	Theme.Colors.Purple,
	Theme.Colors.Yellow,
	Theme.Colors.Green,
	Theme.Colors.Orange,
}

function Effects.Init(effectsLayer: Frame)
	layer = effectsLayer
end

function Effects.SetEnabled(value: boolean)
	enabled = value
end

-- Texte "+X" qui monte et disparaît
function Effects.FloatingText(parent: GuiObject, position: UDim2, text: string, color: Color3?, size: number?)
	local height = size or 34
	local label = UIUtil.Label({
		Text = text,
		Font = Theme.Fonts.Number,
		TextColor3 = color or Theme.Colors.Text,
		Size = UDim2.fromOffset(height * 6, height),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = position,
		Rotation = random:NextNumber(-12, 12),
		ZIndex = 50,
		MaxTextSize = height,
		Parent = parent,
	})
	UIUtil.Stroke(label, Theme.Colors.TextDark, 2).ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual

	local scale = UIUtil.Create("UIScale", { Scale = 0.4, Parent = label })
	UIUtil.Tween(scale, 0.18, { Scale = 1.15 }, Enum.EasingStyle.Back)
	UIUtil.Tween(label, 0.9, {
		Position = position + UDim2.fromOffset(random:NextNumber(-30, 30), -110),
		TextTransparency = 1,
	}, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
	local stroke = label:FindFirstChildOfClass("UIStroke")
	if stroke then
		UIUtil.Tween(stroke, 0.9, { Transparency = 1 }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
	end
	Debris:AddItem(label, 1)
end

-- Explosion de petites particules rondes autour d'un point
function Effects.Burst(parent: GuiObject, position: UDim2, color: Color3?, count: number?)
	if not enabled then
		return
	end
	for _ = 1, count or 8 do
		if activeParticles >= MAX_PARTICLES then
			return
		end
		activeParticles += 1
		local size = random:NextInteger(6, 14)
		local particle = UIUtil.Create("Frame", {
			Size = UDim2.fromOffset(size, size),
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = position,
			BackgroundColor3 = color or CONFETTI_COLORS[random:NextInteger(1, #CONFETTI_COLORS)],
			BorderSizePixel = 0,
			ZIndex = 40,
			Parent = parent,
		})
		UIUtil.Corner(particle, UDim.new(1, 0))

		local angle = random:NextNumber(0, math.pi * 2)
		local distance = random:NextNumber(60, 160)
		local duration = random:NextNumber(0.4, 0.7)
		UIUtil.Tween(particle, duration, {
			Position = position + UDim2.fromOffset(math.cos(angle) * distance, math.sin(angle) * distance),
			BackgroundTransparency = 1,
			Size = UDim2.fromOffset(2, 2),
		}, Enum.EasingStyle.Quart)
		task.delay(duration, function()
			activeParticles -= 1
			particle:Destroy()
		end)
	end
end

-- Pluie de confettis sur tout l'écran
function Effects.Confetti(count: number?)
	local target = layer
	if not enabled or not target then
		return
	end
	for _ = 1, count or 80 do
		if activeParticles >= MAX_PARTICLES then
			return
		end
		activeParticles += 1
		local piece = UIUtil.Create("Frame", {
			Size = UDim2.fromOffset(random:NextInteger(8, 16), random:NextInteger(14, 24)),
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.new(random:NextNumber(0, 1), 0, 0, random:NextInteger(-200, -20)),
			Rotation = random:NextNumber(0, 360),
			BackgroundColor3 = CONFETTI_COLORS[random:NextInteger(1, #CONFETTI_COLORS)],
			BorderSizePixel = 0,
			ZIndex = 90,
			Parent = target,
		})
		local duration = random:NextNumber(1.6, 3)
		local start = piece.Position
		UIUtil.Tween(piece, duration, {
			Position = UDim2.new(start.X.Scale + random:NextNumber(-0.15, 0.15), 0, 1.1, 0),
			Rotation = piece.Rotation + random:NextNumber(-720, 720),
		}, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		task.delay(duration, function()
			activeParticles -= 1
			piece:Destroy()
		end)
	end
end

-- Flash coloré de tout l'écran
function Effects.Flash(color: Color3?, strength: number?)
	local target = layer
	if not target then
		return
	end
	local flash = UIUtil.Create("Frame", {
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = color or Color3.new(1, 1, 1),
		BackgroundTransparency = 1 - (strength or 0.6),
		BorderSizePixel = 0,
		ZIndex = 95,
		Parent = target,
	})
	UIUtil.Tween(flash, 0.6, { BackgroundTransparency = 1 })
	Debris:AddItem(flash, 0.7)
end

-- Gros message au centre de l'écran (jackpot, rebirth...)
function Effects.BigMessage(text: string, color: Color3?, duration: number?)
	local target = layer
	if not target then
		return
	end
	local label = UIUtil.Label({
		Text = text,
		Font = Theme.Fonts.Title,
		TextColor3 = color or Theme.Colors.Yellow,
		Size = UDim2.new(0.9, 0, 0, 110),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.42),
		ZIndex = 100,
		MaxTextSize = 90,
		Parent = target,
	})
	local stroke = UIUtil.Stroke(label, Theme.Colors.Pink, 4)
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual

	local scale = UIUtil.Create("UIScale", { Scale = 0.1, Parent = label })
	UIUtil.Tween(scale, 0.5, { Scale = 1 }, Enum.EasingStyle.Elastic)

	-- Petit clignotement de couleur
	task.spawn(function()
		local colors = { Theme.Colors.Yellow, Theme.Colors.Cyan, Theme.Colors.Pink, Theme.Colors.Green }
		local index = 0
		local finish = os.clock() + (duration or 2.5)
		while label.Parent and os.clock() < finish do
			index = index % #colors + 1
			label.TextColor3 = colors[index]
			task.wait(0.12)
		end
		UIUtil.Tween(label, 0.4, { TextTransparency = 1 })
		UIUtil.Tween(stroke, 0.4, { Transparency = 1 })
		task.wait(0.4)
		label:Destroy()
	end)
end

return Effects
