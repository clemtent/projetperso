--[[
	Settings (ModuleScript) — paramètres (son, musique, effets)
	Emplacement : ReplicatedStorage > Client > Components > Panels > Settings

	- Interrupteurs Son / Musique / Particules : sauvegardés côté serveur
	  avec la progression (RemoteFunction "SetSetting").
	- Curseurs de volume (musique, effets) : gardés en mémoire pour la
	  session (SoundManager.SetMusicVolume / SetEffectsVolume). Ils se
	  glissent à la souris ET au doigt (écran tactile).
	La musique ne joue que si le réglage est actif ET que "Lofi Beats" est
	débloqué (voir SoundManager.SetMusicAllowed).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Client = script.Parent.Parent.Parent
local Theme = require(Client.Theme)
local UIUtil = require(Client.UIUtil)
local SoundManager = require(Client.SoundManager)
local Effects = require(Client.Effects)
local ClientState = require(Client.ClientState)
local Net = require(ReplicatedStorage.Shared.Net)

local Settings = {
	Title = "⚙️ Paramètres",
	Subtitle = "Son, musique et effets",
	Color = Theme.Colors.Dark,
	Size = Vector2.new(640, 520),
}

local ROW_COLOR = Theme.Colors.Surface or Theme.Colors.PanelLight
local ROW_BORDER = Theme.Colors.Divider or Theme.Colors.Disabled

type Toggle = { Button: TextButton, Knob: Frame }
type Slider = { Set: (value: number) -> (), SetEnabled: (enabled: boolean) -> () }

local toggles: { [string]: Toggle } = {} -- [clé] = interrupteur
local sliders: { [string]: Slider } = {} -- [clé du réglage lié] = curseur
local current = { Sound = true, Music = true, Effects = true }

local musicInfo: TextLabel? = nil
local nextButton: TextButton? = nil

----------------------------------------------------------------------
-- Réglages
----------------------------------------------------------------------

-- Texte sous "Musique" : morceau en cours, verrou Lofi, playlist vide...
local function refreshMusicInfo()
	local label = musicInfo
	if not label then
		return
	end
	local name = SoundManager.GetCurrentTrack()
	local playing = SoundManager.IsMusicPlaying()
	local text
	if not ClientState.HasFeature("Lofi") then
		text = "🔒 Se débloque avec 🎧 Lofi Beats"
	elseif not SoundManager.HasPlaylist() then
		text = RunService:IsStudio() and "⚠️ Ajoute des IDs de musique dans Config.Music" or "Aucune musique pour le moment"
	elseif not current.Music then
		text = "Musique coupée"
	elseif playing and name then
		text = "♫ " .. name
	else
		text = "Chargement..."
	end
	label.Text = text
	local button = nextButton
	if button then
		button.Visible = playing and current.Music and SoundManager.HasPlaylist()
	end
end

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
	local slider = sliders[key]
	if slider then
		slider.SetEnabled(value)
	end
	if key == "Music" then
		refreshMusicInfo()
	end
end

function Settings.Get(key: string): boolean
	return current[key] ~= false
end

-- Envoie un réglage au serveur (avec quelques essais), sinon on revient en arrière
local function saveSetting(key: string, newValue: boolean)
	task.spawn(function()
		for attempt = 1, 3 do
			if current[key] ~= newValue then
				return -- un clic plus récent a pris le relais
			end
			local ok, success = pcall(function()
				return Net.Function("SetSetting"):InvokeServer(key, newValue)
			end)
			if ok and success == true then
				return
			end
			if attempt < 3 then
				task.wait(0.3)
			end
		end
		if current[key] == newValue then
			Settings.Apply(key, not newValue)
		end
	end)
end

----------------------------------------------------------------------
-- Composants
----------------------------------------------------------------------

-- Interrupteur ON/OFF (en haut à droite de la ligne)
local function buildToggle(row: Frame, key: string)
	local button = UIUtil.Create("TextButton", {
		Name = "Toggle",
		Size = UDim2.fromOffset(76, 38),
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -14, 0, 10),
		BackgroundColor3 = Theme.Colors.Green,
		AutoButtonColor = false,
		Text = "",
		Parent = row,
	})
	UIUtil.Corner(button, UDim.new(1, 0))
	UIUtil.Stroke(button, Theme.Colors.Border, 1.5)
	local knob = UIUtil.Create("Frame", {
		Name = "Knob",
		Size = UDim2.fromOffset(30, 30),
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -4, 0.5, 0),
		BackgroundColor3 = Color3.new(1, 1, 1),
		Parent = button,
	})
	UIUtil.Corner(knob, UDim.new(1, 0))
	UIUtil.Stroke(knob, Theme.Colors.Border, 1.5)
	UIUtil.AnimateButton(button)
	toggles[key] = { Button = button, Knob = knob }

	button.Activated:Connect(function()
		local newValue = not current[key]
		Settings.Apply(key, newValue)
		SoundManager.Play("Open", newValue and 1.3 or 0.8)
		saveSetting(key, newValue)
	end)
end

-- Curseur de volume 0..100 % (souris + tactile). `onChanged(valeur, relâché)`
local function buildSlider(row: Frame, initial: number, color: Color3, onChanged: (value: number, released: boolean) -> ()): Slider
	local value = math.clamp(initial, 0, 1)

	-- Zone de saisie plus haute que la piste (plus facile au doigt)
	local hit = UIUtil.Create("TextButton", {
		Name = "Slider",
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, 16, 1, -6),
		Size = UDim2.new(1, -96, 0, 30),
		BackgroundTransparency = 1,
		AutoButtonColor = false,
		Text = "",
		Parent = row,
	})
	local track = UIUtil.Create("Frame", {
		Name = "Track",
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.fromScale(0, 0.5),
		Size = UDim2.new(1, 0, 0, 8),
		BackgroundColor3 = Theme.Colors.Disabled,
		BorderSizePixel = 0,
		Parent = hit,
	})
	UIUtil.Corner(track, UDim.new(1, 0))
	local fill = UIUtil.Create("Frame", {
		Name = "Fill",
		Size = UDim2.fromScale(value, 1),
		BackgroundColor3 = color,
		BorderSizePixel = 0,
		Parent = track,
	})
	UIUtil.Corner(fill, UDim.new(1, 0))
	local knob = UIUtil.Create("Frame", {
		Name = "Knob",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(value, 0.5),
		Size = UDim2.fromOffset(24, 24),
		BackgroundColor3 = Color3.new(1, 1, 1),
		BorderSizePixel = 0,
		ZIndex = 2,
		Parent = hit,
	})
	UIUtil.Corner(knob, UDim.new(1, 0))
	UIUtil.Stroke(knob, Theme.Colors.Border, 1.5)
	local knobScale = UIUtil.Create("UIScale", { Parent = knob })

	local percent = UIUtil.Create("TextLabel", {
		Name = "Percent",
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.new(1, -14, 1, -6),
		Size = UDim2.fromOffset(62, 30),
		BackgroundTransparency = 1,
		Font = Theme.Fonts.Number,
		Text = "",
		TextColor3 = Theme.Colors.Text,
		TextSize = 17,
		TextXAlignment = Enum.TextXAlignment.Right,
		Parent = row,
	})

	local function render()
		fill.Size = UDim2.fromScale(value, 1)
		knob.Position = UDim2.fromScale(value, 0.5)
		percent.Text = tostring(math.floor(value * 100 + 0.5)) .. " %"
	end
	render()

	local dragInput: InputObject? = nil
	local function setFromX(x: number, released: boolean)
		local width = track.AbsoluteSize.X
		if width <= 0 then
			return
		end
		value = math.clamp((x - track.AbsolutePosition.X) / width, 0, 1)
		render()
		onChanged(value, released)
	end

	hit.InputBegan:Connect(function(input: InputObject)
		local kind = input.UserInputType
		if kind == Enum.UserInputType.MouseButton1 or kind == Enum.UserInputType.Touch then
			dragInput = input
			UIUtil.Tween(knobScale, 0.12, { Scale = 1.25 }, Enum.EasingStyle.Back)
			setFromX(input.Position.X, false)
		end
	end)
	hit.MouseEnter:Connect(function()
		if not dragInput then
			UIUtil.Tween(knobScale, 0.12, { Scale = 1.12 })
		end
	end)
	hit.MouseLeave:Connect(function()
		if not dragInput then
			UIUtil.Tween(knobScale, 0.12, { Scale = 1 })
		end
	end)
	UserInputService.InputChanged:Connect(function(input: InputObject)
		local dragging = dragInput
		if not dragging then
			return
		end
		local kind = input.UserInputType
		if (kind == Enum.UserInputType.MouseMovement and dragging.UserInputType == Enum.UserInputType.MouseButton1)
			or (kind == Enum.UserInputType.Touch and input == dragging)
		then
			setFromX(input.Position.X, false)
		end
	end)
	UserInputService.InputEnded:Connect(function(input: InputObject)
		local dragging = dragInput
		if not dragging then
			return
		end
		local kind = input.UserInputType
		if (kind == Enum.UserInputType.MouseButton1 and dragging.UserInputType == Enum.UserInputType.MouseButton1)
			or (kind == Enum.UserInputType.Touch and input == dragging)
		then
			dragInput = nil
			UIUtil.Tween(knobScale, 0.15, { Scale = 1 })
			onChanged(value, true)
		end
	end)

	local slider: Slider = {
		Set = function(newValue: number)
			value = math.clamp(newValue, 0, 1)
			render()
		end,
		SetEnabled = function(enabled: boolean)
			fill.BackgroundColor3 = enabled and color or Theme.Colors.Disabled
			percent.TextTransparency = enabled and 0 or 0.5
			knob.BackgroundTransparency = enabled and 0 or 0.3
		end,
	}
	return slider
end

-- Ligne blanche arrondie (fond léger + contour fin)
local function buildRow(content: Frame, order: number, height: number): Frame
	local row = UIUtil.Create("Frame", {
		Name = "Row" .. order,
		Size = UDim2.new(1, 0, 0, height),
		BackgroundColor3 = ROW_COLOR,
		LayoutOrder = order,
		Parent = content,
	})
	UIUtil.Corner(row, 14)
	UIUtil.Stroke(row, ROW_BORDER, 1.5)
	return row
end

local function rowTitle(row: Frame, text: string)
	UIUtil.Create("TextLabel", {
		Name = "Title",
		Size = UDim2.new(1, -120, 0, 24),
		Position = UDim2.fromOffset(16, 8),
		BackgroundTransparency = 1,
		Font = Theme.Fonts.Title,
		Text = text,
		TextColor3 = Theme.Colors.Text,
		TextSize = 19,
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = row,
	})
end

local function rowSubtitle(row: Frame, text: string): TextLabel
	return UIUtil.Create("TextLabel", {
		Name = "Subtitle",
		Size = UDim2.new(1, -150, 0, 18),
		Position = UDim2.fromOffset(16, 31),
		BackgroundTransparency = 1,
		Font = Theme.Fonts.Body,
		Text = text,
		TextColor3 = Theme.Colors.TextDim,
		TextSize = 14,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextTruncate = Enum.TextTruncate.AtEnd,
		Parent = row,
	})
end

local function sectionHeader(content: Frame, text: string, order: number)
	if UIUtil.SectionHeader then
		UIUtil.SectionHeader(content, text, order, Theme.Colors.Dark)
	else
		UIUtil.Create("TextLabel", {
			Size = UDim2.new(1, 0, 0, 26),
			BackgroundTransparency = 1,
			Font = Theme.Fonts.Title,
			Text = text,
			TextColor3 = Theme.Colors.Text,
			TextSize = 19,
			TextXAlignment = Enum.TextXAlignment.Left,
			LayoutOrder = order,
			Parent = content,
		})
	end
end

----------------------------------------------------------------------
-- Construction
----------------------------------------------------------------------

function Settings.Build(content: Frame)
	UIUtil.Create("UIListLayout", {
		Padding = UDim.new(0, 10),
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = content,
	})

	sectionHeader(content, "Audio", 1)

	-- Effets sonores : interrupteur + volume
	local soundRow = buildRow(content, 2, 92)
	rowTitle(soundRow, "🔊 Effets sonores")
	rowSubtitle(soundRow, "Clics, achats, bonus...")
	buildToggle(soundRow, "Sound")
	local lastPreview = 0
	sliders.Sound = buildSlider(soundRow, SoundManager.GetEffectsVolume(), Theme.Colors.Blue, function(value, released)
		SoundManager.SetEffectsVolume(value)
		-- Petit son d'essai (pas trop souvent pendant le glissement)
		local now = os.clock()
		if released or now - lastPreview > 0.15 then
			lastPreview = now
			SoundManager.Play("Click", 0.9 + value * 0.4)
		end
	end)

	-- Musique : interrupteur + volume + morceau en cours
	local musicRow = buildRow(content, 3, 92)
	rowTitle(musicRow, "🎵 Musique lofi")
	musicInfo = rowSubtitle(musicRow, "")
	buildToggle(musicRow, "Music")
	sliders.Music = buildSlider(musicRow, SoundManager.GetMusicVolume(), Theme.Colors.Purple, function(value)
		SoundManager.SetMusicVolume(value)
	end)
	local skip = UIUtil.Create("TextButton", {
		Name = "Next",
		Size = UDim2.fromOffset(38, 38),
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -100, 0, 10),
		BackgroundColor3 = Color3.new(1, 1, 1),
		AutoButtonColor = false,
		Font = Theme.Fonts.Title,
		Text = "⏭",
		TextColor3 = Theme.Colors.Text,
		TextSize = 18,
		Visible = false,
		Parent = musicRow,
	})
	UIUtil.Corner(skip, UDim.new(1, 0))
	UIUtil.Stroke(skip, Theme.Colors.Border, 1.5)
	UIUtil.AnimateButton(skip)
	skip.Activated:Connect(function()
		if SoundManager.NextTrack() then
			SoundManager.Play("Open", 1.2)
		end
	end)
	nextButton = skip

	sectionHeader(content, "Affichage", 4)

	local fxRow = buildRow(content, 5, 60)
	rowTitle(fxRow, "✨ Particules et confettis")
	rowSubtitle(fxRow, "Désactive pour un écran plus calme")
	buildToggle(fxRow, "Effects")

	UIUtil.Create("TextLabel", {
		Name = "Tip",
		Text = "Astuce : chaque amélioration ajoute quelque chose à l'écran. Jusqu'où iras-tu ?",
		TextColor3 = Theme.Colors.TextDim,
		BackgroundTransparency = 1,
		Font = Theme.Fonts.Body,
		TextSize = 14,
		TextWrapped = true,
		Size = UDim2.new(1, 0, 0, 36),
		LayoutOrder = 10,
		Parent = content,
	})

	-- Infos musique en direct
	SoundManager.TrackChanged:Connect(refreshMusicInfo)
	SoundManager.MusicStateChanged:Connect(refreshMusicInfo)
	SoundManager.VolumeChanged:Connect(function(musicVolume: number, effectsVolume: number)
		-- (volumes changés ailleurs : on recale les curseurs)
		local music = sliders.Music
		local sound = sliders.Sound
		if music then
			music.Set(musicVolume)
		end
		if sound then
			sound.Set(effectsVolume)
		end
	end)
	ClientState.FeaturesChanged:Connect(refreshMusicInfo)
	refreshMusicInfo()
end

function Settings.OnOpen()
	refreshMusicInfo()
end

-- Au chargement, on applique les réglages sauvegardés (une seule fois)
local applied = false
function Settings.Update(data)
	if applied or not data.Settings then
		return
	end
	applied = true
	for _, key in ipairs({ "Sound", "Music", "Effects" }) do
		Settings.Apply(key, data.Settings[key] ~= false)
	end
end

return Settings
