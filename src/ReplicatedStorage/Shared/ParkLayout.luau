--[[
	ParkLayout (ModuleScript)
	Emplacement : ReplicatedStorage > Shared > ParkLayout

	🌳 Dopamine Town (v11, PARK11) : le PLAN des bancs et des places assises
	des scènes de parc, PARTAGÉ (pur, sans instance) entre :
	  - le SERVEUR (TownNature / TownPark) qui pose un Seat invisible sur
	    chaque place LIBRE (invite E "S'asseoir") ;
	  - le CLIENT (ParkScenes) qui construit les bancs visibles aux mêmes
	    endroits et assoit des PNJ sur les places marquées Npc.
	Une place n'est jamais à la fois un siège de joueur et un PNJ.
	Règle SCALE11 : le DESSUS du siège = le dessus des lattes (1,85),
	centré sur la profondeur de l'assise, LookVector = regard.

	API :
	  ParkLayout.Benches(kind, seed) -> { { CF: CFrame, Len: number } }
	      repère du banc AU SOL (local à la scène), -Z = devant
	  ParkLayout.Seats(kind, seed) -> { { CF: CFrame, Npc: boolean,
	      Activity: string?, Bench: number } }   CF = dessus du siège (local)
	  ParkLayout.Tables(kind, seed) -> { CFrame }  (tables de pique-nique)
	  ParkLayout.SEAT, ParkLayout.TABLE, ParkLayout.BENCH_LEN
]]

local ParkLayout = {}

ParkLayout.SEAT = 1.85 -- dessus de l'assise (SCALE11)
ParkLayout.TABLE = 3.1
ParkLayout.BENCH_LEN = 5.6 -- 2 places de 2,6 (+ accoudoirs)
ParkLayout.PLACES = { -1.4, 1.4 } -- places sur un banc (x local ; NPCSeats : ±1,4)
ParkLayout.CUSHION_Z = -0.15 -- centre de la profondeur des lattes (devant -1,15, derrière 0,85)

local TAU = math.pi * 2

local function hash(a: number, b: number?): number
	local x = math.sin(a * 12.9898 + (b or 0) * 78.233) * 43758.5453
	return x - math.floor(x)
end
ParkLayout.Hash = hash

local ACTIVITIES = { "read", "phone", "feed", "chat", "doze", "eat", "read", "phone" }

-- Banc tourné vers le point (cx, cz) depuis (x, z) (-Z du banc vers le point)
local function facing(x: number, z: number, cx: number, cz: number): CFrame
	local p = Vector3.new(x, 0, z)
	local c = Vector3.new(cx, 0, cz)
	if (c - p).Magnitude < 1e-3 then
		return CFrame.new(p)
	end
	return CFrame.lookAt(p, c)
end

function ParkLayout.Benches(kind: string, seed: number): { { CF: CFrame, Len: number } }
	local list = {}
	local L = ParkLayout.BENCH_LEN
	if kind == "RoseGarden" then
		for k = 0, 3 do
			local a = (k + 0.5) / 4 * TAU
			table.insert(list, { CF = facing(math.cos(a) * 12.2, math.sin(a) * 12.2, 0, 0), Len = L })
		end
	elseif kind == "FountainSquare" then
		for k = 0, 7 do
			local a = (k + 0.5) / 8 * TAU
			table.insert(list, { CF = facing(math.cos(a) * 17, math.sin(a) * 17, 0, 0), Len = L })
		end
	elseif kind == "Bandstand" then
		for k = -1, 1, 2 do
			table.insert(list, { CF = CFrame.new(k * 4.2, 0, -8.5 - 8) * CFrame.Angles(0, math.pi, 0), Len = L })
		end
	elseif kind == "DogPark" then
		table.insert(list, { CF = CFrame.new(-10, 0, 12.2), Len = L })
	elseif kind == "BenchRow" then
		for k = -1, 1, 2 do
			table.insert(list, { CF = CFrame.new(k * 4, 0, 0), Len = L })
		end
	elseif kind == "PocketBench" then
		-- (squares de quartier : 3 bancs autour du massif, voir DistrictParks)
		for k = 0, 2 do
			local b = k * math.pi / 2
			table.insert(list, { CF = facing(math.cos(b) * 15, math.sin(b) * 15, 0, 0), Len = L })
		end
	end
	return list
end

-- Places assises : un PNJ sur ~40 % des places (jamais deux PNJ sur le même
-- banc quand il n'y a qu'un banc), les autres sont des sièges de joueurs
function ParkLayout.Seats(kind: string, seed: number): { { CF: CFrame, Npc: boolean, Activity: string?, Bench: number } }
	local out = {}
	local benches = ParkLayout.Benches(kind, seed)
	for bi, b in ipairs(benches) do
		local npcPlace = 0
		local r = hash(seed * 7 + bi, kind == "BenchRow" and 3 or 5)
		if r < 0.55 then
			npcPlace = r < 0.27 and 1 or 2
		end
		for pi, x in ipairs(ParkLayout.PLACES) do
			local cf = b.CF * CFrame.new(x, ParkLayout.SEAT, ParkLayout.CUSHION_Z)
			local npc = pi == npcPlace
			local act = nil
			if npc then
				act = ACTIVITIES[1 + math.floor(hash(seed * 11 + bi, pi) * #ACTIVITIES) % #ACTIVITIES]
			end
			table.insert(out, { CF = cf, Npc = npc, Activity = act, Bench = bi })
		end
	end
	-- tables de pique-nique : 2 places par côté
	for ti, T in ipairs(ParkLayout.Tables(kind, seed)) do
		for _, sz in ipairs({ -1, 1 }) do
			for _, x in ipairs({ -1.6, 1.6 }) do
				local cf = T * CFrame.new(x, ParkLayout.SEAT, sz * 2.4) * CFrame.Angles(0, sz > 0 and 0 or math.pi, 0)
				local npc = hash(seed * 5 + ti, x * 3 + sz) < 0.3
				table.insert(out, { CF = cf, Npc = npc, Activity = npc and (hash(seed, ti + x) < 0.6 and "eat" or "chat") or nil, Bench = 100 + ti })
			end
		end
	end
	return out
end

function ParkLayout.Tables(kind: string, seed: number): { CFrame }
	local list = {}
	if kind == "PicnicTables" then
		for k = 0, 2 do
			table.insert(list, CFrame.new(-9 + k * 9, 0, (k % 2) * 3 - 1.5) * CFrame.Angles(0, (hash(seed, k) - 0.5) * 0.5, 0))
		end
	end
	return list
end

return ParkLayout
