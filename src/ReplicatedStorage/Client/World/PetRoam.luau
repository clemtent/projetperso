--[[
	PetRoam (ModuleScript)
	Emplacement : ReplicatedStorage > Client > World > PetRoam

	🐾 Dopamine Town (v9.8, GARDEN98) : les animaux achetés (Config.House,
	catégorie Pets, espèces de House3DCritters.ROAMERS) SE PROMÈNENT dans la
	maison et dans le jardin, comme de vrais animaux :
	  - chien, chat, chaton, renard, dragon : marche / trot (pattes en
	    diagonale), la queue remue (chien) ou se balance levée (chat), la tête
	    regarde autour, s'assoit, se couche, fait la sieste (yeux fermés),
	    renifle le sol ; le lapin avance par petits bonds ; le hérisson
	    trottine ; la tortue rampe ; poussin et caneton se dandinent ; le
	    manchot se balance d'un pied sur l'autre ; la chouette tourne la tête
	    et vole d'un point à l'autre ;
	  - chemins DANS la pièce (grille + A*, lissés) en évitant les meubles
	    posés ; parfois (animaux du rez-de-chaussée) une SORTIE au jardin :
	    pièces voisines par les passages, cage d'escalier, porte de derrière
	    (WorldLayout.BackDoorX, HOUSE98) ou porte d'entrée, marches, pelouse,
	    quelques pas en évitant les objets du jardin (GardenSnapshot), puis
	    retour à sa place ;
	  - DÉTERMINISTE : tout dépend de l'heure du serveur
	    (workspace:GetServerTimeNow) et d'une graine (propriétaire, pièce,
	    objet) -> chaque client voit le même animal au même endroit ; cycles
	    de 50 s qui partent de sa place et y reviennent ;
	  - CÔTÉ CLIENT seulement, plafonné : au plus 12 animaux animés (les plus
	    proches de la caméra, à moins de 70 studs), 30 Hz, BulkMoveTo ; au loin
	    rien n'est construit ;
	  - l'animal posé dans la pièce (modèle de la pièce, attribut Pet) est
	    CACHÉ tant que son double se promène ; il revient en pause
	    (SetPaused : mode édition des meubles), à l'arrêt (Stop) ou quand le
	    double est retiré ; un double n'est visible que dehors, dans la cage
	    d'escalier ou dans une pièce CONSTRUITE (pièces en flux).
	Modèles : House3DRecipes.BuildItem (les mêmes que dans la pièce : taille,
	couleur, miroir) ; articulations "Joint_<nom>" / pièces "J_<nom>_..."
	(House3DCritters, animaux réalistes articulés). AUCUN son.

	API (branchée par TownClient) :
	  PetRoam.Start(ctx)  ctx = { GetHouses = () -> { [userId] = house } }
	  PetRoam.Step(dt)    (chaque image : l'animation se limite à 30 Hz)
	  PetRoam.Stop()
	  PetRoam.SetPaused(paused)
	  PetRoam.Debug() -> état (tests)
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local WorldLayout = require(ReplicatedStorage.Shared.WorldLayout)
local GardenSnapshot = require(ReplicatedStorage.Shared.GardenSnapshot)

local HouseFolder = script.Parent.Parent.Components.House

local PetRoam = {}

local MAX_ANIMATED = 12
local RANGE = 70 -- (studs) animaux animés autour de la caméra
local FAR = 95 -- au-delà : modèle retiré
local HZ = 1 / 30
local CYCLE = 50 -- (s) un cycle part de la place de l'animal et y revient
local CELL = 0.75 -- (studs) grille des pièces
local WALL_MARGIN = 0.7
local LAWN = 0.45

-- Allures et habitudes (vitesse en studs / s ; Outdoor / Nap = chances par cycle)
local SPECIES: { [string]: any } = {
	Puppy = { Gait = "Quad", Speed = 4.6, Stride = 1.4, Outdoor = 0.45, Nap = 0.12, Wag = 9, Idle = { "Sit", "Sniff", "Look", "Sit" } },
	Kitten = { Gait = "Quad", Speed = 3.6, Stride = 1.0, Outdoor = 0.3, Nap = 0.3, Cat = true, Idle = { "Sit", "Groom", "Look", "Sit" } },
	SleepyCat = { Gait = "Quad", Speed = 3, Stride = 1.1, Outdoor = 0.2, Nap = 0.55, Cat = true, Idle = { "Sit", "Groom", "Sleep" } },
	Fox = { Gait = "Quad", Speed = 4.8, Stride = 1.5, Outdoor = 0.5, Nap = 0.15, Wag = 2.4, Idle = { "Sit", "Sniff", "Look" } },
	Dragon = { Gait = "Quad", Speed = 4, Stride = 1.5, Outdoor = 0.45, Nap = 0.15, Wag = 1.4, Wings = true, Idle = { "Sit", "Look", "Flap" } },
	Bunny = { Gait = "Hop", Speed = 3.2, Stride = 1.2, Outdoor = 0.45, Nap = 0.15, Idle = { "Sniff", "Sit", "Look" } },
	Hedgehog = { Gait = "Scurry", Speed = 2, Stride = 0.45, Outdoor = 0.4, Nap = 0.25, Idle = { "Sniff", "Look" } },
	Turtle = { Gait = "Crawl", Speed = 0.7, Stride = 0.55, Outdoor = 0.3, Nap = 0.3, Idle = { "Look", "Sleep" } },
	Chick = { Gait = "Bird", Speed = 2, Stride = 0.42, Outdoor = 0.45, Nap = 0.15, Idle = { "Peck", "Look", "Flap" } },
	Duckling = { Gait = "Bird", Speed = 2.2, Stride = 0.48, Outdoor = 0.55, Nap = 0.15, Idle = { "Peck", "Look", "Flap" } },
	Penguin = { Gait = "Waddle", Speed = 1.8, Stride = 0.55, Outdoor = 0.35, Nap = 0.15, Idle = { "Look", "Flap" } },
	Owl = { Gait = "Owl", Speed = 6, Stride = 1, Outdoor = 0.3, Nap = 0.45, Idle = { "Look", "Look", "Flap" } },
}
PetRoam.SPECIES = SPECIES

----------------------------------------------------------------------
-- État
----------------------------------------------------------------------

type Pet = {
	Key: string,
	House: any,
	UserId: number,
	ItemId: string,
	Entry: any,
	EntryIndex: number,
	Slot: number,
	Info: any,
	Seed: number,
	Home: Vector3, -- (x, y du sol, d) repère de la maison
	HomeYaw: number,
	Nav: any?,
	Model: Model?,
	Rig: any?,
	Plan: any?,
	PlanCycle: number,
	Visible: boolean,
	Pos: Vector3?, -- dernière position (monde)
	Hidden: { [BasePart]: number }, -- original caché (transparences d'origine)
	Original: Model?,
	Routes: any?, -- sorties vers le jardin { Front, Back }
	Perch: boolean?, -- posé SUR un meuble (canapé, lit...) : il reste là (poses seulement)
	PerchCF: CFrame?, -- pivot du modèle de la pièce
}

local ctx: any = {}
local started = false
local paused = false
local folder: Folder? = nil
local pets: { [string]: Pet } = {}
local active: { Pet } = {}
local clock = 0
local refreshClock = 999
local selectClock = 999
local navCache: { [any]: any } = {}
local footprintCache: { [string]: any } = {}
local Recipes: any = nil
local recipesTried = false
local Surfaces: any = nil
local surfacesTried = false

-- (HouseSurfaces : un objet posé SUR un meuble ?)
local function surfaces(): any
	if not surfacesTried then
		surfacesTried = true
		local module = HouseFolder:FindFirstChild("HouseSurfaces")
		if module then
			local ok, result = pcall(require, module)
			if ok and type(result) == "table" then
				Surfaces = result
			end
		end
	end
	return Surfaces
end

local function onFurniture(entry: any, list: { any }, size: any): boolean
	local S = surfaces()
	if not S or type(S.SupportOf) ~= "function" then
		return false
	end
	local ok, support = pcall(S.SupportOf, entry, list, WorldLayout.RoomWidthPx(size), WorldLayout.ROOM_HEIGHT_PX)
	return ok and type(support) == "table" and support.Entry ~= nil and support.Entry ~= entry
end

local function recipes(): any
	if not recipesTried then
		recipesTried = true
		local module = HouseFolder:FindFirstChild("House3DRecipes")
		if module then
			local ok, result = pcall(require, module)
			if ok and type(result) == "table" then
				Recipes = result
			end
		end
	end
	return Recipes
end

local function serverNow(): number
	local ok, value = pcall(function()
		return workspace:GetServerTimeNow()
	end)
	if ok and type(value) == "number" and value == value then
		return value
	end
	return os.clock()
end

-- Graine stable d'un texte
local function hash(text: string): number
	local h = 5381
	for i = 1, #text do
		h = (h * 33 + string.byte(text, i)) % 2147483647
	end
	return h
end

local function wrapAngle(a: number): number
	return (a + math.pi) % (2 * math.pi) - math.pi
end

----------------------------------------------------------------------
-- Géométrie de la maison : pièces, grille, meubles
----------------------------------------------------------------------

local function sizeOf(house: any): any
	local snapshot = house.Snapshot or {}
	local byId: any = Config.HouseSizesById
	return (type(snapshot.Size) == "string" and byId and byId[snapshot.Size]) or house.Size
end

-- Empreinte (studs) d'un objet posé (modèle construit une fois, en cache)
local function footprintOf(itemId: string, scale: number): any
	local key = itemId .. "|" .. string.format("%.2f", scale)
	local cached = footprintCache[key]
	if cached ~= nil then
		return cached or nil
	end
	local result: any = false
	local R = recipes()
	if R and type(R.BuildModel) == "function" then
		local ok, model, data = pcall(R.BuildModel, itemId, { I = itemId, X = 0.5, Y = 0.8, S = scale, Z = 0 }, { Scale = WorldLayout.PX, Collide = false, Query = false })
		if ok and model and type(data) == "table" then
			result = { FW = tonumber(data.FW) or 1, FD = tonumber(data.FD) or 1, Flat = data.Info and data.Info.Flat == true, Wall = data.Info and data.Info.Wall == true }
			model:Destroy()
		elseif ok and model then
			model:Destroy()
		end
	end
	if not result then
		local item = Config.HouseItemsById[itemId]
		local w = (tonumber(item and item.Size) or 80) * scale * WorldLayout.PX
		result = { FW = w * 0.85, FD = w * 0.6, Flat = false, Wall = false }
	end
	footprintCache[key] = result
	return result
end

type Room = {
	Slot: number,
	Floor: number,
	X0: number, X1: number, D0: number, D1: number, Y: number,
	NX: number, ND: number,
	Blocked: { [number]: boolean },
}

local function cellIndex(room: Room, i: number, j: number): number
	return j * room.NX + i
end

local function cellOf(room: Room, x: number, d: number): (number, number)
	return math.floor((x - room.X0) / CELL), math.floor((d - room.D0) / CELL)
end

local function cellCenter(room: Room, i: number, j: number): (number, number)
	return room.X0 + (i + 0.5) * CELL, room.D0 + (j + 0.5) * CELL
end

local function isFree(room: Room, i: number, j: number): boolean
	if i < 0 or j < 0 or i >= room.NX or j >= room.ND then
		return false
	end
	return not room.Blocked[cellIndex(room, i, j)]
end

local function freeAt(room: Room, x: number, d: number): boolean
	local i, j = cellOf(room, x, d)
	return isFree(room, i, j)
end

-- Ligne droite libre (échantillons tous les 0,15 stud : aucun coin de meuble rogné)
local function clearLine(room: Room, x0: number, d0: number, x1: number, d1: number): boolean
	local length = math.sqrt((x1 - x0) ^ 2 + (d1 - d0) ^ 2)
	local steps = math.max(1, math.ceil(length / 0.15))
	for k = 0, steps do
		local t = k / steps
		if not freeAt(room, x0 + (x1 - x0) * t, d0 + (d1 - d0) * t) then
			return false
		end
	end
	return true
end

-- Pièce : intérieur + cases bloquées (meubles posés au sol, sauf l'animal lui-même)
local function buildRoom(house: any, size: any, slot: number, roomData: any, skipIndex: { [number]: boolean }?): Room
	local x0, x1, yFloor, d0, d1 = WorldLayout.RoomInterior(size, slot)
	local floor = WorldLayout.SlotCell(size, slot)
	local room: Room = {
		Slot = slot,
		Floor = floor,
		X0 = x0 + WALL_MARGIN,
		X1 = x1 - WALL_MARGIN,
		D0 = d0 + WALL_MARGIN,
		D1 = d1 - WALL_MARGIN,
		Y = yFloor,
		NX = 0,
		ND = 0,
		Blocked = {},
	}
	room.NX = math.max(1, math.floor((room.X1 - room.X0) / CELL))
	room.ND = math.max(1, math.floor((room.D1 - room.D0) / CELL))
	if type(roomData) ~= "table" or type(roomData.Placed) ~= "table" then
		return room
	end
	local dims = WorldLayout.RoomDims(size, Config.House.WallRatio)
	local xc = (x0 + x1) / 2
	local floorMinY = (tonumber(Config.House.WallRatio) or 0.46) * 0.85
	local pad = 0.55
	for index, entry in ipairs(roomData.Placed) do
		local item = type(entry) == "table" and Config.HouseItemsById[entry.I] or nil
		if item and item.Placement ~= "Wall" and not (skipIndex and skipIndex[index]) and not SPECIES[entry.I] then
			local Y = tonumber(entry.Y) or 0.8
			if Y >= floorMinY then
				local s = math.clamp(tonumber(entry.S) or 1, 0.2, 3)
				local fp = footprintOf(entry.I, s)
				if fp and not fp.Flat then
					local fw, fd = fp.FW, fp.FD
					local r = tonumber(entry.R) or 0
					if math.abs(math.sin(math.rad(r))) > 0.5 then
						fw, fd = fd, fw
					end
					local ok, rx, rz = pcall(WorldLayout.FloorForward, dims, tonumber(entry.X) or 0.5, Y, fw, fd, fp.Wall)
					if ok then
						local cx, cd = xc + rx, d1 - rz
						local i0, j0 = cellOf(room, cx - fw / 2 - pad, cd - fd / 2 - pad)
						local i1, j1 = cellOf(room, cx + fw / 2 + pad, cd + fd / 2 + pad)
						for i = math.max(0, i0), math.min(room.NX - 1, i1) do
							for j = math.max(0, j0), math.min(room.ND - 1, j1) do
								room.Blocked[cellIndex(room, i, j)] = true
							end
						end
					end
				end
			end
		end
	end
	return room
end

-- A* sur la grille (8 voisins) -> points (x, d) lissés ; nil si impossible
local function findPath(room: Room, ax: number, ad: number, bx: number, bd: number): { Vector2 }?
	if clearLine(room, ax, ad, bx, bd) then
		return { Vector2.new(ax, ad), Vector2.new(bx, bd) }
	end
	local si, sj = cellOf(room, ax, ad)
	local gi, gj = cellOf(room, bx, bd)
	if not isFree(room, gi, gj) then
		return nil
	end
	si, sj = math.clamp(si, 0, room.NX - 1), math.clamp(sj, 0, room.ND - 1)
	local start, goal = cellIndex(room, si, sj), cellIndex(room, gi, gj)
	local g: { [number]: number } = { [start] = 0 }
	local came: { [number]: number } = {}
	local closed: { [number]: boolean } = {}
	-- tas binaire (f, index)
	local heapF, heapN = {}, {}
	local function push(f: number, n: number)
		table.insert(heapF, f)
		table.insert(heapN, n)
		local k = #heapF
		while k > 1 do
			local parent = k // 2
			if heapF[parent] <= heapF[k] then
				break
			end
			heapF[parent], heapF[k] = heapF[k], heapF[parent]
			heapN[parent], heapN[k] = heapN[k], heapN[parent]
			k = parent
		end
	end
	local function pop(): number
		local top = heapN[1]
		local lastF, lastN = table.remove(heapF), table.remove(heapN)
		if #heapF > 0 then
			heapF[1], heapN[1] = lastF, lastN
			local k = 1
			while true do
				local l, r = k * 2, k * 2 + 1
				local m = k
				if l <= #heapF and heapF[l] < heapF[m] then
					m = l
				end
				if r <= #heapF and heapF[r] < heapF[m] then
					m = r
				end
				if m == k then
					break
				end
				heapF[m], heapF[k] = heapF[k], heapF[m]
				heapN[m], heapN[k] = heapN[k], heapN[m]
				k = m
			end
		end
		return top
	end
	local function h(n: number): number
		local i, j = n % room.NX, n // room.NX
		local di, dj = math.abs(i - gi), math.abs(j - gj)
		return math.max(di, dj) + 0.414 * math.min(di, dj)
	end
	push(h(start), start)
	local found = false
	local expanded = 0
	while #heapF > 0 and expanded < 6000 do
		local n = pop()
		if n == goal then
			found = true
			break
		end
		if not closed[n] then
			closed[n] = true
			expanded += 1
			local i, j = n % room.NX, n // room.NX
			for di = -1, 1 do
				for dj = -1, 1 do
					if di ~= 0 or dj ~= 0 then
						local ni, nj = i + di, j + dj
						-- (pas de coin coupé à travers un meuble)
						if isFree(room, ni, nj) and (di == 0 or dj == 0 or (isFree(room, i + di, j) and isFree(room, i, j + dj))) then
							local m = cellIndex(room, ni, nj)
							local cost = g[n] + ((di ~= 0 and dj ~= 0) and 1.414 or 1)
							if not closed[m] and (g[m] == nil or cost < g[m]) then
								g[m] = cost
								came[m] = n
								push(cost + h(m), m)
							end
						end
					end
				end
			end
		end
	end
	if not found then
		return nil
	end
	local cells = {}
	local n = goal
	while n ~= nil do
		table.insert(cells, 1, n)
		if n == start then
			break
		end
		n = came[n]
	end
	local raw = { Vector2.new(ax, ad) }
	for index = 2, #cells - 1 do
		local cx, cd = cellCenter(room, cells[index] % room.NX, cells[index] // room.NX)
		table.insert(raw, Vector2.new(cx, cd))
	end
	table.insert(raw, Vector2.new(bx, bd))
	-- lissage : on saute les points visibles en ligne droite
	local smooth = { raw[1] }
	local k = 1
	while k < #raw do
		local far = k + 1
		for m = #raw, k + 1, -1 do
			if clearLine(room, raw[k].X, raw[k].Y, raw[m].X, raw[m].Y) then
				far = m
				break
			end
		end
		table.insert(smooth, raw[far])
		k = far
	end
	return smooth
end

-- Hauteur du sol (repère de la maison) sous un point, par un rayon (perron, marches)
local function groundY(house: any, x: number, d: number, fallback: number): number
	local ok, y = pcall(function()
		local params = RaycastParams.new()
		params.FilterType = Enum.RaycastFilterType.Include
		params.FilterDescendantsInstances = { house.Exterior or house.Model }
		local from = house.HouseCF * Vector3.new(x, 8, -d)
		local result = workspace:Raycast(from, house.HouseCF.UpVector * -12, params)
		if result then
			local localY = house.HouseCF:PointToObjectSpace(result.Position).Y
			if localY > -0.5 and localY < 6 then
				return localY
			end
		end
		return nil
	end)
	if ok and type(y) == "number" then
		return y
	end
	return fallback
end

-- Navigation d'une maison (en cache tant que ses pièces ne changent pas)
local function roomsKey(house: any): string
	local snapshot = house.Snapshot or {}
	local parts = { tostring(snapshot.Size) }
	for _, room in ipairs(snapshot.Rooms or {}) do
		table.insert(parts, tostring(room.Id) .. "@" .. tostring(room.Slot))
		for _, entry in ipairs(room.Placed or {}) do
			table.insert(parts, string.format("%s:%.3f:%.3f:%.2f:%s", tostring(entry.I), tonumber(entry.X) or 0, tonumber(entry.Y) or 0, tonumber(entry.S) or 1, tostring(entry.R)))
		end
	end
	local garden = snapshot.DopamineGarden
	if type(garden) == "table" and type(garden.Layout) == "table" then
		local keys = {}
		for key, e in pairs(garden.Layout) do
			if type(e) == "table" then
				table.insert(keys, string.format("%s:%.1f:%.1f", key, tonumber(e.X) or 0, tonumber(e.D) or 0))
			end
		end
		table.sort(keys)
		table.insert(parts, table.concat(keys, ","))
	end
	return table.concat(parts, "|")
end

local function navFor(house: any): any
	local key = roomsKey(house)
	local cached = navCache[house]
	if cached and cached.Key == key then
		return cached
	end
	local size = sizeOf(house)
	local snapshot = house.Snapshot or {}
	local dims = WorldLayout.Dims(size)
	local bySlot = {}
	for _, room in ipairs(snapshot.Rooms or {}) do
		local slot = tonumber(room.Slot)
		if slot then
			bySlot[slot] = room
		end
	end
	local hall0, hall1 = WorldLayout.HallSpan(size)
	local doorX = WorldLayout.DoorX(size)
	local nav: any = {
		Key = key,
		Size = size,
		Dims = dims,
		BySlot = bySlot,
		Rooms = {},
		Hall0 = hall0,
		Hall1 = hall1,
		DoorX = doorX,
		Floor1 = WorldLayout.FloorY(1),
		HallAfter = WorldLayout.HallAfter(size),
	}
	-- porte de derrière (HOUSE98) : facultative
	local okBack, backX = pcall(function()
		return (WorldLayout :: any).BackDoorX(size)
	end)
	local okBackD, backD = pcall(function()
		return (WorldLayout :: any).BackDoorD(size)
	end)
	local okSteps, stepsD = pcall(function()
		return (WorldLayout :: any).BackStepsD(size)
	end)
	if okBack and type(backX) == "number" and okBackD and type(backD) == "number" and okSteps and type(stepsD) == "number" then
		nav.BackX, nav.BackD, nav.StepsD = backX, backD, stepsD
	end
	-- objets du jardin (empreintes) : pour les promenades dehors
	local gardenState = GardenSnapshot.Sanitize(snapshot.DopamineGarden)
	nav.GardenItems = {}
	for _, entry in ipairs(GardenSnapshot.Arrange(gardenState)) do
		if not entry.Flat then
			local hx, hd = GardenSnapshot.HalfExtents(entry.W, entry.Dp, entry.R)
			table.insert(nav.GardenItems, { entry.X - hx - 0.7, entry.X + hx + 0.7, entry.D - hd - 0.7, entry.D + hd + 0.7 })
		end
	end
	navCache[house] = nav
	return nav
end

local function roomOf(nav: any, house: any, slot: number): Room
	local room = nav.Rooms[slot]
	if not room then
		room = buildRoom(house, nav.Size, slot, nav.BySlot[slot], nil)
		nav.Rooms[slot] = room
	end
	return room
end

-- Point (x, d) dehors libre ? (objets du jardin + parcelle)
local function yardFree(nav: any, x: number, d: number): boolean
	if math.abs(x) > 84 or d > 51 or d < -27 then
		return false
	end
	-- (pas dans la maison)
	if d > -1.5 and d < nav.Dims.Depth + 1.5 and x > nav.Dims.Left - 1.5 and x < nav.Dims.Left + nav.Dims.Width + 1.5 then
		return false
	end
	for _, box in ipairs(nav.GardenItems) do
		if x > box[1] and x < box[2] and d > box[3] and d < box[4] then
			return false
		end
	end
	return true
end

local function yardLine(nav: any, x0: number, d0: number, x1: number, d1: number): boolean
	local length = math.sqrt((x1 - x0) ^ 2 + (d1 - d0) ^ 2)
	local steps = math.max(1, math.ceil(length / 0.5))
	for k = 1, steps do
		local t = k / steps
		if not yardFree(nav, x0 + (x1 - x0) * t, d0 + (d1 - d0) * t) then
			return false
		end
	end
	return true
end

----------------------------------------------------------------------
-- Chemins du rez-de-chaussée vers dehors (pièces voisines, cage, porte)
----------------------------------------------------------------------

-- Case libre du bord d'une pièce la plus proche de `d` dans la largeur d'un passage
local function passableD(room: Room, x: number, d: number): number?
	local half = (WorldLayout.PASS_W or 5) / 2 - 0.9
	local best: number? = nil
	for k = 0, math.floor(half / CELL) do
		for _, sign in ipairs({ 1, -1 }) do
			local dd = d + sign * k * CELL
			if not best and math.abs(dd - d) <= half and freeAt(room, x, dd) then
				best = dd
			end
		end
	end
	return best
end

-- Sortie de la pièce `slot` (rez-de-chaussée) jusqu'au jardin : points
-- { x, y, d, Door? } depuis `home` ; nil si impossible
local function exitRoute(pet: Pet, nav: any, back: boolean): { any }?
	local house = pet.House
	local size = nav.Size
	local floor, column = WorldLayout.SlotCell(size, pet.Slot)
	if floor ~= 1 then
		return nil
	end
	local y1 = nav.Floor1
	-- (v9.9) profondeur du passage : propre à chaque mur (manoir : passage du fond)
	local passD = WorldLayout.WALL_T + WorldLayout.DEPTH / 2
	local points: { any } = {}
	local function add(x: number, d: number, y: number?, door: boolean?)
		table.insert(points, { X = x, Y = y or y1, D = d, Door = door })
	end
	local curX, curD = pet.Home.X, pet.Home.Z
	add(curX, curD)
	local hallAfter = nav.HallAfter
	local columns = nav.Dims.Columns
	local step = column <= hallAfter and 1 or -1
	local c = column
	while true do
		local slot = (floor - 1) * columns + c
		local room = roomOf(nav, house, slot)
		local cx0, cx1 = WorldLayout.ColumnSpan(size, c)
		-- sortie de cette pièce du côté de la cage : case libre du bord, dans
		-- la largeur du passage (une lampe peut en gêner le milieu)
		local exitX = step > 0 and (room.X0 + (room.NX - 0.5) * CELL) or (room.X0 + 0.5 * CELL)
		local passA, passB = WorldLayout.PassageSpan(size, c, step > 0 and "Right" or "Left")
		passD = (passA + passB) / 2
		local exitD = passableD(room, exitX, passD)
		if not exitD then
			return nil
		end
		local path = findPath(room, curX, curD, exitX, exitD)
		if not path then
			return nil
		end
		for index = 2, #path do
			add(path[index].X, path[index].Y)
		end
		-- traverse le mur (passage)
		local wallX = step > 0 and cx1 or cx0
		add(wallX + step * 0.9, exitD)
		curX, curD = wallX + step * 0.9, exitD
		local nextColumn = c + step
		local reachedHall = (step > 0 and c == hallAfter) or (step < 0 and nextColumn == hallAfter)
		if reachedHall or nextColumn < 1 or nextColumn > columns then
			break
		end
		c = nextColumn
		-- pièce voisine : on entre juste après le mur
		local nextRoom = roomOf(nav, house, (floor - 1) * columns + c)
		local entryX = step > 0 and (nextRoom.X0 + 0.5 * CELL) or (nextRoom.X0 + (nextRoom.NX - 0.5) * CELL)
		local entryD = passableD(nextRoom, entryX, curD)
		if not entryD then
			return nil
		end
		curX, curD = entryX, entryD
		add(curX, curD)
	end
	-- cage d'escalier : couloir le long de l'escalier
	-- (v9.9 HOUSE99) couloir libre le long de la cage, à l'écart de l'escalier, de la console et de la table
	local corridorX = WorldLayout.CorridorX(size) + 1.6
	add(corridorX, passD)
	local doorX = nav.DoorX
	if back and nav.BackX then
		add(corridorX, nav.Dims.Depth - 2.2)
		add(nav.BackX, nav.BackD - 1.2)
		add(nav.BackX, nav.BackD + 0.4, nil, true)
		local landingY = groundY(house, nav.BackX, nav.BackD + 1.6, y1)
		add(nav.BackX, nav.BackD + 1.6, landingY)
		add(nav.BackX, nav.StepsD + 1, groundY(house, nav.BackX, nav.StepsD + 1, LAWN))
	else
		add(corridorX, 2.4)
		add(doorX, 1.6)
		add(doorX, -0.6, nil, true)
		for d = -2, -12, -2 do
			add(doorX, d, groundY(house, doorX, d, LAWN))
		end
	end
	return points
end

----------------------------------------------------------------------
-- Plans (cycles) : marche, poses
----------------------------------------------------------------------

local function polylineLength(points: { any }): number
	local total = 0
	for index = 2, #points do
		local a, b = points[index - 1], points[index]
		total += math.sqrt((b.X - a.X) ^ 2 + (b.D - a.D) ^ 2 + (b.Y - a.Y) ^ 2 * 0.25)
	end
	return total
end

local function reversed(points: { any }): { any }
	local out = {}
	for index = #points, 1, -1 do
		table.insert(out, points[index])
	end
	return out
end

local function yawAlong(a: any, b: any): number
	return math.atan2(-(b.X - a.X), -(-(b.D - a.D)))
end

local function planCycle(pet: Pet, cycle: number): any
	local rng = Random.new((pet.Seed * 7919 + cycle * 104729) % 2147483647)
	local info = pet.Info
	local nav = pet.Nav
	local segs: { any } = {}
	local t = 0
	local home = { X = pet.Home.X, Y = pet.Home.Y, D = pet.Home.Z }
	local yaw = pet.HomeYaw
	local function pose(kind: string, duration: number, at: any)
		if duration <= 0.05 then
			return
		end
		table.insert(segs, { K = "Pose", Pose = kind, At = at, Yaw = yaw, T0 = t, T1 = t + duration })
		t += duration
	end
	local function walk(points: { any }): boolean
		if #points < 2 then
			return true
		end
		local length = polylineLength(points)
		local duration = length / info.Speed + (info.Gait == "Owl" and 0.6 or 0)
		if t + duration > CYCLE - 1.5 then
			return false
		end
		table.insert(segs, { K = "Walk", Pts = points, Len = length, YawIn = yaw, T0 = t, T1 = t + duration })
		t += duration
		local last, before = points[#points], points[#points - 1]
		yaw = yawAlong(before, last)
		return true
	end
	local room = nav and nav.Rooms[pet.Slot]
	local roll = rng:NextNumber()
	local idle = info.Idle
	if pet.Perch then
		-- posé sur un meuble : sieste, assis, regarde autour (sans descendre)
		while t < CYCLE - 0.5 do
			local kind = roll < 0.5 and "Sleep" or idle[rng:NextInteger(1, #idle)]
			pose(kind, math.min(CYCLE - t, rng:NextNumber(8, 20)), home)
			roll = rng:NextNumber()
		end
		return { Segs = segs, Cycle = cycle }
	end
	if roll < info.Nap or not room then
		pose("Sleep", CYCLE, home)
		return { Segs = segs, Cycle = cycle }
	end
	local cur = home
	-- sortie au jardin ?
	if roll < info.Nap + info.Outdoor then
		local back = nav.BackX ~= nil and rng:NextNumber() < 0.7
		local route = pet.Routes and pet.Routes[back and "Back" or "Front"]
		if route and #route >= 2 then
			local outside = route[#route]
			local planned = { outside }
			for _ = 1, 2 do
				local from = planned[#planned]
				for _ = 1, 12 do
					local dx = rng:NextNumber(-14, 14)
					local dd = back and rng:NextNumber(2, 14) or rng:NextNumber(-10, -2)
					local x, d = from.X + dx * 0.6, (back and (outside.D + dd) or (outside.D + dd))
					if yardFree(nav, x, d) and yardLine(nav, from.X, from.D, x, d) then
						table.insert(planned, { X = x, Y = LAWN, D = d })
						break
					end
				end
			end
			local saved = { t, yaw, #segs }
			local ok = walk(route)
			for index = 2, #planned do
				ok = ok and walk({ planned[index - 1], planned[index] })
				if ok then
					pose(idle[rng:NextInteger(1, #idle)], rng:NextNumber(2.5, 5), planned[index])
				end
			end
			if ok then
				local backPts = reversed(planned)
				ok = walk(backPts) and walk(reversed(route))
			end
			if ok then
				pose("Sit", CYCLE - t, home)
				return { Segs = segs, Cycle = cycle }
			end
			-- trop long : on oublie la sortie
			t, yaw = saved[1], saved[2]
			while #segs > saved[3] do
				table.remove(segs)
			end
		end
	end
	-- promenade dans la pièce : 2 ou 3 étapes puis retour à sa place
	local stops = rng:NextInteger(2, 3)
	pose(idle[rng:NextInteger(1, #idle)], rng:NextNumber(1.5, 4), cur)
	for _ = 1, stops do
		local target: any = nil
		local path: { Vector2 }? = nil
		for _ = 1, 14 do
			local i, j = rng:NextInteger(0, room.NX - 1), rng:NextInteger(0, room.ND - 1)
			if isFree(room, i, j) then
				local x, d = cellCenter(room, i, j)
				if (x - cur.X) ^ 2 + (d - cur.D) ^ 2 > 6 then
					local p = if info.Gait == "Owl" then { Vector2.new(cur.X, cur.D), Vector2.new(x, d) } else findPath(room, cur.X, cur.D, x, d)
					if p then
						target, path = { X = x, Y = room.Y, D = d }, p
						break
					end
				end
			end
		end
		if not target or not path then
			break
		end
		local points = {}
		for _, v in ipairs(path) do
			table.insert(points, { X = v.X, Y = room.Y, D = v.Y })
		end
		-- (il faut pouvoir revenir : on garde du temps)
		local homePath = if info.Gait == "Owl" then { Vector2.new(target.X, target.D), Vector2.new(home.X, home.D) } else findPath(room, target.X, target.D, home.X, home.D)
		local backLen = 0
		if homePath then
			for index = 2, #homePath do
				backLen += (homePath[index] - homePath[index - 1]).Magnitude
			end
		end
		if not homePath or t + polylineLength(points) / info.Speed + backLen / info.Speed + 5 > CYCLE then
			break
		end
		if not walk(points) then
			break
		end
		cur = target
		pose(idle[rng:NextInteger(1, #idle)], rng:NextNumber(2.5, 7), cur)
	end
	-- retour
	if cur ~= home then
		local p = if info.Gait == "Owl" then { Vector2.new(cur.X, cur.D), Vector2.new(home.X, home.D) } else findPath(room, cur.X, cur.D, home.X, home.D)
		local points = {}
		for _, v in ipairs(p or { Vector2.new(cur.X, cur.D), Vector2.new(home.X, home.D) }) do
			table.insert(points, { X = v.X, Y = room.Y, D = v.Y })
		end
		-- (toujours revenir, même si le cycle déborde un peu : durée recalculée)
		local length = polylineLength(points)
		local duration = length / info.Speed + (info.Gait == "Owl" and 0.6 or 0)
		table.insert(segs, { K = "Walk", Pts = points, Len = length, YawIn = yaw, T0 = t, T1 = math.min(CYCLE - 0.5, t + duration) })
		t = math.min(CYCLE - 0.5, t + duration)
		if #points >= 2 then
			yaw = yawAlong(points[#points - 1], points[#points])
		end
	end
	pose("Sit", CYCLE - t, home)
	return { Segs = segs, Cycle = cycle }
end

-- État de l'animal à l'heure `now` : position (repère maison), cap, allure, pose
local function sample(pet: Pet, now: number): any
	local offset = pet.Seed % CYCLE
	local cycleT = now + offset
	local cycle = math.floor(cycleT / CYCLE)
	if pet.PlanCycle ~= cycle or not pet.Plan then
		pet.Plan = planCycle(pet, cycle)
		pet.PlanCycle = cycle
	end
	local t = cycleT - cycle * CYCLE
	local plan = pet.Plan
	local seg = plan.Segs[#plan.Segs]
	for _, s in ipairs(plan.Segs) do
		if t >= s.T0 and t < s.T1 then
			seg = s
			break
		end
	end
	if not seg then
		return { X = pet.Home.X, Y = pet.Home.Y, D = pet.Home.Z, Yaw = pet.HomeYaw, Move = 0, Dist = 0, Pose = "Sit", W = 1, Hidden = false, Fly = 0 }
	end
	if seg.K == "Pose" then
		local dur = seg.T1 - seg.T0
		local u = t - seg.T0
		local w = math.clamp(math.min(u, dur - u) / 0.6, 0, 1)
		return { X = seg.At.X, Y = seg.At.Y, D = seg.At.D, Yaw = seg.Yaw, Move = 0, Dist = 0, Pose = seg.Pose, W = w, Hidden = false, Fly = 0, U = u }
	end
	-- marche : distance parcourue le long de la ligne brisée
	local dur = math.max(0.05, seg.T1 - seg.T0)
	local u = math.clamp((t - seg.T0) / dur, 0, 1)
	local target = u * seg.Len
	local pts = seg.Pts
	local acc = 0
	local x, y, d, yaw = pts[1].X, pts[1].Y, pts[1].D, seg.YawIn
	local hidden = false
	for index = 2, #pts do
		local a, b = pts[index - 1], pts[index]
		local len = math.sqrt((b.X - a.X) ^ 2 + (b.D - a.D) ^ 2 + (b.Y - a.Y) ^ 2 * 0.25)
		if acc + len >= target or index == #pts then
			local k = len > 1e-4 and math.clamp((target - acc) / len, 0, 1) or 1
			x = a.X + (b.X - a.X) * k
			y = a.Y + (b.Y - a.Y) * k
			d = a.D + (b.D - a.D) * k
			if len > 1e-3 then
				yaw = yawAlong(a, b)
			end
			-- passage d'une porte : caché un instant (la chatière !)
			if (a.Door and k < 0.35) or (b.Door and k > 0.65) then
				hidden = true
			end
			break
		end
		acc += len
	end
	-- tourne en douceur au départ
	local turnIn = math.clamp((t - seg.T0) / 0.35, 0, 1)
	local finalYaw = seg.YawIn + wrapAngle(yaw - seg.YawIn) * turnIn
	local fly = 0
	if pet.Info.Gait == "Owl" then
		fly = math.sin(u * math.pi) * 3
	end
	local move = math.clamp(math.min(t - seg.T0, seg.T1 - t) / 0.3, 0, 1)
	return { X = x, Y = y, D = d, Yaw = finalYaw, Move = move, Dist = target, Pose = "Stand", W = 0, Hidden = hidden, Fly = fly }
end

----------------------------------------------------------------------
-- Modèles articulés
----------------------------------------------------------------------

local SKIP = { Root = true, Hitbox = true, SeatPart = true }

local function buildRig(pet: Pet): boolean
	local R = recipes()
	if not R or type(R.BuildItem) ~= "function" then
		return false
	end
	local entry = table.clone(pet.Entry)
	local model = R.BuildItem(pet.ItemId, entry, { Scale = WorldLayout.PX, Collide = false, Query = false })
	if not model then
		return false
	end
	model.Name = "Roaming_" .. pet.ItemId
	local pivot = model:GetPivot()
	local joints: { [string]: CFrame } = { Body = CFrame.identity }
	local markers = {}
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") then
			local jointName = string.match(d.Name, "^Joint_(%w+)$")
			if jointName then
				joints[jointName] = CFrame.new(pivot:PointToObjectSpace(d.Position))
				table.insert(markers, d)
			end
		end
	end
	for _, m in ipairs(markers) do
		m:Destroy()
	end
	local parts, rel, jointOf, isEye = {}, {}, {}, {}
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") then
			if SKIP[d.Name] then
				d:Destroy()
			else
				local jointName = string.match(d.Name, "^J_(%w+)_") or "Body"
				if not joints[jointName] then
					jointName = "Body"
				end
				d.Anchored = true
				d.CanCollide = false
				d.CanQuery = false
				d.CanTouch = false
				table.insert(parts, d)
				table.insert(jointOf, jointName)
				table.insert(rel, joints[jointName]:Inverse() * pivot:ToObjectSpace(d.CFrame))
				table.insert(isEye, string.find(d.Name, "_Eye", 1, true) ~= nil)
			end
		end
	end
	if #parts == 0 then
		model:Destroy()
		return false
	end
	-- (encombrement mesuré sur les pièces : haut, longueur)
	local top, zMin, zMax = 0.5, 0, 0
	for index, part in ipairs(parts) do
		local p = (joints[jointOf[index]] * rel[index]).Position
		top = math.max(top, p.Y + part.Size.Y / 2)
		zMin = math.min(zMin, p.Z - part.Size.Z / 2)
		zMax = math.max(zMax, p.Z + part.Size.Z / 2)
	end
	local extents = Vector3.new(0, top, zMax - zMin)
	pet.Model = model
	pet.Rig = {
		Parts = parts,
		Rel = rel,
		Joint = jointOf,
		Eye = isEye,
		Joints = joints,
		Height = math.max(0.5, extents.Y),
		Length = math.max(0.5, extents.Z),
		CFrames = table.create(#parts, CFrame.identity),
		HipY = joints.LegBL and joints.LegBL.Position.Y or extents.Y * 0.4,
		HipZ = joints.LegBL and joints.LegBL.Position.Z or extents.Z * 0.3,
	}
	return true
end

local function destroyRig(pet: Pet)
	if pet.Model then
		pet.Model:Destroy()
	end
	pet.Model = nil
	pet.Rig = nil
	pet.Visible = false
end

-- Articulations d'une allure / d'une pose (repère du modèle : devant -Z ;
-- Rx(+) lève l'avant / avance une patte ; Ry(+) tourne vers la gauche)
local function animate(pet: Pet, s: any, t: number): (CFrame, { [string]: CFrame }, boolean)
	local info = pet.Info
	local rig = pet.Rig
	local gait = info.Gait
	local h = rig.Height
	local rot: { [string]: CFrame } = {}
	local phase = (s.Dist / math.max(0.1, info.Stride)) * math.pi * 2
	local move = s.Move
	local seed = pet.Seed % 1000
	local rootOff = CFrame.identity
	local eyesClosed = false
	local w = s.W
	local poseName = s.Pose
	-- tête qui regarde autour (au repos)
	local lookYaw = math.sin(t * 0.55 + seed) * 0.45 + math.sin(t * 1.3 + seed * 2) * 0.15
	local lookPitch = math.sin(t * 0.8 + seed) * 0.08
	if gait == "Quad" or gait == "Scurry" or gait == "Crawl" or gait == "Hop" then
		local amp = (gait == "Scurry" and 0.75 or (gait == "Crawl" and 0.45 or 0.55)) * move
		local a = math.sin(phase) * amp
		if gait == "Hop" then
			local up = math.max(0, math.sin(phase))
			rootOff = CFrame.new(0, up * h * 0.28 * move, 0) * CFrame.Angles(math.cos(phase) * 0.18 * move, 0, 0)
			rot.LegBL = CFrame.Angles(-0.7 * up * move, 0, 0)
			rot.LegBR = rot.LegBL
			rot.LegFL = CFrame.Angles(0.5 * math.sin(phase) * move, 0, 0)
			rot.LegFR = rot.LegFL
		else
			rot.LegFL = CFrame.Angles(a, 0, 0)
			rot.LegBR = CFrame.Angles(a, 0, 0)
			rot.LegFR = CFrame.Angles(-a, 0, 0)
			rot.LegBL = CFrame.Angles(-a, 0, 0)
			rootOff = CFrame.new(0, math.abs(math.sin(phase)) * h * 0.025 * move, 0)
		end
		local headPitch = math.sin(phase * 2) * 0.05 * move
		local headYaw = lookYaw * (1 - move)
		-- queue
		if info.Cat then
			rot.Tail = CFrame.Angles(0.25 + math.sin(t * 1.1 + seed) * 0.1, math.sin(t * 1.6 + seed) * 0.35, 0)
		elseif info.Wag then
			rot.Tail = CFrame.Angles(0.15, math.sin(t * info.Wag + seed) * 0.45, 0)
		else
			rot.Tail = CFrame.Angles(0, math.sin(t * 2 + seed) * 0.15, 0)
		end
		-- poses
		if poseName == "Sit" then
			local hip = CFrame.new(0, rig.HipY, rig.HipZ)
			rootOff = rootOff:Lerp(CFrame.new(0, -rig.HipY * 0.45, 0) * hip * CFrame.Angles(0.5, 0, 0) * hip:Inverse(), w)
			rot.LegBL = (rot.LegBL :: CFrame):Lerp(CFrame.Angles(1.25, 0, 0), w)
			rot.LegBR = rot.LegBL
			rot.LegFL = (rot.LegFL :: CFrame):Lerp(CFrame.Angles(-0.45, 0, 0), w)
			rot.LegFR = rot.LegFL
			headPitch -= 0.35 * w
		elseif poseName == "Sleep" then
			rootOff = rootOff:Lerp(CFrame.new(0, -rig.HipY * 0.82, 0), w)
			rot.LegFL = (rot.LegFL :: CFrame):Lerp(CFrame.Angles(1.35, 0.25, 0), w)
			rot.LegFR = (rot.LegFR :: CFrame):Lerp(CFrame.Angles(1.35, -0.25, 0), w)
			rot.LegBL = (rot.LegBL :: CFrame):Lerp(CFrame.Angles(-1.3, 0, 0), w)
			rot.LegBR = (rot.LegBR :: CFrame):Lerp(CFrame.Angles(-1.3, 0, 0), w)
			rot.Tail = (rot.Tail :: CFrame):Lerp(CFrame.Angles(-0.2, 1.1, 0), w)
			headPitch = headPitch * (1 - w) - 0.45 * w + math.sin(t * 1.2) * 0.02 * w
			headYaw = headYaw * (1 - w) + 0.5 * w
			eyesClosed = w > 0.5
		elseif poseName == "Sniff" or poseName == "Peck" then
			headPitch -= (0.5 + math.sin(t * 11) * 0.06) * w
			headYaw *= 0.4
		elseif poseName == "Groom" then
			headPitch -= 0.3 * w
			headYaw = headYaw * (1 - w) + (0.9 + math.sin(t * 6) * 0.1) * w
		end
		rot.Head = CFrame.Angles(headPitch + lookPitch * (1 - move), headYaw, 0)
		if info.Wings then
			local open = poseName == "Flap" and w or 0
			local flap = math.sin(t * 9) * 0.5 * open
			rot.WingL = CFrame.Angles(0, 0, -(0.1 + 0.6 * open + flap))
			rot.WingR = CFrame.Angles(0, 0, 0.1 + 0.6 * open + flap)
		end
	else
		-- oiseaux : dandinement, pas alternés, ailes
		local roll = (gait == "Waddle" and 0.2 or 0.1) * math.sin(phase) * move
		local legA = math.sin(phase) * 0.6 * move
		rot.LegL = CFrame.Angles(legA, 0, 0)
		rot.LegR = CFrame.Angles(-legA, 0, 0)
		local wingOpen = gait == "Waddle" and 0.35 * move or 0.05
		local flap = 0
		if gait == "Owl" and s.Fly > 0.01 then
			flap = 0.5 + math.sin(t * 14) * 0.9
			rot.LegL = CFrame.Angles(0.9, 0, 0)
			rot.LegR = rot.LegL
		elseif poseName == "Flap" then
			flap = (0.4 + math.sin(t * 16) * 0.6) * w
		end
		rot.WingL = CFrame.Angles(0, 0, -(wingOpen + flap))
		rot.WingR = CFrame.Angles(0, 0, wingOpen + flap)
		rootOff = CFrame.new(0, s.Fly + math.abs(math.sin(phase)) * h * 0.03 * move, 0) * CFrame.Angles(0, 0, roll)
		local headPitch = math.sin(phase * 2) * 0.12 * move
		local headYaw = lookYaw * (1 - move)
		if gait == "Owl" then
			headYaw = math.sin(t * 0.35 + seed) * 1.6 * (1 - move)
		end
		if poseName == "Peck" or poseName == "Sniff" then
			headPitch -= (0.55 + math.max(0, math.sin(t * 7)) * 0.35) * w
		elseif poseName == "Sleep" then
			rootOff = rootOff:Lerp(CFrame.new(0, -h * 0.12, 0), w)
			headPitch -= 0.4 * w
			eyesClosed = w > 0.5
		elseif poseName == "Sit" then
			rootOff = rootOff:Lerp(CFrame.new(0, -h * 0.08, 0), w)
		end
		rot.Head = CFrame.Angles(headPitch, headYaw, 0)
	end
	-- clignement des yeux (toutes les ~4 s)
	if not eyesClosed and ((t + seed) % 4.2) < 0.12 then
		eyesClosed = true
	end
	return rootOff, rot, eyesClosed
end

local function place(pet: Pet, s: any, t: number)
	local rig = pet.Rig
	if not rig then
		return
	end
	local house = pet.House
	local base = house.HouseCF * Vector3.new(s.X, s.Y, -s.D)
	-- cap : yaw (repère maison) -> monde
	local heading = house.HouseCF:VectorToWorldSpace(Vector3.new(-math.sin(s.Yaw), 0, -math.cos(s.Yaw)))
	local ground = CFrame.lookAt(base, base + heading)
	if pet.Perch and pet.PerchCF then
		ground = pet.PerchCF
		base = ground.Position
	end
	local rootOff, rot, eyesClosed = animate(pet, s, t)
	local modelCF = ground * rootOff
	local cfs = rig.CFrames
	local jointCF: { [string]: CFrame } = {}
	for name, rest in pairs(rig.Joints) do
		local r = rot[name]
		jointCF[name] = if r then modelCF * rest * r else modelCF * rest
	end
	for index, part in ipairs(rig.Parts) do
		local cf = jointCF[rig.Joint[index]] * rig.Rel[index]
		if eyesClosed and rig.Eye[index] then
			cf = cf * CFrame.new(0, 0, part.Size.Z * 0.9)
		end
		cfs[index] = cf
	end
	local ok = pcall(function()
		workspace:BulkMoveTo(rig.Parts, cfs, Enum.BulkMoveMode.FireCFrameChanged)
	end)
	if not ok then
		for index, part in ipairs(rig.Parts) do
			part.CFrame = cfs[index]
		end
	end
	pet.Pos = base
end

----------------------------------------------------------------------
-- Originaux (modèles posés dans les pièces) : cachés / rendus
----------------------------------------------------------------------

local function findOriginal(pet: Pet): Model?
	local house = pet.House
	local state = house.Rooms and house.Rooms[pet.Slot]
	if not state or state.State ~= "Built" then
		return nil
	end
	for _, model in ipairs(state.Items or {}) do
		if model.Parent and tonumber(model:GetAttribute("EntryIndex")) == pet.EntryIndex and model:GetAttribute("ItemId") == pet.ItemId then
			return model
		end
	end
	return nil
end

local function restoreOriginal(pet: Pet)
	for part, transparency in pairs(pet.Hidden) do
		if part.Parent then
			part.Transparency = transparency
		end
	end
	table.clear(pet.Hidden)
	pet.Original = nil
end

local function hideOriginal(pet: Pet)
	local original = findOriginal(pet)
	if original ~= pet.Original then
		restoreOriginal(pet)
		pet.Original = original
		if original and pet.Perch then
			pet.PerchCF = original:GetPivot()
		end
		if original then
			for _, d in ipairs(original:GetDescendants()) do
				if d:IsA("BasePart") and d.Transparency < 1 then
					pet.Hidden[d] = d.Transparency
					d.Transparency = 1
				end
			end
		end
	end
end

----------------------------------------------------------------------
-- Inventaire des animaux (instantanés des maisons)
----------------------------------------------------------------------

local function houses(): { [any]: any }
	local fn = ctx.GetHouses
	if type(fn) ~= "function" then
		return {}
	end
	local ok, result = pcall(fn)
	return ok and type(result) == "table" and result or {}
end

local function removePet(key: string)
	local pet = pets[key]
	if not pet then
		return
	end
	restoreOriginal(pet)
	destroyRig(pet)
	pets[key] = nil
end

local function refresh()
	local seen = {}
	for userId, house in pairs(houses()) do
		local snapshot = type(house) == "table" and house.Snapshot or nil
		if snapshot and house.HouseCF and not house.Destroyed then
			local size = sizeOf(house)
			local nav = nil
			for _, roomData in ipairs(snapshot.Rooms or {}) do
				local slot = tonumber(roomData.Slot)
				for index, entry in ipairs(type(roomData.Placed) == "table" and roomData.Placed or {}) do
					local info = type(entry) == "table" and SPECIES[entry.I] or nil
					if info and slot then
						local key = string.format("%s|%s|%d|%s|%.3f|%.3f|%.2f|%s", tostring(userId), tostring(roomData.Id), index, entry.I, tonumber(entry.X) or 0.5,
							tonumber(entry.Y) or 0.8, tonumber(entry.S) or 1, tostring(entry.F))
						seen[key] = true
						nav = nav or navFor(house)
						local pet = pets[key]
						if pet and pet.Nav ~= nav then
							-- (meubles / jardin changés : chemins recalculés)
							pet.Nav = nav
							pet.Plan = nil
							pet.PlanCycle = -1
							pet.Routes = nil
						end
						if not pet then
							local room = roomOf(nav, house, slot)
							local dims = WorldLayout.RoomDims(size, Config.House.WallRatio)
							local item = Config.HouseItemsById[entry.I]
							local s = math.clamp(tonumber(entry.S) or 1, 0.2, 3)
							local box = (tonumber(item and item.Size) or 60) * s * WorldLayout.PX
							local okHome, rx, rz = pcall(WorldLayout.FloorForward, dims, tonumber(entry.X) or 0.5, tonumber(entry.Y) or 0.8, box * 0.45, box * 0.9, false)
							local x0, x1, yFloor, _, d1 = WorldLayout.RoomInterior(size, slot)
							local hx, hd = (x0 + x1) / 2 + (okHome and rx or 0), d1 - (okHome and rz or 12)
							hx = math.clamp(hx, room.X0 + 0.2, room.X1 - 0.2)
							hd = math.clamp(hd, room.D0 + 0.2, room.D1 - 0.2)
							-- (sa place doit être libre : sinon la case libre la plus proche)
							if not freeAt(room, hx, hd) then
								local best, bestD = nil, math.huge
								for i = 0, room.NX - 1 do
									for j = 0, room.ND - 1 do
										if isFree(room, i, j) then
											local cx, cd = cellCenter(room, i, j)
											local dist = (cx - hx) ^ 2 + (cd - hd) ^ 2
											if dist < bestD then
												best, bestD = { cx, cd }, dist
											end
										end
									end
								end
								if best then
									hx, hd = best[1], best[2]
								end
							end
							pet = {
								Key = key,
								House = house,
								UserId = tonumber(userId) or 0,
								ItemId = entry.I,
								Entry = entry,
								EntryIndex = index,
								Slot = slot,
								Info = info,
								Seed = hash(key),
								Home = Vector3.new(hx, yFloor, hd),
								HomeYaw = math.pi, -- (regarde la rue, comme dans la pièce)
								Nav = nav,
								PlanCycle = -1,
								Visible = false,
								Hidden = {},
								Perch = onFurniture(entry, roomData.Placed, size),
							} :: any
							pets[key] = pet
						end
						local p = pet :: any
						if p and p.Routes == nil and not p.Perch then
							p.Routes = {}
							local okF, front = pcall(exitRoute, p, nav, false)
							p.Routes.Front = okF and front or nil
							local okB, back = pcall(exitRoute, p, nav, true)
							p.Routes.Back = okB and back or nil
						end
					end
				end
			end
		end
	end
	for key in pairs(pets) do
		if not seen[key] then
			removePet(key)
		end
	end
	-- maisons disparues : caches oubliés
	local alive = houses()
	for house in pairs(navCache) do
		local found = false
		for _, h in pairs(alive) do
			if h == house then
				found = true
				break
			end
		end
		if not found then
			navCache[house] = nil
		end
	end
end

----------------------------------------------------------------------
-- Boucle
----------------------------------------------------------------------

local function focus(): Vector3?
	local camera = workspace.CurrentCamera
	return camera and camera.CFrame.Position or nil
end

-- Le double est-il visible à cet endroit ? (dehors, cage, pièce construite)
local function visibleAt(pet: Pet, s: any): boolean
	if s.Hidden or (pet.Perch and not pet.PerchCF) then
		return false
	end
	local slot = WorldLayout.SlotAt(sizeOf(pet.House), s.X, s.Y + 1, s.D)
	if not slot then
		return true
	end
	local state = pet.House.Rooms and pet.House.Rooms[slot]
	return state ~= nil and state.State == "Built"
end

local function select(now: number)
	local cam = focus()
	local list = {}
	for _, pet in pairs(pets) do
		local s = sample(pet, now)
		local world = pet.House.HouseCF * Vector3.new(s.X, s.Y, -s.D)
		local dist = cam and (world - cam).Magnitude or math.huge
		pet.Pos = world
		table.insert(list, { Pet = pet, Dist = dist })
	end
	table.sort(list, function(a, b)
		return a.Dist < b.Dist
	end)
	table.clear(active)
	local built = 0
	for index, rec in ipairs(list) do
		local pet = rec.Pet
		if not paused and index <= MAX_ANIMATED and rec.Dist < RANGE then
			if not pet.Model and built < 1 then
				built += 1
				local ok, result = pcall(buildRig, pet)
				if not ok then
					warn("[PetRoam] " .. tostring(pet.ItemId) .. " : " .. tostring(result))
				end
			end
			if pet.Model then
				table.insert(active, pet)
				hideOriginal(pet)
			end
		else
			restoreOriginal(pet)
			if pet.Model and (paused or rec.Dist > FAR or index > MAX_ANIMATED) then
				destroyRig(pet)
			elseif pet.Model then
				pet.Model.Parent = nil
				pet.Visible = false
			end
		end
	end
end

function PetRoam.Start(context: any?)
	ctx = type(context) == "table" and context or {}
	started = true
	paused = false
	clock, refreshClock, selectClock = 0, 999, 999
	if not folder or not folder.Parent then
		local f = Instance.new("Folder")
		f.Name = "RoamingPets"
		f.Parent = workspace
		folder = f
	end
end

function PetRoam.Step(dt: number?)
	if not started then
		return
	end
	local step = dt or HZ
	refreshClock += step
	selectClock += step
	clock += step
	if refreshClock >= 1 then
		refreshClock = 0
		local ok, err = pcall(refresh)
		if not ok then
			warn("[PetRoam] " .. tostring(err))
		end
	end
	local now = serverNow()
	if selectClock >= 0.5 then
		selectClock = 0
		local ok, err = pcall(select, now)
		if not ok then
			warn("[PetRoam] " .. tostring(err))
		end
	end
	if clock < HZ or paused then
		return
	end
	clock = 0
	for _, pet in ipairs(active) do
		local model = pet.Model
		if model and pet.Rig then
			local ok, s = pcall(sample, pet, now)
			if ok then
				local show = visibleAt(pet, s)
				if show then
					place(pet, s, now)
					if not pet.Visible then
						model.Parent = folder
						pet.Visible = true
					end
				elseif pet.Visible then
					model.Parent = nil
					pet.Visible = false
				end
			end
		end
	end
end

function PetRoam.SetPaused(value: boolean)
	-- (appelable à chaque image : ne fait rien si rien ne change)
	if (value == true) == paused then
		return
	end
	paused = value == true
	if paused then
		for _, pet in pairs(pets) do
			restoreOriginal(pet)
			destroyRig(pet)
		end
		table.clear(active)
	else
		selectClock = 999
	end
end

function PetRoam.Stop()
	for key in pairs(pets) do
		removePet(key)
	end
	table.clear(pets)
	table.clear(active)
	table.clear(navCache)
	started = false
	if folder then
		folder:Destroy()
		folder = nil
	end
end

-- (tests) état interne
function PetRoam.Debug(): any
	return { Pets = pets, Active = active, Sample = sample, Plan = planCycle, Nav = navFor, Route = exitRoute, Visible = visibleAt, Refresh = refresh,
		FindPath = findPath, FreeAt = freeAt, RoomOf = roomOf }
end

return PetRoam
