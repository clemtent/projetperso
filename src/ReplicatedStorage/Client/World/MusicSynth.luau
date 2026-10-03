--[[
	MusicSynth (ModuleScript)
	Emplacement : ReplicatedStorage > Client > World > MusicSynth

	🎵 Moteur de SON des instruments de la scène (v9.9 MUSIC99, refait en
	v11 MUSIC11), côté client.

	(v11) LE BUG "TOUT SONNE COMME LE PIANO" — cause et correction :
	  1. les 5 instruments mélodiques jouaient le MÊME échantillon
	     (electronicpingshort.wav) à la MÊME note de base, avec seulement un
	     léger égaliseur / une réverbération : même son partout ;
	  2. la batterie elle-même (toms, ride, corps de la grosse caisse) jouait
	     ce même "ping" : on entendait des notes de "piano" à la batterie ;
	  3. les voix (Sound) étaient rangées par échantillon seulement, pas par
	     instrument : un Sound créé pour un instrument gardait le groupe
	     d'effets (SoundGroup) de cet instrument quand un autre le
	     réutilisait sur le même émetteur (platines du DJ : batterie, basse et
	     effets mélangés dans un seul groupe).
	  Maintenant :
	  - chaque instrument a sa RECETTE (Config.Instruments) : couches
	    accordées (harmoniques, désaccord), bruits d'attaque (marteau,
	    médiator, maillet), impulsions répétées (synthé tenu) ;
	  - chaque instrument / pièce de batterie a sa CHAÎNE D'EFFETS (un
	    SoundGroup par chaîne : CHAINS) : saturation + baffle de la guitare,
	    compresseur + graves de la basse, chorus/flanger/trémolo/écho du
	    synthé, réverbération de salle du piano, filtres de la batterie… ;
	  - GLISSÉ de hauteur pendant la note (grosse caisse "808", toms,
	    scratch, montée, drop du DJ) : PlaybackSpeed suivie à chaque image ;
	  - les voix sont rangées par (émetteur, chaîne, échantillon) : plus de
	    mélange d'effets entre instruments.
	  - enveloppe : chaque note s'éteint en fondu (Decay, courbe propre à
	    chaque chaîne) ; polyphonie : VOICES voix par échantillon, chaîne et
	    émetteur (la plus ancienne est reprise) ;
	  - son 3D : les Sound sont posés sur l'instrument (émetteur), on ne
	    les entend que de près (RollOffMin / RollOffMax) ;
	  - volume : Config.Instruments.Volume x instrument x vélocité, x le
	    volume des effets du joueur (⚙️, SoundManager : lecture seule) ;
	    rien si les sons sont coupés.
	Seuls des sons intégrés à Roblox sont utilisés par défaut
	(Config.Instruments.Samples). Aucun son existant n'est modifié.

	API :
	  MusicSynth.new() -> synth
	  synth:Note(inst, note, vel, emitter, dur?)   instruments mélodiques
	  synth:Drum(piece, vel, emitter)              batterie (1..9, MusicData.DRUMS)
	  synth:Pad(pad, vel, emitter)                 effets du DJ (5..8)
	  synth:Step(dt)                               enveloppes + glissés
	  synth:Destroy()
	  Fonctions pures (tests) :
	  MusicSynth.Speed(inst, note) -> number
	  MusicSynth.NoteLayers(inst, note, vel, dur?) -> { Layer }
	  MusicSynth.HitLayers("Drums" | "DJ", index, vel) -> { Layer }
	  MusicSynth.ChainOf(inst, piece?) -> string
	  MusicSynth.CHAINS                            effets par chaîne
	  MusicSynth.Signature(inst) -> string         empreinte du timbre
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")

local Config = require(ReplicatedStorage.Shared.Config)
local MusicData = require(ReplicatedStorage.Shared.MusicData)

local MusicSynth = {}
MusicSynth.__index = MusicSynth

local VOICES = 8
local MIN_VOLUME = 0.004

export type Layer = {
	Sample: string, -- identifiant complet (rbxasset://…)
	Speed: number,
	Volume: number,
	Decay: number,
	Delay: number,
	SpeedTo: number?, -- glissé de hauteur (vitesse finale)
	SweepT: number?, -- durée du glissé
	Chain: string,
}

----------------------------------------------------------------------
-- Chaînes d'effets (un SoundGroup chacune) : { classe, propriétés }
-- (Priority : l'effet de plus haute priorité est appliqué en premier)
----------------------------------------------------------------------

MusicSynth.CHAINS = {
	Piano = {
		Curve = 2,
		{ "EqualizerSoundEffect", { LowGain = 2, MidGain = 0, HighGain = -1.5, Priority = 4 } },
		{ "CompressorSoundEffect", { Threshold = -18, Ratio = 2, Attack = 0.01, Release = 0.2, Priority = 3 } },
		{ "ReverbSoundEffect", { DecayTime = 1.8, Density = 0.85, Diffusion = 0.85, WetLevel = -9, DryLevel = 0, Priority = 1 } },
	},
	Guitar = {
		Curve = 1.25,
		{ "EqualizerSoundEffect", { LowGain = -4, MidGain = 4, HighGain = 2, Priority = 6 } },
		{ "DistortionSoundEffect", { Level = 0.72, Priority = 5 } },
		{ "EqualizerSoundEffect", { LowGain = 1, MidGain = 3, HighGain = -12, Priority = 4 } }, -- (baffle 4x12)
		{ "ChorusSoundEffect", { Depth = 0.15, Mix = 0.25, Rate = 0.8, Priority = 3 } },
		{ "ReverbSoundEffect", { DecayTime = 1.2, Density = 0.7, Diffusion = 0.7, WetLevel = -14, DryLevel = 0, Priority = 1 } },
	},
	Bass = {
		Curve = 1.4,
		{ "DistortionSoundEffect", { Level = 0.22, Priority = 5 } },
		{ "EqualizerSoundEffect", { LowGain = 9, MidGain = -1, HighGain = -16, Priority = 4 } },
		{ "CompressorSoundEffect", { Threshold = -16, Ratio = 4, Attack = 0.005, Release = 0.15, Priority = 3 } },
	},
	Xylophone = {
		Curve = 2.4,
		{ "EqualizerSoundEffect", { LowGain = -8, MidGain = 2, HighGain = 5, Priority = 4 } },
		{ "ReverbSoundEffect", { DecayTime = 0.9, Density = 0.6, Diffusion = 0.8, WetLevel = -12, DryLevel = 0, Priority = 1 } },
	},
	Synth = {
		Curve = 1.1,
		{ "ChorusSoundEffect", { Depth = 0.45, Mix = 0.6, Rate = 1.6, Priority = 6 } },
		{ "FlangeSoundEffect", { Depth = 0.35, Mix = 0.3, Rate = 0.4, Priority = 5 } },
		{ "TremoloSoundEffect", { Depth = 0.3, Duty = 0.5, Frequency = 5.5, Priority = 4 } },
		{ "EchoSoundEffect", { Delay = 0.24, Feedback = 0.32, WetLevel = -9, DryLevel = 0, Priority = 3 } },
		{ "ReverbSoundEffect", { DecayTime = 2.4, Density = 0.9, Diffusion = 0.9, WetLevel = -10, DryLevel = 0, Priority = 1 } },
	},
	Kick = {
		Curve = 2,
		{ "DistortionSoundEffect", { Level = 0.15, Priority = 5 } },
		{ "EqualizerSoundEffect", { LowGain = 10, MidGain = -6, HighGain = -10, Priority = 4 } },
		{ "CompressorSoundEffect", { Threshold = -12, Ratio = 4, Attack = 0.002, Release = 0.1, Priority = 3 } },
	},
	Snare = {
		Curve = 2.2,
		{ "EqualizerSoundEffect", { LowGain = -6, MidGain = 3, HighGain = 4, Priority = 5 } },
		{ "DistortionSoundEffect", { Level = 0.2, Priority = 4 } },
		{ "ReverbSoundEffect", { DecayTime = 0.7, Density = 0.7, Diffusion = 0.8, WetLevel = -14, DryLevel = 0, Priority = 1 } },
	},
	Hats = {
		Curve = 2.6,
		{ "EqualizerSoundEffect", { LowGain = -30, MidGain = -12, HighGain = 8, Priority = 4 } },
	},
	Cymbals = {
		Curve = 1.6,
		{ "EqualizerSoundEffect", { LowGain = -24, MidGain = -4, HighGain = 6, Priority = 4 } },
		{ "ReverbSoundEffect", { DecayTime = 1.5, Density = 0.8, Diffusion = 0.9, WetLevel = -12, DryLevel = 0, Priority = 1 } },
	},
	Toms = {
		Curve = 1.8,
		{ "EqualizerSoundEffect", { LowGain = 6, MidGain = 1, HighGain = -6, Priority = 4 } },
		{ "CompressorSoundEffect", { Threshold = -14, Ratio = 3, Attack = 0.003, Release = 0.12, Priority = 3 } },
		{ "ReverbSoundEffect", { DecayTime = 1.0, Density = 0.7, Diffusion = 0.8, WetLevel = -14, DryLevel = 0, Priority = 1 } },
	},
	DJ = {
		Curve = 1.4,
		{ "DistortionSoundEffect", { Level = 0.45, Priority = 5 } },
		{ "EqualizerSoundEffect", { LowGain = 4, MidGain = 2, HighGain = -2, Priority = 4 } },
		{ "EchoSoundEffect", { Delay = 0.18, Feedback = 0.3, WetLevel = -10, DryLevel = 0, Priority = 2 } },
	},
} :: { [string]: any }

-- Pièce de batterie -> chaîne
local DRUM_CHAIN: { [string]: string } = {
	Kick = "Kick",
	Snare = "Snare",
	HatClosed = "Hats",
	HatOpen = "Hats",
	Crash = "Cymbals",
	Ride = "Cymbals",
	TomHigh = "Toms",
	TomMid = "Toms",
	TomFloor = "Toms",
}

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

-- "Ping" -> "rbxasset://sounds/electronicpingshort.wav" ; un identifiant complet reste tel quel
local function sample(name: any): string
	if type(name) ~= "string" or name == "" then
		return ""
	end
	local samples = cfg().Samples
	local id = type(samples) == "table" and samples[name] or nil
	if type(id) == "string" then
		return id
	end
	return name
end
MusicSynth.Sample = sample

-- Vitesse de lecture d'une note (repliée à l'octave dans [MinSpeed, MaxSpeed])
function MusicSynth.Speed(inst: string, note: number): number
	local c = cfg()[inst] or {}
	local base = tonumber(c.BaseNote) or 76
	local speed = 2 ^ ((note - base) / 12)
	local lo, hi = tonumber(c.MinSpeed) or 0.25, tonumber(c.MaxSpeed) or 4
	for _ = 1, 8 do
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

function MusicSynth.ChainOf(inst: string, piece: string?): string
	if inst == "Drums" then
		return DRUM_CHAIN[piece or ""] or "Toms"
	end
	if MusicSynth.CHAINS[inst] then
		return inst
	end
	return "Piano"
end

-- Couches d'une note d'un instrument mélodique (pur)
function MusicSynth.NoteLayers(inst: string, note: number, vel: number, dur: number?): { Layer }
	local out: { Layer } = {}
	local c = cfg()[inst]
	if type(c) ~= "table" then
		return out
	end
	local main = sample(c.SampleId)
	if main == "" then
		return out
	end
	vel = math.clamp(vel, 0.05, 1)
	local chain = MusicSynth.ChainOf(inst)
	local speed = MusicSynth.Speed(inst, note)
	local base = (tonumber(c.Volume) or 0.6) * vel
	local decay = tonumber(c.Decay) or 1
	if c.KeyTrack then
		-- (piano : les cordes graves vibrent plus longtemps que les aiguës)
		decay *= math.clamp(1.25 - (note - 60) / 40, 0.45, 1.6)
	end
	if dur and dur > 0 and (inst == "Bass" or inst == "Guitar" or inst == "Synth") then
		-- (notes courtes = étouffées : le groove respire)
		decay = math.clamp(dur * 1.3 + 0.12, 0.12, decay)
	end
	local layers = type(c.Layers) == "table" and c.Layers or { { 0, 1 } }
	for _, layer in ipairs(layers) do
		local semis = tonumber(layer[1]) or 0
		local cents = tonumber(layer[3]) or 0
		table.insert(out, {
			Sample = main,
			Speed = speed * 2 ^ ((semis + cents / 100) / 12),
			Volume = base * (tonumber(layer[2]) or 1),
			Decay = decay * (tonumber(layer[4]) or 1),
			Delay = 0,
			Chain = chain,
		})
	end
	if type(c.Attack) == "table" then
		-- (bruit d'attaque : plus fort quand on joue fort)
		for _, a in ipairs(c.Attack) do
			local id = sample(a[1])
			if id ~= "" then
				table.insert(out, {
					Sample = id,
					Speed = (tonumber(a[2]) or 1) * (0.94 + 0.12 * vel),
					Volume = (tonumber(c.Volume) or 0.6) * (tonumber(a[3]) or 0.1) * vel ^ 1.5,
					Decay = tonumber(a[4]) or 0.05,
					Delay = 0,
					Chain = chain,
				})
			end
		end
	end
	local pulse = c.Pulse
	if type(pulse) == "table" then
		-- (synthé : la note est rejouée -> son tenu)
		local every = math.max(0.05, tonumber(pulse.Every) or 0.17)
		local count = math.floor(tonumber(pulse.Count) or 3)
		if dur and dur > 0 then
			count = math.min(count, math.floor(dur / every))
		end
		local fade = tonumber(pulse.Fade) or 0.6
		local n = #out
		for k = 1, count do
			for i = 1, math.min(n, 2) do
				local l = out[i]
				table.insert(out, {
					Sample = l.Sample,
					Speed = l.Speed,
					Volume = l.Volume * fade ^ k,
					Decay = l.Decay,
					Delay = every * k,
					Chain = chain,
				})
			end
		end
	end
	return out
end

-- Couches d'un coup de batterie ou d'un effet du DJ (pur)
function MusicSynth.HitLayers(kind: string, index: number, vel: number): { Layer }
	local out: { Layer } = {}
	local name = (kind == "Drums" and MusicData.DRUMS or MusicData.DJ_PADS)[index]
	local d = cfg()[kind]
	if not name or type(d) ~= "table" or type(d[name]) ~= "table" then
		return out
	end
	vel = math.clamp(vel, 0.05, 1)
	local group = tonumber(d.Volume) or 0.8
	local chain = kind == "Drums" and MusicSynth.ChainOf("Drums", name) or "DJ"
	for _, layer in ipairs(d[name]) do
		local id = sample(layer[1])
		if id ~= "" then
			local speed = tonumber(layer[2]) or 1
			-- (frappe forte = un peu plus aiguë, comme une vraie peau)
			local tone = kind == "Drums" and (0.97 + 0.06 * vel) or 1
			table.insert(out, {
				Sample = id,
				Speed = speed * tone,
				Volume = (tonumber(layer[3]) or 1) * group * vel,
				Decay = tonumber(layer[4]) or 0.3,
				Delay = tonumber(layer[5]) or 0,
				SpeedTo = tonumber(layer[6]) and (tonumber(layer[6]) :: number) * tone or nil,
				SweepT = tonumber(layer[7]),
				Chain = chain,
			})
		end
	end
	return out
end

-- Empreinte d'un timbre (tests : deux instruments ne doivent pas se ressembler)
function MusicSynth.Signature(inst: string): string
	local layers
	if inst == "Drums" then
		layers = MusicSynth.HitLayers("Drums", 1, 0.8)
	elseif inst == "DJ" then
		layers = MusicSynth.HitLayers("DJ", 8, 0.8)
	else
		layers = MusicSynth.NoteLayers(inst, 60, 0.8)
	end
	local parts = {}
	for _, l in ipairs(layers) do
		table.insert(parts, string.format("%s@%.3f", string.match(l.Sample, "([^/]+)$") or l.Sample, l.Speed / (layers[1] and layers[1].Speed or 1)))
	end
	return (layers[1] and layers[1].Chain or "?") .. "|" .. #layers .. "|" .. table.concat(parts, ",")
end

type Voice = {
	Sound: Sound,
	Start: number,
	Decay: number,
	V0: number,
	Busy: boolean,
	Curve: number,
	From: number,
	To: number?,
	SweepT: number,
}

function MusicSynth.new()
	local self = setmetatable({
		Pools = {} :: { [Instance]: { [string]: { List: { Voice }, Next: number } } },
		Groups = {} :: { [string]: SoundGroup },
		Active = {} :: { Voice },
		Clock = 0,
		Played = 0,
		ByChain = {} :: { [string]: number },
		Volume = 1,
		VolumeAt = -math.huge,
	}, MusicSynth)
	return self
end

-- SoundGroup + effets d'une chaîne (créé à la première note)
function MusicSynth.Group(self: any, chain: string): SoundGroup?
	local g = self.Groups[chain]
	if g and g.Parent then
		return g
	end
	local spec = MusicSynth.CHAINS[chain]
	local ok, result = pcall(function()
		local group = Instance.new("SoundGroup")
		group.Name = "DopamineStage_" .. chain
		group.Volume = 1
		for _, fx in ipairs(spec or {}) do
			local e = Instance.new(fx[1] :: any)
			for k, v in pairs(fx[2]) do
				(e :: any)[k] = v
			end
			if chain == "Guitar" and fx[1] == "DistortionSoundEffect" then
				-- (réglage de la saturation : Config.Instruments.Guitar.Distortion)
				local level = tonumber(cfg().Guitar and cfg().Guitar.Distortion)
				if level then
					(e :: any).Level = math.clamp(level, 0, 1)
				end
			end
			e.Parent = group
		end
		group.Parent = SoundService
		return group
	end)
	if ok then
		self.Groups[chain] = result
		return result
	end
	return nil
end

local function voiceFor(self: any, emitter: Instance, sampleId: string, chain: string): Voice?
	local byEmitter = self.Pools[emitter]
	if not byEmitter then
		byEmitter = {}
		self.Pools[emitter] = byEmitter
	end
	-- (rangées par chaîne ET échantillon : chaque Sound garde le bon groupe d'effets)
	local key = chain .. "|" .. sampleId
	local pool = byEmitter[key]
	if not pool then
		pool = { List = {}, Next = 1 }
		byEmitter[key] = pool
	end
	local voice = pool.List[pool.Next]
	if not voice or not voice.Sound.Parent then
		local c = cfg()
		local sound = Instance.new("Sound")
		sound.Name = "StageVoice_" .. chain
		sound.SoundId = sampleId
		sound.RollOffMode = Enum.RollOffMode.InverseTapered
		sound.RollOffMinDistance = tonumber(c.RollOffMin) or 16
		sound.RollOffMaxDistance = tonumber(c.RollOffMax) or 140
		sound.Volume = 0
		local group = MusicSynth.Group(self, chain)
		if group then
			sound.SoundGroup = group
		end
		sound.Parent = emitter
		voice = { Sound = sound, Start = 0, Decay = 1, V0 = 0, Busy = false, Curve = 2, From = 1, To = nil, SweepT = 0 }
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

local function fire(self: any, emitter: Instance?, layer: Layer, gain: number)
	local volume = layer.Volume * gain
	if not emitter or not emitter.Parent or layer.Sample == "" or volume <= MIN_VOLUME then
		return
	end
	local function go()
		if not emitter.Parent then
			return
		end
		local voice = voiceFor(self, emitter, layer.Sample, layer.Chain)
		if not voice then
			return
		end
		local sound = voice.Sound
		local speed = math.clamp(layer.Speed, 0.03, 20)
		pcall(function()
			sound:Stop()
			sound.PlaybackSpeed = speed
			sound.Volume = volume
			sound.TimePosition = 0
			sound:Play()
		end)
		voice.Start = self.Clock
		voice.Decay = math.max(0.03, layer.Decay)
		voice.V0 = volume
		voice.Curve = (MusicSynth.CHAINS[layer.Chain] and MusicSynth.CHAINS[layer.Chain].Curve) or 2
		voice.From = speed
		voice.To = layer.SpeedTo and math.clamp(layer.SpeedTo, 0.03, 20) or nil
		voice.SweepT = layer.SweepT or 0
		if not voice.Busy then
			voice.Busy = true
			table.insert(self.Active, voice)
		end
		self.Played += 1
		self.ByChain[layer.Chain] = (self.ByChain[layer.Chain] or 0) + 1
	end
	if layer.Delay > 0.005 then
		task.delay(layer.Delay, go)
	else
		go()
	end
end

-- Note d'un instrument mélodique (dur : durée prévue en s, si connue)
function MusicSynth.Note(self: any, inst: string, note: number, vel: number, emitter: Instance?, dur: number?)
	local m = master(self)
	if m <= 0 then
		return
	end
	for _, layer in ipairs(MusicSynth.NoteLayers(inst, note, vel, dur)) do
		fire(self, emitter, layer, m)
	end
end

function MusicSynth.Drum(self: any, piece: number, vel: number, emitter: Instance?)
	local m = master(self)
	if m <= 0 then
		return
	end
	for _, layer in ipairs(MusicSynth.HitLayers("Drums", piece, vel)) do
		fire(self, emitter, layer, m)
	end
end

function MusicSynth.Pad(self: any, pad: number, vel: number, emitter: Instance?)
	local m = master(self)
	if m <= 0 then
		return
	end
	for _, layer in ipairs(MusicSynth.HitLayers("DJ", pad, vel)) do
		fire(self, emitter, layer, m)
	end
end

-- Enveloppes (fondu de sortie) + glissés de hauteur de chaque voix
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
			-- (courbe propre à la chaîne : forte attaque puis extinction)
			local u = age / voice.Decay
			sound.Volume = voice.V0 * (1 - u) ^ voice.Curve
			local to = voice.To
			if to and voice.SweepT > 0 then
				local w = math.min(1, age / voice.SweepT)
				w = 1 - (1 - w) * (1 - w)
				sound.PlaybackSpeed = voice.From + (to - voice.From) * w
			end
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
