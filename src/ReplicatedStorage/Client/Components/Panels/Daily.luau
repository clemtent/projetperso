--[[
	Daily (ModuleScript) — récompense quotidienne
	Emplacement : ReplicatedStorage > Client > Components > Panels > Daily
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Client = script.Parent.Parent.Parent
local Theme = require(Client.Theme)
local UIUtil = require(Client.UIUtil)
local ClientState = require(Client.ClientState)
local Effects = require(Client.Effects)
local SoundManager = require(Client.SoundManager)
local Notifications = require(script.Parent.Parent.Notifications)
local Config = require(ReplicatedStorage.Shared.Config)
local NumberFormatter = require(ReplicatedStorage.Shared.NumberFormatter)
local Net = require(ReplicatedStorage.Shared.Net)

local Daily = {
	Title = "🎁 CADEAU DU JOUR",
	Color = Theme.Colors.Orange,
}

local days = {}
local rewardLabel: TextLabel
local timerLabel: TextLabel
local button: TextButton
local lastInfoClock = 0

function Daily.Build(content: Frame)
	UIUtil.Label({
		Text = "Reviens chaque jour pour augmenter ta série et tes récompenses !",
		TextColor3 = Theme.Colors.TextDim,
		Size = UDim2.new(1, 0, 0, 30),
		MaxTextSize = 17,
		Parent = content,
	})

	-- Les 7 jours de la série
	local row = UIUtil.Create("Frame", {
		Size = UDim2.new(1, 0, 0, 90),
		Position = UDim2.fromOffset(0, 44),
		BackgroundTransparency = 1,
		Parent = content,
	})
	UIUtil.Create("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		Padding = UDim.new(0, 8),
		Parent = row,
	})
	for day = 1, Config.Daily.MaxStreakBonus do
		local box = UIUtil.Create("Frame", {
			Size = UDim2.fromOffset(72, 90),
			BackgroundColor3 = Theme.Colors.Card,
			LayoutOrder = day,
			Parent = row,
		})
		UIUtil.Corner(box, 14)
		local stroke = UIUtil.Stroke(box, Theme.Colors.Disabled, 2)
		UIUtil.Label({
			Text = "Jour " .. day,
			Size = UDim2.new(1, 0, 0, 22),
			Position = UDim2.fromOffset(0, 6),
			MaxTextSize = 15,
			Parent = box,
		})
		UIUtil.Label({
			Text = day == Config.Daily.MaxStreakBonus and "💎" or "🎁",
			Size = UDim2.new(1, 0, 0, 44),
			Position = UDim2.fromOffset(0, 34),
			MaxTextSize = 36,
			Parent = box,
		})
		days[day] = { Box = box, Stroke = stroke }
	end

	rewardLabel = UIUtil.Label({
		Font = Theme.Fonts.Number,
		TextColor3 = Theme.Colors.Yellow,
		Size = UDim2.new(1, 0, 0, 44),
		Position = UDim2.fromOffset(0, 150),
		MaxTextSize = 34,
		Parent = content,
	})
	timerLabel = UIUtil.Label({
		TextColor3 = Theme.Colors.TextDim,
		Size = UDim2.new(1, 0, 0, 24),
		Position = UDim2.fromOffset(0, 198),
		MaxTextSize = 17,
		Parent = content,
	})

	button = UIUtil.NeonButton({
		Text = "RÉCUPÉRER",
		Font = Theme.Fonts.Title,
		Size = UDim2.fromOffset(300, 66),
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 240),
		Color = Theme.Colors.Orange,
		MaxTextSize = 26,
		Parent = content,
	})
	button.Activated:Connect(function()
		if not button:GetAttribute("Enabled") then
			SoundManager.Play("Error", 0.7)
			UIUtil.Shake(button)
			return
		end
		local ok, success, message = pcall(function()
			return Net.Function("ClaimDaily"):InvokeServer()
		end)
		if ok and success then
			SoundManager.Play("Achievement", 1)
			Effects.Confetti(80)
			Effects.Flash(Theme.Colors.Orange, 0.4)
			Notifications.Toast(message, Theme.Colors.Orange, 5, "🎁 CADEAU RÉCUPÉRÉ !")
		else
			SoundManager.Play("Error", 0.7)
			Notifications.Toast(ok and message or "Erreur réseau, réessaie.", Theme.Colors.Red)
		end
	end)

	-- Compte à rebours
	task.spawn(function()
		while content.Parent do
			local data = ClientState.Data
			if data and not data.Daily.Available then
				local remaining = data.Daily.NextIn - (os.clock() - lastInfoClock)
				timerLabel.Text = "Prochain cadeau dans " .. NumberFormatter.Time(remaining)
			end
			task.wait(1)
		end
	end)
end

function Daily.Update(data)
	lastInfoClock = os.clock()
	local info = data.Daily
	local streak = math.min(info.Streak, Config.Daily.MaxStreakBonus)
	for day, ui in pairs(days) do
		local reached = day <= streak
		ui.Stroke.Color = reached and Theme.Colors.Orange or Theme.Colors.Disabled
		ui.Box.BackgroundColor3 = (day == streak and info.Available) and Theme.Colors.PanelLight or Theme.Colors.Card
	end

	if info.Available then
		rewardLabel.Text = "Jour " .. info.Streak .. " : +" .. NumberFormatter.Format(info.Reward) .. " 💧"
		timerLabel.Text = "Ton cadeau t'attend !"
		button.Text = "RÉCUPÉRER"
		UIUtil.SetButtonEnabled(button, true)
	else
		rewardLabel.Text = "Série actuelle : " .. info.Streak .. " jour(s) 🔥"
		button.Text = "DÉJÀ RÉCUPÉRÉ"
		UIUtil.SetButtonEnabled(button, false)
	end
end

return Daily
