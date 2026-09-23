--[[
	SoundManager (ModuleScript)
	Emplacement : ReplicatedStorage > Client > SoundManager

	Joue les sons et la musique (côté client uniquement).
	Les IDs se changent dans Config.Sounds.
]]

local ContentProvider = game:GetService("ContentProvider")
local Debris = game:GetService("Debris")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")

local Config = require(ReplicatedStorage.Shared.Config)

local SoundManager = {}

local soundEnabled = true
local musicEnabled = true
local templates: { [string]: Sound } = {}
local music: Sound? = nil

-- Crée un "modèle" de son pour chaque entrée de Config.Sounds
function SoundManager.Init()
	local folder = Instance.new("Folder")
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
	if not soundEnabled then
		return
	end
	local template = templates[name]
	if not template then
		return
	end
	local sound = template:Clone()
	sound.PlaybackSpeed = pitch or 1
	sound.Parent = SoundService
	sound:Play()
	Debris:AddItem(sound, math.max(2, sound.TimeLength + 0.5))
end

function SoundManager.SetSoundEnabled(enabled: boolean)
	soundEnabled = enabled
end

function SoundManager.SetMusicEnabled(enabled: boolean)
	musicEnabled = enabled
	local track = music
	if not track then
		return
	end
	if musicEnabled and not track.IsPlaying then
		track:Play()
	elseif not musicEnabled and track.IsPlaying then
		track:Stop()
	end
end

return SoundManager
