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

	v8 — 🎧 lecteur de musique (section "Musique lofi") :
	- carte "platine" : vinyle qui tourne, titre du morceau, état (en cours,
	  en pause, verrouillé), petit visualiseur animé (volume réel du morceau
	  via PlaybackLoudness quand il est disponible), boutons ⏮ ⏯ ⏭
	  (⏯ = réglage "Musique" sauvegardé) ;
	- interrupteur + volume de la musique (inchangés) ;
	- liste des morceaux (Config.Music.Playlist) : « 🔀 Aléatoire » ou un
	  morceau précis (joué en boucle), ✓ sur le choix actuel. Le choix est
	  appliqué et sauvegardé par SoundManager.SetMusicTrack
	  (SetSetting "MusicTrack") ;
	- animations seulement quand la fenêtre est ouverte (30 images/s max).
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

local VERSION = "v8"
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

type Toggle = { Button: TextButton, Knob: Frame, Stroke: UIStroke, OnIcon: Frame, OffIcon: Frame }
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
local equalizerConnection: RBXScriptConnection? = nil

-- Lecteur de musique (v8)
type Player = {
	Card: Frame,
	Vinyl: Frame,
	VinylLabel: Frame,
	VinylGradient: UIGradient,
	VinylIcon: TextLabel,
	Arm: Frame,
	Status: TextLabel,
	StatusDot: Frame,
	Title: TextLabel,
	Meta: TextLabel,
	Bars: { Frame },
	Play: TextButton,
	Prev: TextButton,
	Next: TextButton,
}
type TrackRow = {
	Key: string,
	Card: TextButton,
	Stroke: UIStroke,
	Check: Frame,
	Name: TextLabel,
	Sub: TextLabel,
	Eq: { Frame },
	Hovered: boolean,
}
local player: Player? = nil
local trackRows: { TrackRow } = {}
local lockBanner: Frame? = nil
local vinylAngle = 0
local barLevels: { number } = {}
local animClock = 0

-- Pochettes des morceaux (par Key ; les autres ont une pochette générique)
local TRACK_ART = {
	Lofi1 = { Icon = "🌧️", A = Color3.fromRGB(96, 140, 220), B = Color3.fromRGB(58, 70, 140) },
	Lofi2 = { Icon = "📚", A = Color3.fromRGB(255, 176, 92), B = Color3.fromRGB(170, 84, 60) },
	Lofi3 = { Icon = "☕", A = Color3.fromRGB(214, 170, 130), B = Color3.fromRGB(120, 84, 70) },
	Lofi4 = { Icon = "🐱", A = Color3.fromRGB(255, 170, 200), B = Color3.fromRGB(170, 90, 170) },
	Lofi5 = { Icon = "🌅", A = Color3.fromRGB(255, 150, 120), B = Color3.fromRGB(200, 70, 130) },
	Lofi6 = { Icon = "🚆", A = Color3.fromRGB(110, 110, 200), B = Color3.fromRGB(34, 36, 90) },
	Lofi7 = { Icon = "🧣", A = Color3.fromRGB(240, 120, 110), B = Color3.fromRGB(140, 60, 90) },
	Lofi8 = { Icon = "✨", A = Color3.fromRGB(150, 110, 255), B = Color3.fromRGB(40, 30, 110) },
}
local SHUFFLE_ART = { Icon = "🔀", A = Color3.fromRGB(255, 120, 200), B = Color3.fromRGB(120, 70, 230) }
local PLAYER_TOP = Color3.fromRGB(46, 28, 86)
local PLAYER_BOTTOM = Color3.fromRGB(22, 18, 48)
local PLAYER_ACCENT = Color3.fromRGB(255, 120, 200)
local PLAYER_ACCENT2 = Color3.fromRGB(110, 220, 255)
local LAVENDER = Color3.fromRGB(200, 188, 240)
local MUSIC_SOFT = Color3.fromRGB(245, 238, 255)
local BAR_COUNT = 18

local function artFor(key: string?, index: number?)
	if key and TRACK_ART[key] then
		return TRACK_ART[key]
	end
	local keys = { "Lofi1", "Lofi2", "Lofi3", "Lofi4", "Lofi5", "Lofi6", "Lofi7", "Lofi8" }
	local fallback = TRACK_ART[keys[((index or 1) - 1) % #keys + 1]]
	return { Icon = "🎵", A = fallback.A, B = fallback.B }
end

-- Son du clic
type ClickOption = { Id: string, Card: TextButton, Stroke: UIStroke, Check: Frame, Name: TextLabel, Hovered: boolean }
local clickOptions: { ClickOption } = {}
local clickSaveToken = 0 -- change à chaque choix (annule les sauvegardes périmées)
local clickSaving = false -- une sauvegarde est en cours (on ne recale pas sur l'état serveur)

----------------------------------------------------------------------
-- Réglages
----------------------------------------------------------------------

-- Majuscules qui gardent les accents (string.upper ne touche pas à "é")
local ACCENTS = { ["é"] = "É", ["è"] = "È", ["ê"] = "Ê", ["ë"] = "Ë", ["à"] = "À", ["â"] = "Â", ["ç"] = "Ç",
	["î"] = "Î", ["ï"] = "Ï", ["ô"] = "Ô", ["ù"] = "Ù", ["û"] = "Û" }
local function upper(text: string): string
	local result = string.upper(text)
	for small, big in pairs(ACCENTS) do
		result = string.gsub(result, small, big)
	end
	return result
end

-- Infos du lecteur (fonction de repli si SoundManager n'a pas GetMusicInfo)
local function getMusicInfo(): { [string]: any }?
	if type(SoundManager.GetMusicInfo) == "function" then
		return SoundManager.GetMusicInfo()
	end
	return nil
end

local function getMusicMode(): string
	if type(SoundManager.GetMusicMode) == "function" then
		return SoundManager.GetMusicMode()
	end
	return "Shuffle"
end

-- Coche / survol de la liste des morceaux
local function paintTracks()
	local mode = getMusicMode()
	local info = getMusicInfo()
	local playingKey = info and info.Playing and info.Key or nil
	for _, row in ipairs(trackRows) do
		local selected = row.Key == mode
		local isPlaying = row.Key ~= "Shuffle" and row.Key == playingKey
		row.Card.BackgroundColor3 = selected and MUSIC_SOFT or (row.Hovered and ROW_HOVER or Theme.Colors.Card)
		row.Stroke.Color = (selected or row.Hovered) and Theme.Colors.Purple or ROW_BORDER
		row.Stroke.Thickness = selected and 2 or 1.5
		row.Stroke.Transparency = (row.Hovered and not selected) and 0.45 or 0
		row.Name.TextColor3 = selected and Theme.Colors.Purple:Lerp(BLACK, 0.25) or Theme.Colors.Text
		if row.Check.Visible ~= selected then
			row.Check.Visible = selected
			if selected then
				UIUtil.Pop(row.Check, 0.3, 0.35)
			end
		end
		local showEq = isPlaying and not selected
		for _, bar in ipairs(row.Eq) do
			bar.Visible = isPlaying
		end
		-- (morceau choisi ET en cours : la coche reste, l'égaliseur passe à côté)
		if row.Eq[1] then
			local holder = row.Eq[1].Parent :: GuiObject
			holder.Position = showEq and UDim2.new(1, -14, 0.5, 0) or UDim2.new(1, -46, 0.5, 0)
		end
	end
end

-- Textes de la musique : morceau en cours, verrou Lofi, playlist vide...
local function refreshMusicInfo()
	local info = getMusicInfo()
	local name = info and info.Name or SoundManager.GetCurrentTrack()
	local playing = SoundManager.IsMusicPlaying()
	local locked = not ClientState.HasFeature("Lofi")
	local text
	local status
	if locked then
		text = Locale.T("🔒 Unlocks with 🎧 %s", Locale.T("Lofi Beats"))
		status = Locale.T("Locked")
	elseif not SoundManager.HasPlaylist() then
		text = RunService:IsStudio() and Locale.T("⚠️ Add music IDs in Config.Music") or Locale.T("No music for now")
		status = Locale.T("Empty playlist")
	elseif not current.Music then
		text = Locale.T("Music off")
		status = Locale.T("Paused")
	elseif playing and name then
		text = "🎵 " .. name
		status = Locale.T("🎶 Now playing")
	else
		text = Locale.T("Loading...")
		status = Locale.T("Loading")
	end
	local label = musicInfo
	if label then
		label.Text = text
	end
	local ui = player
	if ui then
		ui.Status.Text = upper(status)
		local live = playing and current.Music and not locked
		ui.StatusDot.BackgroundColor3 = live and Color3.fromRGB(90, 240, 150) or (locked and Theme.Colors.Orange or LAVENDER)
		-- Titre : morceau en cours, sinon le choix (ou le message)
		local mode = getMusicMode()
		local title = name
		if not title and mode ~= "Shuffle" and type(SoundManager.GetPlaylist) == "function" then
			for _, track in ipairs(SoundManager.GetPlaylist()) do
				if track.Key == mode then
					title = track.Name
				end
			end
		end
		if locked then
			ui.Title.Text = Locale.T("Unlocks with 🎧 %s", Locale.T("Lofi Beats"))
		else
			ui.Title.Text = title or text
		end
		local count = info and info.Count or 0
		local index = info and info.Index or 0
		local modeText = mode == "Shuffle" and Locale.T("🔀 Shuffle") or Locale.T("🔁 Loop")
		if count > 0 and index > 0 then
			ui.Meta.Text = Locale.T("Track %d of %d", index, count) .. "  •  " .. modeText
		else
			ui.Meta.Text = modeText
		end
		local art = mode == "Shuffle" and not (info and info.Key) and SHUFFLE_ART or artFor(info and info.Key or mode, index)
		ui.VinylGradient.Color = ColorSequence.new(art.A, art.B)
		ui.VinylIcon.Text = locked and "🔒" or art.Icon
		-- (icônes dessinées : pause pendant la lecture, sinon lecture)
		local showPause = current.Music == true and not locked
		local pauseIcon = ui.Play:FindFirstChild("IconPause")
		local playIcon = ui.Play:FindFirstChild("IconPlay")
		if pauseIcon and playIcon and pauseIcon:IsA("GuiObject") and playIcon:IsA("GuiObject") then
			pauseIcon.Visible = showPause
			playIcon.Visible = not showPause
			UIUtil.SetIconTransparency(pauseIcon, locked and 0.5 or 0)
			UIUtil.SetIconTransparency(playIcon, locked and 0.5 or 0)
		end
		local canSkip = not locked and SoundManager.HasPlaylist()
		for _, button in ipairs({ ui.Prev, ui.Next }) do
			local icon = button:FindFirstChild("IconPrev") or button:FindFirstChild("IconNext")
			if icon then
				UIUtil.SetIconTransparency(icon, canSkip and 0 or 0.6)
			end
			button.BackgroundTransparency = canSkip and 0.82 or 0.92
		end
		UIUtil.Tween(ui.Arm, 0.5, { Rotation = live and 28 or 8 }, Enum.EasingStyle.Sine)
	end
	local banner = lockBanner
	if banner then
		banner.Visible = locked
	end
	paintTracks()
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
	-- Coche / croix DESSINÉES dans le bouton rond (plus de ✓ / ✕ en texte)
	ui.OnIcon.Visible = value
	ui.OffIcon.Visible = not value
	UIUtil.SetIconColor(value and ui.OnIcon or ui.OffIcon, (value and ON_COLOR or OFF_COLOR):Lerp(BLACK, 0.2))
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

	-- Bouton "écouter sans choisir" (triangle dessiné)
	local play = UIUtil.Create("TextButton", {
		Name = "Preview",
		Size = UDim2.fromOffset(34, 34),
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 10, 0.5, 0),
		BackgroundColor3 = WHITE,
		AutoButtonColor = false,
		Font = Theme.Fonts.Title,
		Text = "",
		TextColor3 = Theme.Colors.TextLight,
		TextSize = 14,
		ZIndex = 2,
		Parent = card,
	})
	local playIcon = UIUtil.Icon("Play", { Name = "IconPlay", Size = 14, Color = Theme.Colors.TextLight, ZIndex = 3, Parent = play })
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
		play.Text = "🎵"
		playIcon.Visible = false
		task.delay(0.45, function()
			if token == previewToken then
				play.Text = ""
				playIcon.Visible = true
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
	UIUtil.Icon("Check", { Size = 14, Thickness = 3, Color = Theme.Colors.TextLight, ZIndex = 3, Parent = check })

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
	local onIcon = UIUtil.Icon("Check", { Name = "OnIcon", Size = 13, Thickness = 3, Color = ON_COLOR, ZIndex = 3, Parent = knob })
	local offIcon = UIUtil.Icon("Cross", { Name = "OffIcon", Size = 10, Thickness = 3, Color = OFF_COLOR, ZIndex = 3, Parent = knob })
	UIUtil.AnimateButton(button, 1.06, 0.93)
	local ui: Toggle = { Button = button, Knob = knob, Stroke = stroke, OnIcon = onIcon, OffIcon = offIcon }
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

-- Animation du lecteur (vinyle, visualiseur, mini-égaliseurs de la liste) :
-- seulement fenêtre ouverte, 30 images/s max
local function stepPlayer(dt: number)
	animClock += dt
	if animClock < 1 / 30 then
		return
	end
	local step = math.min(animClock, 0.1)
	animClock = 0
	local ui = player
	if not ui then
		return
	end
	local live = SoundManager.IsMusicPlaying() and current.Music and ClientState.HasFeature("Lofi")
	-- Volume réel du morceau (0..1) quand Roblox le donne, sinon une vague douce
	local loudness = 0.55
	local _, sound = SoundManager.GetCurrentTrack()
	if sound then
		local ok, value = pcall(function()
			return (sound :: Sound).PlaybackLoudness
		end)
		if ok and type(value) == "number" and value > 0 then
			loudness = math.clamp(value / 420, 0.15, 1)
		end
	end
	if live then
		vinylAngle = (vinylAngle + step * 100) % 360 -- ~33 tours/min
		ui.Vinyl.Rotation = vinylAngle
	end
	local now = os.clock()
	for index, bar in ipairs(ui.Bars) do
		local target = 0.08
		if live then
			local w1 = math.sin(now * (4.2 + index * 0.37) + index * 1.9) * 0.5 + 0.5
			local w2 = math.sin(now * (1.7 + index * 0.21) + index * 0.6) * 0.5 + 0.5
			local shape = 1 - math.abs(index - BAR_COUNT * 0.4) / BAR_COUNT * 0.9 -- plus haut vers le milieu
			target = math.clamp((w1 * 0.65 + w2 * 0.35) * shape * (0.35 + loudness * 0.9), 0.08, 1)
		end
		local level = barLevels[index] or 0.08
		level += (target - level) * math.min(1, step * (target > level and 18 or 7))
		barLevels[index] = level
		bar.Size = UDim2.new(1 / BAR_COUNT, -3, level, 0)
	end
	-- Mini-égaliseur du morceau en cours dans la liste
	for _, row in ipairs(trackRows) do
		local first = row.Eq[1]
		if first and first.Visible then
			for index, bar in ipairs(row.Eq) do
				local wave = math.sin(now * (6 + index * 1.9) + index) * 0.5 + 0.5
				bar.Size = UDim2.fromOffset(3, live and (4 + math.floor(wave * 12)) or 4)
			end
		end
	end
end

----------------------------------------------------------------------
-- Construction
----------------------------------------------------------------------

local function buildAudio(content: Instance)
	local section = buildSection(content, 2, "🔊", Locale.T("Sounds"), Locale.T("Effects volume and click sound"), SECTION_AUDIO)

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
		Text = Locale.T("🎧 Round button = listen, card = choose"),
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
	local section = buildSection(content, 3, "🖥️", Locale.T("Display"), Locale.T("What moves on screen"), SECTION_DISPLAY)
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
	local section = buildSection(content, 4, "🌐", Locale.T("Language"), Locale.T("Applied the next time you join"), Theme.Colors.Cyan)
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

----------------------------------------------------------------------
-- 🎧 Lecteur de musique (v8)
----------------------------------------------------------------------

-- Bouton rond du lecteur (⏮ ⏯ ⏭)
-- `glyph` : icône dessinée ("Prev", "Next" ou "PlayPause" = pause + lecture)
local function playerButton(parent: Instance, name: string, glyph: string, size: number, x: number, filled: boolean, onActivated: () -> ()): TextButton
	local button = UIUtil.Create("TextButton", {
		Name = name,
		Size = UDim2.fromOffset(size, size),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(1, x, 0.5, 0),
		BackgroundColor3 = WHITE,
		BackgroundTransparency = filled and 0 or 0.82,
		AutoButtonColor = false,
		Text = "",
		ZIndex = 4,
		Parent = parent,
	})
	UIUtil.Corner(button, UDim.new(1, 0))
	local iconColor = filled and PLAYER_BOTTOM or WHITE
	if glyph == "PlayPause" then
		UIUtil.Icon("Pause", { Name = "IconPause", Size = math.floor(size * 0.36), Color = iconColor, ZIndex = 5, Parent = button })
		local playIcon = UIUtil.Icon("Play", { Name = "IconPlay", Size = math.floor(size * 0.42), Color = iconColor, ZIndex = 5, Parent = button })
		playIcon.Visible = false
	else
		UIUtil.Icon(glyph, { Name = "Icon" .. glyph, Size = math.floor(size * 0.46), Color = iconColor, ZIndex = 5, Parent = button })
	end
	UIUtil.Stroke(button, WHITE, filled and 0 or 1.5, filled and 1 or 0.55)
	if filled then
		UIUtil.Gradient(button, ColorSequence.new(WHITE, Color3.fromRGB(230, 222, 255)), 90)
	end
	UIUtil.AnimateButton(button, 1.08, 0.9)
	button.Activated:Connect(onActivated)
	-- Zone tactile d'au moins 44 px
	if size < Theme.TouchTarget then
		local hitbox = UIUtil.Create("TextButton", {
			Name = "Hitbox",
			Size = UDim2.fromOffset(Theme.TouchTarget, Theme.TouchTarget),
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			BackgroundTransparency = 1,
			Text = "",
			ZIndex = 5,
			Parent = button,
		})
		hitbox.Activated:Connect(onActivated)
	end
	return button
end

local function buildPlayerCard(section: Frame)
	local card = UIUtil.Create("Frame", {
		Name = "Player",
		Size = UDim2.new(1, 0, 0, 132),
		BackgroundColor3 = WHITE,
		LayoutOrder = 1,
		ClipsDescendants = true,
		Parent = section,
	})
	card:SetAttribute("DarkSkinIgnore", true) -- déjà sombre
	UIUtil.Corner(card, Theme.Radius.L)
	UIUtil.Stroke(card, Color3.fromRGB(120, 80, 200), 1.5, 0.3)
	UIUtil.Gradient(card, ColorSequence.new({
		ColorSequenceKeypoint.new(0, PLAYER_TOP),
		ColorSequenceKeypoint.new(1, PLAYER_BOTTOM),
	}), 110)
	-- Lueurs douces (décor)
	for _, glow in ipairs({ { -40, -60, 200, PLAYER_ACCENT, 0.86 }, { 380, 50, 260, PLAYER_ACCENT2, 0.9 } }) do
		local blob = UIUtil.Create("Frame", {
			Size = UDim2.fromOffset(glow[3], glow[3]),
			Position = UDim2.fromOffset(glow[1], glow[2]),
			BackgroundColor3 = glow[4],
			BackgroundTransparency = glow[5],
			BorderSizePixel = 0,
			ZIndex = 1,
			Parent = card,
		})
		UIUtil.Corner(blob, UDim.new(1, 0))
		UIUtil.Create("UIGradient", {
			Transparency = NumberSequence.new({
				NumberSequenceKeypoint.new(0, 0),
				NumberSequenceKeypoint.new(0.7, 0.5),
				NumberSequenceKeypoint.new(1, 1),
			}),
			Parent = blob,
		})
	end

	-- Vinyle (tourne quand la musique joue)
	local deck = UIUtil.Create("Frame", {
		Name = "Deck",
		Size = UDim2.fromOffset(108, 108),
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 16, 0.5, 0),
		BackgroundTransparency = 1,
		ZIndex = 2,
		Parent = card,
	})
	local vinyl = UIUtil.Create("Frame", {
		Name = "Vinyl",
		Size = UDim2.fromOffset(94, 94),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		BackgroundColor3 = Color3.fromRGB(18, 16, 24),
		ZIndex = 2,
		Parent = deck,
	})
	UIUtil.Corner(vinyl, UDim.new(1, 0))
	UIUtil.Stroke(vinyl, Color3.fromRGB(0, 0, 0), 2, 0.2)
	-- Sillons
	for _, ratio in ipairs({ 0.9, 0.78, 0.66 }) do
		local groove = UIUtil.Create("Frame", {
			Size = UDim2.fromScale(ratio, ratio),
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			BackgroundTransparency = 1,
			ZIndex = 3,
			Parent = vinyl,
		})
		UIUtil.Corner(groove, UDim.new(1, 0))
		UIUtil.Stroke(groove, Color3.fromRGB(70, 64, 90), 1, 0.35)
	end
	-- Reflet (bande claire qui "tourne" avec le disque)
	local sheen = UIUtil.Create("Frame", {
		Size = UDim2.fromScale(0.96, 0.96),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		BackgroundColor3 = WHITE,
		BackgroundTransparency = 0,
		ZIndex = 3,
		Parent = vinyl,
	})
	UIUtil.Corner(sheen, UDim.new(1, 0))
	UIUtil.Create("UIGradient", {
		Rotation = 35,
		Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 1),
			NumberSequenceKeypoint.new(0.38, 1),
			NumberSequenceKeypoint.new(0.47, 0.82),
			NumberSequenceKeypoint.new(0.53, 0.82),
			NumberSequenceKeypoint.new(0.62, 1),
			NumberSequenceKeypoint.new(1, 1),
		}),
		Parent = sheen,
	})
	-- Étiquette centrale (couleurs de la pochette)
	local label = UIUtil.Create("Frame", {
		Name = "Label",
		Size = UDim2.fromScale(0.42, 0.42),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		BackgroundColor3 = WHITE,
		ZIndex = 4,
		Parent = vinyl,
	})
	UIUtil.Corner(label, UDim.new(1, 0))
	local labelGradient = UIUtil.Gradient(label, ColorSequence.new(PLAYER_ACCENT, Theme.Colors.Purple), 45)
	local icon = UIUtil.Label({
		Name = "Icon",
		Text = "🎵",
		Size = UDim2.fromScale(0.66, 0.66),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 0.5, -3),
		MaxTextSize = 22,
		ZIndex = 5,
		Parent = label,
	})
	local spindle = UIUtil.Create("Frame", {
		Size = UDim2.fromOffset(5, 5),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 0.5, 11),
		BackgroundColor3 = Color3.fromRGB(20, 18, 26),
		ZIndex = 6,
		Parent = label,
	})
	UIUtil.Corner(spindle, UDim.new(1, 0))
	-- Bras de lecture (pivot en haut à droite du disque)
	local armPivot = UIUtil.Create("Frame", {
		Name = "ArmPivot",
		Size = UDim2.fromOffset(12, 12),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(1, -4, 0, 8),
		BackgroundColor3 = Color3.fromRGB(210, 210, 225),
		ZIndex = 7,
		Parent = deck,
	})
	UIUtil.Corner(armPivot, UDim.new(1, 0))
	UIUtil.Stroke(armPivot, Color3.fromRGB(60, 56, 80), 1.5, 0)
	local arm = UIUtil.Create("Frame", {
		Name = "Arm",
		Size = UDim2.fromOffset(4, 104),
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromScale(0.5, 0.5),
		BackgroundTransparency = 1,
		Rotation = 8,
		ZIndex = 6,
		Parent = armPivot,
	})
	local armRod = UIUtil.Create("Frame", {
		Size = UDim2.new(0, 3, 0, 58),
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromScale(0.5, 0),
		BackgroundColor3 = Color3.fromRGB(215, 215, 230),
		BorderSizePixel = 0,
		ZIndex = 6,
		Parent = arm,
	})
	UIUtil.Corner(armRod, UDim.new(1, 0))
	local head = UIUtil.Create("Frame", {
		Size = UDim2.fromOffset(9, 14),
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromOffset(2, 56),
		BackgroundColor3 = Color3.fromRGB(240, 240, 250),
		ZIndex = 7,
		Parent = arm,
	})
	UIUtil.Corner(head, 3)
	UIUtil.Stroke(head, Color3.fromRGB(60, 56, 80), 1, 0.2)

	-- Textes
	local textLeft = 142
	local status = UIUtil.Label({
		Name = "Status",
		Font = Theme.Fonts.Title,
		Text = "",
		TextColor3 = LAVENDER,
		TextXAlignment = Enum.TextXAlignment.Left,
		Size = UDim2.new(1, -(textLeft + 190), 0, 14),
		Position = UDim2.fromOffset(textLeft + 14, 18),
		MaxTextSize = 12,
		ZIndex = 3,
		Parent = card,
	})
	local dot = UIUtil.Create("Frame", {
		Name = "Live",
		Size = UDim2.fromOffset(8, 8),
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.fromOffset(textLeft, 25),
		BackgroundColor3 = Color3.fromRGB(90, 240, 150),
		ZIndex = 3,
		Parent = card,
	})
	UIUtil.Corner(dot, UDim.new(1, 0))
	local title = UIUtil.Label({
		Name = "Title",
		Font = Theme.Fonts.Title,
		Text = "",
		TextColor3 = WHITE,
		TextXAlignment = Enum.TextXAlignment.Left,
		Size = UDim2.new(1, -(textLeft + 176), 0, 26),
		Position = UDim2.fromOffset(textLeft, 34),
		MaxTextSize = 23,
		ZIndex = 3,
		Parent = card,
	})
	local meta = UIUtil.Label({
		Name = "Meta",
		Text = "",
		TextColor3 = LAVENDER,
		TextXAlignment = Enum.TextXAlignment.Left,
		Size = UDim2.new(1, -(textLeft + 176), 0, 16),
		Position = UDim2.fromOffset(textLeft, 62),
		MaxTextSize = 14,
		ZIndex = 3,
		Parent = card,
	})
	-- Visualiseur (barres en bas, du milieu vers les bords)
	local viz = UIUtil.Create("Frame", {
		Name = "Visualizer",
		Size = UDim2.new(1, -(textLeft + 176), 0, 30),
		Position = UDim2.fromOffset(textLeft, 86),
		BackgroundTransparency = 1,
		ZIndex = 3,
		Parent = card,
	})
	UIUtil.Create("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		VerticalAlignment = Enum.VerticalAlignment.Bottom,
		HorizontalAlignment = Enum.HorizontalAlignment.Left,
		Padding = UDim.new(0, 3),
		Parent = viz,
	})
	local bars = {}
	for index = 1, BAR_COUNT do
		local bar = UIUtil.Create("Frame", {
			Name = "Bar" .. index,
			Size = UDim2.new(1 / BAR_COUNT, -3, 0.08, 0),
			BackgroundColor3 = PLAYER_ACCENT:Lerp(PLAYER_ACCENT2, (index - 1) / (BAR_COUNT - 1)),
			BorderSizePixel = 0,
			LayoutOrder = index,
			ZIndex = 3,
			Parent = viz,
		})
		UIUtil.Corner(bar, 2)
		UIUtil.Create("UIGradient", {
			Rotation = 90,
			Transparency = NumberSequence.new(0, 0.35),
			Parent = bar,
		})
		table.insert(bars, bar)
		barLevels[index] = 0.08
	end

	-- Commandes précédent / lecture-pause / suivant (icônes dessinées)
	local prev = playerButton(card, "Previous", "Prev", 40, -146, false, function()
		if type(SoundManager.PreviousTrack) == "function" and SoundManager.PreviousTrack() then
			SoundManager.Play("Open", 1.1)
		end
	end)
	local play = playerButton(card, "PlayPause", "PlayPause", 56, -92, true, function()
		if not ClientState.HasFeature("Lofi") then
			Notifications.Toast(Locale.T("🔒 Unlocks with 🎧 %s", Locale.T("Lofi Beats")), Theme.Colors.Purple)
			return
		end
		local newValue = not current.Music
		Settings.Apply("Music", newValue)
		SoundManager.Play("Open", newValue and 1.3 or 0.8)
		saveSetting("Music", newValue)
	end)
	local nextButton = playerButton(card, "Next", "Next", 40, -38, false, function()
		if SoundManager.NextTrack() then
			SoundManager.Play("Open", 1.25)
		end
	end)

	player = {
		Card = card,
		Vinyl = vinyl,
		VinylLabel = label,
		VinylGradient = labelGradient,
		VinylIcon = icon,
		Arm = arm,
		Status = status,
		StatusDot = dot,
		Title = title,
		Meta = meta,
		Bars = bars,
		Play = play,
		Prev = prev,
		Next = nextButton,
	}
end

-- Carte d'un morceau de la liste (ou "Aléatoire" si key == "Shuffle")
local function buildTrackCard(parent: Instance, key: string, name: string, subtitle: string, art, order: number, wide: boolean)
	local card = UIUtil.Create("TextButton", {
		Name = "Track_" .. key,
		Size = wide and UDim2.new(1, 0, 0, 56) or UDim2.new(),
		BackgroundColor3 = Theme.Colors.Card,
		AutoButtonColor = false,
		Text = "",
		LayoutOrder = order,
		Parent = parent,
	})
	UIUtil.Corner(card, Theme.Radius.M)
	local stroke = UIUtil.Stroke(card, ROW_BORDER, 1.5)
	UIUtil.AnimateButton(card, 1.02, 0.97)

	local cover = UIUtil.Create("Frame", {
		Name = "Cover",
		Size = UDim2.fromOffset(40, 40),
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 8, 0.5, 0),
		BackgroundColor3 = WHITE,
		ZIndex = 2,
		Parent = card,
	})
	cover:SetAttribute("DarkSkinIgnore", true)
	UIUtil.Corner(cover, Theme.Radius.M)
	UIUtil.Gradient(cover, ColorSequence.new(art.A, art.B), 45)
	UIUtil.Label({
		Text = art.Icon,
		Size = UDim2.new(1, -12, 1, -12),
		Position = UDim2.fromOffset(6, 6),
		MaxTextSize = 22,
		ZIndex = 3,
		Parent = cover,
	})
	local nameLabel = UIUtil.Label({
		Name = "TrackName",
		Text = name,
		Font = Theme.Fonts.Title,
		TextXAlignment = Enum.TextXAlignment.Left,
		Size = UDim2.new(1, -110, 0, 20),
		Position = UDim2.fromOffset(58, 8),
		MaxTextSize = 16,
		ZIndex = 2,
		Parent = card,
	})
	local sub = UIUtil.Label({
		Name = "Sub",
		Text = subtitle,
		TextColor3 = Theme.Colors.TextDim,
		TextXAlignment = Enum.TextXAlignment.Left,
		Size = UDim2.new(1, -110, 0, 15),
		Position = UDim2.fromOffset(58, 30),
		MaxTextSize = 13,
		ZIndex = 2,
		Parent = card,
	})
	-- Coche du choix actuel
	local check = UIUtil.Create("Frame", {
		Name = "Check",
		Size = UDim2.fromOffset(24, 24),
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -10, 0.5, 0),
		BackgroundColor3 = Theme.Colors.Purple,
		Visible = false,
		ZIndex = 2,
		Parent = card,
	})
	UIUtil.Corner(check, UDim.new(1, 0))
	UIUtil.Icon("Check", { Size = 14, Thickness = 3, Color = Theme.Colors.TextLight, ZIndex = 3, Parent = check })
	-- Mini-égaliseur "en cours"
	local eqHolder = UIUtil.Create("Frame", {
		Name = "Eq",
		Size = UDim2.fromOffset(18, 16),
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -14, 0.5, 0),
		BackgroundTransparency = 1,
		ZIndex = 2,
		Parent = card,
	})
	UIUtil.Create("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		VerticalAlignment = Enum.VerticalAlignment.Bottom,
		Padding = UDim.new(0, 2),
		Parent = eqHolder,
	})
	local eq = {}
	for index = 1, 4 do
		local bar = UIUtil.Create("Frame", {
			Size = UDim2.fromOffset(3, 4),
			BackgroundColor3 = Theme.Colors.Purple:Lerp(Theme.Colors.Pink, (index - 1) / 3),
			BorderSizePixel = 0,
			LayoutOrder = index,
			Visible = false,
			ZIndex = 2,
			Parent = eqHolder,
		})
		UIUtil.Corner(bar, 1)
		table.insert(eq, bar)
	end

	local row: TrackRow = { Key = key, Card = card, Stroke = stroke, Check = check, Name = nameLabel, Sub = sub, Eq = eq, Hovered = false }
	card.MouseEnter:Connect(function()
		row.Hovered = true
		paintTracks()
	end)
	card.MouseLeave:Connect(function()
		row.Hovered = false
		paintTracks()
	end)
	card.Activated:Connect(function()
		if type(SoundManager.SetMusicTrack) ~= "function" then
			return
		end
		local wasSelected = getMusicMode() == key
		if SoundManager.SetMusicTrack(key) then
			SoundManager.Play("Open", wasSelected and 1 or 1.2)
			-- Choisir un morceau relance la musique si elle était coupée
			if not current.Music and ClientState.HasFeature("Lofi") then
				Settings.Apply("Music", true)
				saveSetting("Music", true)
			end
		end
	end)
	table.insert(trackRows, row)
end

local function buildMusic(content: Instance)
	local section = buildSection(content, 1, "🎧", Locale.T("Lofi music"), Locale.T("Pick your soundtrack, saved automatically"), Theme.Colors.Purple)

	buildPlayerCard(section)

	-- Interrupteur + volume (morceau en cours dans le sous-titre)
	local musicRow, musicSubtitle = buildRow(section, 2, 96, "🎵", Locale.T("Music"), Theme.Colors.Purple)
	musicInfo = musicSubtitle
	buildToggle(musicRow, "Music")
	sliders.Music = buildSlider(musicRow, SoundManager.GetMusicVolume(), Theme.Colors.Purple, function(value)
		SoundManager.SetMusicVolume(value)
	end)

	divider(section, 3)

	-- Bandeau "verrouillé" (musique pas encore débloquée : le choix est gardé)
	local banner = UIUtil.Create("Frame", {
		Name = "LockBanner",
		Size = UDim2.new(1, 0, 0, 34),
		BackgroundColor3 = Color3.fromRGB(255, 244, 226),
		LayoutOrder = 4,
		Visible = false,
		Parent = section,
	})
	UIUtil.Corner(banner, Theme.Radius.M)
	UIUtil.Stroke(banner, Theme.Colors.Orange, 1.2, 0.4)
	UIUtil.Label({
		Text = Locale.T("🔒 Buy 🎧 %s to hear it. Your pick is kept!", Locale.T("Lofi Beats")),
		TextColor3 = Theme.Colors.Orange:Lerp(BLACK, 0.45),
		Font = Theme.Fonts.Title,
		Size = UDim2.new(1, -20, 1, -12),
		Position = UDim2.fromOffset(10, 6),
		MaxTextSize = 14,
		Parent = banner,
	})
	lockBanner = banner

	-- Liste des morceaux
	local listHeader = UIUtil.Create("Frame", {
		Name = "PlaylistHeader",
		Size = UDim2.new(1, 0, 0, 40),
		BackgroundTransparency = 1,
		LayoutOrder = 5,
		Parent = section,
	})
	UIUtil.Label({
		Text = Locale.T("🎶 Playlist"),
		Font = Theme.Fonts.Title,
		TextXAlignment = Enum.TextXAlignment.Left,
		Size = UDim2.new(1, -16, 0, 20),
		Position = UDim2.fromOffset(8, 2),
		MaxTextSize = 17,
		Parent = listHeader,
	})
	UIUtil.Label({
		Text = Locale.T("Tap a track to play it on repeat, or shuffle them all"),
		TextColor3 = Theme.Colors.TextDim,
		TextXAlignment = Enum.TextXAlignment.Left,
		Size = UDim2.new(1, -16, 0, 15),
		Position = UDim2.fromOffset(8, 23),
		MaxTextSize = 13,
		Parent = listHeader,
	})

	local playlist = type(SoundManager.GetPlaylist) == "function" and SoundManager.GetPlaylist() or {}
	local shuffleHolder = UIUtil.Create("Frame", {
		Name = "ShuffleHolder",
		Size = UDim2.new(1, 0, 0, 60),
		BackgroundTransparency = 1,
		LayoutOrder = 6,
		Parent = section,
	})
	UIUtil.Create("UIPadding", {
		PaddingLeft = UDim.new(0, 4),
		PaddingRight = UDim.new(0, 4),
		PaddingTop = UDim.new(0, 2),
		Parent = shuffleHolder,
	})
	buildTrackCard(
		shuffleHolder,
		"Shuffle",
		Locale.T("Shuffle"),
		Locale.T("All %d tracks, random order", #playlist),
		SHUFFLE_ART,
		0,
		true
	)

	local grid = UIUtil.Create("Frame", {
		Name = "Tracks",
		Size = UDim2.fromScale(1, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
		LayoutOrder = 7,
		Parent = section,
	})
	UIUtil.Create("UIPadding", {
		PaddingLeft = UDim.new(0, 4),
		PaddingRight = UDim.new(0, 4),
		PaddingTop = UDim.new(0, 2),
		PaddingBottom = UDim.new(0, 2),
		Parent = grid,
	})
	UIUtil.Create("UIGridLayout", {
		CellSize = UDim2.new(0.5, -5, 0, 56),
		CellPadding = UDim2.fromOffset(10, 8),
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = grid,
	})
	for _, track in ipairs(playlist) do
		buildTrackCard(grid, track.Key, track.Name, Locale.T("Track %d", track.Index), artFor(track.Key, track.Index), track.Index, false)
	end
	if #playlist == 0 then
		grid.Visible = false
		shuffleHolder.Visible = false
	end
end

local function buildGame(content: Instance)
	local section = buildSection(content, 5, "🎮", Locale.T("Game"), Locale.T("Credits and version"), SECTION_GAME)

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
	buildMusic(content)
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
	if SoundManager.MusicChanged then
		SoundManager.MusicChanged:Connect(refreshMusicInfo)
	end
	refreshMusicInfo()
	stepPlayer(1)
end

function Settings.OnOpen()
	refreshMusicInfo()
	-- Lecteur animé seulement quand la fenêtre est ouverte
	if not equalizerConnection then
		equalizerConnection = RunService.Heartbeat:Connect(stepPlayer)
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
