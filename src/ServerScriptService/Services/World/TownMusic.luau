--[[
	TownMusic (ModuleScript)
	Emplacement : ServerScriptService > Services > World > TownMusic

	🎵 SCÈNE MUSICALE de la place de Dopamine Town (v9.9, MUSIC99), côté
	SERVEUR. Ici, SEULEMENT ce qui doit être partagé :
	  - le plancher de la scène, ses 2 marches, les praticables (batterie,
	    DJ) et les volumes solides (tours du portique, enceintes, pupitre) ;
	  - une invite "Jouer" (touche E) par instrument : 🎹 piano à queue,
	    🥁 batterie, 🎸 guitare électrique, 🎸 basse, 🎶 xylophone,
	    🎛️ synthé, 🎧 platines DJ ; et au pied de la scène, le pupitre
	    "musique" : E = choisir un morceau, F = radio lofi sur la scène ;
	  - QUI joue de quoi (attribut "Player" = UserId sur la borne de
	    l'instrument : chaque client anime l'avatar du musicien) ;
	  - le MORCEAU en cours (attributs du dossier : SongId, SongStart = heure
	    du serveur, SongMode "one" | "all") et la RADIO (Radio = numéro de la
	    piste de Config.Music.Playlist, RadioStart) : tous les clients jouent
	    la même chose au même moment, sans autre message ;
	  - le RELAIS des notes : un joueur joue -> ses notes (paquets de 24 au
	    plus) -> le serveur vérifie (c'est bien son instrument, il est à son
	    poste, pas de spam : seau de jetons) -> les joueurs à moins de
	    MusicData.HEAR_RADIUS studs les entendent et le voient jouer.
	Tout le DÉCOR (portique, projecteurs, écran LED, enceintes, instruments
	détaillés, câbles…) est construit par chaque client (Client/World/
	MusicStage), en flux. Budget : ~22 pièces serveur, 2 vraies lumières
	douces (projecteurs de face, la nuit seulement).

	Remote "MusicEvent" (RemoteEvent) :
	  C -> S ("leave")                          : quitter son instrument
	         ("notes", instIndex, { n, v, dt… }) : notes jouées (triplets)
	         ("song", songId | "", "one" | "all") : lancer / arrêter un morceau
	         ("radio", piste 0..N)               : radio lofi (0 = coupée)
	         ("loop", 0..8)                      : boucle du DJ (0 = coupée)
	         ("queue", "add", songId)            : (v11) file d'attente (+1)
	         ("queue", "remove", index)          : (v11) retirer de la file
	         ("skip")                            : (v11) morceau suivant
	         ("chain", on)                       : (v11) enchaîner (mode "all")
	  S -> C ("open", instId)  : tu joues de cet instrument (au joueur)
	         ("close", instId) : ton instrument est libéré
	         ("busy", instId)  : quelqu'un en joue déjà
	         ("picker")        : ouvre le choix des morceaux
	         ("notes", userId, instIndex, { n, v, dt… }) : notes d'un voisin

	API (TownPlaza, via un pcall) :
	  TownMusic.Build(parent, cf) -> Folder "MusicStage"
	    cf : centre de l'empreinte 24 x 16 au niveau du pavé, LookVector = le
	    devant de la scène (vers le public) ; attribut "StageCF" = cf.
	  TownMusic.Debug() -> état (tests)
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local MusicData = require(ReplicatedStorage.Shared.MusicData)
local Config = require(ReplicatedStorage.Shared.Config)
local TownKit = require(script.Parent.TownKit)

local TownMusic = {}

TownMusic.FOLDER_NAME = "MusicStage"

local M = TownKit.M
local part = TownKit.Part

local WATCH_EVERY = 0.5 -- (s) vérification des musiciens / fin du morceau
local STAGE_RANGE = 70 -- (studs) pour lancer un morceau / la radio
local SONG_LEAD = 0.8 -- (s) le morceau démarre un peu après la demande (tous en même temps)
local SONG_COOLDOWN = 1.2 -- (s) entre deux demandes d'un même joueur
local QUEUE_MAX = 12 -- (v11) morceaux dans la file d'attente (attribut "Queue")
local QUEUE_COOLDOWN = 0.35
-- seaux de jetons (anti-spam) : messages et notes par seconde
local MSG_RATE, MSG_BURST = 18, 24
local NOTE_RATE, NOTE_BURST = 40, 64

type Anchor = { Id: string, Part: BasePart, Prompt: ProximityPrompt }

local state = {
	Folder = nil :: Folder?,
	StageCF = CFrame.identity,
	Anchors = {} :: { [string]: Anchor },
	Occupant = {} :: { [Player]: string },
	Buckets = {} :: { [Player]: any },
	Connections = {} :: { RBXScriptConnection },
	Generation = 0,
	Relayed = 0,
	Dropped = 0,
	Accepted = 0,
}
local remoteConnected = false
local watching = false

local function now(): number
	return workspace:GetServerTimeNow()
end

local function remote(): RemoteEvent?
	local folder = ReplicatedStorage:FindFirstChild("Remotes")
	local r = folder and folder:FindFirstChild("MusicEvent")
	return (r and r:IsA("RemoteEvent")) and r or nil
end

local function send(player: Player, ...: any)
	local r = remote()
	if r and player.Parent then
		r:FireClient(player, ...)
	end
end

local function rootOf(player: Player): BasePart?
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	return (root and root:IsA("BasePart")) and root or nil
end

local function alive(player: Player): boolean
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	return humanoid ~= nil and humanoid.Health > 0
end

local function nearStage(player: Player, range: number): boolean
	local root = rootOf(player)
	return root ~= nil and (root.Position - state.StageCF.Position).Magnitude <= range
end

----------------------------------------------------------------------
-- Occupation des instruments
----------------------------------------------------------------------

local function release(player: Player, notify: boolean)
	local id = state.Occupant[player]
	if not id then
		return
	end
	state.Occupant[player] = nil
	local anchor = state.Anchors[id]
	if anchor and anchor.Part.Parent then
		if anchor.Part:GetAttribute("Player") == player.UserId then
			anchor.Part:SetAttribute("Player", 0)
			anchor.Part:SetAttribute("Loop", 0)
		end
		anchor.Prompt.Enabled = true
	end
	if notify then
		send(player, "close", id)
	end
end

local function claim(player: Player, id: string)
	local anchor = state.Anchors[id]
	if not anchor or not anchor.Part.Parent or not alive(player) then
		return
	end
	local root = rootOf(player)
	if not root or (root.Position - anchor.Part.Position).Magnitude > MusicData.PLAY_RANGE + 4 then
		return
	end
	local current = anchor.Part:GetAttribute("Player")
	if type(current) == "number" and current ~= 0 and current ~= player.UserId then
		send(player, "busy", id)
		return
	end
	if state.Occupant[player] and state.Occupant[player] ~= id then
		release(player, false)
	end
	state.Occupant[player] = id
	anchor.Part:SetAttribute("Player", player.UserId)
	anchor.Part:SetAttribute("Since", now())
	anchor.Prompt.Enabled = false
	send(player, "open", id)
end

----------------------------------------------------------------------
-- Anti-spam (seau de jetons)
----------------------------------------------------------------------

local function bucket(player: Player): any
	local b = state.Buckets[player]
	local t = now()
	if not b then
		b = { Msg = MSG_BURST, Notes = NOTE_BURST, At = t, SongAt = -math.huge }
		state.Buckets[player] = b
	end
	local dt = math.max(0, t - b.At)
	b.At = t
	b.Msg = math.min(MSG_BURST, b.Msg + dt * MSG_RATE)
	b.Notes = math.min(NOTE_BURST, b.Notes + dt * NOTE_RATE)
	return b
end

-- Notes reçues -> triplets propres (entiers, bornés) ; {} si rien de valable
local function cleanNotes(id: string, raw: any, allowance: number): { number }
	local out = {}
	if type(raw) ~= "table" then
		return out
	end
	local kind = MusicData.STATIONS[id].Kind
	local lo, hi = MusicData.NOTE_MIN, MusicData.NOTE_MAX
	if kind == "drums" then
		lo, hi = 1, #MusicData.DRUMS
	elseif kind == "dj" then
		lo, hi = MusicData.DJ_LOOPS + 1, #MusicData.DJ_PADS
	end
	local count = math.min(MusicData.MAX_BATCH, math.floor(#raw / 3), math.floor(allowance))
	for i = 1, count do
		local n, v, dt = raw[i * 3 - 2], raw[i * 3 - 1], raw[i * 3]
		if type(n) == "number" and type(v) == "number" and type(dt) == "number" and n == n and v == v and dt == dt then
			n = math.floor(n + 0.5)
			if n >= lo and n <= hi then
				table.insert(out, n)
				table.insert(out, math.clamp(math.floor(v + 0.5), 1, 100))
				table.insert(out, math.clamp(math.floor(dt + 0.5), 0, 400))
			end
		end
	end
	return out
end

local function relay(player: Player, instIndex: number, notes: { number })
	local r = remote()
	if not r or #notes == 0 then
		return
	end
	local center = state.StageCF.Position
	for _, other in ipairs(Players:GetPlayers()) do
		if other ~= player then
			local root = rootOf(other)
			if root and (root.Position - center).Magnitude <= MusicData.HEAR_RADIUS then
				r:FireClient(other, "notes", player.UserId, instIndex, notes)
				state.Relayed += 1
			end
		end
	end
end

----------------------------------------------------------------------
-- Morceaux et radio (attributs du dossier)
----------------------------------------------------------------------

local function setSong(id: string, mode: string)
	local folder = state.Folder
	if not folder then
		return
	end
	if id == "" or MusicData.SONG_INDEX[id] == nil then
		folder:SetAttribute("SongId", "")
		folder:SetAttribute("SongMode", "")
		return
	end
	folder:SetAttribute("Radio", 0)
	folder:SetAttribute("SongStart", now() + SONG_LEAD)
	folder:SetAttribute("SongMode", mode == "all" and "all" or "one")
	folder:SetAttribute("SongId", id)
end

-- (v11) file d'attente : attribut "Queue" = "id1,id2,…" (lu par tous les clients)
local function getQueue(): { string }
	local folder = state.Folder
	local list = {}
	local raw = folder and folder:GetAttribute("Queue")
	if type(raw) == "string" then
		for id in string.gmatch(raw, "[^,]+") do
			if MusicData.SONG_INDEX[id] then
				table.insert(list, id)
			end
		end
	end
	return list
end

local function setQueue(list: { string })
	local folder = state.Folder
	if folder then
		folder:SetAttribute("Queue", table.concat(list, ","))
	end
end

-- Morceau suivant : la file d'attente d'abord, puis (mode "all") le
-- catalogue dans l'ordre ; sinon, silence
local function advance()
	local folder = state.Folder
	if not folder then
		return
	end
	local queue = getQueue()
	local mode = folder:GetAttribute("SongMode")
	if #queue > 0 then
		local nextId = table.remove(queue, 1)
		setQueue(queue)
		setSong(nextId, mode == "all" and "all" or "one")
	elseif mode == "all" then
		local id = folder:GetAttribute("SongId")
		local index = type(id) == "string" and MusicData.SONG_INDEX[id] or 0
		local nextSong = MusicData.SONGS[index % #MusicData.SONGS + 1]
		setSong(nextSong.Id, "all")
	else
		folder:SetAttribute("SongId", "")
		folder:SetAttribute("SongMode", "")
	end
end

local function playlistCount(): number
	local list = Config.Music and Config.Music.Playlist
	return type(list) == "table" and #list or 0
end

local function setRadio(index: number)
	local folder = state.Folder
	if not folder then
		return
	end
	if index < 1 or index > playlistCount() then
		folder:SetAttribute("Radio", 0)
		return
	end
	local track = Config.Music.Playlist[index]
	if type(track) ~= "table" or type(track.Id) ~= "string" or track.Id == "" then
		return
	end
	folder:SetAttribute("SongId", "")
	folder:SetAttribute("SongMode", "")
	folder:SetAttribute("RadioStart", now())
	folder:SetAttribute("Radio", index)
end

local function onEvent(player: Player, kind: any, a: any, b: any)
	if not state.Folder or type(kind) ~= "string" then
		return
	end
	local bk = bucket(player)
	if bk.Msg < 1 then
		state.Dropped += 1
		return
	end
	bk.Msg -= 1
	if kind == "leave" then
		release(player, true)
	elseif kind == "notes" then
		local id = state.Occupant[player]
		if not id or type(a) ~= "number" or MusicData.ORDER[a] ~= id then
			return
		end
		local anchor = state.Anchors[id]
		local root = rootOf(player)
		if not anchor or not root or (root.Position - anchor.Part.Position).Magnitude > MusicData.PLAY_RANGE + 6 then
			return
		end
		local notes = cleanNotes(id, b, bk.Notes)
		bk.Notes -= #notes / 3
		state.Accepted += #notes / 3
		if #notes > 0 then
			relay(player, a, notes)
		end
	elseif kind == "song" then
		if type(a) ~= "string" or not nearStage(player, STAGE_RANGE) then
			return
		end
		local t = now()
		-- (arrêter est toujours permis ; lancer : une demande par SONG_COOLDOWN)
		if a ~= "" and t - bk.SongAt < SONG_COOLDOWN then
			return
		end
		bk.SongAt = t
		setSong(a, type(b) == "string" and b or "one")
	elseif kind == "radio" then
		if type(a) ~= "number" or a ~= a or not nearStage(player, STAGE_RANGE) then
			return
		end
		local t = now()
		if a ~= 0 and t - bk.SongAt < SONG_COOLDOWN then
			return
		end
		bk.SongAt = t
		setRadio(math.floor(a))
	elseif kind == "queue" then
		if not nearStage(player, STAGE_RANGE) then
			return
		end
		local t = now()
		if t - (bk.QueueAt or -math.huge) < QUEUE_COOLDOWN then
			return
		end
		bk.QueueAt = t
		local queue = getQueue()
		if a == "add" and type(b) == "string" and MusicData.SONG_INDEX[b] then
			local current = state.Folder:GetAttribute("SongId")
			if type(current) ~= "string" or current == "" then
				-- (rien ne joue : il démarre tout de suite)
				setSong(b, "one")
			elseif #queue < QUEUE_MAX then
				table.insert(queue, b)
				setQueue(queue)
			end
		elseif a == "remove" and type(b) == "number" and b == b then
			local index = math.floor(b)
			if index >= 1 and index <= #queue then
				table.remove(queue, index)
				setQueue(queue)
			end
		end
	elseif kind == "skip" then
		if not nearStage(player, STAGE_RANGE) then
			return
		end
		local t = now()
		if t - bk.SongAt < SONG_COOLDOWN then
			return
		end
		bk.SongAt = t
		local current = state.Folder:GetAttribute("SongId")
		if type(current) == "string" and current ~= "" then
			advance()
		end
	elseif kind == "chain" then
		if not nearStage(player, STAGE_RANGE) then
			return
		end
		local current = state.Folder:GetAttribute("SongId")
		if type(current) == "string" and current ~= "" then
			state.Folder:SetAttribute("SongMode", a == true and "all" or "one")
		end
	elseif kind == "loop" then
		if state.Occupant[player] ~= "DJ" or type(a) ~= "number" or a ~= a then
			return
		end
		local anchor = state.Anchors.DJ
		local index = math.floor(a)
		if anchor and index >= 0 and index <= MusicData.DJ_LOOPS then
			-- (calée sur une grille de mesures : tous les clients entendent la même boucle)
			local bar = MusicData.LOOP_BAR
			anchor.Part:SetAttribute("LoopStart", math.ceil((now() + 0.25) / bar) * bar)
			anchor.Part:SetAttribute("Loop", index)
		end
	end
end

----------------------------------------------------------------------
-- Surveillance : musiciens partis / trop loin, fin des morceaux
----------------------------------------------------------------------

local function watchStep()
	for player, id in pairs(state.Occupant) do
		local anchor = state.Anchors[id]
		local root = rootOf(player)
		local spot = MusicData.SpotCFrame(state.StageCF, id)
		local flat = root and Vector3.new(root.Position.X - spot.Position.X, 0, root.Position.Z - spot.Position.Z).Magnitude or math.huge
		if not player.Parent or not anchor or not alive(player) or flat > MusicData.LEAVE_RANGE then
			release(player, player.Parent ~= nil)
		end
	end
	local folder = state.Folder
	if folder and folder.Parent then
		local id = folder:GetAttribute("SongId")
		local start = folder:GetAttribute("SongStart")
		if type(id) == "string" and id ~= "" and type(start) == "number" then
			local duration = MusicData.Duration(id)
			if now() > start + duration + 0.6 then
				advance()
			end
		end
	end
end

local function startWatch()
	if watching then
		return
	end
	watching = true
	task.spawn(function()
		while watching do
			task.wait(WATCH_EVERY)
			local ok, err = pcall(watchStep)
			if not ok then
				warn("[TownMusic] surveillance : " .. tostring(err))
			end
		end
	end)
	Players.PlayerRemoving:Connect(function(player)
		release(player, false)
		state.Buckets[player] = nil
	end)
end

local function connectRemote()
	if remoteConnected then
		return
	end
	local r = remote()
	if not r then
		warn("[TownMusic] remote MusicEvent absent (Net.luau)")
		return
	end
	remoteConnected = true
	r.OnServerEvent:Connect(function(player: Player, kind: any, a: any, b: any)
		local ok, err = pcall(onEvent, player, kind, a, b)
		if not ok then
			warn("[TownMusic] " .. tostring(err))
		end
	end)
end

----------------------------------------------------------------------
-- Construction
----------------------------------------------------------------------

local function prompt(host: BasePart, name: string, action: string, object: string, key: Enum.KeyCode, distance: number): ProximityPrompt
	local p = Instance.new("ProximityPrompt")
	p.Name = name
	p.ActionText = action
	p.ObjectText = object
	p.KeyboardKeyCode = key
	p.HoldDuration = 0
	p.MaxActivationDistance = distance
	p.RequiresLineOfSight = false
	p.Style = Enum.ProximityPromptStyle.Default
	-- (textes anglais ; MusicStage les traduit : attributs LocAction / LocObject)
	p:SetAttribute("LocAction", action)
	p:SetAttribute("LocObject", object)
	p.Parent = host
	return p
end

local function ghost(parent: Instance, name: string, size: Vector3, cf: CFrame): BasePart
	-- (volume solide invisible : le décor visible est construit par le client)
	return part(parent, name, size, cf, Color3.fromRGB(40, 40, 44), M.SmoothPlastic, "ghost")
end

function TownMusic.Build(parent: Instance, cf: CFrame): Folder
	local old = parent:FindFirstChild(TownMusic.FOLDER_NAME)
	if old then
		old:Destroy()
	end
	for _, c in ipairs(state.Connections) do
		c:Disconnect()
	end
	table.clear(state.Connections)
	for player in pairs(state.Occupant) do
		release(player, true)
	end
	state.Generation += 1
	state.StageCF = cf
	table.clear(state.Anchors)
	local partsBefore = TownKit.Stats.Parts

	local folder = Instance.new("Folder")
	folder.Name = TownMusic.FOLDER_NAME
	folder:SetAttribute("StageCF", cf)
	folder:SetAttribute("SongId", "")
	folder:SetAttribute("SongStart", 0)
	folder:SetAttribute("SongMode", "")
	folder:SetAttribute("Radio", 0)
	folder:SetAttribute("RadioStart", 0)
	folder:SetAttribute("Queue", "")

	local D = MusicData.DECK
	local top = MusicData.DECK_TOP
	local low = -0.3 -- (plancher enfoncé sous le pavé : aucune face commune avec lui)
	local deckColor = Color3.fromRGB(62, 52, 50)
	-- plancher (bois sombre, comme une vraie scène)
	part(folder, "Deck", Vector3.new(D.X1 - D.X0, top - low, D.Z1 - D.Z0), cf * CFrame.new((D.X0 + D.X1) / 2, (top + low) / 2, (D.Z0 + D.Z1) / 2), deckColor, M.WoodPlanks, "solid")
	-- 2 marches devant (0,5 chacune)
	local S = MusicData.STEPS
	for i = 1, S.Count do
		local stepTop = i * S.Rise
		local z1 = D.Z0 - (S.Count - i) * S.Depth
		local z0 = z1 - S.Depth
		part(folder, "Step", Vector3.new(S.X * 2, stepTop - low, z1 - z0), cf * CFrame.new(0, (stepTop + low) / 2, (z0 + z1) / 2), Color3.fromRGB(70, 60, 58), M.WoodPlanks, "solid")
	end
	-- praticables (batterie, DJ) : posés 0,05 DANS le plancher
	for name, r in pairs(MusicData.RISERS) do
		local h = r.H + 0.05
		part(folder, name .. "Riser", Vector3.new(r.X1 - r.X0, h, r.Z1 - r.Z0), cf * CFrame.new((r.X0 + r.X1) / 2, top - 0.05 + h / 2, (r.Z0 + r.Z1) / 2), Color3.fromRGB(46, 44, 50), M.Carpet, "solid")
	end
	-- volumes solides (invisibles) : tours du portique, enceintes, pupitre
	local ts = MusicData.TOWER_SIZE
	for i, p in ipairs(MusicData.TRUSS_TOWERS) do
		ghost(folder, "TowerBlock" .. i, Vector3.new(ts, MusicData.TRUSS_H, ts), cf * CFrame.new(p.X, MusicData.TRUSS_H / 2, p.Z))
	end
	for i, p in ipairs(MusicData.PA) do
		ghost(folder, "SpeakerBlock" .. i, Vector3.new(2.2, 4.6, 2.0), cf * CFrame.new(p.X, 2.3, p.Z))
	end
	local jukeCF = cf * MusicData.JUKEBOX
	ghost(folder, "JukeboxBlock", Vector3.new(2.6, 3.3, 1.3), jukeCF * CFrame.new(0, 1.65, 0))

	-- bornes des instruments (invites "Jouer")
	for _, id in ipairs(MusicData.ORDER) do
		local st = MusicData.STATIONS[id]
		local host = part(folder, "Play_" .. id, Vector3.new(0.4, 0.4, 0.4), cf * CFrame.new(st.Prompt), Color3.new(1, 1, 1), M.SmoothPlastic, "deco")
		host.Transparency = 1
		host:SetAttribute("Instrument", id)
		host:SetAttribute("Player", 0)
		host:SetAttribute("Loop", 0)
		host:SetAttribute("LoopStart", 0)
		local p = prompt(host, "MusicPrompt", "Play", st.Name, Enum.KeyCode.E, 6.5)
		p:SetAttribute("Instrument", id)
		state.Anchors[id] = { Id = id, Part = host, Prompt = p }
		table.insert(state.Connections, p.Triggered:Connect(function(player: Player)
			local ok, err = pcall(claim, player, id)
			if not ok then
				warn("[TownMusic] jouer : " .. tostring(err))
			end
		end))
	end
	-- pupitre "musique" au pied de la scène : E = morceaux, F = radio lofi
	local juke = part(folder, "Jukebox", Vector3.new(0.4, 0.4, 0.4), jukeCF * CFrame.new(0, 3.6, -0.4), Color3.new(1, 1, 1), M.SmoothPlastic, "deco")
	juke.Transparency = 1
	local songPrompt = prompt(juke, "SongPrompt", "Play a song", "Stage music", Enum.KeyCode.E, 10)
	local radioPrompt = prompt(juke, "RadioPrompt", "Lo-fi radio", "Stage music", Enum.KeyCode.F, 10)
	table.insert(state.Connections, songPrompt.Triggered:Connect(function(player: Player)
		if nearStage(player, STAGE_RANGE) then
			send(player, "picker")
		end
	end))
	table.insert(state.Connections, radioPrompt.Triggered:Connect(function(player: Player)
		if not nearStage(player, STAGE_RANGE) then
			return
		end
		local bk = bucket(player)
		local t = now()
		if t - bk.SongAt < SONG_COOLDOWN then
			return
		end
		bk.SongAt = t
		local current = folder:GetAttribute("Radio")
		if type(current) == "number" and current > 0 then
			setRadio(0)
		else
			setRadio(math.random(1, math.max(1, playlistCount())))
		end
	end))
	-- 2 projecteurs de face, doux (la nuit seulement : TownAtmosphere)
	for _, x in ipairs({ -6, 6 }) do
		local host = part(folder, "StageLight", Vector3.new(0.4, 0.4, 0.4), cf * CFrame.new(x, MusicData.TRUSS_H - 0.6, MusicData.TRUSS_TOWERS[1].Z + 0.8) * CFrame.Angles(math.rad(-32), 0, 0), Color3.new(1, 1, 1), M.SmoothPlastic, "deco")
		host.Transparency = 1
		TownKit.Light(host, Color3.fromRGB(255, 226, 190), 26, 0.8, "Spot")
	end

	folder:SetAttribute("Parts", TownKit.Stats.Parts - partsBefore)
	folder.Parent = parent
	state.Folder = folder
	connectRemote()
	startWatch()
	return folder
end

function TownMusic.Debug(): any
	local occupants = {}
	for player, id in pairs(state.Occupant) do
		occupants[player.Name] = id
	end
	return {
		Folder = state.Folder,
		Anchors = state.Anchors,
		Occupants = occupants,
		Relayed = state.Relayed,
		Dropped = state.Dropped,
		Accepted = state.Accepted,
		Claim = claim,
		Release = release,
		OnEvent = onEvent,
		Watch = watchStep,
	}
end

return TownMusic
