--[[
	MusicSynth (ModuleScript)
	Emplacement : ReplicatedStorage > Client > World > MusicSynth

	🎵 Moteur de SON des instruments de la scène (v9.9, MUSIC99), côté
	client. "Avec de vrais sons" sans nouvel identifiant non vérifiable :
	chaque note est un Sound qui rejoue l'échantillon de son instrument
	(Config.Instruments : SampleId, BaseNote…) à la bonne HAUTEUR :
	    PlaybackSpeed = 2^((note - BaseNote) / 12)   (1 demi-ton = x1,0595)
	  - timbres : couches (octave, quinte) + effets par instrument dans un
	    SoundGroup (réverbération du piano, chorus du synthé, distorsion de
	    la guitare, basses renforcées de la basse…) ;
	  - enveloppe : chaque note s'éteint en fondu (Decay), calculé à chaque
	    image (Step) ; polyphonie : 10 voix par échantillon et par émetteur
	    (la plus ancienne est reprise) ;
	  - son 3D : les Sound sont posés sur l'instrument (émetteur), on ne
	    les entend que de près (RollOffMin / RollOffMax) ;
	  - volume : Config.Instruments.Volume x instrument x vélocité, x le
	    volume des effets du joueur (⚙️, SoundManager : lecture seule) ;
	    rien si les sons sont coupés.
	Aucun son existant n'est modifié (Config.Sounds n'est pas lu ici).

	API :
	  MusicSynth.new() -> synth
	  synth:Note(inst, note, vel, emitter)   instruments mélodiques
	  synth:Drum(piece, vel, emitter)        batterie (1..9, MusicData.DRUMS)
	  synth:Pad(pad, vel, emitter)           effets du DJ (5..8)
	  synth:Step(dt)                         enveloppes
	  synth:Destroy()
	  MusicSynth.Speed(inst, note) -> number (pur : tests)
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")

local Config = require(ReplicatedStorage.Shared.Config)
local MusicData = require(ReplicatedStorage.Shared.MusicData)

local MusicSynth = {}
MusicSynth.__index = MusicSynth

local VOICES = 10
local MIN_VOLUME = 0.004

local soundManager: any = nil
local function userVolume(): number
	if soundManager == nil then
		local ok, result = pcall(function()
			local client = script.Parent.Parent
			return require(client:WaitForChild("SoundManager", 2) :: any)
		end)
		soundManager = ok and result or false
	end
	local sm = soundManager
	if not sm then
		return 1
	end
	local ok, enabled = pcall(sm.IsSoundEnabled)
	if ok and enabled == false then
		return 0
	end
	local okV, volume = pcall(sm.GetEffectsVolume)
	if okV and type(volume) == "number" then
		-- (la scène reste audible même avec des effets discrets)
		return math.clamp(0.35 + volume * 0.8, 0, 1)
	end
	return 1
end

local function cfg(): any
	return Config.Instruments or {}
end

-- Vitesse de lecture d'une note (repliée à l'octave dans [MinSpeed, MaxSpeed])
function MusicSynth.Speed(inst: string, note: number): number
	local c = cfg()[inst] or {}
	local base = tonumber(c.BaseNote) or 76
	local speed = 2 ^ ((note - base) / 12)
	local lo, hi = tonumber(c.MinSpeed) or 0.25, tonumber(c.MaxSpeed) or 4
	for _ = 1, 6 do
		if speed < lo then
			speed *= 2
		elseif speed > hi then
			speed /= 2
		else
			break
		end
	end
	return speed
end

type Voice = { Sound: Sound, Start: number, Decay: number, V0: number, Busy: boolean }

function MusicSynth.new()
	local self = setmetatable({
		Pools = {} :: { [Instance]: { [string]: { List: { Voice }, Next: number } } },
		Groups = {} :: { [string]: SoundGroup },
		Active = {} :: { Voice },
		Clock = 0,
		Played = 0,
		Volume = 1,
		VolumeAt = -math.huge,
	}, MusicSynth)
	return self
end

-- SoundGroup + effets d'un instrument (créé à la première note)
function MusicSynth.Group(self: any, inst: string): SoundGroup?
	local g = self.Groups[inst]
	if g and g.Parent then
		return g
	end
	local ok, result = pcall(function()
		local group = Instance.new("SoundGroup")
		group.Name = "DopamineStage_" .. inst
		group.Volume = 1
		local function fx(className: string, props: { [string]: any })
			local e = Instance.new(className :: any)
			for k, v in pairs(props) do
				(e :: any)[k] = v
			end
			e.Parent = group
		end
		if inst == "Piano" then
			fx("EqualizerSoundEffect", { LowGain = 3, MidGain = 0, HighGain = -3 })
			fx("ReverbSoundEffect", { DecayTime = 1.6, Density = 0.8, Diffusion = 0.8, WetLevel = -10, DryLevel = 0 })
		elseif inst == "Synth" then
			fx("ChorusSoundEffect", { Depth = 0.25, Mix = 0.5, Rate = 1.2 })
			fx("ReverbSoundEffect", { DecayTime = 2.2, WetLevel = -8, DryLevel = 0 })
		elseif inst == "Guitar" then
			fx("DistortionSoundEffect", { Level = tonumber(cfg().Guitar and cfg().Guitar.Distortion) or 0.35 })
			fx("EqualizerSoundEffect", { LowGain = 2, MidGain = 3, HighGain = -6 })
		elseif inst == "Bass" then
			fx("EqualizerSoundEffect", { LowGain = 8, MidGain = -2, HighGain = -12 })
			fx("CompressorSoundEffect", { Threshold = -14, Ratio = 3 })
		elseif inst == "Xylophone" then
			fx("EqualizerSoundEffect", { LowGain = -4, MidGain = 1, HighGain = 3 })
			fx("ReverbSoundEffect", { DecayTime = 1.0, WetLevel = -14, DryLevel = 0 })
		elseif inst == "Drums" then
			fx("CompressorSoundEffect", { Threshold = -12, Ratio = 3 })
			fx("EqualizerSoundEffect", { LowGain = 4, MidGain = 0, HighGain = 1 })
		else
			fx("ReverbSoundEffect", { DecayTime = 1.2, WetLevel = -12, DryLevel = 0 })
		end
		group.Parent = SoundService
		return group
	end)
	if ok then
		self.Groups[inst] = result
		return result
	end
	return nil
end

local function voiceFor(self: any, emitter: Instance, sampleId: string, inst: string): Voice?
	local byEmitter = self.Pools[emitter]
	if not byEmitter then
		byEmitter = {}
		self.Pools[emitter] = byEmitter
	end
	local pool = byEmitter[sampleId]
	if not pool then
		pool = { List = {}, Next = 1 }
		byEmitter[sampleId] = pool
	end
	local voice = pool.List[pool.Next]
	if not voice or not voice.Sound.Parent then
		local c = cfg()
		local sound = Instance.new("Sound")
		sound.Name = "StageVoice"
		sound.SoundId = sampleId
		sound.RollOffMode = Enum.RollOffMode.InverseTapered
		sound.RollOffMinDistance = tonumber(c.RollOffMin) or 14
		sound.RollOffMaxDistance = tonumber(c.RollOffMax) or 120
		sound.Volume = 0
		local group = MusicSynth.Group(self, inst)
		if group then
			sound.SoundGroup = group
		end
		sound.Parent = emitter
		voice = { Sound = sound, Start = 0, Decay = 1, V0 = 0, Busy = false }
		pool.List[pool.Next] = voice
	end
	pool.Next = pool.Next % VOICES + 1
	return voice
end

local function master(self: any): number
	-- (volume du joueur relu au plus toutes les 0,5 s)
	if self.Clock - self.VolumeAt > 0.5 then
		self.VolumeAt = self.Clock
		self.Volume = userVolume()
	end
	return self.Volume * (tonumber(cfg().Volume) or 0.8)
end

local function fire(self: any, emitter: Instance?, inst: string, sampleId: string, speed: number, volume: number, decay: number, delay: number?)
	if not emitter or not emitter.Parent or type(sampleId) ~= "string" or sampleId == "" or volume <= MIN_VOLUME then
		return
	end
	local function go()
		if not emitter.Parent then
			return
		end
		local voice = voiceFor(self, emitter, sampleId, inst)
		if not voice then
			return
		end
		local sound = voice.Sound
		pcall(function()
			sound:Stop()
			sound.PlaybackSpeed = math.clamp(speed, 0.05, 20)
			sound.Volume = volume
			sound.TimePosition = 0
			sound:Play()
		end)
		voice.Start = self.Clock
		voice.Decay = math.max(0.05, decay)
		voice.V0 = volume
		if not voice.Busy then
			voice.Busy = true
			table.insert(self.Active, voice)
		end
		self.Played += 1
	end
	if delay and delay > 0.005 then
		task.delay(delay, go)
	else
		go()
	end
end

-- Note d'un instrument mélodique
function MusicSynth.Note(self: any, inst: string, note: number, vel: number, emitter: Instance?)
	local c = cfg()[inst]
	if type(c) ~= "table" then
		return
	end
	local m = master(self)
	if m <= 0 then
		return
	end
	local speed = MusicSynth.Speed(inst, note)
	local base = (tonumber(c.Volume) or 0.6) * math.clamp(vel, 0.05, 1) * m
	local layers = type(c.Layers) == "table" and c.Layers or { { 0, 1 } }
	for _, layer in ipairs(layers) do
		local semis, vol = tonumber(layer[1]) or 0, tonumber(layer[2]) or 1
		fire(self, emitter, inst, c.SampleId, speed * 2 ^ (semis / 12), base * vol, tonumber(c.Decay) or 1, nil)
	end
end

local function layers(self: any, inst: string, list: any, vel: number, emitter: Instance?, groupVolume: number)
	if type(list) ~= "table" then
		return
	end
	local m = master(self)
	if m <= 0 then
		return
	end
	for _, layer in ipairs(list) do
		local id, speed, vol, decay, delay = layer[1], tonumber(layer[2]) or 1, tonumber(layer[3]) or 1, tonumber(layer[4]) or 0.3, tonumber(layer[5])
		fire(self, emitter, inst, id, speed, vol * groupVolume * math.clamp(vel, 0.05, 1) * m, decay, delay)
	end
end

function MusicSynth.Drum(self: any, piece: number, vel: number, emitter: Instance?)
	local name = MusicData.DRUMS[piece]
	local d = cfg().Drums
	if not name or type(d) ~= "table" then
		return
	end
	layers(self, "Drums", d[name], vel, emitter, tonumber(d.Volume) or 0.75)
end

function MusicSynth.Pad(self: any, pad: number, vel: number, emitter: Instance?)
	local name = MusicData.DJ_PADS[pad]
	local d = cfg().DJ
	if not name or type(d) ~= "table" then
		return
	end
	layers(self, "DJ", d[name], vel, emitter, tonumber(d.Volume) or 0.8)
end

-- Enveloppes (fondu de sortie de chaque voix)
function MusicSynth.Step(self: any, dt: number)
	self.Clock += dt
	local keep = {}
	for _, voice in ipairs(self.Active) do
		local age = self.Clock - voice.Start
		local sound = voice.Sound
		if not sound.Parent or age >= voice.Decay then
			voice.Busy = false
			if sound.Parent then
				pcall(function()
					sound.Volume = 0
					sound:Stop()
				end)
			end
		else
			-- (courbe douce : forte attaque puis extinction)
			local u = age / voice.Decay
			sound.Volume = voice.V0 * (1 - u) * (1 - u)
			table.insert(keep, voice)
		end
	end
	self.Active = keep
end

function MusicSynth.Destroy(self: any)
	for _, byEmitter in pairs(self.Pools) do
		for _, pool in pairs(byEmitter) do
			for _, voice in ipairs(pool.List) do
				pcall(function()
					voice.Sound:Destroy()
				end)
			end
		end
	end
	table.clear(self.Pools)
	table.clear(self.Active)
	for _, g in pairs(self.Groups) do
		pcall(function()
			g:Destroy()
		end)
	end
	table.clear(self.Groups)
end

return MusicSynth
