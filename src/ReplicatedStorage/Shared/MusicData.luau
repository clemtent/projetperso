--[[
	MusicData (ModuleScript)
	Emplacement : ReplicatedStorage > Shared > MusicData

	🎵 SCÈNE MUSICALE de la place (v9.9, MUSIC99) : données PARTAGÉES par le
	serveur (TownMusic : sol de la scène, invites, relais des notes, morceau
	en cours) et le client (MusicStage : décor, sons, interface, animations).
	Aucun service Roblox ici (CFrame / nombres seulement) : testable hors jeu.

	1. Le PLAN de la scène (repère local : origine = centre de l'empreinte
	   24 x 16 au niveau du pavé, -Z = le devant, vers le public et la
	   fontaine ; +X = côté gauche vu du public) : plancher, marches,
	   praticables (batterie, DJ), et pour chaque instrument l'endroit où
	   se tient (ou s'assoit) le musicien (Spot) et l'invite.
	2. Les INSTRUMENTS : ordre, nature (clavier, batterie, cordes, DJ),
	   pièces de batterie et pads du DJ (numéros envoyés sur le réseau).
	3. Les NOTES : "C#4" <-> 61 (MIDI), accords ("Am7" -> notes).
	4. Les MORCEAUX pré-enregistrés (8, dont 6 airs du domaine public et 2
	   compositions originales) : mélodie, accords, basse, batterie…
	   compilés en une liste d'événements { T (s), I, N, V, D } jouée par
	   tous les clients à partir de la MÊME heure du serveur (SongStart).
	5. Les BOUCLES du DJ (1 mesure, calées sur l'heure du serveur).
]]

local MusicData = {}

----------------------------------------------------------------------
-- 1. Plan de la scène (studs, repère local de la scène)
----------------------------------------------------------------------

-- (v11 MUSIC11) une vraie scène de concert : 32 x 22 (avant : 24 x 16),
-- portique de 16 de haut, ailes, écrans latéraux ; devant, la FOSSE du
-- public (zone "MusicCrowd" de WorldLayout : 30 x 16, piste de danse LED).
MusicData.FOOTPRINT = Vector3.new(32, 19, 22) -- (X, hauteur max, Z)
MusicData.GROUND = 0.06 -- dessus du pavé de la place (au-dessus de l'origine)
MusicData.DECK_TOP = 1.5 -- plancher de la scène
MusicData.DECK = { X0 = -14.6, X1 = 14.6, Z0 = -4.6, Z1 = 9.8 }
-- marches du devant (2 marches de 0,5 : une marche Roblox monte sans sauter)
MusicData.STEPS = { X = 5, Depth = 1.0, Rise = 0.5, Count = 2 }
-- praticables (estrades) : batterie au fond au centre, DJ au fond à gauche (+X)
MusicData.RISERS = {
	Drums = { X0 = -3.3, X1 = 3.3, Z0 = 2.6, Z1 = 8.9, H = 0.7 },
	DJ = { X0 = 5.8, X1 = 10.8, Z0 = 3.6, Z1 = 8.9, H = 0.5 },
}
MusicData.TRUSS_H = 16 -- dessous du grill (portique d'éclairage)
MusicData.TRUSS_TOWERS = { Vector3.new(-15.3, 0, -4.2), Vector3.new(15.3, 0, -4.2), Vector3.new(-15.3, 0, 9.5), Vector3.new(15.3, 0, 9.5) }
MusicData.TOWER_SIZE = 1.1
MusicData.PA = { Vector3.new(-13.2, 0, -5.9), Vector3.new(13.2, 0, -5.9) } -- enceintes au sol (devant)
MusicData.JUKEBOX = CFrame.new(10.6, 0, -10.2) -- 🎛️ pupitre "musique" au sol (pour tous)
-- fosse du public (devant la scène, repère de la scène) : piste de danse LED
-- (z ≥ -21,6 : les 6 bancs de la fontaine, à 19 studs du centre, restent libres)
MusicData.CROWD = { X0 = -12, X1 = 12, Z0 = -21.6, Z1 = -12.5 }
-- (v11, SCALE11) piano et batterie à l'échelle Roblox (x1,3 / x1,25) :
-- banquette et tabouret à 1,85–1,9 au-dessus de leur plancher
MusicData.PIANO_SCALE = 1.3
MusicData.PIANO_FRAME = Vector3.new(-4.55, 0, -0.35) -- (repère du piano : bord des touches, au plancher)
MusicData.PIANO_SEAT = 1.46 * 1.3 -- dessus de la banquette (au-dessus du plancher)
MusicData.KIT_SCALE = 1.25
MusicData.KIT_PIVOT = Vector3.new(0.2, 0, 5.4) -- (centre du tapis, sur le praticable)
MusicData.THRONE_SEAT = 1.5 * 1.25 -- dessus du tabouret (au-dessus du praticable)

-- Point agrandi autour d'un pivot (piano, batterie) : pivot * (local x k)
function MusicData.ScalePoint(pivot: CFrame, k: number, p: Vector3): Vector3
	return pivot * (pivot:PointToObjectSpace(p) * k)
end

-- Ordre des instruments (index = numéro envoyé sur le réseau)
MusicData.ORDER = { "Piano", "Drums", "Guitar", "Bass", "Xylophone", "Synth", "DJ" }
MusicData.INDEX = {} :: { [string]: number }
for i, id in ipairs(MusicData.ORDER) do
	MusicData.INDEX[id] = i
end

export type Station = {
	Id: string,
	Name: string,
	Icon: string,
	Kind: string, -- "keys" | "drums" | "strings" | "dj"
	Seated: boolean,
	Floor: number, -- hauteur du sol sous le musicien (repère local)
	Spot: CFrame, -- pieds du musicien (au sol), regard = LookVector
	Prompt: Vector3, -- où l'invite "Jouer" est accrochée
}

local function facing(x: number, z: number, yaw: number): CFrame
	return CFrame.new(x, 0, z) * CFrame.Angles(0, math.rad(yaw), 0)
end

-- yaw 0 = regard vers -Z (le public) ; 90 = regard vers -X
MusicData.STATIONS = {
	Piano = { Id = "Piano", Name = "Grand piano", Icon = "🎹", Kind = "keys", Seated = true, Floor = 1.5, Spot = facing(-4.55 + 1.2 * 1.3, -0.35, 90), Prompt = Vector3.new(-3.2, 3.8, -0.35) },
	Drums = { Id = "Drums", Name = "Drum kit", Icon = "🥁", Kind = "drums", Seated = true, Floor = 2.2, Spot = facing(0.2 - 0.2 * 1.25, 5.4 + 1.05 * 1.25, 0), Prompt = Vector3.new(0, 5.0, 4.6) },
	Guitar = { Id = "Guitar", Name = "Electric guitar", Icon = "🎸", Kind = "strings", Seated = false, Floor = 1.5, Spot = facing(-1.6, -1.5, 0), Prompt = Vector3.new(-1.6, 3.6, -1.5) },
	Bass = { Id = "Bass", Name = "Bass guitar", Icon = "🎸", Kind = "strings", Seated = false, Floor = 1.5, Spot = facing(4.3, 1.9, 0), Prompt = Vector3.new(4.3, 3.6, 1.9) },
	Xylophone = { Id = "Xylophone", Name = "Xylophone", Icon = "🎶", Kind = "keys", Seated = false, Floor = 1.5, Spot = facing(8.0, -0.7, 0), Prompt = Vector3.new(8.0, 3.8, -1.7) },
	Synth = { Id = "Synth", Name = "Synthesizer", Icon = "🎛️", Kind = "keys", Seated = false, Floor = 1.5, Spot = facing(4.0, -1.55, 0), Prompt = Vector3.new(4.0, 3.9, -2.5) },
	DJ = { Id = "DJ", Name = "DJ booth", Icon = "🎧", Kind = "dj", Seated = false, Floor = 2.0, Spot = facing(8.0, 6.35, 0), Prompt = Vector3.new(8.0, 4.8, 4.9) },
} :: { [string]: Station }

-- Pieds du musicien dans le monde
function MusicData.SpotCFrame(stageCF: CFrame, id: string): CFrame
	local st = MusicData.STATIONS[id]
	return stageCF * CFrame.new(0, st.Floor, 0) * st.Spot
end

----------------------------------------------------------------------
-- 2. Batterie et DJ (numéros réseau)
----------------------------------------------------------------------

MusicData.DRUMS = { "Kick", "Snare", "HatClosed", "HatOpen", "TomHigh", "TomMid", "TomFloor", "Crash", "Ride" }
MusicData.DRUM = {} :: { [string]: number }
for i, id in ipairs(MusicData.DRUMS) do
	MusicData.DRUM[id] = i
end
-- pads du DJ : 1..4 = boucles (bascule), 5..8 = effets
-- (v11) 8 boucles (rock, house, hip-hop, lofi, trap, reggae, disco, techno)
MusicData.DJ_PADS = { "LoopRock", "LoopHouse", "LoopHipHop", "LoopLofi", "LoopTrap", "LoopReggae", "LoopDisco", "LoopTechno", "Scratch", "Horn", "Riser", "Drop" }
MusicData.DJ_LOOPS = 8
MusicData.DJ_FX = { Scratch = 9, Horn = 10, Riser = 11, Drop = 12 }

-- Limites réseau (le serveur les applique aussi)
MusicData.NOTE_MIN = 24
MusicData.NOTE_MAX = 108
MusicData.MAX_BATCH = 24 -- notes par envoi
MusicData.SEND_EVERY = 0.06 -- (s) le client regroupe ses notes
MusicData.HEAR_RADIUS = 150 -- (studs) on reçoit les notes des autres
MusicData.PLAY_RANGE = 14 -- (studs) invite "Jouer"
MusicData.LEAVE_RANGE = 9 -- (studs) trop loin de son poste : on le libère

----------------------------------------------------------------------
-- 3. Notes et accords
----------------------------------------------------------------------

local PITCH: { [string]: number } = { C = 0, D = 2, E = 4, F = 5, G = 7, A = 9, B = 11 }
local NAMES = { "C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B" }
local NAMES_FR = { "Do", "Do#", "Ré", "Ré#", "Mi", "Fa", "Fa#", "Sol", "Sol#", "La", "La#", "Si" }

-- "C#4" -> 61 ; "Bb3" -> 58 ; nil si invalide (Do central = C4 = 60)
function MusicData.Note(text: string): number?
	local letter, accidental, octave = string.match(text, "^([A-Ga-g])([#b]?)(%-?%d)$")
	if not letter then
		return nil
	end
	local pc = PITCH[string.upper(letter)]
	if accidental == "#" then
		pc += 1
	elseif accidental == "b" then
		pc -= 1
	end
	return (tonumber(octave) :: number + 1) * 12 + pc
end

function MusicData.NoteName(n: number, french: boolean?): string
	local pc = n % 12
	local octave = (n - pc) / 12 - 1
	return (french and NAMES_FR or NAMES)[pc + 1] .. tostring(octave)
end

-- Qualités d'accord -> intervalles (demi-tons au-dessus de la fondamentale)
local QUALITIES: { [string]: { number } } = {
	[""] = { 0, 4, 7 },
	m = { 0, 3, 7 },
	["7"] = { 0, 4, 7, 10 },
	m7 = { 0, 3, 7, 10 },
	maj7 = { 0, 4, 7, 11 },
	sus4 = { 0, 5, 7 },
	sus2 = { 0, 2, 7 },
	dim = { 0, 3, 6 },
	["6"] = { 0, 4, 7, 9 },
	add9 = { 0, 4, 7, 14 },
}

-- "Am7" -> (classe de la fondamentale 0..11, intervalles) ; nil si inconnu
function MusicData.Chord(name: string): (number?, { number }?)
	local letter, accidental, quality = string.match(name, "^([A-G])([#b]?)(.*)$")
	if not letter then
		return nil, nil
	end
	local intervals = QUALITIES[quality]
	if not intervals then
		return nil, nil
	end
	local pc = PITCH[letter]
	if accidental == "#" then
		pc += 1
	elseif accidental == "b" then
		pc -= 1
	end
	return pc % 12, intervals
end

-- Notes d'un accord en position serrée autour de `center` (chaque note dans
-- [center - 6, center + 6[) : les renversements viennent tout seuls
function MusicData.ChordNotes(name: string, center: number?): { number }
	local pc, intervals = MusicData.Chord(name)
	if not pc or not intervals then
		return {}
	end
	local c = center or 62
	local notes = {}
	for _, iv in ipairs(intervals) do
		local n = pc + iv
		n = n + 12 * math.floor((c - 6 - n) / 12 + 1)
		while n < c - 6 do
			n += 12
		end
		while n >= c + 6 do
			n -= 12
		end
		table.insert(notes, n)
	end
	table.sort(notes)
	return notes
end

-- Fondamentale d'un accord dans [low, low + 12[
function MusicData.Root(name: string, low: number): number?
	local pc = MusicData.Chord(name)
	if not pc then
		return nil
	end
	return low + (pc - low) % 12
end

----------------------------------------------------------------------
-- 4. Morceaux (v11 MUSIC11 : catalogue dans Shared/MusicSongs)
--   Suites de jetons séparés par des espaces ("|" = barre de mesure,
--   ignorée) : "E4" (1 temps), "E4:1.5", "r:2" (silence) ; accords : "Am",
--   "G7:2" (sans durée = une mesure entière). "$A" = la phrase A du morceau
--   (Phrases = { A = "…" }), répétable.
--   Un morceau a une FORME (v11) : Sections = { I = { Chords, Bars,
--   Energy }, V = …, C = …, B = …, O = … } et Form = "I V C V C B C O"
--   (intro, couplet, refrain, pont, fin) ; chaque partie joue dans les
--   sections listées par In (ex. In = "VC"). Sans Form : une seule
--   section (ancien format : Bars + Chords en boucle).
--   Parties : Lead (mélodie : Notes = texte, ou { [section] = texte }),
--   Riff (motif en DEGRÉS de l'accord en cours : "1 3 5 8 5 3" ; ' = octave
--   au-dessus, , = au-dessous : il suit les accords), Harmony (accords :
--   style), Bass (style), Drums (style + breaks automatiques en fin de
--   section, crash au début des sections), Echo (canon : même mélodie
--   décalée), DJ (scratch, vinyl, riser, drop, horn).
--   Swing (0..0,33) : croches "ternaires" (jazz, lofi) ; Transpose : demi-tons.
--   Un accord final (End) termine les morceaux qui ont une forme.
----------------------------------------------------------------------

export type Event = { T: number, I: string, N: number, V: number, D: number }
export type Song = {
	Id: string,
	Name: string,
	Icon: string,
	Author: string,
	Genre: string?,
	Bpm: number,
	Beats: number, -- temps par mesure
	Bars: number?,
	Chords: string?,
	Parts: { any },
	Sections: { [string]: any }?,
	Form: string?,
}

-- Genres (filtres de l'interface ; couleurs des pochettes : RGB)
MusicData.GENRES = {
	{ Id = "Pop", Name = "Pop", Icon = "🎤", A = { 255, 110, 170 }, B = { 255, 196, 120 } },
	{ Id = "Rock", Name = "Rock", Icon = "🎸", A = { 200, 40, 50 }, B = { 40, 30, 40 } },
	{ Id = "Electro", Name = "Electro", Icon = "⚡", A = { 40, 220, 255 }, B = { 120, 40, 220 } },
	{ Id = "HipHop", Name = "Hip-hop", Icon = "🎧", A = { 250, 200, 40 }, B = { 30, 30, 36 } },
	{ Id = "Lofi", Name = "Lo-fi", Icon = "☕", A = { 170, 140, 220 }, B = { 255, 190, 160 } },
	{ Id = "Reggae", Name = "Reggae", Icon = "🌴", A = { 40, 170, 70 }, B = { 250, 210, 40 } },
	{ Id = "Disco", Name = "Disco", Icon = "🪩", A = { 230, 60, 200 }, B = { 255, 220, 90 } },
	{ Id = "Jazz", Name = "Jazz", Icon = "🎷", A = { 30, 60, 120 }, B = { 210, 160, 80 } },
	{ Id = "Chiptune", Name = "Chiptune", Icon = "👾", A = { 60, 230, 120 }, B = { 30, 40, 90 } },
	{ Id = "Ballad", Name = "Ballad", Icon = "🌙", A = { 90, 110, 200 }, B = { 240, 200, 230 } },
	{ Id = "Funk", Name = "Funk", Icon = "🕺", A = { 255, 130, 30 }, B = { 120, 30, 140 } },
	{ Id = "World", Name = "World", Icon = "🌎", A = { 240, 90, 60 }, B = { 250, 200, 80 } },
	{ Id = "Classical", Name = "Classical", Icon = "🎻", A = { 140, 90, 50 }, B = { 245, 230, 200 } },
}
MusicData.GENRE_INDEX = {} :: { [string]: any }
for _, g in ipairs(MusicData.GENRES) do
	MusicData.GENRE_INDEX[g.Id] = g
end

MusicData.SONGS = require(script.Parent:WaitForChild("MusicSongs")) :: { any }

MusicData.SONG_INDEX = {} :: { [string]: number }
for i, song in ipairs(MusicData.SONGS) do
	MusicData.SONG_INDEX[song.Id] = i
end

-- Batterie : 16 doubles-croches par mesure de 4 temps (12 pour 3 temps)
-- "o" = coup accentué, "x" = coup, "g" = note fantôme (très douce),
-- "r" = roulement (2 triples-croches), "." = rien
local GROOVES: { [string]: { [string]: string } } = {
	pop = { Kick = "x.....x.x.......", Snare = "....x.......x...", HatClosed = "x.x.x.x.x.x.x.x." },
	pop2 = { Kick = "x.....x.x.x.....", Snare = "....o.......o...", HatClosed = "x.x.x.x.x.x.x...", HatOpen = "..............x." },
	rock = { Kick = "x.......x.x.....", Snare = "....o.......o...", HatClosed = "x.x.x.x.x.x.x.x." },
	rock2 = { Kick = "x.x.....x.x.....", Snare = "....o.......o...", Ride = "x.x.x.x.x.x.x.x." },
	disco = { Kick = "x...x...x...x...", Snare = "....x.......x...", HatClosed = "x...x...x...x...", HatOpen = "..x...x...x...x." },
	house = { Kick = "x...x...x...x...", Snare = "....x.......x...", HatClosed = ".g.g.g.g.g.g.g.g", HatOpen = "..x...x...x...x." },
	techno = { Kick = "x...x...x...x...", Snare = "....x.......x...", HatClosed = "..x...x...x...x.", Ride = "g.g.g.g.g.g.g.g." },
	boom = { Kick = "x.......x.x.....", Snare = "....x.......x..g", HatClosed = "x.x.x.xxx.x.x.x." },
	hiphop = { Kick = "x......xx.x.....", Snare = "....x.......x...", HatClosed = "x.x.x.x.x.x.x.xx" },
	trap = { Kick = "x......x..x.....", Snare = "........o.......", HatClosed = "x.x.x.xrx.x.xrrr" },
	lofi = { Kick = "x......x..x.....", Snare = "....x.......x...", HatClosed = "x.g.x.g.x.g.x.gx" },
	reggae = { Kick = "........x.......", Snare = "........x.......", HatClosed = "g.x.g.x.g.x.g.x." },
	funk = { Kick = "x..x..x...x..x..", Snare = "....o..g.g..o..g", HatClosed = "xgxgxgxgxgxgxgxg" },
	jazz = { Ride = "x...x..xx...x..x", HatClosed = "....x.......x...", Kick = "g.......g.......", Snare = "......g.......g." },
	bossa = { Kick = "x..xx..xx..xx..x", Snare = "x..x..x...x..x..", HatClosed = "g.g.g.g.g.g.g.g." },
	chip = { Kick = "x.......x.x.....", Snare = "....x.......x...", HatClosed = "x.x.x.x.x.x.x.x." },
	ballad = { Kick = "x.........x.....", Snare = "........x.......", HatClosed = "g.g.g.g.g.g.g.g." },
	halftime = { Kick = "x.....x...x.....", Snare = "........o.......", HatClosed = "x.x.x.x.x.x.x.x." },
	intro = { Kick = "x...............", HatClosed = "x.x.x.x.x.x.x.x." },
	build = { Kick = "x...x...x...x...", Snare = "x.x.x.x.x.x.xxxx" },
	march = { Kick = "x.......x.......", Snare = "x.xgx.x.x.xgx.x." },
	country = { Kick = "x.......x.......", Snare = "g.g.o.g.g.g.o.g.", HatClosed = "........" },
	latin = { Kick = "x...x...x...x...", Snare = "..x...x...x..x..", HatClosed = "gggggggggggggggg", TomHigh = "......x.......x.", TomMid = "...........x...." },
	brush = { Kick = "x.......x.......", Snare = "....x.......x...", Ride = "x..xx..xx..xx..x" },
	waltz = { Kick = "x...........", HatClosed = "....x...x...", Snare = "....g...g..." },
	waltz2 = { Kick = "x...........", Snare = "....x...x...", Ride = "x...x...x..." },
}

-- Breaks (fins de section) : Steps dernières doubles-croches remplacées
local FILLS: { [string]: { Steps: number, [string]: any } } = {
	toms = { Steps = 4, TomHigh = "............xx..", TomMid = "..............x.", TomFloor = "...............x" },
	rock = { Steps = 8, Snare = "........oxox....", TomHigh = "............xx..", TomMid = "..............x.", TomFloor = "...............o" },
	snare = { Steps = 4, Snare = "............xxxo" },
	disco = { Steps = 4, Snare = "............xxxx", HatOpen = "..............x." },
	trap = { Steps = 4, HatClosed = "............rrrr", Snare = "...............o" },
	jazz = { Steps = 4, Snare = "............g.gx", TomFloor = "...............x" },
	soft = { Steps = 2, TomMid = "..............g.", TomFloor = "...............x" },
	build = { Steps = 16, Snare = "x.x.x.x.xxxxrrrr" },
}
local GROOVE_FILL: { [string]: string } = {
	rock = "rock", rock2 = "rock", pop = "toms", pop2 = "rock", disco = "disco", house = "disco", techno = "snare",
	boom = "snare", hiphop = "snare", trap = "trap", lofi = "soft", reggae = "toms", funk = "snare", jazz = "jazz",
	bossa = "soft", chip = "snare", ballad = "soft", halftime = "toms", march = "snare", country = "snare",
	latin = "toms", brush = "jazz", waltz = "soft", waltz2 = "soft", intro = "soft", build = "build",
}
MusicData.GROOVES = GROOVES

local function tokens(text: string): { string }
	local list = {}
	for token in string.gmatch(text, "%S+") do
		if token ~= "|" then
			table.insert(list, token)
		end
	end
	return list
end

-- "$A" -> phrase A du morceau (récursion limitée)
local function expand(text: string, phrases: { [string]: string }?): string
	if not phrases or not string.find(text, "%$") then
		return text
	end
	for _ = 1, 3 do
		local changed = false
		text = string.gsub(text, "%$(%w+)", function(name: string)
			local p = phrases[name]
			if p then
				changed = true
				return " " .. p .. " "
			end
			return ""
		end)
		if not changed then
			break
		end
	end
	return text
end

-- "E4:1.5" -> ("E4", 1.5) ; durée par défaut `default`
local function split(token: string, default: number): (string, number)
	local head, dur = string.match(token, "^([^:]+):([%d%.]+)$")
	if head then
		return head, tonumber(dur) or default
	end
	return token, default
end

-- Mélodie -> { { beat, note|nil, beats } }
function MusicData.ParseNotes(text: string, phrases: { [string]: string }?): { { number } }
	local out = {}
	local beat = 0
	for _, token in ipairs(tokens(expand(text, phrases))) do
		local head, dur = split(token, 1)
		local n = head ~= "r" and MusicData.Note(head) or nil
		if n then
			table.insert(out, { beat, n, dur })
		end
		beat += dur
	end
	return out
end

-- Durée (temps) d'un texte de notes (silences compris)
function MusicData.TextBeats(text: string, phrases: { [string]: string }?): number
	local beat = 0
	for _, token in ipairs(tokens(expand(text, phrases))) do
		local _, dur = split(token, 1)
		beat += dur
	end
	return beat
end

-- Riff -> { { beat, degré (texte), beats } }
local function parseRiff(text: string, phrases: { [string]: string }?): { any }
	local out = {}
	local beat = 0
	for _, token in ipairs(tokens(expand(text, phrases))) do
		local head, dur = split(token, 0.5)
		if head ~= "r" then
			table.insert(out, { beat, head, dur })
		end
		beat += dur
	end
	return out, beat
end

-- Accords -> { { beat, name|"r", beats } } ; sans durée = une mesure
function MusicData.ParseChords(text: string, beatsPerBar: number): { any }
	local out = {}
	local beat = 0
	for _, token in ipairs(tokens(text)) do
		local head, dur = split(token, beatsPerBar)
		table.insert(out, { beat, head, dur })
		beat += dur
	end
	return out
end

local function melodyLength(list: { { number } }): number
	local last = list[#list]
	return last and (last[1] + last[3]) or 0
end

-- Degré de riff ("1", "3", "5", "7", "8", "2", "4", "6", "9", "b7"… + ' ou ,)
-- -> note MIDI, sur l'accord `name` (+ transposition), autour de `center`
local DEGREE: { [string]: number } = { ["2"] = 2, ["4"] = 5, ["6"] = 9, ["8"] = 12, ["9"] = 14, b3 = 3, b7 = 10, ["#4"] = 6, b6 = 8 }
function MusicData.Degree(token: string, name: string, center: number, transpose: number?): number?
	local pc, intervals = MusicData.Chord(name)
	if not pc or not intervals then
		return nil
	end
	local up = 0
	local core = string.gsub(token, "'", function()
		up += 12
		return ""
	end)
	core = string.gsub(core, ",", function()
		up -= 12
		return ""
	end)
	local iv: number?
	if core == "1" then
		iv = 0
	elseif core == "3" then
		iv = intervals[2] or 4
	elseif core == "5" then
		iv = intervals[3] or 7
	elseif core == "7" then
		iv = intervals[4] or ((intervals[2] == 3) and 10 or 11)
	else
		iv = DEGREE[core]
	end
	if not iv then
		return nil
	end
	local root = (pc + (transpose or 0)) % 12
	-- (fondamentale la plus proche de `center` par en dessous)
	local base = root + 12 * math.floor((center - root) / 12)
	return base + iv + up
end

type Section = { L: string, Bar0: number, Bars: number, Beat0: number, Beat1: number, Energy: number }

-- Normalise la forme : liste des sections (dans l'ordre), accords absolus
local function timeline(song: any): ({ Section }, { any }, number)
	local barBeats = song.Beats or 4
	local sections: { Section } = {}
	local chords: { any } = {}
	local beat = 0
	local function addSection(letter: string, chordText: string, bars: number, energy: number)
		local list = MusicData.ParseChords(chordText, barBeats)
		local cycle = 0
		for _, c in ipairs(list) do
			cycle = math.max(cycle, c[1] + c[3])
		end
		local total = bars * barBeats
		local index = #sections + 1
		if cycle > 0 then
			local offset = 0
			while offset < total - 1e-6 do
				for _, c in ipairs(list) do
					if offset + c[1] < total - 1e-6 then
						table.insert(chords, { beat + offset + c[1], c[2], math.min(c[3], total - offset - c[1]), index })
					end
				end
				offset += cycle
			end
		end
		table.insert(sections, { L = letter, Bar0 = math.floor(beat / barBeats + 0.5), Bars = bars, Beat0 = beat, Beat1 = beat + total, Energy = energy })
		beat += total
	end
	if type(song.Form) == "string" and type(song.Sections) == "table" then
		for _, letter in ipairs(tokens(song.Form)) do
			local sec = song.Sections[letter]
			if sec then
				local list = MusicData.ParseChords(sec.Chords or "C", barBeats)
				local cycle = 0
				for _, c in ipairs(list) do
					cycle = math.max(cycle, c[1] + c[3])
				end
				local bars = sec.Bars or math.max(1, math.ceil(cycle / barBeats - 1e-6))
				addSection(letter, sec.Chords or "C", bars, sec.Energy or 1)
			end
		end
		if song.End ~= false then
			addSection("END", type(song.End) == "string" and song.End or "C", 1, 1)
		end
	else
		addSection("A", song.Chords or "C", song.Bars or 8, 1)
	end
	return sections, chords, beat
end

-- Compile un morceau en événements triés (T en secondes)
function MusicData.Compile(song: Song): { Events: { Event }, Duration: number, BeatSec: number, Sections: { Section } }
	local s: any = song
	local beatSec = 60 / s.Bpm
	local barBeats = s.Beats or 4
	local sections, chords, totalBeats = timeline(s)
	local transpose = tonumber(s.Transpose) or 0
	local swing = math.clamp(tonumber(s.Swing) or 0, 0, 0.33)
	local phrases = s.Phrases
	local hasForm = type(s.Form) == "string"
	local events: { Event } = {}
	local function sectionAt(beat: number): (number, Section?)
		for i, sec in ipairs(sections) do
			if beat >= sec.Beat0 - 1e-6 and beat < sec.Beat1 - 1e-6 then
				return i, sec
			end
		end
		return 0, nil
	end
	local function add(beat: number, inst: string, n: number, v: number, dur: number)
		if beat < -1e-6 or beat >= totalBeats - 1e-6 then
			return
		end
		local _, sec = sectionAt(beat)
		local energy = sec and sec.Energy or 1
		if swing > 0 then
			-- (croches ternaires : le contretemps arrive plus tard)
			local frac = beat % 1
			if math.abs(frac - 0.5) < 1e-3 then
				beat += swing * 0.5
			elseif math.abs(frac - 0.75) < 1e-3 then
				beat += swing * 0.25
			end
		end
		if inst ~= "Drums" and inst ~= "DJ" then
			n += transpose
		end
		table.insert(events, { T = beat * beatSec, I = inst, N = n, V = math.clamp(v * energy, 0.05, 1), D = math.max(0.05, dur * beatSec) })
	end
	local function chordAt(beat: number): string?
		local found = nil
		for _, c in ipairs(chords) do
			if c[1] <= beat + 1e-6 then
				found = c[2]
			else
				break
			end
		end
		return found
	end
	local function inPart(part: any, beat: number): boolean
		local index, sec = sectionAt(beat)
		if not sec or index == 0 then
			return false
		end
		local bar = math.floor(beat / barBeats + 1e-6) + 1
		if bar < (part.FromBar or 1) or bar > (part.ToBar or math.huge) then
			return false
		end
		if sec.L == "END" then
			return part.Kind == "Harmony" or part.Kind == "Bass"
		end
		if type(part.In) == "string" then
			return string.find(part.In, sec.L, 1, true) ~= nil
		end
		return true
	end
	-- dernière section (avant la fin) où une partie joue : pour l'accord final
	local function activeInSection(part: any, sec: Section): boolean
		if type(part.In) == "string" then
			return string.find(part.In, sec.L, 1, true) ~= nil
		end
		return true
	end
	local lastSection = sections[#sections]
	if lastSection and lastSection.L == "END" then
		lastSection = sections[#sections - 1]
	end
	local melodies: { [number]: { { number } } } = {}
	for index, part in ipairs(s.Parts) do
		local kind = part.Kind
		local vel = part.Vel or 0.85
		local octave = 12 * (part.Octave or 0)
		if kind == "Lead" or kind == "Riff" then
			local full = {}
			local function place(text: string, start: number, stop: number, loop: boolean)
				if kind == "Lead" then
					local list = MusicData.ParseNotes(text, phrases)
					local len = math.max(MusicData.TextBeats(text, phrases), melodyLength(list))
					if len <= 0 then
						return
					end
					local offset = 0
					repeat
						for _, e in ipairs(list) do
							local b = start + offset + e[1]
							if b < stop - 1e-6 then
								table.insert(full, { b, e[2], e[3] })
							end
						end
						offset += len
					until not loop or start + offset >= stop - 1e-6
				else
					local list, len = parseRiff(text, phrases)
					if len <= 0 then
						return
					end
					local center = part.Center or 64
					local offset = 0
					repeat
						for _, e in ipairs(list) do
							local b = start + offset + e[1]
							local name = b < stop - 1e-6 and chordAt(b) or nil
							if name and name ~= "r" then
								local n = MusicData.Degree(e[2], name, center, 0)
								if n then
									table.insert(full, { b, n, e[3] })
								end
							end
						end
						offset += len
					until start + offset >= stop - 1e-6
				end
			end
			if hasForm then
				for _, sec in ipairs(sections) do
					if sec.L ~= "END" and activeInSection(part, sec) then
						local text = part.Notes or part.Pattern
						if type(text) == "table" then
							text = text[sec.L]
						end
						if type(text) == "string" then
							place(text, sec.Beat0, sec.Beat1, true)
						end
					end
				end
			else
				local text = part.Notes or part.Pattern or ""
				if kind == "Lead" then
					local list = MusicData.ParseNotes(text, phrases)
					local len = melodyLength(list)
					for r = 0, (part.Repeat or 1) - 1 do
						for _, e in ipairs(list) do
							table.insert(full, { e[1] + r * len, e[2], e[3] })
						end
					end
				else
					place(text, 0, totalBeats, true)
				end
			end
			melodies[index] = full
			for _, e in ipairs(full) do
				if inPart(part, e[1]) then
					-- (petite respiration : accents sur les temps forts)
					local accent = (e[1] % barBeats) < 1e-6 and 1 or ((e[1] % 1) < 1e-6 and 0.9 or 0.8)
					local n = e[2] + octave
					add(e[1], part.I, n, vel * accent, e[3])
				end
			end
		elseif kind == "Echo" then
			local source = melodies[part.Of]
			for _, e in ipairs(source or {}) do
				local beat = e[1] + (part.Delay or 0)
				if inPart(part, beat) then
					add(beat, part.I, e[2] + octave, vel, e[3])
				end
			end
		elseif kind == "Harmony" then
			local style = part.Style
			for _, c in ipairs(chords) do
				local start, name, dur = c[1], c[2], c[3]
				local sec = sections[c[4]]
				if name ~= "r" and inPart(part, start) and not (sec.L == "END" and lastSection and not activeInSection(part, lastSection)) then
					local pc0 = MusicData.Chord(name)
					local center = 62 + octave
					local notes = MusicData.ChordNotes(name, center)
					local st = sec.L == "END" and "end" or style
					if st == "end" then
						for k, n in ipairs(notes) do
							add(start + (k - 1) * 0.04, part.I, n, vel, barBeats)
						end
						if pc0 then
							add(start, part.I, MusicData.Root(name, center - 18) or notes[1] - 12, vel * 0.8, barBeats)
						end
					elseif st == "block" then
						local step = math.min(2, dur)
						local b = 0
						while b < dur - 1e-6 do
							for _, n in ipairs(notes) do
								add(start + b, part.I, n, vel, math.min(step, dur - b))
							end
							b += step
						end
					elseif st == "pad" then
						for _, n in ipairs(notes) do
							add(start, part.I, n, vel, dur)
						end
					elseif st == "arp" or st == "chip" or st == "ballad" then
						local seq = table.clone(notes)
						local stepLen = st == "chip" and 0.25 or 0.5
						if st == "ballad" then
							-- (main gauche large : basse, quinte, octave, dixième…)
							local root = MusicData.Root(name, center - 18) or notes[1] - 12
							seq = { root, root + 7, root + 12, notes[2] or root + 16, root + 19, notes[2] or root + 16, root + 12, root + 7 }
						else
							table.insert(seq, notes[1] + 12)
							for i = #notes - 1, 2, -1 do
								table.insert(seq, notes[i])
							end
						end
						local b, i = 0, 0
						while b < dur - 1e-6 do
							add(start + b, part.I, seq[i % #seq + 1], vel * (i % 2 == 0 and 1 or 0.8), stepLen * (st == "ballad" and 2 or 1))
							b += stepLen
							i += 1
						end
					elseif st == "alberti" then
						-- (classique : grave, aigu, médium, aigu)
						local seq = { notes[1], notes[3] or notes[1] + 7, notes[2] or notes[1] + 4, notes[3] or notes[1] + 7 }
						local b, i = 0, 0
						while b < dur - 1e-6 do
							add(start + b, part.I, seq[i % 4 + 1] - 12, vel * (i % 4 == 0 and 1 or 0.75), 0.5)
							b += 0.5
							i += 1
						end
					elseif st == "strum" then
						-- rythme "Bas, Bas-Haut, Haut-Bas-Haut" (croches) ; guitare : 5 cordes
						local root = MusicData.Root(name, 40) or 48
						local voicing = { root }
						for _, n in ipairs(MusicData.ChordNotes(name, 58)) do
							table.insert(voicing, n)
						end
						table.insert(voicing, (MusicData.ChordNotes(name, 66))[1] or root + 24)
						local pattern = { { 0, 1 }, { 1, 1 }, { 1.5, -1 }, { 2.5, -1 }, { 3, 1 }, { 3.5, -1 } }
						for _, hit in ipairs(pattern) do
							local b = hit[1]
							if b < dur - 1e-6 then
								local down = hit[2] > 0
								local count = down and #voicing or 3
								for k = 1, count do
									local n = down and voicing[k] or voicing[#voicing - k + 1]
									add(start + b + (k - 1) * 0.035, part.I, n, vel * (down and 0.9 or 0.65), 0.45)
								end
							end
						end
					elseif st == "power" then
						-- (rock : quinte + octave, croches étouffées)
						local root = MusicData.Root(name, 40) or 40
						local b = 0
						while b < dur - 1e-6 do
							local accent = (b % 2) < 1e-6 and 1 or 0.7
							for _, n in ipairs({ root, root + 7, root + 12 }) do
								add(start + b, part.I, n, vel * accent, 0.4)
							end
							b += 0.5
						end
					elseif st == "stabs" or st == "skank" then
						-- (contretemps : disco / reggae)
						local b = 0.5
						local len = st == "skank" and 0.2 or 0.25
						while b < dur - 1e-6 do
							for _, n in ipairs(notes) do
								add(start + b, part.I, n, vel, len)
							end
							b += 1
						end
					elseif st == "comp" then
						-- (jazz : accords à 4 sons, poussés sur le "et" de 2 et sur 4)
						local four = MusicData.ChordNotes(name, center - 2)
						for _, b in ipairs({ 1.5, 3 }) do
							if b < dur - 1e-6 then
								for k, n in ipairs(four) do
									add(start + b + (k - 1) * 0.02, part.I, n, vel * (b == 3 and 0.75 or 1), 0.6)
								end
							end
						end
					elseif st == "pulse" then
						-- (électro : croches régulières, accord serré)
						local b = 0
						while b < dur - 1e-6 do
							for _, n in ipairs(notes) do
								add(start + b, part.I, n, vel * ((b % 1) < 1e-6 and 1 or 0.7), 0.4)
							end
							b += 0.5
						end
					elseif st == "lofi" then
						-- accord égrené (main un peu en retard), rejoué au 3e temps
						for k, n in ipairs(notes) do
							add(start + (k - 1) * 0.06, part.I, n, vel, 2)
							if dur >= 3 then
								add(start + 2.5 + (k - 1) * 0.05, part.I, n, vel * 0.7, 1.4)
							end
						end
					elseif st == "waltz" then
						-- (oum-pa-pa : basse au 1er temps, accord aux 2e et 3e)
						local root = MusicData.Root(name, 43) or 43
						add(start, part.I, root, vel, 1)
						for _, b in ipairs({ 1, 2 }) do
							if b < dur - 1e-6 then
								for _, n in ipairs(notes) do
									add(start + b, part.I, n, vel * 0.7, 0.6)
								end
							end
						end
					elseif st == "broken" then
						-- main gauche de "Lettre à Élise" : fondamentale grave, quinte, octave
						local root = MusicData.Root(name, 45) or 45
						add(start, part.I, root, vel, 0.25)
						add(start + 0.25, part.I, root + 7, vel * 0.8, 0.25)
						add(start + 0.5, part.I, root + 12, vel * 0.8, 0.25)
					end
				end
			end
		elseif kind == "Bass" then
			for ci, c in ipairs(chords) do
				local start, name, dur = c[1], c[2], c[3]
				local root = name ~= "r" and MusicData.Root(name, 36) or nil
				local sec = sections[c[4]]
				if root and inPart(part, start) and not (sec.L == "END" and lastSection and not activeInSection(part, lastSection)) then
					local _, iv = MusicData.Chord(name)
					local third = iv and iv[2] or 4
					local style = sec.L == "END" and "whole" or part.Style
					local nextChord = chords[ci + 1]
					local nextRoot = nextChord and nextChord[2] ~= "r" and MusicData.Root(nextChord[2], 36) or root
					if style == "whole" then
						add(start, part.I, root, vel, dur)
					elseif style == "half" then
						add(start, part.I, root, vel, math.min(2, dur))
						if dur > 2 then
							add(start + 2, part.I, root + 7, vel * 0.8, dur - 2)
						end
					elseif style == "octave" then
						local b, i = 0, 0
						while b < dur - 1e-6 do
							add(start + b, part.I, root + (i % 2 == 1 and 12 or 0), vel * (i % 2 == 1 and 0.75 or 1), 0.45)
							b += 0.5
							i += 1
						end
					elseif style == "eighth" then
						local b = 0
						while b < dur - 1e-6 do
							add(start + b, part.I, root, vel * ((b % 1) < 1e-6 and 1 or 0.75), 0.4)
							b += 0.5
						end
					elseif style == "walk" then
						-- (jazz : noires qui marchent vers l'accord suivant)
						local steps = { root, root + third, root + 7 }
						local b, i = 0, 0
						while b < dur - 1e-6 do
							local n = steps[i % 3 + 1]
							if b >= dur - 1 - 1e-6 then
								-- (approche chromatique de la prochaine fondamentale)
								local target = nextRoot or root
								n = target + ((target > root) and -1 or 1)
							end
							add(start + b, part.I, n, vel * (i % 2 == 0 and 1 or 0.8), 0.9)
							b += 1
							i += 1
						end
					elseif style == "reggae" then
						add(start, part.I, root, vel, 1.4)
						if dur >= 3 then
							add(start + 1.5, part.I, root + 7, vel * 0.8, 0.5)
							add(start + 2, part.I, root + 12, vel * 0.85, 0.9)
							add(start + 3, part.I, root + third, vel * 0.75, 0.9)
						end
					elseif style == "funk" then
						local pattern = { { 0, 0, 1 }, { 0.75, 12, 0.7 }, { 1.5, 0, 0.8 }, { 2.5, 10, 0.8 }, { 3, 7, 0.9 }, { 3.5, 12, 0.7 } }
						for _, p in ipairs(pattern) do
							if p[1] < dur - 1e-6 then
								add(start + p[1], part.I, root + p[2], vel * p[3], 0.3)
							end
						end
					elseif style == "808" then
						-- (hip-hop / trap : notes longues, rebond à l'octave)
						add(start, part.I, root, vel, math.min(1.5, dur))
						if dur >= 3 then
							add(start + 1.75, part.I, root, vel * 0.85, 1)
							add(start + 3, part.I, root + 12, vel * 0.7, 0.5)
							add(start + 3.5, part.I, root, vel * 0.8, 0.5)
						end
					elseif style == "synth" then
						-- (synthwave : croches, octave sur les contretemps)
						local b, i = 0, 0
						while b < dur - 1e-6 do
							add(start + b, part.I, root + ((i % 4 == 3) and 12 or 0), vel * (i % 2 == 0 and 1 or 0.7), 0.35)
							b += 0.5
							i += 1
						end
					elseif style == "bossa" then
						add(start, part.I, root, vel, 1.4)
						add(start + 1.5, part.I, root + 7, vel * 0.8, 0.5)
						if dur >= 3 then
							add(start + 2, part.I, root + 7, vel * 0.85, 1.4)
							add(start + 3.5, part.I, root, vel * 0.75, 0.5)
						end
					elseif style == "country" then
						add(start, part.I, root, vel, 0.9)
						if dur >= 3 then
							add(start + 2, part.I, root + 7, vel * 0.85, 0.9)
						end
					else -- "root" : fondamentale au 1er temps, quinte au 3e
						add(start, part.I, root, vel, math.min(dur, 1.5))
						if dur >= 3 then
							add(start + 2, part.I, root + 7, vel * 0.8, 1)
							add(start + 3.5, part.I, root + 12, vel * 0.55, 0.5)
						end
					end
				end
			end
		elseif kind == "Drums" and part.Style ~= "none" then
			local groove = GROOVES[part.Style] or GROOVES.pop
			local fillDef = FILLS[part.Fill or GROOVE_FILL[part.Style] or "toms"] or FILLS.toms
			local steps = math.floor(barBeats * 4 + 0.5)
			for si, sec in ipairs(sections) do
				local active = sec.L ~= "END" and activeInSection(part, sec)
				if active then
					for k = 0, sec.Bars - 1 do
						local barStart = sec.Beat0 + k * barBeats
						local bar = math.floor(barStart / barBeats + 1e-6) + 1
						if bar >= (part.FromBar or 1) and bar <= (part.ToBar or math.huge) then
							local lastOfSection = k == sec.Bars - 1
							local nextSec = sections[si + 1]
							local fill = false
							if lastOfSection and nextSec and part.Fills ~= false then
								fill = true
							elseif not hasForm and (bar % 4 == 0) and bar < (part.ToBar or math.huge) and k < sec.Bars - 1 then
								fill = true
							elseif hasForm and (k % 8 == 7) and part.Fills ~= false then
								fill = true
							end
							local songEnd = not hasForm and k == sec.Bars - 1
							local fillFrom = fill and (steps - math.min(steps, fillDef.Steps)) or steps
							for pieceKey, pattern in pairs(groove) do
								local piece: string = pieceKey
								local isKick = piece == "Kick"
								for st = 1, steps do
									local ch = string.sub(pattern, (st - 1) % #pattern + 1, (st - 1) % #pattern + 1)
									if ch ~= "." and ch ~= "" and not songEnd and (isKick or st <= fillFrom) then
										local beat = barStart + (st - 1) * 0.25
										local v = (ch == "o" and 1 or (ch == "g" and 0.4 or 0.8)) * vel
										if piece == "HatClosed" and ch ~= "g" then
											v *= (st % 2 == 1) and 0.8 or 0.55
										end
										add(beat, "Drums", MusicData.DRUM[piece], v, 0.2)
										if ch == "r" then
											add(beat + 0.125, "Drums", MusicData.DRUM[piece], v * 0.8, 0.1)
										end
									end
								end
							end
							if fill then
								for pieceKey, pattern in pairs(fillDef) do
									if type(pattern) == "string" then
										for st = fillFrom + 1, steps do
											local ch = string.sub(pattern, st, st)
											if ch ~= "." and ch ~= "" then
												local beat = barStart + (st - 1) * 0.25
												local v = (ch == "o" and 1 or (ch == "g" and 0.45 or 0.82)) * vel
												add(beat, "Drums", MusicData.DRUM[pieceKey], v, 0.2)
												if ch == "r" then
													add(beat + 0.125, "Drums", MusicData.DRUM[pieceKey], v * 0.8, 0.1)
												end
											end
										end
									end
								end
							end
							-- crash : début de section (sauf la toute première mesure) et toutes les 8 mesures
							if (k == 0 and si > 1) or (k > 0 and k % 8 == 0) or (not hasForm and bar % 4 == 1 and bar > 1) then
								add(barStart, "Drums", MusicData.DRUM.Crash, vel * 0.85, 1)
							end
							if songEnd then
								add(barStart, "Drums", MusicData.DRUM.Crash, vel, 2)
								add(barStart, "Drums", MusicData.DRUM.Kick, vel, 0.5)
							end
						end
					end
				end
			end
			-- accord final : crash + grosse caisse
			local final = sections[#sections]
			if hasForm and final and final.L == "END" and lastSection and activeInSection(part, lastSection) then
				add(final.Beat0, "Drums", MusicData.DRUM.Crash, vel, 2)
				add(final.Beat0, "Drums", MusicData.DRUM.Kick, vel, 0.5)
			end
		elseif kind == "DJ" then
			local style: string = tostring(part.Style)
			local fx = MusicData.DJ_FX
			for si, sec in ipairs(sections) do
				if sec.L ~= "END" and (hasForm and activeInSection(part, sec) or (not hasForm and inPart(part, sec.Beat0))) then
					for k = 0, sec.Bars - 1 do
						local barStart = sec.Beat0 + k * barBeats
						if style == "scratch" and k % 4 == 3 then
							add(barStart + barBeats - 1, "DJ", fx.Scratch, 0.8, 0.5)
							add(barStart + barBeats - 0.5, "DJ", fx.Scratch, 0.7, 0.5)
						elseif style == "vinyl" and k % 8 == 7 then
							add(barStart + barBeats - 1, "DJ", fx.Riser, 0.5, 1)
						end
					end
					if style == "riser" then
						-- (montée sur la dernière mesure de la section)
						add(sec.Beat1 - barBeats, "DJ", fx.Riser, 0.8, barBeats)
					elseif style == "drop" then
						add(sec.Beat0, "DJ", fx.Drop, 0.9, 2)
					elseif style == "horn" and si > 1 then
						add(sec.Beat0, "DJ", fx.Horn, 0.8, 1)
					end
				end
			end
		end
	end
	table.sort(events, function(a, b)
		if a.T ~= b.T then
			return a.T < b.T
		end
		if a.I ~= b.I then
			return a.I < b.I
		end
		return a.N < b.N
	end)
	return { Events = events, Duration = totalBeats * beatSec, BeatSec = beatSec, Sections = sections }
end

local compiled: { [string]: any } = {}

-- Morceau compilé (mis en cache) ; nil si inconnu
function MusicData.Song(id: string): any
	local cached = compiled[id]
	if cached then
		return cached
	end
	local index = MusicData.SONG_INDEX[id]
	if not index then
		return nil
	end
	local song = MusicData.SONGS[index]
	local result: any = MusicData.Compile(song)
	result.Id = song.Id
	result.Name = song.Name
	result.Icon = song.Icon
	result.Author = song.Author
	result.Genre = song.Genre
	result.Bpm = song.Bpm
	compiled[id] = result
	return result
end

-- Durée d'un morceau (s), 0 si inconnu
function MusicData.Duration(id: string): number
	local song = MusicData.Song(id)
	return song and song.Duration or 0
end

-- Instruments joués par un morceau (pour les pochettes : 🎹🥁🎸…)
function MusicData.SongInstruments(id: string): { string }
	local song = MusicData.Song(id)
	local seen, list = {}, {}
	for _, ev in ipairs(song and song.Events or {}) do
		if not seen[ev.I] then
			seen[ev.I] = true
			table.insert(list, ev.I)
		end
	end
	table.sort(list, function(a, b)
		return (MusicData.INDEX[a] or 99) < (MusicData.INDEX[b] or 99)
	end)
	return list
end

----------------------------------------------------------------------
-- 5. Boucles du DJ (1 mesure à 120 BPM = 2 s, calées sur l'heure du serveur)
----------------------------------------------------------------------

MusicData.LOOP_BPM = 120
MusicData.LOOP_BAR = 4 * 60 / MusicData.LOOP_BPM

local LOOPS: { { Groove: string, Bass: { number }, Chord: string?, Stab: string? } } = {
	{ Groove = "rock", Bass = { 45, 0, 45, 0, 0, 0, 48, 0, 45, 0, 45, 0, 43, 0, 43, 0 } },
	{ Groove = "house", Bass = { 0, 0, 45, 0, 0, 0, 45, 0, 0, 0, 48, 0, 0, 0, 47, 0 }, Chord = "Am7", Stab = "..x...x...x...x." },
	{ Groove = "hiphop", Bass = { 45, 0, 0, 0, 0, 0, 0, 45, 45, 0, 43, 0, 0, 0, 0, 0 } },
	{ Groove = "lofi", Bass = { 50, 0, 0, 0, 0, 0, 0, 0, 43, 0, 0, 0, 0, 0, 45, 0 }, Chord = "Dm7", Stab = "x.........x....." },
	{ Groove = "trap", Bass = { 41, 0, 0, 0, 0, 0, 0, 41, 0, 0, 41, 0, 0, 0, 0, 0 } },
	{ Groove = "reggae", Bass = { 43, 0, 0, 0, 0, 0, 50, 0, 55, 0, 0, 0, 47, 0, 0, 0 }, Chord = "G", Stab = "....x.......x..." },
	{ Groove = "disco", Bass = { 45, 0, 57, 0, 45, 0, 57, 0, 43, 0, 55, 0, 43, 0, 55, 0 }, Chord = "Am7", Stab = "..x.......x....." },
	{ Groove = "techno", Bass = { 0, 0, 45, 45, 0, 0, 45, 45, 0, 0, 45, 45, 0, 0, 45, 48 }, Chord = "Am", Stab = "...x.....x....x." },
}
MusicData.LOOP_NAMES = { "Rock", "House", "Hip-hop", "Lo-fi", "Trap", "Reggae", "Disco", "Techno" }
MusicData.LOOP_ICONS = { "🤘", "🏠", "🎤", "☕", "🔥", "🌴", "🪩", "⚡" }

local loopCache: { [number]: { Event } } = {}

-- Événements d'une boucle (T dans [0, LOOP_BAR[) : batterie + basse (+ accords)
function MusicData.Loop(index: number): { Event }
	local cached = loopCache[index]
	if cached then
		return cached
	end
	local def = LOOPS[index]
	local events: { Event } = {}
	if def then
		local step = MusicData.LOOP_BAR / 16
		for piece, pattern in pairs(GROOVES[def.Groove] or {}) do
			for s = 1, 16 do
				local ch = string.sub(pattern, s, s)
				if ch ~= "." and ch ~= "" then
					local v = ch == "o" and 0.95 or (ch == "g" and 0.4 or 0.75)
					table.insert(events, { T = (s - 1) * step, I = "Drums", N = MusicData.DRUM[piece], V = v, D = 0.2 })
					if ch == "r" then
						table.insert(events, { T = (s - 0.5) * step, I = "Drums", N = MusicData.DRUM[piece], V = v * 0.8, D = 0.1 })
					end
				end
			end
		end
		for s, n in ipairs(def.Bass) do
			if n > 0 then
				table.insert(events, { T = (s - 1) * step, I = "Bass", N = n, V = 0.8, D = step * 2 })
			end
		end
		if def.Chord and def.Stab then
			for s = 1, 16 do
				if string.sub(def.Stab, s, s) == "x" then
					for _, n in ipairs(MusicData.ChordNotes(def.Chord, 64)) do
						table.insert(events, { T = (s - 1) * step, I = "Synth", N = n, V = 0.45, D = step * 1.5 })
					end
				end
			end
		end
		table.sort(events, function(a, b)
			return a.T < b.T
		end)
	end
	loopCache[index] = events
	return events
end

return MusicData
