--[[
	SoundManager (ModuleScript)
	Emplacement : ReplicatedStorage > Client > SoundManager

	Joue les sons et la musique (côté client uniquement).
	Les IDs se changent dans Config.Sounds.

	Musique : elle ne joue que si le réglage "Musique" est activé
	(SetMusicEnabled) ET qu'elle est autorisée (SetMusicAllowed : ClientMain
	l'autorise quand le joueur possède la Feature "Lofi").
]]

local ContentProvider = game:GetService("ContentProvider")
local Debris = game:GetService("Debris")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")

local Config = require(ReplicatedStorage.Shared.Config)

local SoundManager = {}

local soundEnabled = true
local musicEnabled = true -- réglage du joueur
local musicAllowed = false -- Feature "Lofi" possédée
local templates: { [string]: Sound } = {}
local music: Sound? = nil
local lastPlayed: { [string]: number } = {}
local MIN_INTERVAL = 0.035 -- évite d'empiler 20 fois le même son dans la même image

local function refreshMusic()
	local track = music
	if not track then
		return
	end
	local shouldPlay = musicEnabled and musicAllowed
	if shouldPlay and not track.IsPlaying then
		track:Play()
	elseif not shouldPlay and track.IsPlaying then
		track:Stop()
	end
end

-- Crée un "modèle" de son pour chaque entrée de Config.Sounds
function SoundManager.Init()
	local folder = SoundService:FindFirstChild("DopamineSounds")
	if folder then
		folder:Destroy()
	end
	folder = Instance.new("Folder")
	folder.Name = "DopamineSounds"
	folder.Parent = SoundService

	local toPreload = {}
	for name, info in pairs(Config.Sounds) do
		if info.Id ~= "" then
			local sound = Instance.new("Sound")
			sound.Name = name
			sound.SoundId = info.Id
			sound.Volume = info.Volume
			sound.Parent = folder
			templates[name] = sound
			table.insert(toPreload, sound)
		end
	end

	-- Musique de fond
	local musicTemplate = templates.Music
	if musicTemplate then
		musicTemplate.Looped = true
		music = musicTemplate
	end

	-- Préchargement en arrière-plan (évite un petit délai au premier clic)
	task.spawn(function()
		pcall(function()
			ContentProvider:PreloadAsync(toPreload)
		end)
	end)
end

-- Joue un son. `pitch` change la hauteur (1 = normal).
function SoundManager.Play(name: string, pitch: number?)
	if not soundEnabled or name == "Music" then
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
	local sound = template:Clone()
	sound.PlaybackSpeed = pitch or 1
	sound.Parent = SoundService
	sound:Play()
	Debris:AddItem(sound, math.max(2, sound.TimeLength / math.max(0.1, sound.PlaybackSpeed) + 0.5))
end

function SoundManager.SetSoundEnabled(enabled: boolean)
	soundEnabled = enabled
end

-- Réglage "Musique" du joueur
function SoundManager.SetMusicEnabled(enabled: boolean)
	musicEnabled = enabled
	refreshMusic()
end

-- Autorisation de la musique (Feature "Lofi")
function SoundManager.SetMusicAllowed(allowed: boolean)
	musicAllowed = allowed
	refreshMusic()
end

function SoundManager.IsSoundEnabled(): boolean
	return soundEnabled
end

return SoundManager
