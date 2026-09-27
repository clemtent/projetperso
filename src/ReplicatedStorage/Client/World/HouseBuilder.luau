--[[
	HouseBuilder (ModuleScript)
	Emplacement : ReplicatedStorage > Client > World > HouseBuilder

	🚶 Dopamine Town : construit côté CLIENT la maison 3D d'un joueur sur sa
	parcelle, d'après l'instantané envoyé par WorldService (mêmes données que
	la maison 2D : taille, pièces, façade / toit / motif du toit / jardin).
	  - EXTÉRIEUR (v9.4, HouseFacade) : dessiné COMME la maison 2D
	    (HouseExterior : chaumière, maison de ville, loft, manoir), en vraies
	    matières ; une vraie fenêtre par pièce, porte d'entrée battante
	    (s'ouvre quand on approche, reste fermée et 🔒 si le propriétaire
	    n'accueille pas ce joueur), perron à marches, jardin de devant avec la
	    déco choisie dans la 2D, plaque au nom du propriétaire ;
	  - CAGE D'ESCALIER (v9.4, HouseStairs) : là où la 2D dessine l'entrée ;
	    une volée droite par étage avec une rampe de collision lisse et
	    invisible (on monte / descend sans jamais accrocher) ;
	  - INTÉRIEURS en flux (Stream) : seulement les pièces proches du joueur
	    (House3DScene.BuildRoomShell + House3DScene.PlaceItems : coque avec
	    papier peint, moulures, fenêtre du fond, passages vers les pièces
	    voisines / la cage ; vrais meubles 3D) + mur avant intérieur (papier
	    peint autour de la vraie fenêtre de la façade, rideaux) + plafonnier
	    qui éclaire vraiment ; une pièce à la fois ; détruites de loin ;
	  - emplacements vides de la grille : pièce vide ("à acheter") ;
	  - sièges : les modèles avec une "SeatPart" reçoivent une invite
	    ProximityPrompt "S'asseoir" (voir TownClient : le serveur crée le Seat).
	INVARIANTS (v9.4, anti-"empilement") vérifiés et RÉPARÉS à chaque
	construction : une seule maison par propriétaire dans le dossier, une
	seule coque par emplacement, exactement UN modèle par objet posé
	(EntryIndex) ; compteurs en attributs du modèle (StrayHouses,
	StrayShells, DuplicateItems, Chimneys) ; house:Audit() pour les tests.
	Repère : WorldLayout (maison, pièces, conversions 2D <-> 3D).

	API :
	  HouseBuilder.new(snapshot, plotCF, parent) -> House
	  house:Update(snapshot)            (reconstruit ce qui a changé)
	  house:NextToBuild(focus) -> slot?, distance ; house:BuildRoom(slot) ;
	  house:DestroyRoom(slot)
	  house:StepDoor(near, locked)      (porte d'entrée)
	  house:DoorPosition() -> Vector3 ; house:RoomAt(worldPoint) -> slot?
	  house:SetRoomPlaced(slot, placed) (après un déplacement de meuble)
	  house:Audit() -> Audit ; house:Destroy()
	  HouseBuilder.OnItemAttach / OnItemDetach (facultatifs, v9.5) :
	    function(house, slot, model, entry, itemId) appelées pour CHAQUE
	    modèle d'objet construit / retiré (voir attachItems / detachItems)
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Config = require(ReplicatedStorage.Shared.Config)
local WorldLayout = require(ReplicatedStorage.Shared.WorldLayout)
local Locale = require(ReplicatedStorage.Shared.Locale)
local HouseKit = require(script.Parent.HouseKit)
local HouseFacade = require(script.Parent.HouseFacade)
local HouseStairs = require(script.Parent.HouseStairs)

local HouseFolder = script.Parent.Parent.Components.House

local HouseBuilder = {}
HouseBuilder.__index = HouseBuilder

-- (v9.5) crochets facultatifs : un modèle d'objet vient d'être construit /
-- va disparaître (house, slot, model, entry, itemId)
HouseBuilder.OnItemAttach = nil :: ((house: any, slot: number, model: Model, entry: any, itemId: string) -> ())?
HouseBuilder.OnItemDetach = nil :: ((house: any, slot: number, model: Model, entry: any, itemId: string) -> ())?

local NEAR = 62 -- (studs) une pièce plus proche que ça est meublée
local FAR = 90 -- plus loin : on la vide
local M = Enum.Material
local WHITE = Color3.new(1, 1, 1)
local CREAM = Color3.fromRGB(255, 247, 236)

-- Modules 3D de la maison (HOUSE3D93) : chargés une fois, jamais bloquants
local Scene: any = nil
local HouseCommon: any = nil
local loadedModules = false
local function modules()
	if loadedModules then
		return
	end
	loadedModules = true
	local okCommon, common = pcall(require, HouseFolder:WaitForChild("HouseCommon", 5) :: ModuleScript)
	if okCommon then
		HouseCommon = common
	end
	local sceneModule = HouseFolder:FindFirstChild("House3DScene")
	if sceneModule and sceneModule:IsA("ModuleScript") then
		local ok, result = pcall(require, sceneModule)
		if ok and type(result) == "table" then
			Scene = result
		else
			warn("[World] House3DScene : " .. tostring(result))
		end
	end
end

export type RoomState = {
	Slot: number,
	Data: any?, -- pièce de l'instantané (nil = emplacement vide)
	Shell: Model?,
	Items: { Model },
	State: string, -- "None" | "Building" | "Built"
	Signature: string,
	Fill: BasePart?, -- lueur de la pièce derrière la fenêtre (quand elle est vide)
	Prompts: { ProximityPrompt },
	Token: number,
}

export type Audit = {
	OK: boolean,
	Shells: number, -- coques dans Interiors
	ExtraShells: number, -- coques en trop (même emplacement / orphelines)
	Items: number, -- modèles d'objets dans les coques
	Duplicates: number, -- modèles en trop pour un même objet posé
	Missing: number, -- objets posés sans modèle (pièces construites)
	Houses: number, -- maisons de ce propriétaire dans le dossier parent
	Chimneys: number,
	ChimneysExpected: number,
	Parts: number, -- pièces de l'extérieur (budget)
	Lights: number,
}

export type House = typeof(setmetatable({} :: {
	UserId: number,
	Snapshot: any,
	Size: any,
	PlotCF: CFrame,
	HouseCF: CFrame,
	Model: Model,
	Exterior: Folder,
	Interiors: Folder,
	Rooms: { [number]: RoomState },
	ExteriorKey: string,
	Door: BasePart?,
	DoorHinge: CFrame?,
	DoorOpen: boolean,
	DoorLock: TextLabel?,
	Ramps: { BasePart },
	Style: string,
	Chimneys: number,
	ExteriorParts: number,
	ExteriorLights: number,
	OnSeat: ((house: any, slot: number, model: Model, seatPart: BasePart) -> ())?,
	OnRoomBuilt: ((house: any, slot: number) -> ())?,
	Night: boolean,
	Alive: boolean,
}, HouseBuilder))

----------------------------------------------------------------------
-- Outils
----------------------------------------------------------------------

local function sizeDefOf(snapshot: any): any
	local id = type(snapshot) == "table" and snapshot.Size or nil
	return Config.HouseSizesById[id] or Config.House.Sizes[1]
end

local function lookEntry(kind: string, id: any): any
	local byId = Config.HouseLooksById and Config.HouseLooksById[kind]
	return byId and type(id) == "string" and byId[id] or nil
end

local function lookColor(kind: string, id: any): Color3?
	local entry = lookEntry(kind, id)
	local color = entry and entry.Color
	return typeof(color) == "Color3" and color or nil
end

local function wallpaperOf(room: any): any
	return room and Config.HouseWallpapersById[room.Wallpaper]
end

local function wallpaperColor(room: any): Color3
	local style = wallpaperOf(room)
	local color = style and style.A
	return typeof(color) == "Color3" and color or Color3.fromRGB(255, 222, 236)
end

-- Signature d'une pièce (reconstruire seulement ce qui a changé)
local function roomSignature(room: any): string
	if type(room) ~= "table" then
		return "empty"
	end
	local parts = { tostring(room.Id), tostring(room.Type), tostring(room.Wallpaper), tostring(room.Floor), tostring(room.Trim), tostring(room.Mood), tostring(room.View) }
	if type(room.Placed) == "table" then
		for _, e in ipairs(room.Placed) do
			if type(e) == "table" then
				table.insert(parts, string.format("%s/%s/%s/%s/%s/%s/%s/%s", tostring(e.I), tostring(e.X), tostring(e.Y), tostring(e.S), tostring(e.Z),
					tostring(e.F), tostring(e.C), tostring(e.R)))
			end
		end
	end
	return table.concat(parts, "|")
end

local function exteriorKey(snapshot: any): string
	local parts = { tostring(snapshot.Size), tostring(snapshot.Facade), tostring(snapshot.Roof), tostring(snapshot.RoofStyle), tostring(snapshot.Plot),
		tostring(snapshot.DisplayName), tostring(snapshot.Garage) }
	if type(snapshot.Garden) == "table" then
		table.insert(parts, table.concat(snapshot.Garden, ","))
	end
	if type(snapshot.Rooms) == "table" then
		for _, room in ipairs(snapshot.Rooms) do
			if type(room) == "table" then
				table.insert(parts, tostring(room.Slot) .. ":" .. tostring(room.Wallpaper))
			end
		end
	end
	return table.concat(parts, "|")
end

local function roomsBySlot(snapshot: any): { [number]: any }
	local bySlot: { [number]: any } = {}
	if type(snapshot.Rooms) == "table" then
		for _, room in ipairs(snapshot.Rooms) do
			if type(room) == "table" and tonumber(room.Slot) then
				bySlot[tonumber(room.Slot) :: number] = room
			end
		end
	end
	return bySlot
end

local function newPart(parent: Instance, name: string, size: Vector3, cf: CFrame, color: Color3, material: Enum.Material?, collide: boolean?): BasePart
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored = true
	p.Size = Vector3.new(math.max(0.05, size.X), math.max(0.05, size.Y), math.max(0.05, size.Z))
	p.CFrame = cf
	p.Color = color
	p.Material = material or M.SmoothPlastic
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.CanCollide = collide == true
	p.CanTouch = false
	p.CanQuery = collide == true
	p.CastShadow = collide == true
	p.Parent = parent
	return p
end

----------------------------------------------------------------------
-- Construction de l'extérieur
----------------------------------------------------------------------

function HouseBuilder.new(snapshot: any, plotCF: CFrame, parent: Instance): House
	modules()
	local userId = tonumber(snapshot.UserId) or 0
	-- INVARIANT : une seule maison par propriétaire dans ce dossier (une copie
	-- oubliée par un appelant se superposerait exactement à celle-ci)
	local strays = 0
	for _, child in ipairs(parent:GetChildren()) do
		if child:IsA("Model") and child:GetAttribute("OwnerId") == userId then
			strays += 1
			child:Destroy()
		end
	end
	if strays > 0 then
		warn("[World] Maison " .. tostring(userId) .. " : " .. strays .. " copie(s) en trop retirée(s)")
	end
	local model = Instance.new("Model")
	model.Name = "House_" .. tostring(snapshot.UserId)
	local exterior = Instance.new("Folder")
	exterior.Name = "Exterior"
	exterior.Parent = model
	local interiors = Instance.new("Folder")
	interiors.Name = "Interiors"
	interiors.Parent = model
	local self = setmetatable({
		UserId = userId,
		Snapshot = snapshot,
		Size = sizeDefOf(snapshot),
		PlotCF = plotCF,
		HouseCF = WorldLayout.HouseCFrame(plotCF),
		Model = model,
		Exterior = exterior,
		Interiors = interiors,
		Rooms = {},
		ExteriorKey = "",
		Door = nil,
		DoorHinge = nil,
		DoorOpen = false,
		DoorLock = nil,
		Ramps = {},
		Style = "Cottage",
		Chimneys = 0,
		ExteriorParts = 0,
		ExteriorLights = 0,
		OnSeat = nil,
		OnRoomBuilt = nil,
		Night = false,
		Alive = true,
	}, HouseBuilder)
	model:SetAttribute("OwnerId", self.UserId)
	model:SetAttribute("StrayHouses", strays)
	model:SetAttribute("StrayShells", 0)
	model:SetAttribute("DuplicateItems", 0)
	self:BuildExterior()
	model.Parent = parent
	return self
end

function HouseBuilder.BuildExterior(self: House)
	local snapshot = self.Snapshot
	local size = self.Size
	local dims = WorldLayout.Dims(size)
	local folder = self.Exterior
	folder:ClearAllChildren()
	self.ExteriorKey = exteriorKey(snapshot)
	self.Door = nil
	self.DoorHinge = nil
	self.DoorLock = nil
	self.DoorOpen = false
	local bySlot = roomsBySlot(snapshot)
	local style = lookEntry("RoofStyle", snapshot.RoofStyle)
	local kit = HouseKit.new(self.HouseCF, folder, 6)
	local looks: HouseFacade.Looks = {
		Wall = lookColor("Facade", snapshot.Facade),
		Roof = lookColor("Roof", snapshot.Roof),
		Pattern = style and tostring(style.Pattern) or "None",
		Garden = type(snapshot.Garden) == "table" and snapshot.Garden or {},
		Rooms = bySlot,
		Name = tostring(snapshot.DisplayName or snapshot.Name or ""),
		Garage = if type(snapshot.Garage) == "boolean" then snapshot.Garage else nil, -- v9.6 🏎️ garage du manoir (CarService)
	}
	local okFacade, built = pcall(HouseFacade.Build, kit, size, looks)
	if not okFacade then
		warn("[World] Façade : " .. tostring(built))
		built = { Fills = {}, Chimneys = 0, Style = WorldLayout.StyleOf(size) }
	end
	local accent = Color3.fromRGB(236, 72, 140)
	local okStairs, stairs = pcall(HouseStairs.Build, kit, size, {
		Wall = Color3.fromRGB(255, 244, 240),
		Trim = CREAM,
		Accent = accent,
	})
	if okStairs then
		self.Ramps = stairs.Ramps
	else
		warn("[World] Escalier : " .. tostring(stairs))
		self.Ramps = {}
	end
	self.Door = built.Door
	self.DoorHinge = built.Hinge
	self.DoorLock = built.Lock
	self.Style = built.Style
	self.Chimneys = built.Chimneys
	self.ExteriorParts = kit.Stats.Count
	self.ExteriorLights = kit.Stats.Lights
	self.Model:SetAttribute("Style", built.Style)
	self.Model:SetAttribute("Chimneys", built.Chimneys)
	self.Model:SetAttribute("ExteriorParts", kit.Stats.Count)
	-- états des pièces (tous les emplacements de la grille)
	for slot = 1, dims.Floors * dims.Columns do
		local room = bySlot[slot]
		local state = self.Rooms[slot]
		if not state then
			state = { Slot = slot, Data = room, Shell = nil, Items = {}, State = "None", Signature = roomSignature(room), Fill = nil, Prompts = {}, Token = 0 }
			self.Rooms[slot] = state
		end
		state.Data = room
		local fill = built.Fills[slot]
		state.Fill = fill
		if fill and state.State ~= "None" then
			fill.Transparency = 1
		end
	end
end

----------------------------------------------------------------------
-- Intérieurs (en flux)
----------------------------------------------------------------------

-- Coque de secours (si House3DScene n'est pas disponible) : sol, murs, plafond
local function fallbackShell(room: any, size: any): Model
	local model = Instance.new("Model")
	model.Name = "RoomShell"
	local W, D, WH, T = WorldLayout.RoomWidth(size), WorldLayout.DEPTH, WorldLayout.WALL_H, WorldLayout.WALL_T
	local wall = wallpaperColor(room)
	local floorStyle = room and Config.HouseFloorsById[room.Floor]
	local floorColor = floorStyle and typeof(floorStyle.A) == "Color3" and floorStyle.A or Color3.fromRGB(220, 200, 240)
	local floorPart = newPart(model, "Floor", Vector3.new(W + 2 * T, 1, D + 2 * T), CFrame.new(0, -0.5, 0), floorColor, nil, true)
	model.PrimaryPart = floorPart
	newPart(model, "WallBack", Vector3.new(W + 2 * T, WH, T), CFrame.new(0, WH / 2, -D / 2 - T / 2), wall, nil, true)
	local pass, passH = WorldLayout.PASS_W, WorldLayout.PASS_H
	for _, sx in ipairs({ -1, 1 }) do
		local x = sx * (W / 2 + T / 2)
		local seg = (D - pass) / 2
		newPart(model, "WallSide", Vector3.new(T, WH, seg), CFrame.new(x, WH / 2, -D / 2 + seg / 2), wall, nil, true)
		newPart(model, "WallSide", Vector3.new(T, WH, seg), CFrame.new(x, WH / 2, D / 2 - seg / 2), wall, nil, true)
		newPart(model, "WallSide", Vector3.new(T, WH - passH, pass), CFrame.new(x, passH + (WH - passH) / 2, 0), wall, nil, true)
	end
	newPart(model, "Ceiling", Vector3.new(W + 2 * T, 0.6, D + 2 * T), CFrame.new(0, WH + 0.3, 0), CREAM, nil, true)
	model.WorldPivot = CFrame.new()
	return model
end

-- Mur avant INTÉRIEUR d'une pièce (la façade vue de dedans) : papier peint
-- autour de la vraie fenêtre, plinthe, corniche, appui, rideaux ; plafonnier
local function roomFront(self: House, shell: Model, room: any, slot: number)
	local size = self.Size
	local floor, column = WorldLayout.SlotCell(size, slot)
	local xMin, xMax, yFloor = WorldLayout.RoomInterior(size, slot)
	local T = WorldLayout.WALL_T
	local kit = HouseKit.new(self.HouseCF, shell, 1)
	local rect = HouseFacade.WindowRect(size, column, floor)
	local paper = wallpaperColor(room)
	local trimEntry = Config.HouseTrimsById and Config.HouseTrimsById[tostring(room and room.Trim or "Cream")]
	local trim = trimEntry and typeof(trimEntry.Color) == "Color3" and trimEntry.Color or CREAM
	local top = yFloor + WorldLayout.WALL_H
	kit:WallX("FrontWall", xMin, xMax, yFloor, top, T, T + 0.12, { rect }, paper, M.SmoothPlastic, { Solid = false, Shadow = false })
	kit:Box("FrontSkirting", xMin, xMax, yFloor, yFloor + 0.7, T + 0.12, T + 0.32, trim, M.SmoothPlastic, { Shadow = false })
	kit:Box("FrontCrown", xMin, xMax, top - 0.5, top, T + 0.12, T + 0.32, trim, M.SmoothPlastic, { Shadow = false })
	kit:Box("InnerSill", rect[1] - 0.5, rect[2] + 0.5, rect[3] - 0.3, rect[3], T, T + 0.7, trim, M.Wood, { Shadow = false })
	-- rideaux (couleur secondaire du papier peint) + tringle
	local style = wallpaperOf(room)
	local curtain = style and typeof(style.B) == "Color3" and style.B or Color3.fromRGB(255, 190, 214)
	kit:Box("CurtainRod", rect[1] - 1.6, rect[2] + 1.6, rect[4] + 0.6, rect[4] + 0.8, T + 0.5, T + 0.7, Color3.fromRGB(246, 196, 84), M.Metal, { Shadow = false })
	for _, sx in ipairs({ -1, 1 }) do
		local x = if sx < 0 then rect[1] - 0.2 else rect[2] + 0.2
		kit:Box("Curtain", x - 1.2, x + 1.2, rect[3] - 0.6, rect[4] + 0.6, T + 0.35, T + 0.7, curtain, M.Fabric, { Shadow = false })
	end
	-- plafonnier : vraie lumière chaude
	local cx = (xMin + xMax) / 2
	local cd = T + WorldLayout.DEPTH * 0.5
	kit:Box("LampCord", cx - 0.06, cx + 0.06, top - 2, top, cd - 0.06, cd + 0.06, Color3.fromRGB(92, 58, 96), M.SmoothPlastic, { Shadow = false })
	kit:CylY("LampShade", cx, top - 2.8, cd, 2.2, 1, trim:Lerp(WHITE, 0.4), M.Fabric, { Shadow = false })
	local bulb = kit:Ball("LampBulb", cx, top - 2.9, cd, 0.8, Color3.fromRGB(255, 236, 190), M.Neon, { Shadow = false })
	-- (v9.6 "flash bang" : portée 30 -> 16, la lumière ne traverse plus 3 pièces ; 0.9 -> 0.75)
	kit:Light(bulb, Color3.fromRGB(255, 226, 184), 16, 0.75)
end

-- (v9.5) crochets : chaque modèle d'objet construit / retiré
local function attachItems(self: House, slot: number, state: RoomState)
	local hook = HouseBuilder.OnItemAttach
	if not hook or not state.Data then
		return
	end
	for _, model in ipairs(state.Items) do
		local index = tonumber(model:GetAttribute("EntryIndex"))
		local entry = index and state.Data.Placed and state.Data.Placed[index]
		if entry then
			local ok, err = pcall(hook, self, slot, model, entry, tostring(model:GetAttribute("ItemId")))
			if not ok then
				warn("[World] OnItemAttach : " .. tostring(err))
			end
		end
	end
end

local function detachItems(self: House, slot: number, state: RoomState)
	local hook = HouseBuilder.OnItemDetach
	if not hook then
		return
	end
	for _, model in ipairs(state.Items) do
		local index = tonumber(model:GetAttribute("EntryIndex"))
		local entry = index and state.Data and state.Data.Placed and state.Data.Placed[index]
		pcall(hook, self, slot, model, entry, tostring(model:GetAttribute("ItemId")))
	end
end

function HouseBuilder.DestroyRoom(self: House, slot: number)
	local state = self.Rooms[slot]
	if not state then
		return
	end
	state.Token += 1
	detachItems(self, slot, state)
	if state.Shell then
		state.Shell:Destroy()
		state.Shell = nil
	end
	for _, prompt in ipairs(state.Prompts) do
		prompt:Destroy()
	end
	table.clear(state.Prompts)
	state.Items = {}
	state.State = "None"
	if state.Fill then
		state.Fill.Transparency = 0
	end
end

-- INVARIANT (après chaque construction) : une seule coque pour cet
-- emplacement dans Interiors, et UN modèle par objet posé ; tout le reste
-- est détruit et compté (attributs StrayShells / DuplicateItems)
function HouseBuilder.EnforceRoom(self: House, slot: number)
	local state = self.Rooms[slot]
	if not state then
		return
	end
	local strays = 0
	for _, child in ipairs(self.Interiors:GetChildren()) do
		if child:GetAttribute("Slot") == slot and child ~= state.Shell then
			strays += 1
			child:Destroy()
		end
	end
	local duplicates = 0
	local shell = state.Shell
	local items = shell and shell:FindFirstChild("Items")
	if items then
		local seen: { [number]: Model } = {}
		local kept: { Model } = {}
		for _, model in ipairs(items:GetChildren()) do
			local index = tonumber(model:GetAttribute("EntryIndex"))
			if model:IsA("Model") and index then
				if seen[index] then
					duplicates += 1
					model:Destroy()
				else
					seen[index] = model :: Model
					table.insert(kept, model :: Model)
				end
			end
		end
		state.Items = kept
	end
	if strays > 0 or duplicates > 0 then
		warn(string.format("[World] Pièce %s : %s coque(s) et %s objet(s) en double retirés", tostring(slot), tostring(strays), tostring(duplicates)))
		self.Model:SetAttribute("StrayShells", (tonumber(self.Model:GetAttribute("StrayShells")) or 0) + strays)
		self.Model:SetAttribute("DuplicateItems", (tonumber(self.Model:GetAttribute("DuplicateItems")) or 0) + duplicates)
	end
end

-- Construit la pièce (coque + objets) ; peut céder la main (appel dans une tâche)
function HouseBuilder.BuildRoom(self: House, slot: number)
	local state = self.Rooms[slot]
	if not state or not self.Alive then
		return
	end
	self:DestroyRoom(slot)
	state.State = "Building"
	state.Token += 1
	local token = state.Token
	local room = state.Data
	local size = self.Size
	local _, column = WorldLayout.SlotCell(size, slot)
	local roomData = room or { Id = "", Slot = slot, Placed = {} }
	local shell: Model? = nil
	if Scene and type(Scene.BuildRoomShell) == "function" then
		local ok, result = pcall(Scene.BuildRoomShell, roomData, size, {
			Scale = WorldLayout.PX,
			Depth = WorldLayout.DEPTH,
			WallHeight = WorldLayout.WALL_H,
			Doors = WorldLayout.RoomDoors(size, column),
			DoorWidth = WorldLayout.PASS_W,
			DoorHeight = WorldLayout.PASS_H,
			Front = false,
			Ceiling = true,
			Patterns = true,
		})
		if ok and typeof(result) == "Instance" and result:IsA("Model") then
			shell = result
		elseif not ok then
			warn("[World] BuildRoomShell : " .. tostring(result))
		end
	end
	if not shell then
		shell = fallbackShell(room, size)
	end
	local s = shell :: Model
	s.Name = "Room_" .. slot
	s:SetAttribute("Slot", slot)
	s:PivotTo(WorldLayout.ShellPivot(self.HouseCF, size, slot))
	local okFront, errFront = pcall(roomFront, self, s, room, slot)
	if not okFront then
		warn("[World] Mur avant : " .. tostring(errFront))
	end
	s.Parent = self.Interiors
	state.Shell = s
	if state.Fill then
		state.Fill.Transparency = 1
	end
	-- pièce vide : panneau "à acheter"
	if not room then
		local sign = newPart(s, "EmptySign", Vector3.new(8, 3, 0.3), WorldLayout.ShellPivot(self.HouseCF, size, slot) * CFrame.new(0, 5, -WorldLayout.DEPTH / 2 + 0.4), WHITE,
			M.SmoothPlastic, false)
		local gui = Instance.new("SurfaceGui")
		gui.Face = Enum.NormalId.Back
		gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
		gui.PixelsPerStud = 40
		gui.LightInfluence = 0.2
		gui.Parent = sign
		local label = Instance.new("TextLabel")
		label.BackgroundTransparency = 1
		label.Size = UDim2.fromScale(0.92, 0.8)
		label.Position = UDim2.fromScale(0.04, 0.1)
		label.Font = Enum.Font.GothamBold
		label.TextScaled = true
		label.TextColor3 = Color3.fromRGB(160, 110, 180)
		label.Text = Locale.T("🚪 Empty room · buy it in 🏠 My house")
		label.Parent = gui
		state.State = "Built"
		self:EnforceRoom(slot)
		return
	end
	-- objets (vrais modèles 3D, placés comme la vue 3D)
	if Scene and type(Scene.PlaceItems) == "function" then
		local ok, models = pcall(Scene.PlaceItems, s, room, { Collide = true, Query = true, Yield = true, Night = self.Night })
		-- (construction dépassée pendant la pause : la coque a déjà été détruite
		-- par DestroyRoom ; on s'assure qu'elle n'est plus nulle part)
		if state.Token ~= token or not self.Alive then
			if state.Shell ~= s then
				s:Destroy()
			end
			return
		end
		if ok and type(models) == "table" then
			state.Items = models
		elseif not ok then
			warn("[World] PlaceItems : " .. tostring(models))
		end
	end
	self:EnforceRoom(slot)
	-- sièges : une invite "S'asseoir" par place assise
	for _, itemModel in ipairs(state.Items) do
		local seatPart = itemModel:FindFirstChild("SeatPart")
		if seatPart and seatPart:IsA("BasePart") then
			local prompt = Instance.new("ProximityPrompt")
			prompt.Name = "SitPrompt"
			prompt.ActionText = Locale.T("Sit")
			local item = HouseCommon and HouseCommon.ItemsById[tostring(itemModel:GetAttribute("ItemId"))]
			prompt.ObjectText = item and Locale.T(item.Name) or ""
			prompt.MaxActivationDistance = 8
			prompt.RequiresLineOfSight = false
			prompt.HoldDuration = 0
			prompt.KeyboardKeyCode = Enum.KeyCode.E
			prompt.Parent = seatPart
			prompt.Triggered:Connect(function()
				local callback = self.OnSeat
				if callback then
					callback(self, slot, itemModel, seatPart :: BasePart)
				end
			end)
			table.insert(state.Prompts, prompt)
		end
	end
	state.State = "Built"
	attachItems(self, slot, state)
	local built = self.OnRoomBuilt
	if built then
		task.spawn(built, self, slot)
	end
end

-- Pièces à meubler / vider selon la distance à `focus` ; renvoie l'emplacement
-- à construire en priorité (ou nil)
function HouseBuilder.NextToBuild(self: House, focus: Vector3): (number?, number)
	local best: number? = nil
	local bestDistance = math.huge
	for slot, state in pairs(self.Rooms) do
		local x, y, d = WorldLayout.RoomCenter(self.Size, slot)
		local distance = (WorldLayout.ToWorld(self.HouseCF, x, y + 4, d) - focus).Magnitude
		if state.State == "None" and distance < NEAR and distance < bestDistance then
			best = slot
			bestDistance = distance
		elseif state.State ~= "None" and distance > FAR then
			self:DestroyRoom(slot)
		end
	end
	return best, bestDistance
end

-- Pièce (emplacement) qui contient un point du monde
function HouseBuilder.RoomAt(self: House, point: Vector3): number?
	local x, y, d = WorldLayout.ToLocal(self.HouseCF, point)
	return WorldLayout.SlotAt(self.Size, x, y, d)
end

-- Porte d'entrée : ouverte si quelqu'un d'autorisé est proche
function HouseBuilder.StepDoor(self: House, open: boolean, locked: boolean)
	local leaf = self.Door
	local hinge = self.DoorHinge
	if not leaf or not hinge then
		return
	end
	local lock = self.DoorLock
	if lock then
		lock.Text = locked and "🔒" or ""
	end
	local want = open and not locked
	if want == self.DoorOpen then
		return
	end
	self.DoorOpen = want
	local closedCF = hinge * CFrame.new(WorldLayout.DOOR_W / 2 - 0.05, (WorldLayout.DOOR_H - 0.05) / 2, 0)
	local target = want and hinge * CFrame.Angles(0, math.rad(100), 0) * CFrame.new(WorldLayout.DOOR_W / 2 - 0.05, (WorldLayout.DOOR_H - 0.05) / 2, 0) or closedCF
	leaf.CanCollide = not want
	local ok = pcall(function()
		TweenService:Create(leaf, TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { CFrame = target }):Play()
	end)
	if not ok then
		leaf.CFrame = target
	end
end

-- Position de la porte (monde) : pour savoir si quelqu'un approche
function HouseBuilder.DoorPosition(self: House): Vector3
	return WorldLayout.ToWorld(self.HouseCF, WorldLayout.DoorX(self.Size), WorldLayout.FloorY(1) + 2, 0)
end

-- Nouvel instantané : extérieur reconstruit si besoin, pièces changées vidées
function HouseBuilder.Update(self: House, snapshot: any)
	self.Snapshot = snapshot
	local newSize = sizeDefOf(snapshot)
	local sizeChanged = newSize ~= self.Size
	self.Size = newSize
	local bySlot = roomsBySlot(snapshot)
	if sizeChanged then
		for slot in pairs(self.Rooms) do
			self:DestroyRoom(slot)
		end
		table.clear(self.Rooms)
	end
	for slot, state in pairs(self.Rooms) do
		local room = bySlot[slot]
		local signature = roomSignature(room)
		if signature ~= state.Signature then
			state.Signature = signature
			state.Data = room
			if state.State ~= "None" then
				self:DestroyRoom(slot)
			end
		end
	end
	if sizeChanged or exteriorKey(snapshot) ~= self.ExteriorKey then
		self:BuildExterior()
	end
end

-- Remplace la liste d'objets d'une pièce (déplacement local, avant la réponse
-- du serveur) et la reconstruit tout de suite
function HouseBuilder.SetRoomPlaced(self: House, slot: number, placed: { any })
	local state = self.Rooms[slot]
	if not state or not state.Data then
		return
	end
	state.Data.Placed = placed
	state.Signature = roomSignature(state.Data)
	task.spawn(function()
		self:BuildRoom(slot)
	end)
end

function HouseBuilder.Signature(room: any): string
	return roomSignature(room)
end

-- État des invariants (tests / diagnostic) : ne répare rien
function HouseBuilder.Audit(self: House): Audit
	local shells: { [number]: number } = {}
	local extraShells = 0
	local count = 0
	for _, child in ipairs(self.Interiors:GetChildren()) do
		local slot = tonumber(child:GetAttribute("Slot"))
		count += 1
		if not slot or not self.Rooms[slot] or self.Rooms[slot].Shell ~= child then
			extraShells += 1
		end
		if slot then
			shells[slot] = (shells[slot] or 0) + 1
		end
	end
	local items, duplicates, missing = 0, 0, 0
	for _, state in pairs(self.Rooms) do
		local shell = state.Shell
		local folder = shell and shell:FindFirstChild("Items")
		if folder then
			local seen: { [number]: boolean } = {}
			for _, model in ipairs(folder:GetChildren()) do
				local index = tonumber(model:GetAttribute("EntryIndex"))
				if index then
					items += 1
					if seen[index] then
						duplicates += 1
					end
					seen[index] = true
				end
			end
			if state.State == "Built" and state.Data and type(state.Data.Placed) == "table" and HouseCommon then
				for index, entry in ipairs(state.Data.Placed) do
					if type(entry) == "table" and HouseCommon.ItemsById[entry.I] and not seen[index] then
						missing += 1
					end
				end
			end
		end
	end
	local houses = 0
	local parent = self.Model.Parent
	if parent then
		for _, child in ipairs(parent:GetChildren()) do
			if child:IsA("Model") and child:GetAttribute("OwnerId") == self.UserId then
				houses += 1
			end
		end
	end
	local expected = HouseFacade.Chimneys[self.Style] or 0
	return {
		OK = extraShells == 0 and duplicates == 0 and missing == 0 and houses == 1 and self.Chimneys == expected,
		Shells = count,
		ExtraShells = extraShells,
		Items = items,
		Duplicates = duplicates,
		Missing = missing,
		Houses = houses,
		Chimneys = self.Chimneys,
		ChimneysExpected = expected,
		Parts = self.ExteriorParts,
		Lights = self.ExteriorLights,
	}
end

function HouseBuilder.Destroy(self: House)
	self.Alive = false
	for slot in pairs(self.Rooms) do
		self:DestroyRoom(slot)
	end
	self.Model:Destroy()
end

return HouseBuilder
