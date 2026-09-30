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

MusicData.FOOTPRINT = Vector3.new(24, 16, 16) -- (X, hauteur max, Z)
MusicData.GROUND = 0.06 -- dessus du pavé de la place (au-dessus de l'origine)
MusicData.DECK_TOP = 1.5 -- plancher de la scène
MusicData.DECK = { X0 = -10.2, X1 = 10.2, Z0 = -3.6, Z1 = 7.6 }
-- marches du devant (2 marches de 0,5 : une marche Roblox monte sans sauter)
MusicData.STEPS = { X = 3.6, Depth = 0.95, Rise = 0.5, Count = 2 }
-- praticables (estrades) : batterie au fond au centre, DJ au fond à gauche (+X)
MusicData.RISERS = {
	Drums = { X0 = -3.2, X1 = 3.2, Z0 = 3.3, Z1 = 7.6, H = 0.7 },
	DJ = { X0 = 5.8, X1 = 10.2, Z0 = 3.6, Z1 = 7.6, H = 0.5 },
}
MusicData.TRUSS_H = 13.4 -- dessous du grill (portique d'éclairage)
MusicData.TRUSS_TOWERS = { Vector3.new(-11.2, 0, -3.2), Vector3.new(11.2, 0, -3.2), Vector3.new(-11.2, 0, 7.3), Vector3.new(11.2, 0, 7.3) }
MusicData.TOWER_SIZE = 0.9
MusicData.PA = { Vector3.new(-10.6, 0, -5.4), Vector3.new(10.6, 0, -5.4) } -- enceintes au sol (devant)
MusicData.JUKEBOX = CFrame.new(6.8, 0, -6.3) -- 🎛️ pupitre "musique" au sol (pour tous)

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
	Piano = { Id = "Piano", Name = "Grand piano", Icon = "🎹", Kind = "keys", Seated = true, Floor = 1.5, Spot = facing(-3.35, -0.35, 90), Prompt = Vector3.new(-3.5, 3.4, -0.35) },
	Drums = { Id = "Drums", Name = "Drum kit", Icon = "🥁", Kind = "drums", Seated = true, Floor = 2.2, Spot = facing(0, 6.45, 0), Prompt = Vector3.new(0, 4.6, 4.6) },
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
MusicData.DJ_PADS = { "LoopBeat", "LoopHouse", "LoopHipHop", "LoopLofi", "Scratch", "Horn", "Riser", "Drop" }
MusicData.DJ_LOOPS = 4

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
-- 4. Morceaux
--   Suites de jetons séparés par des espaces ("|" = barre de mesure,
--   ignorée) : "E4" (1 temps), "E4:1.5", "r:2" (silence) ; accords : "Am",
--   "G7:2" (sans durée = une mesure entière).
--   Parties : Lead (mélodie), Harmony (accords : style), Bass (style),
--   Drums (style), Echo (canon : même mélodie décalée), DJ (style).
----------------------------------------------------------------------

export type Event = { T: number, I: string, N: number, V: number, D: number }
export type Song = {
	Id: string,
	Name: string,
	Icon: string,
	Author: string,
	Bpm: number,
	Beats: number, -- temps par mesure
	Bars: number,
	Chords: string,
	Parts: { any },
}

MusicData.SONGS = {
	{
		Id = "OdeToJoy",
		Name = "Ode to Joy",
		Icon = "🎼",
		Author = "Beethoven",
		Bpm = 126,
		Beats = 4,
		Bars = 16,
		Chords = "C | G | C | G | C | G | C | G:2 C:2 | G:2 C:2 | G:2 C:2 | G:2 Am:2 | D:2 G:2 | C | G | C | G:2 C:2",
		Parts = {
			{
				Kind = "Lead",
				I = "Piano",
				Octave = 1,
				Notes = "E4 E4 F4 G4 | G4 F4 E4 D4 | C4 C4 D4 E4 | E4:1.5 D4:0.5 D4:2 | E4 E4 F4 G4 | G4 F4 E4 D4 | C4 C4 D4 E4 | D4:1.5 C4:0.5 C4:2"
					.. " | D4 D4 E4 C4 | D4 E4:0.5 F4:0.5 E4 C4 | D4 E4:0.5 F4:0.5 E4 D4 | C4 D4 G3:2 | E4 E4 F4 G4 | G4 F4 E4 D4 | C4 C4 D4 E4 | D4:1.5 C4:0.5 C4:2",
			},
			{ Kind = "Lead", I = "Xylophone", Octave = 2, FromBar = 13, Vel = 0.55, Notes = "r:48 E4 E4 F4 G4 | G4 F4 E4 D4 | C4 C4 D4 E4 | D4:1.5 C4:0.5 C4:2" },
			{ Kind = "Harmony", I = "Guitar", Style = "strum" },
			{ Kind = "Harmony", I = "Synth", Style = "pad", FromBar = 9, Vel = 0.35 },
			{ Kind = "Bass", I = "Bass", Style = "root" },
			{ Kind = "Drums", Style = "pop" },
		},
	},
	{
		Id = "FrereJacques",
		Name = "Brother John (round)",
		Icon = "🔔",
		Author = "Traditional",
		Bpm = 116,
		Beats = 4,
		Bars = 20,
		Chords = "C",
		Parts = {
			{ Kind = "Lead", I = "Piano", Octave = 1, Repeat = 2, Notes = "C4 D4 E4 C4 | C4 D4 E4 C4 | E4 F4 G4:2 | E4 F4 G4:2 | G4:0.5 A4:0.5 G4:0.5 F4:0.5 E4 C4 | G4:0.5 A4:0.5 G4:0.5 F4:0.5 E4 C4 | C4 G3 C4:2 | C4 G3 C4:2" },
			{ Kind = "Echo", I = "Xylophone", Of = 1, Delay = 8, Octave = 1, Vel = 0.8 },
			{ Kind = "Echo", I = "Synth", Of = 1, Delay = 16, Octave = 0, Vel = 0.7 },
			{ Kind = "Bass", I = "Bass", Style = "root" },
			{ Kind = "Drums", Style = "brush" },
		},
	},
	{
		Id = "ClairDeLune",
		Name = "By the Light of the Moon",
		Icon = "🌙",
		Author = "Traditional (France)",
		Bpm = 100,
		Beats = 4,
		Bars = 16,
		Chords = "C | C:2 G:2 | C:2 G:2 | C | C | C:2 G:2 | C:2 G:2 | C | G | Dm | G:2 D:2 | G | C | C:2 G:2 | C:2 G:2 | C",
		Parts = {
			{
				Kind = "Lead",
				I = "Xylophone",
				Octave = 1,
				Notes = "C4 C4 C4 D4 | E4:2 D4:2 | C4 E4 D4 D4 | C4:4 | C4 C4 C4 D4 | E4:2 D4:2 | C4 E4 D4 D4 | C4:4"
					.. " | D4 D4 D4 D4 | A3:2 A3:2 | D4 C4 B3 A3 | G3:4 | C4 C4 C4 D4 | E4:2 D4:2 | C4 E4 D4 D4 | C4:4",
			},
			{ Kind = "Harmony", I = "Piano", Style = "arp", Vel = 0.5 },
			{ Kind = "Bass", I = "Bass", Style = "whole" },
			{ Kind = "Drums", Style = "brush" },
		},
	},
	{
		Id = "Twinkle",
		Name = "Twinkle Twinkle",
		Icon = "⭐",
		Author = "Traditional",
		Bpm = 108,
		Beats = 4,
		Bars = 12,
		Chords = "C | F:2 C:2 | F:2 C:2 | G:2 C:2 | C:2 F:2 | C:2 G:2 | C:2 F:2 | C:2 G:2 | C | F:2 C:2 | F:2 C:2 | G:2 C:2",
		Parts = {
			{
				Kind = "Lead",
				I = "Synth",
				Octave = 1,
				Notes = "C4 C4 G4 G4 | A4 A4 G4:2 | F4 F4 E4 E4 | D4 D4 C4:2 | G4 G4 F4 F4 | E4 E4 D4:2 | G4 G4 F4 F4 | E4 E4 D4:2"
					.. " | C4 C4 G4 G4 | A4 A4 G4:2 | F4 F4 E4 E4 | D4 D4 C4:2",
			},
			{ Kind = "Lead", I = "Xylophone", Octave = 2, Vel = 0.5, Notes = "r:32 C4 C4 G4 G4 | A4 A4 G4:2 | F4 F4 E4 E4 | D4 D4 C4:2" },
			{ Kind = "Harmony", I = "Piano", Style = "block", Vel = 0.55 },
			{ Kind = "Harmony", I = "Guitar", Style = "strum", FromBar = 5, Vel = 0.5 },
			{ Kind = "Bass", I = "Bass", Style = "root" },
			{ Kind = "Drums", Style = "pop" },
		},
	},
	{
		Id = "Canon",
		Name = "Canon in C",
		Icon = "🎻",
		Author = "Pachelbel",
		Bpm = 72,
		Beats = 4,
		Bars = 13,
		Chords = "C:2 G:2 | Am:2 Em:2 | F:2 C:2 | F:2 G:2 | C:2 G:2 | Am:2 Em:2 | F:2 C:2 | F:2 G:2 | C:2 G:2 | Am:2 Em:2 | F:2 C:2 | F:2 G:2 | C",
		Parts = {
			{
				Kind = "Lead",
				I = "Piano",
				Octave = 0,
				Notes = "E5:2 D5:2 | C5:2 B4:2 | A4:2 G4:2 | A4:2 B4:2 | C5 E5 D5 B4 | C5 E5 B4 G4 | A4 C5 G4 E4 | F4 A4 B4 D5"
					.. " | C5:0.5 D5:0.5 E5:0.5 C5:0.5 B4:0.5 C5:0.5 D5:0.5 B4:0.5 | A4:0.5 B4:0.5 C5:0.5 A4:0.5 G4:0.5 A4:0.5 B4:0.5 G4:0.5"
					.. " | F4:0.5 G4:0.5 A4:0.5 F4:0.5 E4:0.5 F4:0.5 G4:0.5 E4:0.5 | F4:0.5 G4:0.5 A4:0.5 B4:0.5 C5:0.5 D5:0.5 E5:0.5 G5:0.5 | C5:4",
			},
			{ Kind = "Lead", I = "Xylophone", Octave = 1, Vel = 0.45, Notes = "r:32 E5:2 D5:2 | C5:2 B4:2 | A4:2 G4:2 | A4:2 B4:2 | C5:4" },
			{ Kind = "Harmony", I = "Synth", Style = "pad", Vel = 0.4 },
			{ Kind = "Harmony", I = "Piano", Style = "arp", FromBar = 5, Vel = 0.35 },
			{ Kind = "Bass", I = "Bass", Style = "half" },
			{ Kind = "Drums", Style = "none" },
		},
	},
	{
		Id = "FurElise",
		Name = "Für Elise",
		Icon = "💌",
		Author = "Beethoven",
		Bpm = 66,
		Beats = 1.5,
		Bars = 18,
		Chords = "r:1.5 | r | Am | E | Am | r | Am | E | Am | r | r | Am | E | Am | r | Am | E | Am",
		Parts = {
			{
				Kind = "Lead",
				I = "Piano",
				Octave = 0,
				Repeat = 2,
				Notes = "r:1 E5:0.25 D#5:0.25 | E5:0.25 D#5:0.25 E5:0.25 B4:0.25 D5:0.25 C5:0.25 | A4:0.5 r:0.25 C4:0.25 E4:0.25 A4:0.25"
					.. " | B4:0.5 r:0.25 E4:0.25 G#4:0.25 B4:0.25 | C5:0.5 r:0.25 E4:0.25 E5:0.25 D#5:0.25"
					.. " | E5:0.25 D#5:0.25 E5:0.25 B4:0.25 D5:0.25 C5:0.25 | A4:0.5 r:0.25 C4:0.25 E4:0.25 A4:0.25"
					.. " | B4:0.5 r:0.25 E4:0.25 C5:0.25 B4:0.25 | A4:1.5",
			},
			{ Kind = "Harmony", I = "Piano", Style = "broken", Vel = 0.45 },
			{ Kind = "Drums", Style = "none" },
		},
	},
	{
		Id = "DopamineGroove",
		Name = "Dopamine Groove",
		Icon = "🧠",
		Author = "Dopamine Town band",
		Bpm = 116,
		Beats = 4,
		Bars = 16,
		Chords = "Am7 | D7 | Fmaj7 | E7",
		Parts = {
			{
				Kind = "Lead",
				I = "Synth",
				Octave = 0,
				Notes = "r:16 r:0.5 A4:0.5 C5:0.5 E5:0.5 G5 E5 | F#5:0.5 E5:0.5 D5:0.5 C5:0.5 A4:2 | r:0.5 A4:0.5 C5:0.5 F5:0.5 E5 C5 | B4:0.5 C5:0.5 D5:0.5 B4:0.5 G#4:2"
					.. " | r:0.5 A4:0.5 C5:0.5 E5:0.5 A5 G5 | F#5:0.5 A5:0.5 F#5:0.5 D5:0.5 E5:2 | r:0.5 F5:0.5 E5:0.5 C5:0.5 A4 C5 | B4 G#4 E4 r",
			},
			{ Kind = "Harmony", I = "Guitar", Style = "stabs", Vel = 0.6 },
			{ Kind = "Harmony", I = "Xylophone", Style = "arp", FromBar = 13, Octave = 1, Vel = 0.45 },
			{ Kind = "Harmony", I = "Piano", Style = "block", FromBar = 5, ToBar = 12, Vel = 0.35 },
			{ Kind = "Bass", I = "Bass", Style = "octave" },
			{ Kind = "Drums", Style = "disco" },
			{ Kind = "DJ", Style = "scratch" },
		},
	},
	{
		Id = "LofiEvening",
		Name = "Evening Lo-fi",
		Icon = "☕",
		Author = "Dopamine Town band",
		Bpm = 82,
		Beats = 4,
		Bars = 16,
		Chords = "Dm7 | G7 | Cmaj7 | Am7",
		Parts = {
			{
				Kind = "Lead",
				I = "Xylophone",
				Octave = 0,
				Vel = 0.75,
				Notes = "r:16 r F5:0.5 E5:0.5 D5 A4 | B4:1.5 C5:0.5 D5 G4 | r E5:0.5 D5:0.5 C5 G4 | A4:2 C5 E5"
					.. " | F5 E5:0.5 D5:0.5 C5 A4 | B4 D5 F5 E5 | E5:1.5 D5:0.5 C5 B4 | A4:3 r"
					.. " | r F5:0.5 E5:0.5 D5 A4 | B4:1.5 C5:0.5 D5 G4 | r E5:0.5 D5:0.5 C5 G4 | A4:4",
			},
			{ Kind = "Harmony", I = "Piano", Style = "lofi", Vel = 0.5 },
			{ Kind = "Bass", I = "Bass", Style = "root" },
			{ Kind = "Drums", Style = "boom" },
			{ Kind = "DJ", Style = "vinyl" },
		},
	},
} :: { any }

MusicData.SONG_INDEX = {} :: { [string]: number }
for i, song in ipairs(MusicData.SONGS) do
	MusicData.SONG_INDEX[song.Id] = i
end

-- Batterie : 16 doubles-croches par mesure de 4 temps (12 pour 3 temps)
-- "x" = coup, "o" = coup accentué, "." = rien
local GROOVES: { [string]: { [string]: string } } = {
	pop = { Kick = "x.....x.x.......", Snare = "....x.......x...", HatClosed = "x.x.x.x.x.x.x.x." },
	rock = { Kick = "x.......x.x.....", Snare = "....o.......o...", HatClosed = "x.x.x.x.x.x.x.x." },
	disco = { Kick = "x...x...x...x...", Snare = "....x.......x...", HatClosed = "x...x...x...x...", HatOpen = "..x...x...x...x." },
	boom = { Kick = "x.......x.x.....", Snare = "....x.......x..x", HatClosed = "x.x.x.xxx.x.x.x." },
	brush = { Kick = "x.......x.......", Snare = "....x.......x...", Ride = "x..xx..xx..xx..x" },
	house = { Kick = "x...x...x...x...", HatOpen = "..x...x...x...x.", Snare = "....x.......x..." },
	hiphop = { Kick = "x......xx.x.....", Snare = "....x.......x...", HatClosed = "x.x.x.x.x.x.x.xx" },
}

local function tokens(text: string): { string }
	local list = {}
	for token in string.gmatch(text, "%S+") do
		if token ~= "|" then
			table.insert(list, token)
		end
	end
	return list
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
function MusicData.ParseNotes(text: string): { { number } }
	local out = {}
	local beat = 0
	for _, token in ipairs(tokens(text)) do
		local head, dur = split(token, 1)
		local n = head ~= "r" and MusicData.Note(head) or nil
		if n then
			table.insert(out, { beat, n, dur })
		end
		beat += dur
	end
	return out
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

-- Compile un morceau en événements triés (T en secondes)
function MusicData.Compile(song: Song): { Events: { Event }, Duration: number, BeatSec: number }
	local beatSec = 60 / song.Bpm
	local barBeats = song.Beats
	local totalBeats = song.Bars * barBeats
	local events: { Event } = {}
	local function add(beat: number, inst: string, n: number, v: number, dur: number)
		if beat < -1e-6 or beat >= totalBeats - 1e-6 then
			return
		end
		table.insert(events, { T = beat * beatSec, I = inst, N = n, V = math.clamp(v, 0.05, 1), D = math.max(0.05, dur * beatSec) })
	end
	-- accords (en boucle sur tout le morceau)
	local chordList = MusicData.ParseChords(song.Chords, barBeats)
	local cycle = 0
	for _, c in ipairs(chordList) do
		cycle = math.max(cycle, c[1] + c[3])
	end
	local chords: { any } = {}
	if cycle > 0 then
		local offset = 0
		while offset < totalBeats do
			for _, c in ipairs(chordList) do
				if offset + c[1] < totalBeats then
					table.insert(chords, { offset + c[1], c[2], c[3] })
				end
			end
			offset += cycle
		end
	end
	local function inBars(part: any, beat: number): boolean
		local bar = math.floor(beat / barBeats + 1e-6) + 1
		return bar >= (part.FromBar or 1) and bar <= (part.ToBar or song.Bars)
	end
	local melodies: { [number]: { { number } } } = {}
	for index, part in ipairs(song.Parts) do
		local kind = part.Kind
		local vel = part.Vel or 0.85
		if kind == "Lead" then
			local list = MusicData.ParseNotes(part.Notes)
			local len = melodyLength(list)
			local full = {}
			for r = 0, (part.Repeat or 1) - 1 do
				for _, e in ipairs(list) do
					table.insert(full, { e[1] + r * len, e[2], e[3] })
				end
			end
			melodies[index] = full
			for _, e in ipairs(full) do
				if inBars(part, e[1]) then
					-- (petite respiration : accents sur les temps forts)
					local accent = (e[1] % barBeats) < 1e-6 and 1 or 0.88
					add(e[1], part.I, e[2] + 12 * (part.Octave or 0), vel * accent, e[3])
				end
			end
		elseif kind == "Echo" then
			local source = melodies[part.Of]
			for _, e in ipairs(source or {}) do
				local beat = e[1] + (part.Delay or 0)
				if inBars(part, beat) then
					add(beat, part.I, e[2] + 12 * (part.Octave or 0), vel, e[3])
				end
			end
		elseif kind == "Harmony" then
			local style = part.Style
			local octave = 12 * (part.Octave or 0)
			for _, c in ipairs(chords) do
				local start, name, dur = c[1], c[2], c[3]
				if name ~= "r" and inBars(part, start) then
					local notes = MusicData.ChordNotes(name, 62 + octave)
					if style == "block" then
						local step = math.min(2, dur)
						local b = 0
						while b < dur - 1e-6 do
							for _, n in ipairs(notes) do
								add(start + b, part.I, n, vel, math.min(step, dur - b))
							end
							b += step
						end
					elseif style == "pad" then
						for _, n in ipairs(notes) do
							add(start, part.I, n, vel, dur)
						end
					elseif style == "arp" then
						local seq = table.clone(notes)
						table.insert(seq, notes[1] + 12)
						for i = #notes - 1, 2, -1 do
							table.insert(seq, notes[i])
						end
						local b, i = 0, 0
						while b < dur - 1e-6 do
							add(start + b, part.I, seq[i % #seq + 1], vel * (i % 2 == 0 and 1 or 0.8), 0.5)
							b += 0.5
							i += 1
						end
					elseif style == "strum" then
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
					elseif style == "stabs" then
						local b = 0.5
						while b < dur - 1e-6 do
							for _, n in ipairs(notes) do
								add(start + b, part.I, n, vel, 0.25)
							end
							b += 1
						end
					elseif style == "lofi" then
						-- accord égrené (main un peu en retard), rejoué au 3e temps
						for k, n in ipairs(notes) do
							add(start + (k - 1) * 0.06, part.I, n, vel, 2)
							if dur >= 3 then
								add(start + 2.5 + (k - 1) * 0.05, part.I, n, vel * 0.7, 1.4)
							end
						end
					elseif style == "broken" then
						-- main gauche de "Lettre à Élise" : fondamentale grave, quinte, octave
						local root = MusicData.Root(name, 45) or 45
						add(start, part.I, root, vel, 0.25)
						add(start + 0.25, part.I, root + 7, vel * 0.8, 0.25)
						add(start + 0.5, part.I, root + 12, vel * 0.8, 0.25)
					end
				end
			end
		elseif kind == "Bass" then
			for _, c in ipairs(chords) do
				local start, name, dur = c[1], c[2], c[3]
				local root = name ~= "r" and MusicData.Root(name, 36) or nil
				if root and inBars(part, start) then
					local style = part.Style
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
			local steps = math.floor(barBeats * 4 + 0.5)
			for bar = 0, song.Bars - 1 do
				local barStart = bar * barBeats
				local last = bar == song.Bars - 1
				local fill = (bar % 4 == 3) and not last
				for pieceKey, pattern in pairs(groove) do
					local piece: string = pieceKey
					local hatSoft = piece == "HatClosed"
					local isKick = piece == "Kick"
					for s = 1, steps do
						local ch = string.sub(pattern, (s - 1) % #pattern + 1, (s - 1) % #pattern + 1)
						local beat = barStart + (s - 1) * 0.25
						local inFill = fill and s > steps - 4
						if (ch == "x" or ch == "o") and not (inFill and not isKick) and not last then
							local v = (ch == "o" and 1 or 0.8) * vel * (hatSoft and (s % 2 == 1 and 0.75 or 0.5) or 1)
							add(beat, "Drums", MusicData.DRUM[piece], v, 0.2)
						end
					end
				end
				if fill then
					-- roulement de toms sur le dernier temps
					for k, piece in ipairs({ "TomHigh", "TomHigh", "TomMid", "TomFloor" }) do
						add(barStart + barBeats - 1 + (k - 1) * 0.25, "Drums", MusicData.DRUM[piece], vel * (0.7 + 0.08 * k), 0.2)
					end
				end
				if bar % 4 == 0 then
					add(barStart, "Drums", MusicData.DRUM.Crash, vel * 0.8, 1)
				end
				if last then
					add(barStart, "Drums", MusicData.DRUM.Crash, vel, 2)
					add(barStart, "Drums", MusicData.DRUM.Kick, vel, 0.5)
				end
			end
		elseif kind == "DJ" then
			local style: string = tostring(part.Style)
			for bar = 0, song.Bars - 1 do
				local barStart = bar * barBeats
				if style == "scratch" and bar % 4 == 3 then
					add(barStart + barBeats - 1, "DJ", 5, 0.8, 0.5)
					add(barStart + barBeats - 0.5, "DJ", 5, 0.7, 0.5)
				elseif style == "vinyl" and bar % 8 == 7 then
					add(barStart + barBeats - 1, "DJ", 7, 0.5, 1)
				end
			end
		end
	end
	table.sort(events, function(a, b)
		if a.T ~= b.T then
			return a.T < b.T
		end
		return a.I < b.I
	end)
	return { Events = events, Duration = totalBeats * beatSec, BeatSec = beatSec }
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
	local result = MusicData.Compile(song)
	result.Id = song.Id
	result.Name = song.Name
	result.Icon = song.Icon
	result.Author = song.Author
	compiled[id] = result
	return result
end

-- Durée d'un morceau (s), 0 si inconnu
function MusicData.Duration(id: string): number
	local song = MusicData.Song(id)
	return song and song.Duration or 0
end

----------------------------------------------------------------------
-- 5. Boucles du DJ (1 mesure à 120 BPM = 2 s, calées sur l'heure du serveur)
----------------------------------------------------------------------

MusicData.LOOP_BPM = 120
MusicData.LOOP_BAR = 4 * 60 / MusicData.LOOP_BPM

local LOOPS: { { Groove: string, Bass: { number } } } = {
	{ Groove = "rock", Bass = { 45, 0, 45, 0, 0, 0, 48, 0, 45, 0, 45, 0, 43, 0, 43, 0 } },
	{ Groove = "house", Bass = { 0, 0, 45, 0, 0, 0, 45, 0, 0, 0, 48, 0, 0, 0, 47, 0 } },
	{ Groove = "hiphop", Bass = { 45, 0, 0, 0, 0, 0, 0, 45, 45, 0, 43, 0, 0, 0, 0, 0 } },
	{ Groove = "boom", Bass = { 50, 0, 0, 0, 0, 0, 0, 0, 43, 0, 0, 0, 0, 0, 45, 0 } },
}

local loopCache: { [number]: { Event } } = {}

-- Événements d'une boucle (T dans [0, LOOP_BAR[) : batterie + basse
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
				if ch == "x" or ch == "o" then
					table.insert(events, { T = (s - 1) * step, I = "Drums", N = MusicData.DRUM[piece], V = ch == "o" and 0.95 or 0.75, D = 0.2 })
				end
			end
		end
		for s, n in ipairs(def.Bass) do
			if n > 0 then
				table.insert(events, { T = (s - 1) * step, I = "Bass", N = n, V = 0.8, D = step * 2 })
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
