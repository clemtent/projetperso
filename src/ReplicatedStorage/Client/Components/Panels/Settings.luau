--[[
	Settings (ModuleScript) — paramètres (son, musique, son du clic, effets)
	Emplacement : ReplicatedStorage > Client > Components > Panels > Settings

	Présentation "premium" en cartes de section (icône, titre, sous-titre) :
	  - 🔊 Audio : Effets sonores / Musique lofi (interrupteur animé +
	    curseur de volume à halo lumineux), puis le choix du son du clic
	    (▶ pour écouter, clic pour choisir) ;
	  - 🖥️ Affichage : particules et confettis ;
	  - 🎮 Jeu : musique en cours (égaliseur animé, ⏭ morceau suivant),
	    crédits et version.

	Comportements (inchangés) :
	- Interrupteurs Son / Musique / Particules : sauvegardés côté serveur
	  avec la progression (RemoteFunction "SetSetting", booléens), 3 essais
	  puis retour en arrière si le serveur refuse.
	- Son du clic (v4) : liste de Config.ClickSounds, sauvegardé avec
	  SetSetting("ClickSound", id) et joué par SoundManager.PlayClick sur le
	  gros bouton.
	- Curseurs de volume (musique, effets) : gardés en mémoire pour la
	  session (SoundManager.SetMusicVolume / SetEffectsVolume). Ils se
	  glissent à la souris ET au doigt (écran tactile).
	La musique ne joue que si le réglage est actif ET que "Lofi Beats" est
	débloqué (voir SoundManager.SetMusicAllowed).

	v5 :
	- 🌙 Mode sombre (section Affichage) : SetSetting("DarkMode", bool),
	  appliqué tout de suite (ClientState.SetUserDarkMode -> DarkSkin).
	- 🌐 Langue : Auto / English / Français, SetSetting("Language", valeur)
	  ; la langue change au prochain passage dans le jeu (pas de
	  reconstruction en direct) : un bandeau le rappelle.
	- Textes en anglais traduits (Locale) ; zones tactiles agrandies.
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
local Config = require(ReplicatedStorage.Shared.Config)
local Locale = require(ReplicatedStorage.Shared.Locale)
local Notifications = require(script.Parent.Parent.Notifications)

-- Title / Subtitle en anglais : traduits par PanelManager
local Settings = {
	Title = "⚙️ Settings",
	Subtitle = "Sound, music, display and language",
	Color = Theme.Colors.Dark,
	Size = Vector2.new(680, 600),
}

local VERSION = "v5"
local WHITE = Color3.new(1, 1, 1)
local BLACK = Color3.new(0, 0, 0)
local ROW_HOVER = Theme.Colors.Surface or Theme.Colors.PanelLight
local ROW_BORDER = Theme.Colors.Divider or Theme.Colors.Disabled
local ON_COLOR = Theme.Colors.Green
local OFF_COLOR = Theme.Colors.Disabled
local SELECTED_SOFT = Color3.fromRGB(230, 242, 255)

local SECTION_AUDIO = Theme.Colors.Blue
local SECTION_DISPLAY = Theme.Colors.Purple
local SECTION_GAME = Theme.Colors.Orange

type Toggle = { Button: TextButton, Knob: Frame, Stroke: UIStroke, Glyph: TextLabel }
type Slider = { Set: (value: number) -> (), SetEnabled: (enabled: boolean) -> () }

local toggles: { [string]: Toggle } = {} -- [clé] = interrupteur
local sliders: { [string]: Slider } = {} -- [clé du réglage lié] = curseur
local current = { Sound = true, Music = true, Effects = true, DarkMode = false }

-- Langue : onglets Auto / English / Français
local LANGUAGE_OPTIONS = { "Auto", "en", "fr" }
local languageTabs: UIUtil.Tabs? = nil
local languageSaveToken = 0
local languageSaving = false
local languageChosen: string? = nil -- choix local (en attente de sauvegarde)

local musicInfo: TextLabel? = nil -- sous-titre de la ligne "Musique lofi"
local nowPlayingLabel: TextLabel? = nil -- grand texte de la carte "En cours de lecture"
local nowPlayingStatus: TextLabel? = nil -- petite ligne au-dessus ("♫ En cours de lecture"...)
local nextButton: TextButton? = nil
local equalizerBars: { Frame } = {}
local equalizerConnection: RBXScriptConnection? = nil

-- Son du clic
type ClickOption = { Id: string, Card: TextButton, Stroke: UIStroke, Check: Frame, Name: TextLabel, Hovered: boolean }
local clickOptions: { ClickOption } = {}
local clickSaveToken = 0 -- change à chaque choix (annule les sauvegardes périmées)
local clickSaving = false -- une sauvegarde est en cours (on ne recale pas sur l'état serveur)

----------------------------------------------------------------------
-- Réglages
----------------------------------------------------------------------

-- Textes de la musique : morceau en cours, verrou Lofi, playlist vide...
local function refreshMusicInfo()
	local name = SoundManager.GetCurrentTrack()
	local playing = SoundManager.IsMusicPlaying()
	local text
	local status
	if not ClientState.HasFeature("Lofi") then
		text = Locale.T("🔒 Unlocks with 🎧 %s", Locale.T("Lofi Beats"))
		status = Locale.T("Locked")
	elseif not SoundManager.HasPlaylist() then
		text = RunService:IsStudio() and Locale.T("⚠️ Add music IDs in Config.Music") or Locale.T("No music for now")
		status = Locale.T("Empty playlist")
	elseif not current.Music then
		text = Locale.T("Music off")
		status = Locale.T("Paused")
	elseif playing and name then
		text = "♫ " .. name
		status = Locale.T("♫ Now playing")
	else
		text = Locale.T("Loading...")
		status = Locale.T("Loading")
	end
	local label = musicInfo
	if label then
		label.Text = text
	end
	local big = nowPlayingLabel
	if big then
		big.Text = (playing and name and current.Music) and tostring(name) or text
	end
	local small = nowPlayingStatus
	if small then
		small.Text = string.upper(status)
	end
	local button = nextButton
	if button then
		button.Visible = playing and current.Music and SoundManager.HasPlaylist()
	end
end

-- Dessine un interrupteur (animé) selon sa valeur
local function paintToggle(ui: Toggle, value: boolean, animate: boolean)
	local duration = animate and 0.22 or 0
	UIUtil.Tween(ui.Knob, duration, {
		Position = value and UDim2.new(1, -3, 0.5, 0) or UDim2.new(0, 3, 0.5, 0),
		AnchorPoint = value and Vector2.new(1, 0.5) or Vector2.new(0, 0.5),
	}, Enum.EasingStyle.Back)
	UIUtil.Tween(ui.Button, duration, { BackgroundColor3 = value and ON_COLOR or OFF_COLOR })
	UIUtil.Tween(ui.Stroke, duration, { Color = (value and ON_COLOR or OFF_COLOR):Lerp(BLACK, 0.25) })
	ui.Glyph.Text = value and "✓" or "✕"
	ui.Glyph.TextColor3 = (value and ON_COLOR or OFF_COLOR):Lerp(BLACK, 0.2)
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
	elseif key == "DarkMode" then
		ClientState.SetUserDarkMode(value)
	end

	local ui = toggles[key]
	if ui then
		paintToggle(ui, value, true)
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
-- Son du clic
----------------------------------------------------------------------

-- Met en valeur l'option choisie (et celle survolée)
local function paintClickOptions()
	local selected = SoundManager.GetClickSound()
	for _, option in ipairs(clickOptions) do
		local isSelected = option.Id == selected
		option.Card.BackgroundColor3 = isSelected and SELECTED_SOFT or (option.Hovered and ROW_HOVER or Theme.Colors.Card)
		option.Stroke.Color = (isSelected or option.Hovered) and Theme.Colors.Blue or ROW_BORDER
		option.Stroke.Transparency = (option.Hovered and not isSelected) and 0.5 or 0
		option.Stroke.Thickness = isSelected and 2 or 1.5
		option.Name.TextColor3 = isSelected and Theme.Colors.Blue:Lerp(BLACK, 0.3) or Theme.Colors.Text
		if option.Check.Visible ~= isSelected then
			option.Check.Visible = isSelected
			if isSelected then
				UIUtil.Pop(option.Check, 0.3, 0.35)
			end
		end
	end
end

-- Choisit un son de clic : appliqué tout de suite, puis sauvegardé (3 essais)
local function chooseClickSound(id: string)
	local previous = SoundManager.GetClickSound()
	SoundManager.SetClickSound(id)
	SoundManager.PreviewClickSound(id)
	paintClickOptions()
	if previous == SoundManager.GetClickSound() then
		return
	end
	clickSaveToken += 1
	local token = clickSaveToken
	clickSaving = true
	task.spawn(function()
		for attempt = 1, 3 do
			if token ~= clickSaveToken then
				return -- un choix plus récent a pris le relais
			end
			local ok, success = pcall(function()
				return Net.Function("SetSetting"):InvokeServer("ClickSound", id)
			end)
			if ok and success == true then
				if token == clickSaveToken then
					clickSaving = false
				end
				return
			end
			if attempt < 3 then
				task.wait(0.3)
			end
		end
		if token == clickSaveToken then
			clickSaving = false
			-- Refusé : on revient au choix précédent
			SoundManager.SetClickSound(previous)
			paintClickOptions()
		end
	end)
end

local function buildClickOption(grid: Frame, entry, order: number)
	local card = UIUtil.Create("TextButton", {
		Name = tostring(entry.Id),
		BackgroundColor3 = Theme.Colors.Card,
		AutoButtonColor = false,
		Text = "",
		LayoutOrder = order,
		Parent = grid,
	})
	UIUtil.Corner(card, Theme.Radius.M)
	local stroke = UIUtil.Stroke(card, ROW_BORDER, 1.5)
	UIUtil.AnimateButton(card, 1.03, 0.96)

	-- Bouton ▶ (écouter sans choisir)
	local play = UIUtil.Create("TextButton", {
		Name = "Preview",
		Size = UDim2.fromOffset(34, 34),
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 10, 0.5, 0),
		BackgroundColor3 = WHITE,
		AutoButtonColor = false,
		Font = Theme.Fonts.Title,
		Text = "▶",
		TextColor3 = Theme.Colors.TextLight,
		TextSize = 14,
		ZIndex = 2,
		Parent = card,
	})
	UIUtil.Corner(play, UDim.new(1, 0))
	UIUtil.Gradient(play, ColorSequence.new(Theme.Colors.Blue:Lerp(WHITE, 0.2), Theme.Colors.Blue:Lerp(BLACK, 0.2)), 90)
	UIUtil.AnimateButton(play, 1.12, 0.9)
	local previewToken = 0
	play.Activated:Connect(function()
		SoundManager.PreviewClickSound(entry.Id)
		UIUtil.Pop(play, 1.25, 0.3)
		-- Petite note pendant l'écoute
		previewToken += 1
		local token = previewToken
		play.Text = "♪"
		task.delay(0.45, function()
			if token == previewToken then
				play.Text = "▶"
			end
		end)
	end)

	local isKeyboard = string.find(string.lower(tostring(entry.Id)), "keyboard") ~= nil
	local name = UIUtil.Label({
		Name = "SoundName",
		Text = Locale.T(tostring(entry.Name or entry.Id)),
		Font = Theme.Fonts.Title,
		TextXAlignment = Enum.TextXAlignment.Left,
		Size = UDim2.new(1, -86, 0, 20),
		Position = UDim2.fromOffset(52, 9),
		MaxTextSize = 16,
		ZIndex = 2,
		Parent = card,
	})
	UIUtil.Label({
		Name = "Kind",
		Text = isKeyboard and Locale.T("⌨️ Keyboard") or Locale.T("🖱️ Click"),
		TextColor3 = Theme.Colors.TextDim,
		TextXAlignment = Enum.TextXAlignment.Left,
		Size = UDim2.new(1, -86, 0, 15),
		Position = UDim2.fromOffset(52, 30),
		MaxTextSize = 13,
		ZIndex = 2,
		Parent = card,
	})

	-- Coche "choisi"
	local check = UIUtil.Create("Frame", {
		Name = "Check",
		Size = UDim2.fromOffset(24, 24),
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -10, 0.5, 0),
		BackgroundColor3 = Theme.Colors.Blue,
		Visible = false,
		ZIndex = 2,
		Parent = card,
	})
	UIUtil.Corner(check, UDim.new(1, 0))
	UIUtil.Label({
		Text = "✔",
		Font = Theme.Fonts.Title,
		TextColor3 = Theme.Colors.TextLight,
		Size = UDim2.new(1, -6, 1, -6),
		Position = UDim2.fromOffset(3, 3),
		MaxTextSize = 14,
		ZIndex = 3,
		Parent = check,
	})

	local option: ClickOption = { Id = entry.Id, Card = card, Stroke = stroke, Check = check, Name = name, Hovered = false }
	card.MouseEnter:Connect(function()
		option.Hovered = true
		paintClickOptions()
	end)
	card.MouseLeave:Connect(function()
		option.Hovered = false
		paintClickOptions()
	end)
	card.Activated:Connect(function()
		chooseClickSound(entry.Id)
	end)
	table.insert(clickOptions, option)
end

----------------------------------------------------------------------
-- Composants
----------------------------------------------------------------------

-- Carte de section (icône colorée, titre, sous-titre). Renvoie la carte :
-- ses lignes s'empilent en dessous (LayoutOrder >= 1).
local function buildSection(content: Instance, order: number, icon: string, title: string, subtitle: string, accent: Color3): Frame
	local card = UIUtil.Create("Frame", {
		Name = "Section" .. order,
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundColor3 = WHITE,
		LayoutOrder = order,
		Parent = content,
	})
	UIUtil.Corner(card, Theme.Radius.L)
	UIUtil.Stroke(card, ROW_BORDER, 1.5)
	-- Léger voile de la couleur de la section en haut de la carte
	UIUtil.Create("UIGradient", {
		Rotation = 90,
		Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, accent:Lerp(WHITE, 0.9)),
			ColorSequenceKeypoint.new(0.3, WHITE),
			ColorSequenceKeypoint.new(1, WHITE),
		}),
		Parent = card,
	})
	UIUtil.Create("UIPadding", {
		PaddingTop = UDim.new(0, 12),
		PaddingBottom = UDim.new(0, 12),
		PaddingLeft = UDim.new(0, 12),
		PaddingRight = UDim.new(0, 12),
		Parent = card,
	})
	UIUtil.Create("UIListLayout", {
		Padding = UDim.new(0, 6),
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = card,
	})

	local header = UIUtil.Create("Frame", {
		Name = "Header",
		Size = UDim2.new(1, 0, 0, 44),
		BackgroundTransparency = 1,
		LayoutOrder = 0,
		Parent = card,
	})
	local badge = UIUtil.Create("Frame", {
		Name = "Icon",
		Size = UDim2.fromOffset(40, 40),
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 2, 0.5, 0),
		BackgroundColor3 = WHITE,
		Parent = header,
	})
	UIUtil.Corner(badge, Theme.Radius.M)
	UIUtil.Stroke(badge, accent:Lerp(BLACK, 0.25), 1.5, 0.35)
	UIUtil.SoftGradient(badge, accent, 90)
	UIUtil.Label({
		Text = icon,
		Size = UDim2.new(1, -12, 1, -12),
		Position = UDim2.fromOffset(6, 6),
		MaxTextSize = 22,
		Parent = badge,
	})
	UIUtil.Label({
		Name = "Title",
		Text = title,
		Font = Theme.Fonts.Title,
		TextXAlignment = Enum.TextXAlignment.Left,
		Size = UDim2.new(1, -60, 0, 22),
		Position = UDim2.fromOffset(54, 2),
		MaxTextSize = Theme.TextSize.Heading,
		Parent = header,
	})
	UIUtil.Label({
		Name = "Subtitle",
		Text = subtitle,
		TextColor3 = Theme.Colors.TextDim,
		TextXAlignment = Enum.TextXAlignment.Left,
		Size = UDim2.new(1, -60, 0, 16),
		Position = UDim2.fromOffset(54, 25),
		MaxTextSize = Theme.TextSize.Caption,
		Parent = header,
	})
	return card
end

-- Fine ligne de séparation dans une section
local function divider(section: Frame, order: number)
	UIUtil.Create("Frame", {
		Name = "Divider",
		Size = UDim2.new(1, -16, 0, 1),
		BackgroundColor3 = ROW_BORDER,
		BorderSizePixel = 0,
		LayoutOrder = order,
		Parent = section,
	})
end

-- Ligne d'une section : pastille d'icône, titre, sous-titre (fond au survol)
local function buildRow(section: Frame, order: number, height: number, icon: string, title: string, accent: Color3): (Frame, TextLabel)
	local row = UIUtil.Create("Frame", {
		Name = "Row" .. order,
		Size = UDim2.new(1, 0, 0, height),
		BackgroundColor3 = ROW_HOVER,
		BackgroundTransparency = 1,
		LayoutOrder = order,
		Parent = section,
	})
	UIUtil.Corner(row, Theme.Radius.M)
	row.MouseEnter:Connect(function()
		UIUtil.Tween(row, 0.15, { BackgroundTransparency = 0 })
	end)
	row.MouseLeave:Connect(function()
		UIUtil.Tween(row, 0.2, { BackgroundTransparency = 1 })
	end)

	local bubble = UIUtil.Create("Frame", {
		Name = "Icon",
		Size = UDim2.fromOffset(36, 36),
		Position = UDim2.fromOffset(8, 12),
		BackgroundColor3 = accent:Lerp(WHITE, 0.85),
		Parent = row,
	})
	UIUtil.Corner(bubble, UDim.new(1, 0))
	UIUtil.Stroke(bubble, accent, 1, 0.6)
	UIUtil.Label({
		Text = icon,
		Size = UDim2.new(1, -10, 1, -10),
		Position = UDim2.fromOffset(5, 5),
		MaxTextSize = 20,
		Parent = bubble,
	})
	UIUtil.Label({
		Name = "Title",
		Text = title,
		Font = Theme.Fonts.Title,
		TextXAlignment = Enum.TextXAlignment.Left,
		Size = UDim2.new(1, -150, 0, 20),
		Position = UDim2.fromOffset(56, 10),
		MaxTextSize = 17,
		Parent = row,
	})
	local subtitle = UIUtil.Create("TextLabel", {
		Name = "Subtitle",
		Size = UDim2.new(1, -150, 0, 17),
		Position = UDim2.fromOffset(56, 31),
		BackgroundTransparency = 1,
		Font = Theme.Fonts.Body,
		Text = "",
		TextColor3 = Theme.Colors.TextDim,
		TextSize = 14,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextTruncate = Enum.TextTruncate.AtEnd,
		Parent = row,
	})
	return row, subtitle
end

-- Interrupteur ON/OFF animé (en haut à droite de la ligne)
local function buildToggle(row: Frame, key: string)
	local button = UIUtil.Create("TextButton", {
		Name = "Toggle",
		Size = UDim2.fromOffset(60, 32),
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -12, 0, 14),
		BackgroundColor3 = ON_COLOR,
		AutoButtonColor = false,
		Text = "",
		Parent = row,
	})
	UIUtil.Corner(button, UDim.new(1, 0))
	local stroke = UIUtil.Stroke(button, ON_COLOR:Lerp(BLACK, 0.25), 1.5, 0.2)
	-- Reflet (haut plus clair)
	UIUtil.Create("UIGradient", {
		Rotation = 90,
		Color = ColorSequence.new(WHITE, Color3.fromRGB(215, 215, 215)),
		Parent = button,
	})
	local knob = UIUtil.Create("Frame", {
		Name = "Knob",
		Size = UDim2.fromOffset(26, 26),
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -3, 0.5, 0),
		BackgroundColor3 = WHITE,
		ZIndex = 2,
		Parent = button,
	})
	UIUtil.Corner(knob, UDim.new(1, 0))
	UIUtil.Stroke(knob, BLACK, 1, 0.8)
	local glyph = UIUtil.Label({
		Name = "Glyph",
		Text = "✓",
		Font = Theme.Fonts.Title,
		TextColor3 = ON_COLOR,
		Size = UDim2.new(1, -10, 1, -10),
		Position = UDim2.fromOffset(5, 5),
		MaxTextSize = 13,
		ZIndex = 3,
		Parent = knob,
	})
	UIUtil.AnimateButton(button, 1.06, 0.93)
	local ui: Toggle = { Button = button, Knob = knob, Stroke = stroke, Glyph = glyph }
	toggles[key] = ui
	paintToggle(ui, current[key] == true, false)

	local function onActivated()
		local newValue = not current[key]
		Settings.Apply(key, newValue)
		SoundManager.Play("Open", newValue and 1.3 or 0.8)
		saveSetting(key, newValue)
	end
	button.Activated:Connect(onActivated)
	-- Zone tactile plus grande que l'interrupteur (au moins 44 px de haut)
	local hitbox = UIUtil.Create("TextButton", {
		Name = "Hitbox",
		Size = UDim2.new(1, 20, 1, 20),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		BackgroundTransparency = 1,
		AutoButtonColor = false,
		Text = "",
		ZIndex = 4,
		Parent = button,
	})
	hitbox.Activated:Connect(onActivated)
end

-- Icône de volume selon le niveau
local function volumeIcon(value: number): string
	if value <= 0.001 then
		return "🔇"
	elseif value < 0.34 then
		return "🔈"
	elseif value < 0.67 then
		return "🔉"
	end
	return "🔊"
end

-- Curseur de volume 0..100 % (souris + tactile), halo lumineux autour du
-- bouton (survol / glissement). `onChanged(valeur, relâché)`
local function buildSlider(row: Frame, initial: number, color: Color3, onChanged: (value: number, released: boolean) -> ()): Slider
	local value = math.clamp(initial, 0, 1)
	local enabled = true
	local hovering = false

	local icon = UIUtil.Label({
		Name = "VolumeIcon",
		Size = UDim2.fromOffset(24, 24),
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, 56, 1, -9),
		MaxTextSize = 18,
		Parent = row,
	})

	-- Zone de saisie plus haute que la piste (plus facile au doigt).
	-- Marges : le bouton rond (et son halo) ne touche jamais l'icône ni le "100 %"
	local hit = UIUtil.Create("TextButton", {
		Name = "Slider",
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, 100, 1, -6),
		Size = UDim2.new(1, -198, 0, 30),
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
		BackgroundColor3 = Color3.fromRGB(226, 226, 230),
		BorderSizePixel = 0,
		Parent = hit,
	})
	UIUtil.Corner(track, UDim.new(1, 0))
	local fill = UIUtil.Create("Frame", {
		Name = "Fill",
		Size = UDim2.fromScale(value, 1),
		BackgroundColor3 = WHITE,
		BorderSizePixel = 0,
		Parent = track,
	})
	UIUtil.Corner(fill, UDim.new(1, 0))
	local fillGradient = UIUtil.Gradient(fill, ColorSequence.new(color:Lerp(WHITE, 0.35), color), 0)

	-- Halo (derrière le bouton)
	local glow = UIUtil.Create("Frame", {
		Name = "Glow",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(value, 0.5),
		Size = UDim2.fromOffset(32, 32),
		BackgroundColor3 = color,
		BackgroundTransparency = 0.88,
		BorderSizePixel = 0,
		ZIndex = 2,
		Parent = hit,
	})
	UIUtil.Corner(glow, UDim.new(1, 0))
	local knob = UIUtil.Create("Frame", {
		Name = "Knob",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(value, 0.5),
		Size = UDim2.fromOffset(22, 22),
		BackgroundColor3 = WHITE,
		BorderSizePixel = 0,
		ZIndex = 3,
		Parent = hit,
	})
	UIUtil.Corner(knob, UDim.new(1, 0))
	local knobStroke = UIUtil.Stroke(knob, color, 2.5, 0)
	local knobScale = UIUtil.Create("UIScale", { Parent = knob })

	local percent = UIUtil.Create("TextLabel", {
		Name = "Percent",
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.new(1, -12, 1, -9),
		Size = UDim2.fromOffset(60, 24),
		BackgroundColor3 = WHITE,
		Font = Theme.Fonts.Number,
		Text = "",
		TextColor3 = Theme.Colors.Text,
		TextSize = 15,
		Parent = row,
	})
	UIUtil.Corner(percent, UDim.new(1, 0))
	UIUtil.Stroke(percent, ROW_BORDER, 1.5)

	local function render()
		fill.Size = UDim2.fromScale(value, 1)
		knob.Position = UDim2.fromScale(value, 0.5)
		glow.Position = UDim2.fromScale(value, 0.5)
		percent.Text = tostring(math.floor(value * 100 + 0.5)) .. " %"
		icon.Text = enabled and volumeIcon(value) or "🔇"
	end
	render()

	-- Halo : 0 = repos, 1 = survol, 2 = glissement
	local function setGlow(level: number)
		local size = level == 2 and 46 or (level == 1 and 40 or 32)
		local transparency = level == 2 and 0.62 or (level == 1 and 0.74 or 0.88)
		UIUtil.Tween(glow, 0.15, { Size = UDim2.fromOffset(size, size), BackgroundTransparency = transparency })
		UIUtil.Tween(knobScale, 0.15, { Scale = level == 2 and 1.2 or (level == 1 and 1.1 or 1) }, Enum.EasingStyle.Back)
	end

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
			setGlow(2)
			setFromX(input.Position.X, false)
		end
	end)
	hit.MouseEnter:Connect(function()
		hovering = true
		if not dragInput then
			setGlow(1)
		end
	end)
	hit.MouseLeave:Connect(function()
		hovering = false
		if not dragInput then
			setGlow(0)
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
			setGlow(hovering and 1 or 0)
			onChanged(value, true)
		end
	end)

	local slider: Slider = {
		Set = function(newValue: number)
			value = math.clamp(newValue, 0, 1)
			render()
		end,
		SetEnabled = function(isEnabled: boolean)
			enabled = isEnabled
			local tint = isEnabled and color or Theme.Colors.Disabled
			fillGradient.Color = ColorSequence.new(tint:Lerp(WHITE, 0.35), tint)
			glow.BackgroundColor3 = tint
			knobStroke.Color = tint
			percent.TextTransparency = isEnabled and 0 or 0.5
			knob.BackgroundTransparency = isEnabled and 0 or 0.3
			render()
		end,
	}
	return slider
end

-- Égaliseur de la carte "En cours de lecture" (barres qui dansent)
local function stepEqualizer()
	local playing = SoundManager.IsMusicPlaying() and current.Music
	local now = os.clock()
	for index, bar in ipairs(equalizerBars) do
		local height = 4
		if playing then
			local wave = math.sin(now * (5 + index * 1.7) + index * 1.3) * 0.5 + 0.5
			local wave2 = math.sin(now * (2.3 + index * 0.9)) * 0.5 + 0.5
			height = 5 + math.floor((wave * 0.7 + wave2 * 0.3) * 17)
		end
		bar.Size = UDim2.fromOffset(4, height)
	end
end

----------------------------------------------------------------------
-- Construction
----------------------------------------------------------------------

local function buildAudio(content: Instance)
	local section = buildSection(content, 1, "🔊", Locale.T("Audio"), Locale.T("Sound effects, music and click sound"), SECTION_AUDIO)

	-- Effets sonores : interrupteur + volume
	local soundRow, soundSubtitle = buildRow(section, 1, 96, "🔔", Locale.T("Sound effects"), SECTION_AUDIO)
	soundSubtitle.Text = Locale.T("Clicks, purchases, bonuses...")
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

	divider(section, 2)

	-- Musique : interrupteur + volume (morceau en cours dans le sous-titre)
	local musicRow, musicSubtitle = buildRow(section, 3, 96, "🎵", Locale.T("Lofi music"), Theme.Colors.Purple)
	musicInfo = musicSubtitle
	buildToggle(musicRow, "Music")
	sliders.Music = buildSlider(musicRow, SoundManager.GetMusicVolume(), Theme.Colors.Purple, function(value)
		SoundManager.SetMusicVolume(value)
	end)

	divider(section, 4)

	-- Son du clic (gros bouton)
	local clickHeader = UIUtil.Create("Frame", {
		Name = "ClickHeader",
		Size = UDim2.new(1, 0, 0, 40),
		BackgroundTransparency = 1,
		LayoutOrder = 5,
		Parent = section,
	})
	UIUtil.Label({
		Text = Locale.T("🖱️ Click sound"),
		Font = Theme.Fonts.Title,
		TextXAlignment = Enum.TextXAlignment.Left,
		Size = UDim2.new(1, -16, 0, 20),
		Position = UDim2.fromOffset(8, 2),
		MaxTextSize = 17,
		Parent = clickHeader,
	})
	UIUtil.Label({
		Text = Locale.T("▶ to listen, tap the card to choose"),
		TextColor3 = Theme.Colors.TextDim,
		TextXAlignment = Enum.TextXAlignment.Left,
		Size = UDim2.new(1, -16, 0, 15),
		Position = UDim2.fromOffset(8, 23),
		MaxTextSize = 13,
		Parent = clickHeader,
	})
	local clickGrid = UIUtil.Create("Frame", {
		Name = "ClickSounds",
		Size = UDim2.fromScale(1, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
		LayoutOrder = 6,
		Parent = section,
	})
	UIUtil.Create("UIPadding", {
		PaddingLeft = UDim.new(0, 4),
		PaddingRight = UDim.new(0, 4),
		PaddingTop = UDim.new(0, 2),
		PaddingBottom = UDim.new(0, 2),
		Parent = clickGrid,
	})
	UIUtil.Create("UIGridLayout", {
		CellSize = UDim2.new(1 / 3, -7, 0, 54),
		CellPadding = UDim2.fromOffset(10, 10),
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = clickGrid,
	})
	for index, entry in ipairs(Config.ClickSounds or {}) do
		if type(entry) == "table" and type(entry.Id) == "string" then
			buildClickOption(clickGrid, entry, index)
		end
	end
	paintClickOptions()
	SoundManager.ClickSoundChanged:Connect(paintClickOptions)
end

local function buildDisplay(content: Instance)
	local section = buildSection(content, 2, "🖥️", Locale.T("Display"), Locale.T("What moves on screen"), SECTION_DISPLAY)
	local fxRow, fxSubtitle = buildRow(section, 1, 60, "✨", Locale.T("Particles and confetti"), SECTION_DISPLAY)
	fxSubtitle.Text = Locale.T("Turn off for a calmer screen")
	buildToggle(fxRow, "Effects")

	divider(section, 2)

	-- Mode sombre (appliqué tout de suite, sauvegardé avec la progression)
	local darkRow, darkSubtitle = buildRow(section, 3, 60, "🌙", Locale.T("Dark mode"), Theme.Colors.Dark)
	darkSubtitle.Text = Locale.T("Easier on the eyes at night")
	current.DarkMode = ClientState.IsUserDarkMode()
	buildToggle(darkRow, "DarkMode")
end

-- Sauvegarde de la langue (3 essais) ; la langue change au prochain passage
local function chooseLanguage(value: string)
	if table.find(LANGUAGE_OPTIONS, value) == nil then
		return
	end
	languageChosen = value
	languageSaveToken += 1
	local token = languageSaveToken
	languageSaving = true
	SoundManager.Play("Open", 1.1)
	-- Message dans la langue choisie (Auto : langue Roblox du joueur)
	local player = game:GetService("Players").LocalPlayer
	local target = Locale.Resolve(value, player and player.LocaleId or nil)
	if target == Locale.GetLanguage() then
		Notifications.Toast(Locale.TFor(target, "Language saved"), Theme.Colors.Blue, 3.5, nil, false, "🌐")
	else
		Notifications.Toast(Locale.TFor(target, "Language will change after rejoining"), Theme.Colors.Blue, 5, nil, false, "🌐")
	end
	task.spawn(function()
		for attempt = 1, 3 do
			if token ~= languageSaveToken then
				return
			end
			local ok, success = pcall(function()
				return Net.Function("SetSetting"):InvokeServer("Language", value)
			end)
			if ok and success == true then
				if token == languageSaveToken then
					languageSaving = false
				end
				return
			end
			if attempt < 3 then
				task.wait(0.3)
			end
		end
		if token == languageSaveToken then
			languageSaving = false
			languageChosen = nil
			Notifications.Toast(Locale.T("Couldn't save the language, try again."), Theme.Colors.Red)
			local tabs = languageTabs
			if tabs then
				tabs.Select(ClientState.GetLanguageSetting(), true)
			end
		end
	end)
end

local function buildLanguage(content: Instance)
	local section = buildSection(content, 3, "🌐", Locale.T("Language"), Locale.T("Applied the next time you join"), Theme.Colors.Cyan)
	local holder = UIUtil.Create("Frame", {
		Name = "LanguageRow",
		Size = UDim2.new(1, 0, 0, 52),
		BackgroundTransparency = 1,
		LayoutOrder = 1,
		Parent = section,
	})
	languageTabs = UIUtil.Tabs({
		Parent = holder,
		Tabs = {
			{ Id = "Auto", Text = Locale.T("🌐 Auto") },
			{ Id = "en", Text = "🇬🇧 English" },
			{ Id = "fr", Text = "🇫🇷 Français" },
		},
		Color = Theme.Colors.Cyan,
		Size = UDim2.new(1, -8, 0, Theme.TouchTarget),
		Position = UDim2.fromOffset(4, 4),
		TextSize = 16,
		Selected = ClientState.GetLanguageSetting(),
		OnSelect = chooseLanguage,
	})
end

local function buildGame(content: Instance)
	local section = buildSection(content, 4, "🎮", Locale.T("Game"), Locale.T("Now playing and credits"), SECTION_GAME)

	-- Carte "En cours de lecture"
	local nowPlaying = UIUtil.Create("Frame", {
		Name = "NowPlaying",
		Size = UDim2.new(1, 0, 0, 72),
		BackgroundColor3 = WHITE,
		LayoutOrder = 1,
		Parent = section,
	})
	UIUtil.Corner(nowPlaying, Theme.Radius.M)
	UIUtil.Stroke(nowPlaying, Theme.Colors.Purple, 1.5, 0.6)
	UIUtil.Gradient(nowPlaying, ColorSequence.new(Color3.fromRGB(246, 238, 255), Color3.fromRGB(255, 240, 248)), 0)
	local cover = UIUtil.Create("Frame", {
		Name = "Cover",
		Size = UDim2.fromOffset(52, 52),
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 10, 0.5, 0),
		BackgroundColor3 = WHITE,
		Parent = nowPlaying,
	})
	UIUtil.Corner(cover, Theme.Radius.M)
	UIUtil.Gradient(cover, ColorSequence.new(Theme.Colors.Purple, Theme.Colors.Pink), 45)
	UIUtil.Label({
		Text = "🎧",
		Size = UDim2.new(1, -16, 1, -16),
		Position = UDim2.fromOffset(8, 8),
		MaxTextSize = 26,
		Parent = cover,
	})
	nowPlayingStatus = UIUtil.Label({
		Name = "Status",
		Font = Theme.Fonts.Title,
		TextColor3 = Theme.Colors.Purple,
		TextXAlignment = Enum.TextXAlignment.Left,
		Size = UDim2.new(1, -190, 0, 14),
		Position = UDim2.fromOffset(74, 14),
		MaxTextSize = 12,
		Parent = nowPlaying,
	})
	nowPlayingLabel = UIUtil.Label({
		Name = "Track",
		Font = Theme.Fonts.Title,
		TextXAlignment = Enum.TextXAlignment.Left,
		Size = UDim2.new(1, -190, 0, 22),
		Position = UDim2.fromOffset(74, 32),
		MaxTextSize = 18,
		Parent = nowPlaying,
	})
	-- Égaliseur (4 barres) à droite du titre
	local equalizer = UIUtil.Create("Frame", {
		Name = "Equalizer",
		Size = UDim2.fromOffset(34, 24),
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -62, 0.5, 0),
		BackgroundTransparency = 1,
		Parent = nowPlaying,
	})
	UIUtil.Create("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		VerticalAlignment = Enum.VerticalAlignment.Bottom,
		Padding = UDim.new(0, 4),
		Parent = equalizer,
	})
	table.clear(equalizerBars)
	for index = 1, 4 do
		local bar = UIUtil.Create("Frame", {
			Name = "Bar" .. index,
			Size = UDim2.fromOffset(4, 4),
			BackgroundColor3 = Theme.Colors.Purple:Lerp(Theme.Colors.Pink, (index - 1) / 3),
			BorderSizePixel = 0,
			LayoutOrder = index,
			Parent = equalizer,
		})
		UIUtil.Corner(bar, 2)
		table.insert(equalizerBars, bar)
	end
	local skip = UIUtil.Create("TextButton", {
		Name = "Next",
		Size = UDim2.fromOffset(40, 40),
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -12, 0.5, 0),
		BackgroundColor3 = WHITE,
		AutoButtonColor = false,
		Font = Theme.Fonts.Title,
		Text = "⏭",
		TextColor3 = Theme.Colors.Text,
		TextSize = 18,
		Visible = false,
		Parent = nowPlaying,
	})
	UIUtil.Corner(skip, UDim.new(1, 0))
	UIUtil.Stroke(skip, Theme.Colors.Purple, 1.5, 0.3)
	UIUtil.AnimateButton(skip)
	skip.Activated:Connect(function()
		if SoundManager.NextTrack() then
			SoundManager.Play("Open", 1.2)
		end
	end)
	nextButton = skip

	-- Crédits et version
	local credits = UIUtil.Create("Frame", {
		Name = "Credits",
		Size = UDim2.new(1, 0, 0, 64),
		BackgroundTransparency = 1,
		LayoutOrder = 2,
		Parent = section,
	})
	local logo = UIUtil.Create("Frame", {
		Size = UDim2.fromOffset(44, 44),
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 14, 0.5, 0),
		BackgroundColor3 = WHITE,
		Parent = credits,
	})
	UIUtil.Corner(logo, UDim.new(1, 0))
	UIUtil.Stroke(logo, SECTION_GAME, 1.5, 0.4)
	UIUtil.SoftGradient(logo, Theme.Colors.Pink, 90)
	UIUtil.Label({
		Text = "🧠",
		Size = UDim2.new(1, -12, 1, -12),
		Position = UDim2.fromOffset(6, 6),
		MaxTextSize = 24,
		Parent = logo,
	})
	UIUtil.Label({
		Text = "Dopamine Clicker",
		Font = Theme.Fonts.Title,
		TextXAlignment = Enum.TextXAlignment.Left,
		Size = UDim2.new(1, -170, 0, 20),
		Position = UDim2.fromOffset(70, 12),
		MaxTextSize = 17,
		Parent = credits,
	})
	UIUtil.Label({
		Text = Locale.T("A Roblox game  •  thanks for playing 💙"),
		TextColor3 = Theme.Colors.TextDim,
		TextXAlignment = Enum.TextXAlignment.Left,
		Size = UDim2.new(1, -170, 0, 16),
		Position = UDim2.fromOffset(70, 34),
		MaxTextSize = 13,
		Parent = credits,
	})
	local versionChip = UIUtil.Chip({
		Name = "Version",
		Text = Locale.T("Version %s", VERSION),
		Color = SECTION_GAME,
		TextColor3 = Theme.Colors.TextLight,
		Height = 26,
		TextSize = 13,
		Parent = credits,
	})
	versionChip.AnchorPoint = Vector2.new(1, 0.5)
	versionChip.Position = UDim2.new(1, -12, 0.5, 0)
end

function Settings.Build(panel: Frame)
	-- Contenu défilant (tout ne tient pas toujours en hauteur)
	local content = UIUtil.Create("ScrollingFrame", {
		Name = "Scroll",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 5,
		ScrollBarImageColor3 = Theme.Colors.Dark,
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollingDirection = Enum.ScrollingDirection.Y,
		Parent = panel,
	})
	UIUtil.Create("UIPadding", {
		PaddingTop = UDim.new(0, 2),
		PaddingLeft = UDim.new(0, 2),
		PaddingRight = UDim.new(0, 12),
		PaddingBottom = UDim.new(0, 8),
		Parent = content,
	})
	UIUtil.Create("UIListLayout", {
		Padding = UDim.new(0, 12),
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = content,
	})

	buildAudio(content)
	buildDisplay(content)
	buildLanguage(content)
	buildGame(content)

	UIUtil.Create("TextLabel", {
		Name = "Tip",
		Text = Locale.T("Tip: every upgrade adds something to the screen. How far will you go?"),
		TextColor3 = Theme.Colors.TextDim,
		BackgroundTransparency = 1,
		Font = Theme.Fonts.Body,
		TextSize = 14,
		TextWrapped = true,
		Size = UDim2.new(1, 0, 0, 30),
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
	stepEqualizer()
end

function Settings.OnOpen()
	refreshMusicInfo()
	-- Égaliseur animé seulement quand la fenêtre est ouverte
	if not equalizerConnection then
		equalizerConnection = RunService.Heartbeat:Connect(stepEqualizer)
	end
end

function Settings.OnClose()
	local connection = equalizerConnection
	if connection then
		connection:Disconnect()
		equalizerConnection = nil
	end
end

-- Au chargement, on applique les réglages sauvegardés (une seule fois) ;
-- le son du clic suit ensuite l'état du serveur (sauf pendant une sauvegarde)
local applied = false
function Settings.Update(data)
	if type(data) ~= "table" or type(data.Settings) ~= "table" then
		return
	end
	if not applied then
		applied = true
		for _, key in ipairs({ "Sound", "Music", "Effects" }) do
			Settings.Apply(key, data.Settings[key] ~= false)
		end
	end
	-- Mode sombre : appliqué par ClientState, on recale juste l'interrupteur
	local dark = ClientState.IsUserDarkMode()
	if current.DarkMode ~= dark then
		current.DarkMode = dark
		local ui = toggles.DarkMode
		if ui then
			paintToggle(ui, dark, true)
		end
	end
	-- Langue sauvegardée (sauf pendant une sauvegarde)
	local tabs = languageTabs
	if tabs and not languageSaving then
		local saved = ClientState.GetLanguageSetting()
		if languageChosen == nil or languageChosen == saved then
			languageChosen = nil
			if tabs.GetSelected() ~= saved then
				tabs.Select(saved, true)
			end
		end
	end
	local clickSound = data.Settings.ClickSound
	if not clickSaving and type(clickSound) == "string" and clickSound ~= SoundManager.GetClickSound() then
		SoundManager.SetClickSound(clickSound)
	end
end

return Settings
