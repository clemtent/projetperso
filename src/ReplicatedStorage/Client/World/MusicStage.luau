--[[
	MusicStage (ModuleScript)
	Emplacement : ReplicatedStorage > Client > World > MusicStage

	🎵 SCÈNE MUSICALE de la place, côté CLIENT (v9.9, MUSIC99).
	Le serveur (TownMusic) pose le plancher, les invites "Jouer" (E), le
	juke-box (E : morceaux, F : radio), qui joue de quoi (attribut "Player")
	et le morceau en cours (SongId / SongStart). Ici :
	  - le DÉCOR complet (MusicStageBuild), en flux : construit à moins de
	    BUILD_R studs (x Détail), un morceau par image ; détruit au-delà de
	    DROP_R ;
	  - JOUER : l'invite "Jouer" -> le serveur réserve l'instrument ->
	    l'avatar est placé à son poste (assis au piano / à la batterie),
	    déplacements coupés, panneau de jeu (MusicUI) + touches du clavier
	    (ContextActionService, priorité haute : ZQSD ne fait pas bouger
	    l'avatar pendant qu'on joue ; Espace = se lever) ;
	  - les SONS (MusicSynth) : chaque note est jouée tout de suite chez soi,
	    puis envoyée par paquets (MusicData.SEND_EVERY) ; les voisins la
	    reçoivent (relais du serveur) et l'entendent / la voient jouer ;
	  - les MORCEAUX pré-enregistrés (MusicData) : joués par tous les
	    clients à partir de la même heure du serveur ; les instruments
	    jouent tout seuls (touches qui s'enfoncent, fûts qui vibrent,
	    cymbales qui oscillent, platines qui tournent) et les musiciens
	    présents jouent leur partie automatiquement ;
	  - la RADIO lofi (Config.Music.Playlist) en son 3D sur la scène ;
	  - les MUSICIENS animés (MusicPose : mains sur les touches, baguettes,
	    médiators, platines) pour TOUS les joueurs proches ;
	  - l'écran LED (titre, égaliseur, progression), les lyres
	    motorisées et leurs faisceaux (la nuit), les lueurs des projecteurs.

	API (TownClient, via optionalModule) :
	  MusicStage.Start(options?)   à l'entrée en ville
	  MusicStage.Step(dt)          à chaque image
	  MusicStage.Stop()            à la sortie (tout est détruit / remis)
	  MusicStage.Debug() -> table
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ContextActionService = game:GetService("ContextActionService")

local Config = require(ReplicatedStorage.Shared.Config)
local Locale = require(ReplicatedStorage.Shared.Locale)
local MusicData = require(ReplicatedStorage.Shared.MusicData)
local GraphicsQuality = require(ReplicatedStorage.Shared.GraphicsQuality)
local MusicStageBuild = require(script.Parent.MusicStageBuild)
local MusicSynth = require(script.Parent.MusicSynth)
local MusicPose = require(script.Parent.MusicPose)
local MusicUI = require(script.Parent.MusicUI)

local MusicStage = {}

local LocalPlayer = Players.LocalPlayer

local BUILD_R = 210 -- (studs) on construit le décor…
local DROP_R = 290 -- …on le détruit au-delà
local POSE_R = 110 -- musiciens animés à moins de…
local VISUAL_STEP = 1 / 30
local LOOKAHEAD = 0.12 -- (s) notes des morceaux programmées d'avance
local ACTION = "DopamineStageKeys"
local UP = Vector3.new(0, 1, 0)
local TAU = math.pi * 2

local state: any = nil

local function T(text: string, ...): string
	return Locale.T(text, ...)
end

local function serverNow(): number
	return workspace:GetServerTimeNow()
end

-- Horloge locale de la scène (somme des dt de Step : suit les images)
local function clockNow(): number
	local s = state
	return s and s.Clock or 0
end

local function smooth(x: number): number
	x = math.clamp(x, 0, 1)
	return x * x * (3 - 2 * x)
end

----------------------------------------------------------------------
-- Claviers (disposition "tracker" : 2 rangées = 2 octaves + 5 notes)
----------------------------------------------------------------------

local K = Enum.KeyCode
local LOWER_ROW = { K.Z, K.S, K.X, K.D, K.C, K.V, K.G, K.B, K.H, K.N, K.J, K.M }
local UPPER_ROW = { K.Q, K.Two, K.W, K.Three, K.E, K.R, K.Five, K.T, K.Six, K.Y, K.Seven, K.U, K.I, K.Nine, K.O, K.Zero, K.P }
local KEY_SPAN = 29 -- demi-tons montrés (Do .. Mi + 2 octaves)

local DEFAULT_LOW: { [string]: number } = { Piano = 48, Synth = 60, Xylophone = 60 }
local LOW_RANGE: { [string]: { number } } = { Piano = { 24, 72 }, Synth = { 36, 72 }, Xylophone = { 48, 72 } }

-- Accords de la guitare (valeur = 1000 + index)
local CHORDS = { "C", "G", "Am", "F", "D", "Em", "E", "Dm" }
local CHORD_KEYS = { K.One, K.Two, K.Three, K.Four, K.Five, K.Six, K.Seven, K.Eight }
local CHORDS_FR: { [string]: string } = { C = "Do", G = "Sol", Am = "Lam", F = "Fa", D = "Ré", Em = "Mim", E = "Mi", Dm = "Rém" }
local SOLO = { 57, 60, 62, 64, 67, 69, 72, 74, 76 } -- pentatonique de La mineur
local SOLO_KEYS = { K.A, K.S, K.D, K.F, K.G, K.H, K.J, K.K, K.L }
local BASS_LOW = { 36, 38, 40, 41, 43, 45, 46, 47 }
local BASS_HIGH = { 48, 50, 52, 53, 55, 57, 58, 60 }
local BASS_LOW_KEYS = { K.A, K.S, K.D, K.F, K.G, K.H, K.J, K.K }
local BASS_HIGH_KEYS = { K.Q, K.W, K.E, K.R, K.T, K.Y, K.U, K.I }
-- (v11) notes du solo sur le manche : { corde (1 = Mi aigu), case } (gamme
-- pentatonique de La mineur, position en case 5)
local SOLO_POS = { { 6, 5 }, { 6, 8 }, { 5, 5 }, { 5, 7 }, { 4, 5 }, { 4, 7 }, { 3, 5 }, { 3, 7 }, { 2, 5 } }
-- (v11) 8 boucles du DJ : première rangée du clavier
local DJ_LOOP_KEYS = { K.Q, K.W, K.E, K.R, K.T, K.Y, K.U, K.I }

local PAD = {
	Red = Color3.fromRGB(236, 96, 120),
	Blue = Color3.fromRGB(96, 150, 236),
	Gold = Color3.fromRGB(226, 172, 70),
	Lilac = Color3.fromRGB(160, 120, 226),
	Mint = Color3.fromRGB(80, 190, 150),
	Pink = Color3.fromRGB(236, 110, 170),
}


----------------------------------------------------------------------
-- Outils
----------------------------------------------------------------------

local function remote(): RemoteEvent?
	local folder = ReplicatedStorage:FindFirstChild("Remotes")
	local r = folder and folder:FindFirstChild("MusicEvent")
	return (r and r:IsA("RemoteEvent")) and r or nil
end

local function fire(...: any)
	local r = remote()
	if r then
		r:FireServer(...)
	end
end

local function rootOf(player: Player?): BasePart?
	local character = player and player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	return (root and root:IsA("BasePart")) and root or nil
end

local function findStage(): Folder?
	local town = workspace:FindFirstChild("DopamineTown")
	if not town then
		return nil
	end
	local decor = town:FindFirstChild("Decor")
	local plaza = decor and decor:FindFirstChild("Plaza")
	local found = plaza and plaza:FindFirstChild("MusicStage")
	if not found then
		found = town:FindFirstChild("MusicStage", true)
	end
	return (found and found:IsA("Folder")) and found or nil
end

local atmosphere: any = nil
local function isNight(): boolean
	if atmosphere == nil then
		local module = script.Parent:FindFirstChild("TownAtmosphere")
		local ok, result = false, nil
		if module then
			ok, result = pcall(require, module)
		end
		atmosphere = ok and result or false
	end
	if atmosphere and type(atmosphere.LampsOn) == "function" then
		local ok, on = pcall(atmosphere.LampsOn)
		if ok then
			return on == true
		end
	end
	local clock = game:GetService("Lighting").ClockTime
	return clock < 6.3 or clock > 18
end

local controlsModule: any = nil
local function setControls(enabled: boolean)
	if controlsModule == nil then
		controlsModule = false
		pcall(function()
			local playerScripts = LocalPlayer:FindFirstChild("PlayerScripts")
			local module = playerScripts and playerScripts:FindFirstChild("PlayerModule")
			if module and module:IsA("ModuleScript") then
				controlsModule = (require(module) :: any):GetControls()
			end
		end)
	end
	if controlsModule then
		pcall(function()
			if enabled then
				controlsModule:Enable()
			else
				controlsModule:Disable()
			end
		end)
	end
end

local function anchorOf(id: string): BasePart?
	local s = state
	local folder = s and s.Folder
	local a = folder and folder:FindFirstChild("Play_" .. id)
	return (a and a:IsA("BasePart")) and a or nil
end

local function occupant(id: string): number
	local a = anchorOf(id)
	local v = a and a:GetAttribute("Player")
	return type(v) == "number" and v or 0
end

----------------------------------------------------------------------
-- Visuels des coups (touches, fûts, cymbales, platines, écran)
----------------------------------------------------------------------

local ENERGY_BAND: { [string]: { number } } = {
	Bass = { 1, 5 },
	Drums = { 1, 24 },
	Piano = { 6, 16 },
	Synth = { 8, 20 },
	Guitar = { 6, 14 },
	Xylophone = { 14, 24 },
	DJ = { 1, 24 },
}

-- Touche la plus proche qui existe (même note à l'octave près)
local function keyFor(keys: any, n: number): any
	if not keys then
		return nil
	end
	local k = keys[n]
	local m = n
	for _ = 1, 6 do
		if k then
			return k
		end
		if m < 60 then
			m += 12
		else
			m -= 12
		end
		k = keys[m]
	end
	return k
end

local function pressKey(s: any, keys: any, n: number, depth: number)
	local key = keyFor(keys, n)
	if not key or not key.Part.Parent then
		return
	end
	key.Part.CFrame = key.CF * CFrame.new(0, -depth, 0.02) * CFrame.Angles(math.rad(-2.5), 0, 0)
	s.Pressed[key.Part] = { CF = key.CF, Until = clockNow() + 0.16 }
end

local function energize(s: any, inst: string, vel: number, n: number?)
	local band = ENERGY_BAND[inst] or { 1, 24 }
	local lo, hi = band[1], band[2]
	local center = n and (lo + (hi - lo) * math.clamp(((n % 48) / 48), 0, 1)) or math.random(lo, hi)
	for i = lo, hi do
		local d = math.abs(i - center)
		local add = vel * math.max(0, 1 - d / 5)
		s.Energy[i] = math.min(1, (s.Energy[i] or 0) + add * 0.7)
	end
	s.LastHit = clockNow()
end

----------------------------------------------------------------------
-- Mains des musiciens (points visés, mis à jour par les coups)
----------------------------------------------------------------------

local function handState(s: any, inst: string): any
	local hs = s.Hands[inst]
	if not hs then
		hs = { R = { HitT = -math.huge }, L = { HitT = -math.huge }, KickT = -math.huge, Note = 60, Chord = 0, Strum = 1, ScratchT = -math.huge, UpT = -math.huge }
		s.Hands[inst] = hs
	end
	return hs
end

-- Un coup sur un instrument : son + visuel + mains du musicien
local function hit(inst: string, n: number, vel: number, via: string?, dur: number?)
	local s = state
	if not s then
		return
	end
	local H = s.Build and s.Build.H
	local emitters = H and H.Emitters or {}
	local emitter = emitters[via or inst]
	local kind = inst
	if inst == "Drums" then
		s.Synth:Drum(n, vel, emitter)
	elseif inst == "DJ" then
		s.Synth:Pad(n, vel, emitter)
	else
		s.Synth:Note(inst, n, vel, emitter, dur)
	end
	energize(s, inst, vel, (inst ~= "Drums" and inst ~= "DJ") and n or nil)
	if s.Playing == (via or inst) and s.UI then
		s.UI:Flash(n, vel)
	end
	if via then
		-- (boucles du DJ : seules les platines réagissent)
		local hs = handState(s, via)
		if inst == "Drums" and n == MusicData.DRUM.Snare then
			hs.R.HitT = clockNow()
		end
		return
	end
	if not H then
		return
	end
	local hs = handState(s, kind)
	local now = clockNow()
	if inst == "Piano" or inst == "Synth" or inst == "Xylophone" then
		local keys = H.Keys[inst]
		pressKey(s, keys, n, inst == "Xylophone" and 0.02 or 0.04)
		local key = keyFor(keys, n)
		if key then
			local side = n < (inst == "Xylophone" and 78 or 60) and "L" or "R"
			if inst == "Xylophone" and now - hs[side].HitT < 0.09 then
				side = side == "L" and "R" or "L"
			end
			hs[side].HitT = now
			hs[side].Point = key.Top
			hs[side].Vel = vel
		end
	elseif inst == "Drums" then
		local piece = H.Drums and H.Drums[n]
		if n == MusicData.DRUM.Kick then
			hs.KickT = now
		end
		if piece then
			s.Wobble[n] = { T = now, A = vel }
			if n ~= MusicData.DRUM.Kick then
				local left = n == MusicData.DRUM.Snare or n == MusicData.DRUM.TomHigh or n == MusicData.DRUM.Crash
				local side = left and "L" or "R"
				hs[side].HitT = now
				hs[side].Point = piece.Hit
				hs[side].Vel = vel
			end
		end
	elseif inst == "Guitar" or inst == "Bass" then
		if now - hs.R.HitT > 0.08 then
			hs.Strum = -hs.Strum
			hs.R.HitT = now
		end
		hs.Note = n
	elseif inst == "DJ" then
		if n == MusicData.DJ_FX.Scratch then
			hs.ScratchT = now
			s.Scratch = { T = now }
		else
			hs.UpT = now
		end
	end
end

----------------------------------------------------------------------
-- Jouer (joueur local)
----------------------------------------------------------------------

local function layoutFor(id: string): any
	local s = state
	local st = MusicData.STATIONS[id]
	local fr = Locale.IsFrench()
	if st.Kind == "keys" then
		local low = s.Octave[id] or DEFAULT_LOW[id] or 48
		local keys = {}
		for i, kc in ipairs(LOWER_ROW) do
			keys[low + i - 1] = kc
		end
		keys[low + 12] = K.Comma
		for i, kc in ipairs(UPPER_ROW) do
			keys[low + 11 + i] = kc
		end
		return { Kind = "keys", Low = low, Count = KEY_SPAN, Keys = keys }
	elseif id == "Drums" then
		-- (v11) le kit vu du dessus : chaque pièce à sa vraie place
		local D = MusicData.DRUM
		return {
			Kind = "drums",
			Pads = {
				{ Name = "Crash", Value = D.Crash, Label = T("Crash"), KeyCode = K.Q, X = 0.2, Y = 0.27, R = 0.26, Type = "cymbal" },
				{ Name = "HiHat", Value = D.HatClosed, Label = T("Hi-hat"), KeyCode = K.S, X = 0.075, Y = 0.6, R = 0.2, Type = "hat" },
				{ Name = "HiHatOpen", Value = D.HatOpen, Label = T("Open hi-hat"), KeyCode = K.A, X = 0.085, Y = 0.92, R = 0.09, Type = "pill" },
				{ Name = "Snare", Value = D.Snare, Label = T("Snare"), KeyCode = K.D, X = 0.275, Y = 0.68, R = 0.19, Type = "drum", Shell = Color3.fromRGB(190, 192, 204) },
				{ Name = "Tom1", Value = D.TomHigh, Label = T("Tom 1"), KeyCode = K.W, X = 0.4, Y = 0.28, R = 0.16, Type = "drum" },
				{ Name = "Tom2", Value = D.TomMid, Label = T("Tom 2"), KeyCode = K.E, X = 0.585, Y = 0.28, R = 0.17, Type = "drum" },
				{ Name = "Kick", Value = D.Kick, Label = T("Bass drum"), KeyCode = K.X, X = 0.49, Y = 0.72, R = 0.28, Type = "kick" },
				{ Name = "FloorTom", Value = D.TomFloor, Label = T("Floor tom"), KeyCode = K.F, X = 0.72, Y = 0.7, R = 0.21, Type = "drum" },
				{ Name = "Ride", Value = D.Ride, Label = T("Ride"), KeyCode = K.R, X = 0.88, Y = 0.3, R = 0.27, Type = "cymbal" },
			},
		}
	elseif id == "Guitar" then
		local chords, notes = {}, {}
		for i, name in ipairs(CHORDS) do
			table.insert(chords, { Value = 1000 + i, Label = fr and (CHORDS_FR[name] or name) or name, KeyCode = CHORD_KEYS[i] })
		end
		for i, n in ipairs(SOLO) do
			local pos = SOLO_POS[i]
			table.insert(notes, { Value = n, Label = MusicData.NoteName(n, fr), KeyCode = SOLO_KEYS[i], String = pos[1], Fret = pos[2] })
		end
		return { Kind = "guitar", Chords = chords, Notes = notes }
	elseif id == "Bass" then
		local notes = {}
		for i, n in ipairs(BASS_HIGH) do
			table.insert(notes, { Value = n, Label = MusicData.NoteName(n, fr), KeyCode = BASS_HIGH_KEYS[i], String = 1, Fret = n - 43, Color = Color3.fromRGB(110, 160, 255) })
		end
		for i, n in ipairs(BASS_LOW) do
			table.insert(notes, { Value = n, Label = MusicData.NoteName(n, fr), KeyCode = BASS_LOW_KEYS[i], String = 3, Fret = n - 33, Color = Color3.fromRGB(160, 110, 255) })
		end
		return { Kind = "bass", Notes = notes }
	else -- DJ
		local loops, fx = {}, {}
		for i = 1, MusicData.DJ_LOOPS do
			table.insert(loops, { Value = i, Label = T(MusicData.LOOP_NAMES[i]), Icon = MusicData.LOOP_ICONS[i], KeyCode = DJ_LOOP_KEYS[i], Color = Color3.fromHSV((i - 1) / 8, 0.65, 0.9) })
		end
		local F = MusicData.DJ_FX
		table.insert(fx, { Value = F.Scratch, Label = "💿 " .. T("Scratch"), KeyCode = K.A, Color = PAD.Pink })
		table.insert(fx, { Value = F.Horn, Label = "📯 " .. T("Horn"), KeyCode = K.S, Color = PAD.Gold })
		table.insert(fx, { Value = F.Riser, Label = "🌊 " .. T("Riser"), KeyCode = K.D, Color = PAD.Mint })
		table.insert(fx, { Value = F.Drop, Label = "💥 " .. T("Drop"), KeyCode = K.F, Color = PAD.Red })
		return { Kind = "dj", Loops = loops, Fx = fx }
	end
end

local function keyMap(layout: any): { [Enum.KeyCode]: number }
	local map = {}
	if layout.Kind == "keys" then
		for n, kc in pairs(layout.Keys) do
			map[kc] = n
		end
	else
		local function add(list: any)
			for _, pad in ipairs(list or {}) do
				if pad.KeyCode then
					map[pad.KeyCode] = pad.Value
				end
			end
		end
		add(layout.Pads)
		add(layout.Chords)
		add(layout.Notes)
		add(layout.Loops)
		add(layout.Fx)
		if layout.Kind == "drums" then
			map[K.C] = MusicData.DRUM.Kick
			map[K.V] = MusicData.DRUM.Kick
		end
	end
	return map
end

local function queue(n: number, vel: number)
	local s = state
	if not s or not s.Playing then
		return
	end
	local now = clockNow()
	if #s.Out == 0 then
		s.OutStart = now
	end
	if #s.Out >= MusicData.MAX_BATCH * 3 then
		return
	end
	table.insert(s.Out, n)
	table.insert(s.Out, math.floor(vel * 100 + 0.5))
	table.insert(s.Out, math.floor((now - s.OutStart) * 1000 + 0.5))
end

local function flush(force: boolean?)
	local s = state
	if not s or #s.Out == 0 then
		return
	end
	if not force and clockNow() - s.OutStart < MusicData.SEND_EVERY then
		return
	end
	local id = s.Playing
	if id then
		fire("notes", MusicData.INDEX[id], s.Out)
	end
	s.Out = {}
end

local function playLocal(value: number, vel: number)
	local s = state
	if not s or not s.Playing then
		return
	end
	local id = s.Playing
	s.LastInput = clockNow()
	if id == "DJ" then
		if value <= MusicData.DJ_LOOPS then
			local current = anchorOf("DJ")
			local loop = current and current:GetAttribute("Loop")
			fire("loop", (loop == value) and 0 or value)
			s.UI:Flash(value)
			return
		end
		hit("DJ", value, vel)
		queue(value, vel)
		return
	end
	if id == "Guitar" and value > 1000 then
		local name = CHORDS[value - 1000]
		local now = clockNow()
		local down = not (s.LastChord == value and now - (s.LastChordT or 0) < 0.4 and s.LastDown)
		s.LastChord, s.LastChordT, s.LastDown = value, now, down
		local root = MusicData.Root(name, 40) or 48
		local voicing = { root }
		for _, n in ipairs(MusicData.ChordNotes(name, 58)) do
			table.insert(voicing, n)
		end
		table.insert(voicing, (MusicData.ChordNotes(name, 66))[1] or root + 24)
		local count = down and #voicing or 3
		for k = 1, count do
			local n = down and voicing[k] or voicing[#voicing - k + 1]
			local delay = (k - 1) * 0.028
			task.delay(delay, function()
				if state == s then
					hit("Guitar", n, vel * (down and 0.9 or 0.7))
				end
			end)
			queue(n, vel * (down and 0.9 or 0.7))
			-- (décalage réel conservé pour les voisins)
			s.Out[#s.Out] = s.Out[#s.Out] + math.floor(delay * 1000)
		end
		s.UI:Flash(value)
		return
	end
	hit(id, value, vel)
	queue(value, vel)
end

local function refreshOctave()
	local s = state
	local id = s and s.Playing
	if not id or MusicData.STATIONS[id].Kind ~= "keys" then
		return
	end
	local low = s.Octave[id] or DEFAULT_LOW[id]
	s.UI:SetOctaveText(MusicData.NoteName(low, Locale.IsFrench()) .. " – " .. MusicData.NoteName(low + KEY_SPAN - 1, Locale.IsFrench()))
	s.UI:SetOctaveRange(low, KEY_SPAN)
end

local exitLocal: (sendLeave: boolean) -> ()

local function bindKeys(layout: any)
	local s = state
	s.KeyMap = keyMap(layout)
	local list = {}
	for kc in pairs(s.KeyMap) do
		table.insert(list, kc)
	end
	table.insert(list, K.Space)
	table.insert(list, K.Left)
	table.insert(list, K.Right)
	pcall(function()
		ContextActionService:UnbindAction(ACTION)
	end)
	pcall(function()
		ContextActionService:BindActionAtPriority(ACTION, function(_name: string, inputState: Enum.UserInputState, input: InputObject)
			local cur = state
			if not cur or not cur.Playing then
				return Enum.ContextActionResult.Pass
			end
			if inputState == Enum.UserInputState.Begin then
				local kc = input.KeyCode
				if kc == K.Space then
					exitLocal(true)
				elseif kc == K.Left or kc == K.Right then
					cur.UICallbacks.Octave(kc == K.Left and -1 or 1)
				else
					local value = cur.KeyMap[kc]
					if value then
						playLocal(value, 0.85)
					end
				end
			end
			return Enum.ContextActionResult.Sink
		end, false, Enum.ContextActionPriority.High.Value + 50, table.unpack(list))
	end)
end

local function setStagePromptsHidden(hidden: boolean)
	local s = state
	local folder = s and s.Folder
	if not folder then
		return
	end
	for _, d in ipairs(folder:GetDescendants()) do
		if d:IsA("ProximityPrompt") then
			if hidden then
				d.Enabled = false
			else
				local host = d.Parent
				local who = host and host:GetAttribute("Player")
				d.Enabled = not (type(who) == "number" and who ~= 0)
			end
		end
	end
end

local function enterLocal(id: string)
	local s = state
	if not s or not s.Folder then
		return
	end
	local character = LocalPlayer.Character
	local root = rootOf(LocalPlayer)
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not root or not humanoid or not character then
		fire("leave")
		return
	end
	s.Playing = id
	s.LastInput = -math.huge
	-- l'avatar à son poste (pieds au sol du poste, regard vers l'instrument)
	local spot = MusicData.SpotCFrame(s.StageCF, id)
	local lift = humanoid.RigType == Enum.HumanoidRigType.R6 and 3 or ((tonumber(humanoid.HipHeight) or 2) + root.Size.Y / 2)
	pcall(function()
		root.AssemblyLinearVelocity = Vector3.zero
		character:PivotTo(spot * CFrame.new(0, lift + 0.05, 0))
	end)
	setControls(false)
	local layout = layoutFor(id)
	s.UI:Open(id, layout)
	refreshOctave()
	if id == "DJ" then
		local a = anchorOf("DJ")
		s.UI:SetLoop(a and a:GetAttribute("Loop") or 0)
	end
	bindKeys(layout)
	setStagePromptsHidden(true)
end

exitLocal = function(sendLeave: boolean)
	local s = state
	if not s or not s.Playing then
		return
	end
	flush(true)
	s.Playing = nil
	pcall(function()
		ContextActionService:UnbindAction(ACTION)
	end)
	setControls(true)
	s.UI:Close()
	s.UI:ClosePicker()
	setStagePromptsHidden(false)
	if sendLeave then
		fire("leave")
	end
end

-- État de la discothèque (attributs du dossier, partagés par le serveur)
local function pickerState(): any
	local s = state
	local folder = s and s.Folder
	if not folder then
		return {}
	end
	local queue = {}
	local raw = folder:GetAttribute("Queue")
	if type(raw) == "string" then
		for id in string.gmatch(raw, "[^,]+") do
			if MusicData.SONG_INDEX[id] then
				table.insert(queue, id)
			end
		end
	end
	local id = folder:GetAttribute("SongId")
	local start = folder:GetAttribute("SongStart")
	local mode = folder:GetAttribute("SongMode")
	local st: any = { SongId = (type(id) == "string" and id ~= "") and id or nil, Radio = folder:GetAttribute("Radio"), Chain = s.Chain or mode == "all", Queue = queue }
	if st.SongId and type(start) == "number" then
		local total = MusicData.Duration(st.SongId)
		local elapsed = math.clamp(serverNow() - start, 0, total)
		st.Elapsed, st.Total = elapsed, total
		st.Progress = total > 0 and elapsed / total or 0
	end
	return st
end

local function openPicker()
	local s = state
	if not s or not s.Folder then
		return
	end
	s.UI:OpenPicker(pickerState())
end

----------------------------------------------------------------------
-- Réseau
----------------------------------------------------------------------

local function onEvent(kind: any, a: any, b: any, c: any)
	local s = state
	if not s or type(kind) ~= "string" then
		return
	end
	if kind == "open" and type(a) == "string" and MusicData.STATIONS[a] then
		if s.Playing then
			exitLocal(false)
		end
		enterLocal(a)
	elseif kind == "close" then
		exitLocal(false)
	elseif kind == "busy" and type(a) == "string" then
		local st = MusicData.STATIONS[a]
		if s.Toast and st then
			pcall(s.Toast, T("Someone is already playing the %s!", T(st.Name)), Color3.fromRGB(226, 80, 90))
		end
	elseif kind == "picker" then
		openPicker()
	elseif kind == "notes" and type(b) == "number" and type(c) == "table" then
		if a == LocalPlayer.UserId then
			return
		end
		local inst = MusicData.ORDER[b]
		if not inst then
			return
		end
		for i = 1, math.min(#c // 3, MusicData.MAX_BATCH) do
			local n, v, dt = c[i * 3 - 2], c[i * 3 - 1], c[i * 3]
			if type(n) == "number" and type(v) == "number" and type(dt) == "number" then
				task.delay(math.clamp(dt, 0, 400) / 1000, function()
					if state == s then
						hit(inst, n, math.clamp(v / 100, 0.05, 1))
					end
				end)
			end
		end
	end
end

----------------------------------------------------------------------
-- Morceaux, boucles du DJ, radio
----------------------------------------------------------------------

local function stepSong(s: any, now: number)
	local folder = s.Folder
	local id = folder:GetAttribute("SongId")
	local start = folder:GetAttribute("SongStart")
	if type(id) ~= "string" or id == "" or type(start) ~= "number" then
		s.Song = nil
		return
	end
	local song = s.Song
	if not song or song.Id ~= id or song.Start ~= start then
		local data = MusicData.Song(id)
		if not data then
			s.Song = nil
			return
		end
		-- (on arrive en cours de morceau : on reprend là où il en est)
		local ptr = 1
		while data.Events[ptr] and start + data.Events[ptr].T < now - 0.05 do
			ptr += 1
		end
		song = { Id = id, Start = start, Data = data, Ptr = ptr }
		s.Song = song
	end
	local events = song.Data.Events
	while events[song.Ptr] and song.Start + events[song.Ptr].T <= now + LOOKAHEAD do
		local ev = events[song.Ptr]
		song.Ptr += 1
		local at = song.Start + ev.T
		if at >= now - 0.25 then
			local delay = math.max(0, at - now)
			if delay < 0.01 then
				hit(ev.I, ev.N, ev.V, nil, ev.D)
			else
				task.delay(delay, function()
					if state == s then
						hit(ev.I, ev.N, ev.V, nil, ev.D)
					end
				end)
			end
		end
	end
end

local function stepLoop(s: any, now: number)
	local a = anchorOf("DJ")
	local loop = a and a:GetAttribute("Loop")
	local start = a and a:GetAttribute("LoopStart")
	if type(loop) ~= "number" or loop <= 0 or type(start) ~= "number" or occupant("DJ") == 0 then
		s.LoopCursor = nil
		s.LoopId = 0
		return
	end
	if s.LoopId ~= loop or s.LoopStart ~= start then
		s.LoopId, s.LoopStart = loop, start
		s.LoopCursor = math.max(now, start) - 1e-3
		if s.Playing == "DJ" then
			s.UI:SetLoop(loop)
		end
	end
	local bar = MusicData.LOOP_BAR
	local horizon = now + LOOKAHEAD
	local cursor = s.LoopCursor or now
	if horizon <= cursor then
		return
	end
	local events = MusicData.Loop(loop)
	local first = math.floor((cursor - start) / bar)
	local last = math.floor((horizon - start) / bar)
	for k = math.max(0, first), last do
		local barStart = start + k * bar
		for _, ev in ipairs(events) do
			local at = barStart + ev.T
			if at > cursor and at <= horizon then
				task.delay(math.max(0, at - now), function()
					if state == s then
						hit(ev.I, ev.N, ev.V, "DJ", ev.D)
					end
				end)
			end
		end
	end
	s.LoopCursor = horizon
end

local function stepRadio(s: any, now: number)
	local folder = s.Folder
	local index = folder:GetAttribute("Radio")
	local start = folder:GetAttribute("RadioStart")
	local emitter = s.Build and s.Build.H.Radio
	local playlist = Config.Music and Config.Music.Playlist or {}
	local track = type(index) == "number" and index > 0 and playlist[index] or nil
	local radio = s.Radio
	if not track or not emitter or not emitter.Parent then
		if radio then
			pcall(function()
				radio.Sound:Destroy()
			end)
			s.Radio = nil
		end
		return
	end
	if not radio or radio.Index ~= index or radio.Start ~= start or not radio.Sound.Parent then
		if radio then
			pcall(function()
				radio.Sound:Destroy()
			end)
		end
		local c = Config.Instruments.Radio
		local sound = Instance.new("Sound")
		sound.Name = "StageRadio"
		sound.SoundId = track.Id
		sound.Looped = true
		sound.RollOffMode = Enum.RollOffMode.InverseTapered
		sound.RollOffMinDistance = c.RollOffMin
		sound.RollOffMaxDistance = c.RollOffMax
		sound.Volume = 0
		sound.Parent = emitter
		pcall(function()
			sound:Play()
		end)
		radio = { Sound = sound, Index = index, Start = start, Synced = false }
		s.Radio = radio
	end
	local sound = radio.Sound
	if not radio.Synced and sound.IsLoaded and sound.TimeLength > 1 then
		radio.Synced = true
		pcall(function()
			sound.TimePosition = (now - (tonumber(start) or now)) % sound.TimeLength
		end)
	end
	-- (volume : réglage de la scène x volume des effets du joueur)
	local user = s.Synth and s.Synth.Volume or 1
	sound.Volume = Config.Instruments.Radio.Volume * user
end

----------------------------------------------------------------------
-- Animation du décor (30 Hz, de près)
----------------------------------------------------------------------

local function musicActive(s: any): boolean
	return s.Song ~= nil or (s.Radio ~= nil) or (s.LoopId or 0) > 0 or clockNow() - (s.LastHit or -math.huge) < 2
end

local function stepVisuals(s: any, dt: number, now: number)
	local H = s.Build and s.Build.H
	if not H then
		return
	end
	local clock = clockNow()
	-- touches relâchées
	for part, info in pairs(s.Pressed) do
		if clock >= info.Until then
			if part.Parent then
				part.CFrame = info.CF
			end
			s.Pressed[part] = nil
		end
	end
	-- fûts qui vibrent, cymbales qui oscillent, batte de grosse caisse
	local pieces = H.Drums
	if pieces then
		local moved, cfs = {}, {}
		for n, w in pairs(s.Wobble) do
			local piece = pieces[n]
			local age = clock - w.T
			if not piece or age > 1.6 then
				if piece then
					for i, p in ipairs(piece.Parts) do
						table.insert(moved, p)
						table.insert(cfs, piece.CFs[i])
					end
				end
				s.Wobble[n] = nil
			else
				local offset: CFrame
				if piece.Kind == "cymbal" then
					local ang = math.rad(9) * w.A * math.exp(-age * 2.6) * math.sin(age * 15)
					local axis = piece.Axis:Cross(UP)
					if axis.Magnitude < 1e-3 then
						axis = Vector3.new(1, 0, 0)
					end
					offset = CFrame.new(piece.Center) * CFrame.fromAxisAngle(axis.Unit, ang) * CFrame.new(-piece.Center)
				else
					local d = 0.035 * w.A * math.exp(-age * 18) * math.cos(age * 40)
					offset = CFrame.new(-piece.Axis * d)
				end
				for i, p in ipairs(piece.Parts) do
					table.insert(moved, p)
					table.insert(cfs, offset * piece.CFs[i])
				end
			end
		end
		if #moved > 0 then
			pcall(function()
				workspace:BulkMoveTo(moved, cfs, Enum.BulkMoveMode.FireCFrameChanged)
			end)
		end
	end
	local beater = H.Beater
	if beater and beater.Part.Parent then
		local hs = s.Hands.Drums
		local age = hs and (clock - hs.KickT) or 99
		local swing = age < 0.25 and math.sin(math.clamp(age / 0.25, 0, 1) * math.pi) or 0
		local strike = age < 0.25 and (1 - age / 0.25) or 0
		beater.Part.CFrame = beater.Pivot * CFrame.Angles(math.rad(-25 + 30 * strike - 5 * swing), 0, 0) * CFrame.new(0, 0.4 * MusicData.KIT_SCALE, 0)
	end
	-- platines du DJ
	local dj = H.DJ
	if dj then
		local spinning = (s.LoopId or 0) > 0 or s.Song ~= nil or occupant("DJ") ~= 0
		local scratch = s.Scratch and (clock - s.Scratch.T) < 0.5
		for i, platter in ipairs(dj.Platters) do
			local speed = spinning and TAU * 0.55 or 0
			if scratch and i == 2 then
				speed = TAU * 2.2 * math.sin((clock - s.Scratch.T) * 25)
			end
			platter.Angle = (platter.Angle + speed * dt) % TAU
			if speed ~= 0 then
				local rot = platter.Center * CFrame.Angles(0, platter.Angle, 0) * platter.Center:Inverse()
				local parts, cfs = {}, {}
				for k, p in ipairs(platter.Parts) do
					parts[k] = p
					cfs[k] = rot * platter.CFs[k]
				end
				pcall(function()
					workspace:BulkMoveTo(parts, cfs, Enum.BulkMoveMode.FireCFrameChanged)
				end)
			end
		end
		if dj.Fader and dj.Fader.Parent then
			local x = scratch and 0.18 * math.sin((clock - s.Scratch.T) * 22) or 0
			dj.Fader.CFrame = dj.FaderCF * CFrame.new(x, 0, 0)
		end
		local level = 0
		for i = 1, 6 do
			level += (s.Energy[i] or 0)
		end
		level = math.clamp(level / 4, 0, 1)
		for k, led in ipairs(dj.Meters) do
			local row = (k - 1) % 6
			local on = level * 6 > row + 0.3
			local c = led:GetAttribute("OnColor")
			led.Color = on and (typeof(c) == "Color3" and c or Color3.new(0, 1, 0)) or Color3.fromRGB(40, 40, 40)
			led.Material = on and Enum.Material.Neon or Enum.Material.SmoothPlastic
		end
		for i, b in ipairs(dj.Bars) do
			local e = s.Energy[math.clamp(i * 24 // 16, 1, 24)] or 0
			b.Size = UDim2.fromScale(1 / 16 - 0.01, 0.05 + 0.6 * e)
		end
	end
	-- écran LED : égaliseur, titre, progression
	local screen = H.Screen
	if screen then
		for i, b in ipairs(screen.Bars) do
			local e = s.Energy[i] or 0
			b.Size = UDim2.fromScale(1 / 24 - 0.012, 0.06 + 0.94 * e)
		end
		local song = s.Song
		local title, sub, progress
		if song then
			local data = song.Data
			title = data.Icon .. " " .. T(data.Name)
			sub = "♪ " .. T(data.Author)
			progress = math.clamp((now - song.Start) / data.Duration, 0, 1)
		elseif s.Radio then
			local track = (Config.Music.Playlist or {})[s.Radio.Index]
			title = "📻 " .. tostring(track and track.Name or "Lo-fi")
			sub = T("Lo-fi radio on the stage")
			progress = 0
		else
			title = "🎵 DOPAMINE LIVE"
			sub = T("[E] Play an instrument · Jukebox: songs")
			progress = 0
		end
		if screen.Title.Text ~= title then
			screen.Title.Text = title
		end
		if screen.Sub.Text ~= sub then
			screen.Sub.Text = sub
		end
		screen.Progress.Size = UDim2.fromScale(0.88 * progress, 0.02)
		screen.Grad.Rotation = (screen.Grad.Rotation + dt * (musicActive(s) and 12 or 3)) % 360
	end
	-- (v11) écrans latéraux : même titre, égaliseur
	local energyAvg = 0
	for i = 1, 24 do
		energyAvg += s.Energy[i] or 0
	end
	energyAvg = math.clamp(energyAvg / 10, 0, 1)
	for _, side in ipairs(H.SideScreens or {}) do
		local song = s.Song
		local icon = song and song.Data.Icon or (s.Radio and "📻" or "🎵")
		local title = song and T(song.Data.Name) or "DOPAMINE LIVE"
		if side.Icon.Text ~= icon then
			side.Icon.Text = icon
		end
		if side.Title.Text ~= title then
			side.Title.Text = title
		end
		for i, b in ipairs(side.Bars) do
			local e = s.Energy[math.clamp(i * 3, 1, 24)] or 0
			b.Size = UDim2.fromScale(1 / #side.Bars - 0.02, 0.08 + 0.92 * e)
		end
	end
	-- (v11) piste de danse LED : vague de couleurs au rythme (15 fois / s)
	local floor = H.DanceFloor
	if floor then
		s.FloorT = (s.FloorT or 0) + dt
		if s.FloorT >= 1 / 15 then
			s.FloorT = 0
			local active = musicActive(s)
			local beat = s.Song and s.Song.Data.BeatSec or 0.5
			local phase = clock / beat
			for _, tile in ipairs(floor) do
				local p = tile.Part
				if p.Parent then
					local c: Color3
					if active then
						local d = math.sqrt((tile.U - 0.5) ^ 2 + (tile.V - 0.5) ^ 2)
						local wave = 0.5 + 0.5 * math.cos((d * 6 - phase) * math.pi)
						local hue = (clock * 0.05 + tile.U * 0.35 + tile.V * 0.2 + ((tile.I + tile.J) % 2) * 0.08) % 1
						c = Color3.fromHSV(hue, 0.75, 0.25 + 0.6 * wave * (0.45 + 0.55 * energyAvg))
					else
						local breathe = 0.5 + 0.5 * math.sin(clock * 0.8 + tile.U * 3)
						c = Color3.fromHSV(0.8, 0.45, 0.16 + 0.08 * breathe)
					end
					p.Color = c
				end
			end
		end
	end
	for i = 1, 24 do
		s.Energy[i] = (s.Energy[i] or 0) * math.exp(-dt * 5)
	end
	-- lyres motorisées + faisceaux (la nuit, quand la musique joue)
	local active = musicActive(s)
	local night = isNight()
	for _, head in ipairs(H.Heads or {}) do
		if head.Head.Parent then
			local t = clock + head.Phase
			local yaw = active and math.rad(38) * math.sin(t * 0.8) or 0
			local pitch = active and math.rad(22 + 16 * math.sin(t * 1.1)) or math.rad(10)
			local yokeCF = head.Base * CFrame.new(0, -0.22, 0) * CFrame.Angles(0, yaw, 0)
			local pivot = yokeCF * CFrame.new(0, -0.5, 0) * CFrame.Angles(pitch, 0, 0)
			local lensCF = pivot * CFrame.new(0, -0.26, 0) * CFrame.Angles(0, 0, math.rad(90))
			pcall(function()
				workspace:BulkMoveTo({ head.Yoke, head.Arms[1], head.Arms[2], head.Head, head.Lens }, {
					yokeCF,
					yokeCF * CFrame.new(-0.36, -0.28, 0),
					yokeCF * CFrame.new(0.36, -0.28, 0),
					pivot,
					lensCF,
				}, Enum.BulkMoveMode.FireCFrameChanged)
			end)
			local dir = -pivot.UpVector
			local deckY = s.StageCF.Y + MusicData.DECK_TOP
			if dir.Y < -0.1 then
				local dist = (lensCF.Position.Y - deckY) / -dir.Y
				head.Target.CFrame = CFrame.new(lensCF.Position + dir * dist)
			end
			head.Beam.Enabled = active and night
		end
	end
	-- lueurs (projecteurs, rampe, juke-box) : la nuit ; pulsent avec la musique
	for _, p in ipairs(s.Glows) do
		if p.Parent then
			p.Material = night and Enum.Material.Neon or Enum.Material.SmoothPlastic
		end
	end
	-- écran du synthé
	if H.SynthLCD and s.Hands.Synth then
		local n = s.Hands.Synth.R.Point and s.Hands.Synth.Note or nil
		H.SynthLCD.Text = n and ("PAD 01  " .. MusicData.NoteName(n)) or "PAD 01"
	end
end

----------------------------------------------------------------------
-- Musiciens : poses (Stepped) et accessoires portés (Heartbeat)
----------------------------------------------------------------------

-- Point visé par une main : au coup (frappe) puis rebond vers le survol
local function handPoint(side: any, hover: Vector3, lift: Vector3, clock: number, default: Vector3): Vector3
	local point = side.Point or default
	local age = clock - (side.HitT or -math.huge)
	local up = 1
	if age < 0.05 then
		up = 0 -- (frappe : la main est en bas)
	elseif age < 0.22 then
		up = smooth((age - 0.05) / 0.17)
	end
	if age > 2.5 then
		point = default
	end
	return point + hover + lift * up
end

local function poseSpec(s: any, id: string, rig: any, clock: number): any
	local H = s.Build and s.Build.H
	if not H then
		return nil
	end
	local hs = handState(s, id)
	local spec: any = {}
	local st = MusicData.STATIONS[id]
	local spot = MusicData.SpotCFrame(s.StageCF, id)
	local toward = spot.LookVector -- (du musicien vers l'instrument)
	local beat = s.Song and (60 / (MusicData.SONGS[MusicData.SONG_INDEX[s.Song.Id] or 1].Bpm)) or 0.5
	spec.Nod = musicActive(s) and 5 * math.sin(clock * TAU / beat) or 0
	if id == "Piano" or id == "Synth" then
		local keys = H.Keys[id]
		local c3, g4 = keyFor(keys, 55), keyFor(keys, 67)
		local back = -toward * 0.12
		spec.L = handPoint(hs.L, back + UP * 0.12, UP * 0.2, clock, c3 and c3.Top or spot.Position)
		spec.R = handPoint(hs.R, back + UP * 0.12, UP * 0.2, clock, g4 and g4.Top or spot.Position)
		spec.Lean = id == "Piano" and 12 or 8
		if id == "Piano" then
			local pf = H.Frames.Piano
			local k = MusicData.PIANO_SCALE
			spec.Seat = s.StageCF.Y + MusicData.DECK_TOP + MusicData.PIANO_SEAT
			spec.Feet = { R = (pf * CFrame.new(0.3 * k, 0.3, -0.25 * k)).Position, L = (pf * CFrame.new(-0.35 * k, 0.3, -0.1 * k)).Position }
		end
	elseif id == "Xylophone" then
		local keys = H.Keys.Xylophone
		local a, b = keyFor(keys, 67), keyFor(keys, 79)
		local hover = -toward * 0.9 + UP * 0.25
		spec.L = handPoint(hs.L, hover, UP * 0.4, clock, a and a.Top or spot.Position)
		spec.R = handPoint(hs.R, hover, UP * 0.4, clock, b and b.Top or spot.Position)
		spec.Lean = 10
	elseif id == "Drums" then
		local pieces = H.Drums
		local df = H.Frames.Drums
		local snare = pieces and pieces[MusicData.DRUM.Snare]
		local hat = pieces and pieces[MusicData.DRUM.HatClosed]
		local hover = -toward * 0.85 + UP * 0.25
		spec.L = handPoint(hs.L, hover, UP * 0.55, clock, snare and snare.Hit or spot.Position)
		spec.R = handPoint(hs.R, hover, UP * 0.55, clock, hat and hat.Hit or spot.Position)
		spec.Seat = s.StageCF.Y + MusicData.DECK_TOP + MusicData.RISERS.Drums.H + MusicData.THRONE_SEAT
		local kickAge = clock - hs.KickT
		local lift = kickAge < 0.2 and 0.28 * math.sin(math.clamp(kickAge / 0.2, 0, 1) * math.pi) or 0
		local pivot = H.KitPivot or df
		local kit = H.KitPivot and MusicData.KIT_SCALE or 1
		-- (pédales agrandies avec le kit ; pieds posés à plat sur le praticable)
		local rf = MusicData.ScalePoint(pivot, kit, (df * CFrame.new(0.25, 0.32, 5.9)).Position)
		local lf = MusicData.ScalePoint(pivot, kit, (df * CFrame.new(-0.9, 0.32, 5.85)).Position)
		spec.Feet = { R = Vector3.new(rf.X, df.Y + 0.32 + lift, rf.Z), L = Vector3.new(lf.X, df.Y + 0.32, lf.Z) }
		spec.Lean = 8
	elseif id == "Guitar" or id == "Bass" then
		local inst = id == "Guitar" and H.Guitar or H.Bass
		local g = s.Worn[id]
		if g and inst then
			local u = math.clamp(((hs.Note or 60) % 24) / 24, 0, 1)
			local neckX = inst.NeckStart + inst.NeckLen * (0.2 + 0.45 * (1 - u))
			spec.L = (g * CFrame.new(neckX, -0.02, 0.2)).Position
			local age = clock - hs.R.HitT
			local strum = age < 0.12 and (1 - age / 0.12) * hs.Strum or 0
			spec.R = (g * CFrame.new(-0.12 * inst.K, 0.05 + 0.2 * strum, 0.22)).Position
			spec.LPole = Vector3.new(-1, -0.8, 0.3)
			spec.RPole = Vector3.new(1, -0.3, 0.6)
		end
		spec.Lean = 4
	elseif id == "DJ" then
		local dj = H.DJ
		local p = dj and dj.Platters[2]
		local center = p and p.Center.Position or spot.Position
		local sAge = clock - hs.ScratchT
		local wiggle = sAge < 0.5 and 0.18 * math.sin(sAge * 25) or 0.03 * math.sin(clock * 2)
		spec.R = center + UP * 0.12 - toward * 0.25 + spot.RightVector * wiggle
		spec.L = (dj and dj.FaderCF.Position or spot.Position) + UP * 0.15 - toward * 0.1
		if clock - hs.UpT < 0.7 then
			local e = math.sin(math.clamp((clock - hs.UpT) / 0.7, 0, 1) * math.pi)
			spec.L = spec.L:Lerp(spot.Position + UP * 7 - spot.RightVector * 0.8, e)
		end
		spec.Lean = 10
		spec.Nod = musicActive(s) and 9 * math.sin(clock * TAU / beat) or 0
	end
	if st.Seated and not spec.Seat then
		spec.Seat = spot.Y + 1.45
	end
	return spec
end

local function stepPoses(dt: number)
	local s = state
	if not s or not s.Folder or not s.Build then
		return
	end
	local clock = clockNow()
	local me = rootOf(LocalPlayer)
	local seen = {}
	for _, id in ipairs(MusicData.ORDER) do
		local userId = occupant(id)
		local player = userId ~= 0 and Players:GetPlayerByUserId(userId) or nil
		local character = player and player.Character
		local root = rootOf(player)
		if character and root and (not me or (root.Position - me.Position).Magnitude < POSE_R) then
			local entry = s.Rigs[character]
			if not entry or entry.Id ~= id then
				if entry then
					MusicPose.Release(entry.Rig)
				end
				local rig = MusicPose.Rig(character)
				entry = rig and { Rig = rig, Id = id, W = 0 } or nil
				s.Rigs[character] = entry
			end
			if entry then
				seen[character] = true
				entry.W = math.min(1, entry.W + dt / 0.35)
				local spec = poseSpec(s, id, entry.Rig, clock)
				if spec then
					local ok, err = pcall(MusicPose.Solve, entry.Rig, spec, smooth(entry.W))
					if not ok and not s.PoseWarned then
						s.PoseWarned = true
						warn("[MusicStage] pose : " .. tostring(err))
					end
				end
			end
		end
	end
	for character, entry in pairs(s.Rigs) do
		if not seen[character] then
			MusicPose.Release(entry.Rig)
			s.Rigs[character] = nil
		end
	end
end

-- Guitare / basse portées, baguettes, maillets : suivent les mains
local function stepProps()
	local s = state
	local H = s and s.Build and s.Build.H
	if not H then
		return
	end
	for _, id in ipairs({ "Guitar", "Bass" }) do
		local inst = id == "Guitar" and H.Guitar or H.Bass
		if inst then
			local userId = occupant(id)
			local player = userId ~= 0 and Players:GetPlayerByUserId(userId) or nil
			local entry = player and player.Character and s.Rigs[player.Character]
			local torso = entry and entry.Rig.Torso
			local frame: CFrame? = nil
			if torso and torso.Parent then
				-- manche vers la gauche du musicien, relevé de 22°, cordes vers l'avant
				local tcf = torso.CFrame
				local scale = entry.Rig.Scale
				local pos = tcf * Vector3.new(0.12 * scale, -0.55 * scale, -0.7 * scale)
				local x = (-tcf.RightVector * math.cos(math.rad(22)) + tcf.UpVector * math.sin(math.rad(22))).Unit
				local z = tcf.LookVector
				local y = z:Cross(x).Unit
				z = x:Cross(y).Unit
				frame = CFrame.fromMatrix(pos, x, y, z)
			end
			local target = frame or inst.Idle
			s.Worn[id] = frame
			-- (au repos : replacé une seule fois, puis plus rien à faire)
			if frame or not inst.AtIdle then
				inst.AtIdle = frame == nil
				local parts, cfs = {}, {}
				for k, p in ipairs(inst.Parts) do
					parts[k] = p
					cfs[k] = target * inst.Rel[k]
				end
				pcall(function()
					workspace:BulkMoveTo(parts, cfs, Enum.BulkMoveMode.FireCFrameChanged)
				end)
			end
			-- sangle : du bas du corps à l'épaule gauche, puis à la corne
			local strapA, strapB = inst.Straps[1], inst.Straps[2]
			if frame and torso then
				local shoulder = torso.CFrame * Vector3.new(-0.55, 0.85, 0.35)
				local a = frame * Vector3.new(-0.85 * inst.K, 0, -0.08)
				local b = frame * Vector3.new(0.72 * inst.K, 0.32, -0.08)
				for _, pair in ipairs({ { strapA, a, shoulder }, { strapB, shoulder, b } }) do
					local p0, p1 = pair[2], pair[3]
					pair[1].Size = Vector3.new(0.16, 0.03, math.max(0.05, (p1 - p0).Magnitude))
					pair[1].CFrame = CFrame.lookAt((p0 + p1) / 2, p1)
					pair[1].Transparency = 0
				end
			else
				strapA.Transparency = 1
				strapB.Transparency = 1
			end
		end
	end
	-- baguettes (batterie) et maillets (xylophone)
	local function holdStick(part: BasePart, hand: CFrame?, tip: Vector3?, length: number, rest: CFrame)
		if hand and tip then
			local from = hand.Position
			local dir = tip - from
			if dir.Magnitude < 0.05 then
				dir = hand.LookVector
			end
			local to = from + dir.Unit * length
			local cf = CFrame.lookAt((from + to) / 2, to) * CFrame.Angles(0, math.rad(90), 0)
			part.CFrame = cf
		elseif part.CFrame ~= rest then
			part.CFrame = rest
		end
	end
	s.Rest = s.Rest or {}
	local drummer = occupant("Drums")
	local dPlayer = drummer ~= 0 and Players:GetPlayerByUserId(drummer) or nil
	local dEntry = dPlayer and dPlayer.Character and s.Rigs[dPlayer.Character]
	local hs = s.Hands.Drums
	for side, stick in pairs(H.Sticks or {}) do
		s.Rest[stick] = s.Rest[stick] or stick.CFrame
		local hand = dEntry and MusicPose.Hand(dEntry.Rig, side)
		local tip = hs and hs[side].Point or (H.Drums and H.Drums[MusicData.DRUM.Snare] and H.Drums[MusicData.DRUM.Snare].Hit)
		holdStick(stick, hand, hand and tip or nil, 1.35, s.Rest[stick])
	end
	local xylo = occupant("Xylophone")
	local xPlayer = xylo ~= 0 and Players:GetPlayerByUserId(xylo) or nil
	local xEntry = xPlayer and xPlayer.Character and s.Rigs[xPlayer.Character]
	local xs = s.Hands.Xylophone
	for side, mallet in pairs(H.Mallets or {}) do
		s.Rest[mallet.Handle] = s.Rest[mallet.Handle] or mallet.Handle.CFrame
		s.Rest[mallet.Head] = s.Rest[mallet.Head] or mallet.Head.CFrame
		local hand = xEntry and MusicPose.Hand(xEntry.Rig, side)
		local keys = H.Keys.Xylophone
		local default = keyFor(keys, side == "L" and 67 or 79)
		local tip = xs and xs[side].Point or (default and default.Top)
		holdStick(mallet.Handle, hand, hand and tip or nil, 1.05, s.Rest[mallet.Handle])
		if hand and tip then
			local from = hand.Position
			local dir = (tip - from)
			mallet.Head.CFrame = CFrame.new(from + (dir.Magnitude > 0.05 and dir.Unit or hand.LookVector) * 1.1)
		elseif mallet.Head.CFrame ~= s.Rest[mallet.Head] then
			mallet.Head.CFrame = s.Rest[mallet.Head]
		end
	end
end

----------------------------------------------------------------------
-- Construction en flux
----------------------------------------------------------------------

local function detail(): string
	local ok, q = pcall(GraphicsQuality.Get)
	return ok and type(q) == "table" and q.Detail or "Medium"
end

local function dropBuild(s: any)
	if s.Radio then
		pcall(function()
			s.Radio.Sound:Destroy()
		end)
		s.Radio = nil
	end
	for _, entry in pairs(s.Rigs) do
		MusicPose.Release(entry.Rig)
	end
	table.clear(s.Rigs)
	if s.Build then
		s.Build:Destroy()
		s.Build = nil
	end
	s.Synth:Destroy()
	s.Synth = MusicSynth.new()
	table.clear(s.Pressed)
	table.clear(s.Wobble)
	s.Glows = {}
	s.Rest = {}
end

local function localizePrompts(s: any)
	if not s.Folder then
		return
	end
	for _, d in ipairs(s.Folder:GetDescendants()) do
		if d:IsA("ProximityPrompt") then
			local action, object = d:GetAttribute("LocAction"), d:GetAttribute("LocObject")
			if type(action) == "string" then
				local text = T(action)
				if d.ActionText ~= text then
					d.ActionText = text
				end
			end
			if type(object) == "string" then
				local text = T(object)
				if d.ObjectText ~= text then
					d.ObjectText = text
				end
			end
		end
	end
	local H = s.Build and s.Build.H
	local juke = H and H.JukeText
	if juke then
		local key = juke:GetAttribute("LocText")
		if type(key) == "string" then
			juke.Text = T(key)
		end
	end
end

----------------------------------------------------------------------
-- API
----------------------------------------------------------------------

function MusicStage.Start(options: any?)
	if state then
		MusicStage.Stop()
	end
	local s: any = {
		Conns = {},
		Toast = options and options.Toast or nil,
		Folder = nil,
		StageCF = CFrame.identity,
		Build = nil,
		Synth = MusicSynth.new(),
		UI = nil,
		Playing = nil,
		Octave = {},
		Out = {},
		OutStart = 0,
		Song = nil,
		Radio = nil,
		LoopId = 0,
		Pressed = {},
		Wobble = {},
		Energy = {},
		Hands = {},
		Rigs = {},
		Worn = {},
		Glows = {},
		Clock = 0,
		VisualT = 0,
		SearchT = 99,
		LocT = 0,
		Chain = false,
		KeyMap = {},
	}
	state = s
	local callbacks = {
		Note = function(value: number, vel: number)
			playLocal(value, vel)
		end,
		Leave = function()
			exitLocal(true)
		end,
		Picker = function()
			openPicker()
		end,
		Song = function(id: string, mode: string)
			fire("song", id, mode)
		end,
		StopSong = function()
			fire("song", "", "one")
		end,
		Radio = function(index: number)
			fire("radio", index)
		end,
		Chain = function(on: boolean)
			s.Chain = on
			-- (le morceau en cours enchaîne aussi : mode "all" côté serveur)
			fire("chain", on)
		end,
		Queue = function(id: string)
			fire("queue", "add", id)
		end,
		Unqueue = function(index: number)
			fire("queue", "remove", index)
		end,
		Skip = function()
			fire("skip")
		end,
		Octave = function(delta: number)
			local id = s.Playing
			if not id or MusicData.STATIONS[id].Kind ~= "keys" then
				return
			end
			local range = LOW_RANGE[id] or { 24, 72 }
			local low = math.clamp((s.Octave[id] or DEFAULT_LOW[id]) + 12 * delta, range[1], range[2])
			s.Octave[id] = low
			local layout = layoutFor(id)
			s.UI:Open(id, layout)
			refreshOctave()
			bindKeys(layout)
		end,
	}
	s.UICallbacks = callbacks
	s.UI = MusicUI.new(callbacks)
	local r = remote()
	if r then
		table.insert(s.Conns, r.OnClientEvent:Connect(function(...)
			local ok, err = pcall(onEvent, ...)
			if not ok then
				warn("[MusicStage] " .. tostring(err))
			end
		end))
	end
	table.insert(s.Conns, RunService.Stepped:Connect(function(_t: number, dt: number)
		if state == s and s.Build ~= nil and s.Build.Done then
			local ok, err = pcall(stepPoses, dt)
			if not ok and not s.PoseWarned then
				s.PoseWarned = true
				warn("[MusicStage] musiciens : " .. tostring(err))
			end
		end
	end))
	table.insert(s.Conns, RunService.Heartbeat:Connect(function()
		if state == s and s.Build and s.Build.Done then
			local ok, err = pcall(stepProps)
			if not ok and not s.PropWarned then
				s.PropWarned = true
				warn("[MusicStage] accessoires : " .. tostring(err))
			end
		end
	end))
end

function MusicStage.Step(dt: number)
	local s = state
	if not s then
		return
	end
	s.Clock += dt
	if not s.Folder or not s.Folder.Parent then
		s.SearchT += dt
		if s.SearchT < 2 then
			return
		end
		s.SearchT = 0
		s.Folder = findStage()
		if not s.Folder then
			return
		end
		local cf = s.Folder:GetAttribute("StageCF")
		s.StageCF = typeof(cf) == "CFrame" and cf or CFrame.identity
	end
	local root = rootOf(LocalPlayer)
	local camera = workspace.CurrentCamera
	local focus = root and root.Position or (camera and camera.CFrame.Position) or s.StageCF.Position
	local dist = (focus - s.StageCF.Position).Magnitude
	local scale = GraphicsQuality.DetailScale()
	if not s.Build and dist < BUILD_R * scale then
		local town = workspace:FindFirstChild("DopamineTown")
		s.Build = MusicStageBuild.new(s.StageCF, town or workspace, detail())
	elseif s.Build and dist > DROP_R * math.max(scale, 1) then
		if s.Playing then
			exitLocal(true)
		end
		dropBuild(s)
	end
	local build = s.Build
	if build and not build.Done then
		if build:Step() then
			for _, d in ipairs(build.Model:GetDescendants()) do
				if d:IsA("BasePart") and d:GetAttribute("MusicGlow") == true then
					table.insert(s.Glows, d)
				end
			end
		end
	end
	s.Synth:Step(dt)
	local now = serverNow()
	if dist < MusicData.HEAR_RADIUS + 20 then
		stepSong(s, now)
		stepLoop(s, now)
	else
		s.Song = nil
	end
	stepRadio(s, now)
	flush(false)
	-- quitter si l'avatar a été déplacé loin de son poste (téléportation…)
	if s.Playing and root then
		local spot = MusicData.SpotCFrame(s.StageCF, s.Playing)
		local flat = Vector3.new(root.Position.X - spot.Position.X, 0, root.Position.Z - spot.Position.Z).Magnitude
		if flat > MusicData.LEAVE_RANGE then
			exitLocal(true)
		end
	end
	s.VisualT += dt
	if build and dist < BUILD_R and s.VisualT >= VISUAL_STEP then
		local ok, err = pcall(stepVisuals, s, s.VisualT, now)
		if not ok and not s.VisualWarned then
			s.VisualWarned = true
			warn("[MusicStage] décor animé : " .. tostring(err))
		end
		s.VisualT = 0
	end
	s.LocT += dt
	if s.LocT > 1 then
		s.LocT = 0
		pcall(localizePrompts, s)
		if s.Playing then
			setStagePromptsHidden(true)
		end
	end
	-- pastille "en cours" (près de la scène)
	if s.UI then
		s.UI:Step(dt)
		if s.UI:IsPickerOpen() then
			s.PickerT = (s.PickerT or 0) + dt
			if s.PickerT > 0.25 then
				s.PickerT = 0
				s.UI:UpdatePicker(pickerState())
			end
		end
		local song = s.Song
		if dist < 80 and song then
			local elapsed = math.max(0, now - song.Start)
			local total = song.Data.Duration
			s.UI:SetNowPlaying(string.format("%s %s · %d:%02d / %d:%02d", song.Data.Icon, T(song.Data.Name), elapsed // 60, math.floor(elapsed) % 60, total // 60, math.floor(total) % 60), elapsed / total)
		elseif dist < 80 and s.Radio then
			local track = (Config.Music.Playlist or {})[s.Radio.Index]
			s.UI:SetNowPlaying("📻 " .. T("Stage radio") .. " · " .. tostring(track and track.Name or ""), 0)
		else
			s.UI:SetNowPlaying(nil)
		end
	end
end

function MusicStage.Stop()
	local s = state
	if not s then
		return
	end
	if s.Playing then
		exitLocal(true)
	end
	for _, c in ipairs(s.Conns) do
		c:Disconnect()
	end
	dropBuild(s)
	s.Synth:Destroy()
	if s.UI then
		s.UI:Destroy()
		s.UI = nil
	end
	state = nil
end

function MusicStage.Debug(): any
	local s = state
	return {
		State = s,
		Hit = hit,
		PlayLocal = playLocal,
		OnEvent = onEvent,
		Flush = flush,
		Layout = layoutFor,
		StepPoses = stepPoses,
		StepProps = stepProps,
		PoseSpec = poseSpec,
	}
end

return MusicStage
