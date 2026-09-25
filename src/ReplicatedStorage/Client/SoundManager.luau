--[[
	SoundManager (ModuleScript)
	Emplacement : ReplicatedStorage > Client > SoundManager

	Joue les sons et la musique (côté client uniquement).
	- Sons : IDs dans Config.Sounds, joués avec SoundManager.Play(nom, hauteur).
	- Musique : vraie playlist lofi (Config.Music.Playlist). Les pistes avec
	  Id = "" sont ignorées ; ordre mélangé si Config.Music.Shuffle ; fondu
	  enchaîné entre deux morceaux ; passe au suivant à la fin d'un morceau
	  ou si un morceau ne se charge pas ; la playlist tourne en boucle.

	La musique ne joue que si le réglage "Musique" est activé
	(SetMusicEnabled) ET qu'elle est autorisée (SetMusicAllowed : ClientMain
	l'autorise quand le joueur possède la Feature "Lofi").

	Volumes (0 à 1, gardés en mémoire pour la session) : SetMusicVolume /
	SetEffectsVolume, appliqués via deux SoundGroups ("Musique", "Effets").

	Son du clic (v4) : le joueur choisit son son de clic dans ⚙️ Paramètres
	(Config.ClickSounds, sauvegardé côté serveur dans Settings.ClickSound).
	SoundManager.PlayClick(hauteur) joue le son choisi pour le gros bouton
	(repli : Config.Sounds.Click). Play("Click") reste le petit clic de l'interface.

	Signaux :
	  SoundManager.TrackChanged (nom?, sound?)  : un nouveau morceau commence
	                                             (nil, nil quand la musique s'arrête)
	  SoundManager.MusicStateChanged (joue)      : la musique démarre / s'arrête
	  SoundManager.VolumeChanged (musique, effets)
	  SoundManager.ClickSoundChanged (id)        : le son du clic a changé
]]

local ContentProvider = game:GetService("ContentProvider")
local Debris = game:GetService("Debris")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")

local Config = require(ReplicatedStorage.Shared.Config)
local Signal = require(ReplicatedStorage.Shared.Signal)
local Locale = require(ReplicatedStorage.Shared.Locale)

local SoundManager = {}

-- Nom affiché d'un morceau, dans la langue du joueur ("Track 2" sans nom)
local function trackName(track): string
	if track.Name then
		return Locale.T(track.Name)
	end
	return Locale.T("Track %d", track.Index or 1)
end

SoundManager.TrackChanged = Signal.new() -- (name: string?, sound: Sound?)
SoundManager.MusicStateChanged = Signal.new() -- (playing: boolean)
SoundManager.VolumeChanged = Signal.new() -- (musicVolume, effectsVolume)
SoundManager.ClickSoundChanged = Signal.new() -- (clickSoundId)

local MIN_INTERVAL = 0.035 -- évite d'empiler 20 fois le même son dans la même image
local CROSSFADE = 2.5 -- durée (s) du fondu enchaîné entre deux morceaux
local FADE_IN = 1.5 -- fondu à la reprise
local FADE_OUT = 1 -- fondu à la coupure
local LOAD_TIMEOUT = 10 -- (s) au-delà, un morceau qui ne charge pas est sauté
local RETRY_DELAY = 30 -- (s) si AUCUN morceau ne charge, on réessaie plus tard

local soundEnabled = true
local musicEnabled = true -- réglage du joueur
local musicAllowed = false -- Feature "Lofi" possédée
local musicVolume = math.clamp(tonumber(Config.Music and Config.Music.DefaultVolume) or 0.35, 0, 1)
local effectsVolume = 1

local folder: Folder? = nil
local effectsGroup: SoundGroup? = nil
local musicGroup: SoundGroup? = nil
local templates: { [string]: Sound } = {}
local lastPlayed: { [string]: number } = {}

-- Sons de clic au choix (Config.ClickSounds)
local DEFAULT_CLICK_SOUND = "Default"
local clickTemplates: { [string]: Sound } = {} -- [Id] = modèle de son
local clickSoundId = DEFAULT_CLICK_SOUND
local lastClick = 0

-- Playlist
type Track = { Name: string?, Index: number?, Id: string }
local tracks: { Track } = {} -- pistes valides (Id non vide)
local order: { number } = {} -- ordre de lecture (indices dans `tracks`)
local orderPosition = 0
local current: Sound? = nil
local currentTrack: Track? = nil
local generation = 0 -- change à chaque nouveau morceau (annule les attentes périmées)
local pauseToken = 0 -- change à chaque coupure / reprise (annule un fondu de coupure périmé)
local playing = false -- état "la musique joue" (pour MusicStateChanged)
local failures = 0 -- échecs de chargement d'affilée
local retryAt = 0 -- os.clock() avant lequel on ne relance pas (tout a échoué)
local warnedEmpty = false

----------------------------------------------------------------------
-- Outils
----------------------------------------------------------------------

-- "123" ou 123 -> "rbxassetid://123" ; sinon l'ID tel quel ("" si invalide)
local function normalizeId(id: any): string
	if type(id) == "number" then
		return id > 0 and ("rbxassetid://" .. tostring(math.floor(id))) or ""
	end
	if type(id) ~= "string" then
		return ""
	end
	local trimmed = string.gsub(id, "^%s*(.-)%s*$", "%1")
	if trimmed == "" or trimmed == "0" then
		return ""
	end
	if string.match(trimmed, "^%d+$") then
		return "rbxassetid://" .. trimmed
	end
	return trimmed
end

local function fade(sound: Sound, volume: number, duration: number): Tween
	local tween = TweenService:Create(sound, TweenInfo.new(duration, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut), {
		Volume = volume,
	})
	tween:Play()
	return tween
end

-- Fait disparaître un morceau en douceur puis le détruit
local function fadeAndDestroy(sound: Sound, duration: number)
	local tween = fade(sound, 0, duration)
	tween.Completed:Once(function()
		sound:Destroy()
	end)
	-- Filet de sécurité si le tween est interrompu
	Debris:AddItem(sound, duration + 1)
end

local function shouldPlay(): boolean
	return musicEnabled and musicAllowed and #tracks > 0
end

local function setPlaying(value: boolean)
	if playing ~= value then
		playing = value
		SoundManager.MusicStateChanged:Fire(value)
	end
end

-- Nouvel ordre de lecture (mélangé si demandé, sans rejouer tout de suite le dernier)
local function buildOrder()
	local last = order[#order]
	table.clear(order)
	for index = 1, #tracks do
		table.insert(order, index)
	end
	if Config.Music.Shuffle and #order > 1 then
		local random = Random.new()
		for i = #order, 2, -1 do
			local j = random:NextInteger(1, i)
			order[i], order[j] = order[j], order[i]
		end
		if last and order[1] == last then
			order[1], order[#order] = order[#order], order[1]
		end
	end
	orderPosition = 0
end

local function nextTrackIndex(): number?
	if #tracks == 0 then
		return nil
	end
	orderPosition += 1
	if orderPosition > #order then
		buildOrder()
		orderPosition = 1
	end
	return order[orderPosition]
end

----------------------------------------------------------------------
-- Lecture
----------------------------------------------------------------------

local startNext: (crossfade: number) -> ()

-- Surveille le chargement d'un morceau : s'il ne charge pas à temps, on passe au suivant
local function watchLoading(sound: Sound, myGeneration: number)
	task.spawn(function()
		local started = os.clock()
		while not sound.IsLoaded and os.clock() - started < LOAD_TIMEOUT do
			task.wait(0.25)
			if generation ~= myGeneration or not sound.Parent then
				return
			end
		end
		if generation ~= myGeneration or not sound.Parent then
			return
		end
		if sound.IsLoaded then
			failures = 0
			return
		end
		-- Échec : morceau suivant (ou pause si tout échoue)
		failures += 1
		warn("[SoundManager] Musique impossible à charger : " .. sound.SoundId .. " (morceau suivant)")
		if failures >= #tracks then
			failures = 0
			retryAt = os.clock() + RETRY_DELAY
			if current == sound then
				current = nil
				currentTrack = nil
				sound:Destroy()
				setPlaying(false)
				SoundManager.TrackChanged:Fire(nil, nil)
			end
			return
		end
		if shouldPlay() then
			startNext(0.5)
		end
	end)
end

-- Lance le morceau suivant avec un fondu enchaîné
startNext = function(crossfade: number)
	local group = musicGroup
	local parent = folder
	if not group or not parent then
		return
	end
	local index = nextTrackIndex()
	if not index then
		return
	end
	local track = tracks[index]
	generation += 1
	local displayName = trackName(track)
	local myGeneration = generation

	-- L'ancien morceau s'efface
	local old = current
	if old then
		fadeAndDestroy(old, math.max(0.2, crossfade))
	end

	local sound = Instance.new("Sound")
	sound.Name = "Music_" .. tostring(track.Name or track.Index)
	sound.SoundId = track.Id
	sound.Volume = 0
	sound.Looped = #tracks == 1 -- un seul morceau : il boucle tout seul
	sound.SoundGroup = group
	sound.Parent = parent
	current = sound
	currentTrack = track

	sound.Ended:Connect(function()
		-- Fin naturelle (si le fondu anticipé n'a pas déjà pris le relais)
		if generation == myGeneration and current == sound and shouldPlay() then
			startNext(0.3)
		end
	end)

	sound:Play()
	fade(sound, 1, math.max(0.2, crossfade))
	watchLoading(sound, myGeneration)
	setPlaying(true)
	SoundManager.TrackChanged:Fire(displayName, sound)
end

-- Démarre / reprend / coupe la musique selon les réglages
local function refreshMusic()
	local sound = current
	if shouldPlay() then
		if os.clock() < retryAt then
			return
		end
		if sound then
			if not playing or not sound.IsPlaying then
				pauseToken += 1 -- annule un éventuel fondu de coupure en cours
				if not sound.IsPlaying then
					sound.Volume = 0
					sound:Resume()
				end
				fade(sound, 1, FADE_IN)
				setPlaying(true)
			end
		else
			startNext(FADE_IN)
		end
	else
		if RunService:IsStudio() and musicEnabled and musicAllowed and #tracks == 0 and not warnedEmpty then
			warnedEmpty = true
			warn("[SoundManager] Aucune musique : ajoute des IDs dans Config.Music.Playlist")
		end
		if sound and sound.IsPlaying and playing then
			pauseToken += 1
			local myToken = pauseToken
			local tween = fade(sound, 0, FADE_OUT)
			tween.Completed:Once(function()
				-- Pause (on reprend au même endroit), sauf si la musique est revenue entre-temps
				if pauseToken == myToken and current == sound and not shouldPlay() then
					sound:Pause()
				end
			end)
		end
		setPlaying(false)
	end
end

----------------------------------------------------------------------
-- API
----------------------------------------------------------------------

-- Crée un "modèle" de son pour chaque entrée de Config.Sounds + la playlist
function SoundManager.Init()
	local old = SoundService:FindFirstChild("DopamineSounds")
	if old then
		old:Destroy()
	end
	local newFolder = Instance.new("Folder")
	newFolder.Name = "DopamineSounds"
	newFolder.Parent = SoundService
	folder = newFolder

	local fx = Instance.new("SoundGroup")
	fx.Name = "Effets"
	fx.Volume = effectsVolume
	fx.Parent = newFolder
	effectsGroup = fx

	local mu = Instance.new("SoundGroup")
	mu.Name = "Musique"
	mu.Volume = musicVolume
	mu.Parent = newFolder
	musicGroup = mu

	table.clear(templates)
	local toPreload = {}
	for name, info in pairs(Config.Sounds) do
		local id = normalizeId(info.Id)
		if id ~= "" then
			local sound = Instance.new("Sound")
			sound.Name = name
			sound.SoundId = id
			sound.Volume = info.Volume or 0.5
			sound.SoundGroup = fx
			sound.Parent = newFolder
			templates[name] = sound
			table.insert(toPreload, sound)
		end
	end

	-- Sons de clic au choix
	table.clear(clickTemplates)
	for _, entry in ipairs(Config.ClickSounds or {}) do
		local id = normalizeId(entry.Sound)
		if type(entry.Id) == "string" and id ~= "" then
			local sound = Instance.new("Sound")
			sound.Name = "ClickSound_" .. entry.Id
			sound.SoundId = id
			sound.Volume = tonumber(entry.Volume) or 0.5
			sound.SoundGroup = fx
			sound.Parent = newFolder
			clickTemplates[entry.Id] = sound
			table.insert(toPreload, sound)
		end
	end

	-- Playlist : on garde seulement les pistes avec un ID
	table.clear(tracks)
	local playlist = (Config.Music and Config.Music.Playlist) or {}
	for index, entry in ipairs(playlist) do
		local id = normalizeId(entry.Id)
		if id ~= "" then
			table.insert(tracks, { Name = entry.Name and tostring(entry.Name) or nil, Index = index, Id = id })
		end
	end
	buildOrder()

	-- Préchargement en arrière-plan (évite un petit délai au premier clic)
	task.spawn(function()
		pcall(function()
			ContentProvider:PreloadAsync(toPreload)
		end)
	end)

	-- Surveillance : fondu enchaîné un peu avant la fin du morceau,
	-- et nouvel essai si tout avait échoué au chargement
	task.spawn(function()
		while true do
			task.wait(0.25)
			local sound = current
			if shouldPlay() then
				if not sound and os.clock() >= retryAt and retryAt > 0 then
					retryAt = 0
					refreshMusic()
				elseif sound and #tracks > 1 and sound.IsPlaying and sound.IsLoaded then
					local length = sound.TimeLength
					if length > CROSSFADE * 3 and sound.TimePosition >= length - CROSSFADE then
						startNext(CROSSFADE)
					end
				end
			end
		end
	end)

	refreshMusic()
end

-- Joue un modèle de son (clone temporaire)
local function playTemplate(template: Sound, pitch: number)
	local sound = template:Clone()
	sound.PlaybackSpeed = pitch
	sound.Parent = SoundService
	sound:Play()
	Debris:AddItem(sound, math.max(2, sound.TimeLength / math.max(0.1, sound.PlaybackSpeed) + 0.5))
end

-- Joue un son. `pitch` change la hauteur (1 = normal).
function SoundManager.Play(name: string, pitch: number?)
	if not soundEnabled or effectsVolume <= 0 or name == "Music" then
		return
	end
	local template = templates[name]
	if not template then
		return
	end
	local now = os.clock()
	if now - (lastPlayed[name] or 0) < MIN_INTERVAL then
		return
	end
	lastPlayed[name] = now
	playTemplate(template, pitch or 1)
end

----------------------------------------------------------------------
-- Son du clic (v4)
----------------------------------------------------------------------

-- Choisit le son du clic (Id de Config.ClickSounds ; inconnu = "Default")
function SoundManager.SetClickSound(id: string)
	local newId = (type(id) == "string" and clickTemplates[id] ~= nil) and id or DEFAULT_CLICK_SOUND
	if newId == clickSoundId then
		return
	end
	clickSoundId = newId
	SoundManager.ClickSoundChanged:Fire(newId)
end

function SoundManager.GetClickSound(): string
	return clickSoundId
end

-- Joue le son de clic choisi (gros bouton). `pitch` : hauteur (1 = normal).
-- Les sons de clavier gardent une hauteur plus naturelle (variation réduite).
function SoundManager.PlayClick(pitch: number?)
	if not soundEnabled or effectsVolume <= 0 then
		return
	end
	local template = clickTemplates[clickSoundId]
	if not template then
		SoundManager.Play("Click", pitch)
		return
	end
	local now = os.clock()
	if now - lastClick < MIN_INTERVAL then
		return
	end
	lastClick = now
	local speed = pitch or 1
	if clickSoundId ~= DEFAULT_CLICK_SOUND then
		speed = 1 + (speed - 1) * 0.35
	end
	playTemplate(template, speed)
end

-- Fait écouter un son de clic (bouton ▶ des paramètres), même s'il n'est pas choisi
function SoundManager.PreviewClickSound(id: string)
	if not soundEnabled or effectsVolume <= 0 then
		return
	end
	local template = clickTemplates[id]
	if template then
		playTemplate(template, 1)
	else
		SoundManager.Play("Click", 1)
	end
end

function SoundManager.SetSoundEnabled(enabled: boolean)
	soundEnabled = enabled == true
end

function SoundManager.IsSoundEnabled(): boolean
	return soundEnabled
end

-- Réglage "Musique" du joueur
function SoundManager.SetMusicEnabled(enabled: boolean)
	musicEnabled = enabled == true
	refreshMusic()
end

function SoundManager.IsMusicEnabled(): boolean
	return musicEnabled
end

-- Autorisation de la musique (Feature "Lofi")
function SoundManager.SetMusicAllowed(allowed: boolean)
	musicAllowed = allowed == true
	refreshMusic()
end

function SoundManager.IsMusicAllowed(): boolean
	return musicAllowed
end

-- Vrai si un morceau est en train de jouer
function SoundManager.IsMusicPlaying(): boolean
	return playing
end

-- Vrai si la playlist contient au moins un morceau avec un ID
function SoundManager.HasPlaylist(): boolean
	return #tracks > 0
end

-- Volume de la musique (0 à 1)
function SoundManager.SetMusicVolume(volume: number)
	musicVolume = math.clamp(tonumber(volume) or 0, 0, 1)
	local group = musicGroup
	if group then
		group.Volume = musicVolume
	end
	SoundManager.VolumeChanged:Fire(musicVolume, effectsVolume)
end

function SoundManager.GetMusicVolume(): number
	return musicVolume
end

-- Volume des effets sonores (0 à 1)
function SoundManager.SetEffectsVolume(volume: number)
	effectsVolume = math.clamp(tonumber(volume) or 0, 0, 1)
	local group = effectsGroup
	if group then
		group.Volume = effectsVolume
	end
	SoundManager.VolumeChanged:Fire(musicVolume, effectsVolume)
end

function SoundManager.GetEffectsVolume(): number
	return effectsVolume
end

-- Passe au morceau suivant (fondu court). Renvoie vrai si c'est fait.
function SoundManager.NextTrack(): boolean
	if not shouldPlay() then
		return false
	end
	failures = 0
	retryAt = 0
	startNext(0.8)
	return true
end

-- Morceau actuel : (nom, Sound) ou (nil, nil) si aucun
function SoundManager.GetCurrentTrack(): (string?, Sound?)
	local track = currentTrack
	if not track or not current then
		return nil, nil
	end
	return trackName(track), current
end

return SoundManager
