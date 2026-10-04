--[[
	NPCSeats (ModuleScript)
	Emplacement : ReplicatedStorage > Shared > NPCSeats

	v9.9 (NPC99) 🪑 Places des bancs de la ville occupées par des PNJ.
	Le MÊME calcul (entier, déterministe) sert :
	  - au client (TownPeople) pour asseoir les passants sur les places ;
	  - au serveur (NPCSeatGuard) pour qu'un joueur qui s'assoit sur ce banc
	    soit placé sur la place LIBRE, à côté du PNJ (jamais "dedans"), et
	    pour désactiver un banc déjà plein.

	Un banc (TownKit.Bench, 5,6 de long en v11) = 2 places, à x = ±1,4
	(repère du banc : avant = -Z, dossier = +Z). Le pivot d'un PNJ assis est
	au sol, sous le bassin, à z = SLOT_Z (v11 : assise de -1,15 à +0,85, profonde
	de 2,0 ; bassin à -0,2 : les cuisses (1,1) reposent sur les lattes et le
	GENOU dépasse juste du bord avant (-1,3), les tibias pendent sans
	traverser la latte avant ; le buste s'adosse en arrière). La HAUTEUR de
	l'assise n'est jamais supposée : le serveur la mesure sur le Seat
	(NpcBenches).

	API :
	  NPCSeats.BENCH_SLOTS = { -1.4, 1.4 }
	  NPCSeats.SLOT_Z = -0.2
	  NPCSeats.BenchPlan(seed) -> { Occupied = {bool, bool}, Mask = "10",
	      Npcs = { { Slot, Style, Seed, Prop } } }
	  NPCSeats.FreeSlots(seed) -> { number } (indices des places libres)
]]

local NPCSeats = {}

NPCSeats.BENCH_SLOTS = { -1.4, 1.4 } -- (v11 : banc de 5,6 = 2 places de 2,8)
NPCSeats.SLOT_Z = -0.2

local SIT_STYLES = { "elder", "pedestrian", "shopper", "pedestrian", "elder" }
local PROPS = { "none", "phone", "coffee", "none" }

-- (même hachage entier que NPCModels : identique sur tous les processeurs)
local MODP = 2147483647
local function hash(a: number, b: number): number
	local x = (math.floor(a) * 7919 + math.floor(b) * 104729 + 12345) % MODP
	x = (x * 48271) % MODP
	x = (x * 48271) % MODP
	x = (x * 48271) % MODP
	return x / MODP
end
NPCSeats.Hash = hash

export type Plan = {
	Occupied: { boolean },
	Mask: string,
	Npcs: { { Slot: number, Style: string, Seed: number, Prop: string } },
}

function NPCSeats.BenchPlan(seed: number): Plan
	local occupied = { false, false }
	local npcs = {}
	-- un banc sur deux environ a quelqu'un ; parfois deux (un couple qui discute)
	if hash(seed, 21) < 0.5 then
		local first = hash(seed, 22) < 0.5 and 1 or 2
		occupied[first] = true
		table.insert(npcs, {
			Slot = first,
			Style = SIT_STYLES[math.floor(hash(seed, 23) * #SIT_STYLES) + 1],
			Seed = seed * 7 + 3,
			Prop = PROPS[math.floor(hash(seed, 25) * #PROPS) + 1],
		})
		if hash(seed, 24) < 0.22 then
			local other = 3 - first
			occupied[other] = true
			table.insert(npcs, {
				Slot = other,
				Style = SIT_STYLES[math.floor(hash(seed, 26) * #SIT_STYLES) + 1],
				Seed = seed * 7 + 4,
				Prop = "none",
			})
		end
	end
	return {
		Occupied = occupied,
		Mask = (occupied[1] and "1" or "0") .. (occupied[2] and "1" or "0"),
		Npcs = npcs,
	}
end

function NPCSeats.FreeSlots(seed: number): { number }
	local plan = NPCSeats.BenchPlan(seed)
	local free = {}
	for i = 1, #NPCSeats.BENCH_SLOTS do
		if not plan.Occupied[i] then
			table.insert(free, i)
		end
	end
	return free
end

return NPCSeats
