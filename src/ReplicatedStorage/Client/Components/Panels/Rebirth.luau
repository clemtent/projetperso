--[[
	Rebirth (ModuleScript) — panneau de prestige
	Emplacement : ReplicatedStorage > Client > Components > Panels > Rebirth

	Remet la Dopamine et les améliorations à zéro contre un multiplicateur
	permanent. Double confirmation pour éviter les erreurs.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Client = script.Parent.Parent.Parent
local Theme = require(Client.Theme)
local UIUtil = require(Client.UIUtil)
local ClientState = require(Client.ClientState)
local Effects = require(Client.Effects)
local SoundManager = require(Client.SoundManager)
local Notifications = require(script.Parent.Parent.Notifications)
local NumberFormatter = require(ReplicatedStorage.Shared.NumberFormatter)
local Net = require(ReplicatedStorage.Shared.Net)

local Rebirth = {
	Title = "♻️ REBIRTH",
	Color = Theme.Colors.Pink,
}

local countLabel: TextLabel
local multLabel: TextLabel
local costLabel: TextLabel
local fill: Frame
local button: TextButton
local confirmUntil = 0

function Rebirth.Build(content: Frame)
	UIUtil.Label({
		Text = "Recommence de zéro (Dopamine + améliorations) et gagne un MULTIPLICATEUR PERMANENT sur tous tes gains. Les succès et statistiques sont conservés.",
		TextColor3 = Theme.Colors.TextDim,
		Size = UDim2.new(1, 0, 0, 60),
		MaxTextSize = 17,
		Parent = content,
	})

	countLabel = UIUtil.Label({
		Font = Theme.Fonts.Title,
		Size = UDim2.new(1, 0, 0, 34),
		Position = UDim2.fromOffset(0, 70),
		MaxTextSize = 24,
		Parent = content,
	})
	multLabel = UIUtil.Label({
		Font = Theme.Fonts.Number,
		TextColor3 = Theme.Colors.Yellow,
		Size = UDim2.new(1, 0, 0, 50),
		Position = UDim2.fromOffset(0, 110),
		MaxTextSize = 40,
		Parent = content,
	})
	costLabel = UIUtil.Label({
		Size = UDim2.new(1, 0, 0, 26),
		Position = UDim2.fromOffset(0, 170),
		MaxTextSize = 18,
		Parent = content,
	})

	local bar = UIUtil.Create("Frame", {
		Size = UDim2.new(0.8, 0, 0, 24),
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 204),
		BackgroundColor3 = Theme.Colors.Card,
		ClipsDescendants = true,
		Parent = content,
	})
	UIUtil.Corner(bar, 12)
	UIUtil.Stroke(bar, Theme.Colors.Pink, 2, 0.3)
	fill = UIUtil.Create("Frame", {
		Size = UDim2.fromScale(0, 1),
		BackgroundColor3 = Color3.new(1, 1, 1),
		Parent = bar,
	})
	UIUtil.Corner(fill, 12)
	UIUtil.Gradient(fill, ColorSequence.new(Theme.Colors.Purple, Theme.Colors.Pink), 0)

	button = UIUtil.NeonButton({
		Text = "♻️ REBIRTH",
		Font = Theme.Fonts.Title,
		Size = UDim2.fromOffset(300, 70),
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 250),
		Color = Theme.Colors.Pink,
		MaxTextSize = 28,
		Parent = content,
	})

	button.Activated:Connect(function()
		if not button:GetAttribute("Enabled") then
			SoundManager.Play("Error", 0.7)
			UIUtil.Shake(button)
			return
		end
		-- Premier clic : demande de confirmation
		if os.clock() > confirmUntil then
			confirmUntil = os.clock() + 3
			button.Text = "⚠️ CONFIRMER ?"
			task.delay(3, function()
				if os.clock() >= confirmUntil then
					button.Text = "♻️ REBIRTH"
				end
			end)
			return
		end
		confirmUntil = 0
		button.Text = "♻️ REBIRTH"

		local ok, success, message = pcall(function()
			return Net.Function("Rebirth"):InvokeServer()
		end)
		if ok and success then
			SoundManager.Play("Rebirth", 1)
			Effects.Flash(Theme.Colors.Pink, 0.8)
			Effects.Confetti(120)
			Effects.BigMessage("♻️ REBIRTH !", Theme.Colors.Pink, 2.5)
			Notifications.Toast(message, Theme.Colors.Pink, 5)
		else
			SoundManager.Play("Error", 0.7)
			Notifications.Toast(ok and message or "Erreur réseau, réessaie.", Theme.Colors.Red)
		end
	end)
end

function Rebirth.Update(data)
	countLabel.Text = "Rebirths : " .. data.Rebirths
	multLabel.Text = NumberFormatter.Multiplier(data.RebirthMultiplier)
		.. "  ➜  "
		.. NumberFormatter.Multiplier(data.NextRebirthMultiplier)
	local money = ClientState.GetDisplayDopamine()
	costLabel.Text = "Coût : "
		.. NumberFormatter.Format(data.RebirthCost)
		.. " Dopamine  (tu as "
		.. NumberFormatter.Format(money)
		.. ")"
	local ratio = math.clamp(data.Dopamine / data.RebirthCost, 0, 1)
	fill.Size = UDim2.fromScale(ratio, 1)
	UIUtil.SetButtonEnabled(button, data.Dopamine >= data.RebirthCost)
end

return Rebirth
