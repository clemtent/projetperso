--[[
	Settings (ModuleScript) — paramètres (son, musique, effets)
	Emplacement : ReplicatedStorage > Client > Components > Panels > Settings

	Les réglages sont sauvegardés côté serveur avec la progression.
	La musique ne joue que si le réglage est actif ET que "Lofi Beats" est
	débloqué (voir SoundManager.SetMusicAllowed).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Client = script.Parent.Parent.Parent
local Theme = require(Client.Theme)
local UIUtil = require(Client.UIUtil)
local SoundManager = require(Client.SoundManager)
local Effects = require(Client.Effects)
local Net = require(ReplicatedStorage.Shared.Net)

local Settings = {
	Title = "⚙️ Paramètres",
	Color = Theme.Colors.Dark,
}

local OPTIONS = {
	{ Key = "Sound", Label = "🔊 Effets sonores" },
	{ Key = "Music", Label = "🎵 Musique (avec Lofi Beats)" },
	{ Key = "Effects", Label = "✨ Particules et confettis" },
}

local toggles = {} -- [clé] = { Button, Knob }
local current = { Sound = true, Music = true, Effects = true }

-- Applique un réglage localement (son / musique / effets)
function Settings.Apply(key: string, value: boolean)
	current[key] = value
	if key == "Sound" then
		SoundManager.SetSoundEnabled(value)
	elseif key == "Music" then
		SoundManager.SetMusicEnabled(value)
	elseif key == "Effects" then
		Effects.SetEnabled(value)
	end

	local ui = toggles[key]
	if ui then
		UIUtil.Tween(ui.Knob, 0.2, {
			Position = value and UDim2.new(1, -4, 0.5, 0) or UDim2.new(0, 4, 0.5, 0),
			AnchorPoint = value and Vector2.new(1, 0.5) or Vector2.new(0, 0.5),
		}, Enum.EasingStyle.Back)
		UIUtil.Tween(ui.Button, 0.2, { BackgroundColor3 = value and Theme.Colors.Green or Theme.Colors.Disabled })
	end
end

function Settings.Get(key: string): boolean
	return current[key] ~= false
end

function Settings.Build(content: Frame)
	UIUtil.Create("UIListLayout", {
		Padding = UDim.new(0, 12),
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = content,
	})

	for index, option in ipairs(OPTIONS) do
		local row = UIUtil.Create("Frame", {
			Size = UDim2.new(1, 0, 0, 62),
			BackgroundColor3 = Theme.Colors.PanelLight,
			LayoutOrder = index,
			Parent = content,
		})
		UIUtil.Corner(row, 14)
		UIUtil.Stroke(row, Theme.Colors.Disabled, 1.5)
		UIUtil.Label({
			Text = option.Label,
			Font = Theme.Fonts.Title,
			TextXAlignment = Enum.TextXAlignment.Left,
			Size = UDim2.new(1, -140, 1, -18),
			Position = UDim2.fromOffset(16, 9),
			MaxTextSize = 21,
			Parent = row,
		})

		-- Interrupteur ON/OFF
		local button = UIUtil.Create("TextButton", {
			Size = UDim2.fromOffset(84, 40),
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.new(1, -16, 0.5, 0),
			BackgroundColor3 = Theme.Colors.Green,
			AutoButtonColor = false,
			Text = "",
			Parent = row,
		})
		UIUtil.Corner(button, UDim.new(1, 0))
		UIUtil.Stroke(button, Theme.Colors.Border, 1.5)
		local knob = UIUtil.Create("Frame", {
			Size = UDim2.fromOffset(32, 32),
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.new(1, -4, 0.5, 0),
			BackgroundColor3 = Color3.new(1, 1, 1),
			Parent = button,
		})
		UIUtil.Corner(knob, UDim.new(1, 0))
		UIUtil.Stroke(knob, Theme.Colors.Border, 1.5)
		UIUtil.AnimateButton(button)
		toggles[option.Key] = { Button = button, Knob = knob }

		button.Activated:Connect(function()
			local newValue = not current[option.Key]
			Settings.Apply(option.Key, newValue)
			SoundManager.Play("Open", newValue and 1.3 or 0.8)
			-- On prévient le serveur pour sauvegarder le choix
			task.spawn(function()
				pcall(function()
					Net.Function("SetSetting"):InvokeServer(option.Key, newValue)
				end)
			end)
		end)
	end

	UIUtil.Label({
		Text = "Astuce : chaque amélioration ajoute quelque chose à l'écran. Jusqu'où iras-tu ?",
		TextColor3 = Theme.Colors.TextDim,
		Size = UDim2.new(1, 0, 0, 40),
		LayoutOrder = 10,
		MaxTextSize = 16,
		Parent = content,
	})
end

-- Au chargement, on applique les réglages sauvegardés (une seule fois)
local applied = false
function Settings.Update(data)
	if applied or not data.Settings then
		return
	end
	applied = true
	for _, option in ipairs(OPTIONS) do
		Settings.Apply(option.Key, data.Settings[option.Key] ~= false)
	end
end

return Settings
