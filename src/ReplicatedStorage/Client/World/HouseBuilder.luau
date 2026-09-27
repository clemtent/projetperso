--[[
	HouseBuilder (ModuleScript)
	Emplacement : ReplicatedStorage > Client > World > HouseBuilder

	🚶 Dopamine Town : construit côté CLIENT la maison 3D d'un joueur sur sa
	parcelle, d'après l'instantané envoyé par WorldService (même données que
	la maison 2D : taille, pièces, façade / toit / motif du toit / jardin v9.1).
	  - EXTÉRIEUR (toujours, ~60 à ~200 Parts) : fondation, façade avec une
	    fenêtre par pièce (vitre + "lumière" de la pièce derrière), porte
	    d'entrée battante (s'ouvre quand on approche, reste fermée et 🔒 si le
	    propriétaire n'accueille pas ce joueur), murs du fond / des côtés,
	    toit à deux pans (couleur + motif), cheminée, perron, allée, jardin
	    (déco choisie dans la maison 2D), plaque au nom du propriétaire ;
	  - CAGE D'ESCALIER à gauche : paliers, trémies et une volée de marches
	    par étage (on monte à pied) ;
	  - INTÉRIEURS en flux (Stream) : seulement les pièces proches du joueur
	    (House3DScene.BuildRoomShell + House3DScene.PlaceItems : vraie coque
	    avec papier peint, moulures, fenêtre du fond, passages vers les pièces
	    voisines et la cage ; vrais meubles 3D, gros meubles solides), une
	    pièce à la fois, sur plusieurs images ; détruites quand on s'éloigne ;
	  - emplacements vides de la grille : pièce vide ("à acheter") pour que
	    les passages mènent toujours quelque part ;
	  - sièges : les modèles avec une "SeatPart" reçoivent une invite
	    ProximityPrompt "S'asseoir" (voir TownClient : le serveur crée le Seat).
	Repère : WorldLayout (maison, pièces, conversions 2D <-> 3D).

	API :
	  HouseBuilder.new(snapshot, plotCF, parent) -> House
	  house:Update(snapshot)            (reconstruit ce qui a changé)
	  house:Stream(focus, budget)       (pièces proches / lointaines)
	  house:StepDoor(near, allowed)     (porte d'entrée)
	  house:RoomAt(worldPoint) -> slot?
	  house:RebuildRoom(slot)           (après un déplacement de meuble)
	  house:Destroy()
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Config = require(ReplicatedStorage.Shared.Config)
local WorldLayout = require(ReplicatedStorage.Shared.WorldLayout)
local Locale = require(ReplicatedStorage.Shared.Locale)

local HouseFolder = script.Parent.Parent.Components.House

local HouseBuilder = {}
HouseBuilder.__index = HouseBuilder

local NEAR = 62 -- (studs) une pièce plus proche que ça est meublée
local FAR = 90 -- plus loin : on la vide
local M = Enum.Material
local WHITE = Color3.new(1, 1, 1)
local CREAM = Color3.fromRGB(255, 247, 236)
local GLASS = Color3.fromRGB(214, 238, 255)
local WOOD = Color3.fromRGB(214, 164, 120)

-- Couleurs par défaut du bâtiment (Config.HouseSizes Exterior)
local FACADES: { [string]: Color3 } = {
	Cottage = Color3.fromRGB(255, 232, 220),
	Townhouse = Color3.fromRGB(236, 224, 255),
	Loft = Color3.fromRGB(214, 228, 242),
	Mansion = Color3.fromRGB(255, 244, 250),
}
local ROOFS: { [string]: Color3 } = {
	Cottage = Color3.fromRGB(236, 118, 150),
	Townhouse = Color3.fromRGB(160, 124, 222),
	Loft = Color3.fromRGB(92, 112, 146),
	Mansion = Color3.fromRGB(118, 168, 238),
}

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
	Fill: BasePart?, -- lumière de la pièce derrière la fenêtre (quand elle est vide)
	Prompts: { ProximityPrompt },
	Token: number,
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

local function lookColor(kind: string, id: any): Color3?
	local byId = Config.HouseLooksById and Config.HouseLooksById[kind]
	local entry = byId and type(id) == "string" and byId[id] or nil
	local color = entry and entry.Color
	return typeof(color) == "Color3" and color or nil
end

local function lookEntry(kind: string, id: any): any
	local byId = Config.HouseLooksById and Config.HouseLooksById[kind]
	return byId and type(id) == "string" and byId[id] or nil
end

local function wallpaperColor(room: any): Color3
	local style = room and Config.HouseWallpapersById[room.Wallpaper]
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
		tostring(snapshot.DisplayName) }
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

local function newPart(parent: Instance, name: string, size: Vector3, cf: CFrame, color: Color3, material: Enum.Material?, collide: boolean?, className: string?): BasePart
	local p = Instance.new((className or "Part") :: any) :: BasePart
	p.Name = name
	p.Anchored = true
	p.Size = Vector3.new(math.max(0.05, size.X), math.max(0.05, size.Y), math.max(0.05, size.Z))
	p.CFrame = cf
	p.Color = color
	p.Material = material or M.SmoothPlastic
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.CanCollide = collide ~= false
	p.CanTouch = false
	p.CanQuery = collide ~= false
	p.Parent = parent
	return p
end

----------------------------------------------------------------------
-- Construction de l'extérieur
----------------------------------------------------------------------

function HouseBuilder.new(snapshot: any, plotCF: CFrame, parent: Instance): House
	modules()
	local model = Instance.new("Model")
	model.Name = "House_" .. tostring(snapshot.UserId)
	local exterior = Instance.new("Folder")
	exterior.Name = "Exterior"
	exterior.Parent = model
	local interiors = Instance.new("Folder")
	interiors.Name = "Interiors"
	interiors.Parent = model
	local self = setmetatable({
		UserId = tonumber(snapshot.UserId) or 0,
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
		OnSeat = nil,
		OnRoomBuilt = nil,
		Night = false,
		Alive = true,
	}, HouseBuilder)
	model:SetAttribute("OwnerId", self.UserId)
	self:BuildExterior()
	model.Parent = parent
	return self
end

-- Mur plein en x (le long de la façade) avec des ouvertures : `holes` =
-- { { x0, x1, y0, y1 } } ; d0..d1 = épaisseur (profondeur) ; y0..y1 = hauteur
local function wallAlongX(house: any, folder: Instance, name: string, x0: number, x1: number, y0: number, y1: number, d0: number, d1: number,
	holes: { { number } }, color: Color3, material: Enum.Material?)
	table.sort(holes, function(a, b)
		return a[1] < b[1]
	end)
	local cursor = x0
	local function block(ax: number, bx: number, ay: number, by: number)
		if bx - ax < 0.05 or by - ay < 0.05 then
			return
		end
		local center = WorldLayout.ToWorld(house.HouseCF, (ax + bx) / 2, (ay + by) / 2, (d0 + d1) / 2)
		newPart(folder, name, Vector3.new(bx - ax, by - ay, d1 - d0), house.HouseCF.Rotation + center, color, material)
	end
	for _, hole in ipairs(holes) do
		local hx0, hx1 = math.max(x0, hole[1]), math.min(x1, hole[2])
		if hx1 > hx0 then
			block(cursor, hx0, y0, y1)
			block(hx0, hx1, y0, math.max(y0, hole[3]))
			block(hx0, hx1, math.min(y1, hole[4]), y1)
			cursor = hx1
		end
	end
	block(cursor, x1, y0, y1)
end

-- Boîte en repère local : x0..x1, y0..y1, d0..d1
local function localBox(house: any, folder: Instance, name: string, x0: number, x1: number, y0: number, y1: number, d0: number, d1: number, color: Color3,
	material: Enum.Material?, collide: boolean?): BasePart
	local center = WorldLayout.ToWorld(house.HouseCF, (x0 + x1) / 2, (y0 + y1) / 2, (d0 + d1) / 2)
	return newPart(folder, name, Vector3.new(math.abs(x1 - x0), math.abs(y1 - y0), math.abs(d1 - d0)), house.HouseCF.Rotation + center, color, material, collide)
end

function HouseBuilder.BuildExterior(self: House)
	local snapshot = self.Snapshot
	local size = self.Size
	local dims = WorldLayout.Dims(size)
	local folder = self.Exterior
	folder:ClearAllChildren()
	self.ExteriorKey = exteriorKey(snapshot)
	self.Door = nil
	self.DoorLock = nil
	local exteriorType = tostring(size.Exterior or "Cottage")
	local facade = lookColor("Facade", snapshot.Facade) or FACADES[exteriorType] or FACADES.Cottage
	local roofColor = lookColor("Roof", snapshot.Roof) or ROOFS[exteriorType] or ROOFS.Cottage
	local trim = WHITE
	local T = WorldLayout.WALL_T
	local left, right = dims.Left, dims.Left + dims.Width
	local depth = dims.Depth
	local height = dims.Height
	local hallX0, hallX1 = WorldLayout.HallSpan(size)
	local doorX = WorldLayout.DoorX(size)
	local roomsBySlot: { [number]: any } = {}
	if type(snapshot.Rooms) == "table" then
		for _, room in ipairs(snapshot.Rooms) do
			if type(room) == "table" and tonumber(room.Slot) then
				roomsBySlot[tonumber(room.Slot) :: number] = room
			end
		end
	end

	-- Fondation (juste sous le dessus des sols)
	localBox(self, folder, "Foundation", left - 0.4, right + 0.4, 0, WorldLayout.SLAB - 0.05, -0.4, depth + 0.4, Color3.fromRGB(226, 214, 230), M.Slate)
	-- Façade : une fenêtre par pièce, porte d'entrée au rez-de-chaussée
	local WIN_W, WIN_H, WIN_Y = 7, 5.5, 3.4
	for floor = 1, dims.Floors do
		local yFloor = WorldLayout.FloorY(floor)
		local y0 = floor == 1 and WorldLayout.SLAB - 0.05 or yFloor - WorldLayout.SLAB
		local y1 = yFloor + WorldLayout.WALL_H
		local holes = {}
		-- cage : porte (rez-de-chaussée) ou petite fenêtre
		if floor == 1 then
			table.insert(holes, { doorX - WorldLayout.DOOR_W / 2, doorX + WorldLayout.DOOR_W / 2, y0, yFloor + WorldLayout.DOOR_H })
		else
			table.insert(holes, { doorX - 2, doorX + 2, yFloor + 4, yFloor + 8 })
		end
		for column = 1, dims.Columns do
			local x0, x1 = WorldLayout.ColumnSpan(size, column)
			local cx = (x0 + x1) / 2
			table.insert(holes, { cx - WIN_W / 2, cx + WIN_W / 2, yFloor + WIN_Y, yFloor + WIN_Y + WIN_H })
		end
		wallAlongX(self, folder, "Facade", left, right, y0, y1, -0.3, T, holes, facade, M.SmoothPlastic)
		-- vitres, rebords, lumière des pièces derrière
		for index, hole in ipairs(holes) do
			local isDoor = floor == 1 and index == 1
			if not isDoor then
				local glass = localBox(self, folder, "Glass", hole[1], hole[2], hole[3], hole[4], 0.35, 0.55, GLASS, M.Glass)
				glass.Transparency = 0.55
				glass.CastShadow = false
				localBox(self, folder, "Sill", hole[1] - 0.5, hole[2] + 0.5, hole[3] - 0.35, hole[3], -0.8, 0.6, trim, M.SmoothPlastic, false)
				localBox(self, folder, "Lintel", hole[1] - 0.3, hole[2] + 0.3, hole[4], hole[4] + 0.35, -0.55, 0, trim, M.SmoothPlastic, false)
				localBox(self, folder, "Mullion", (hole[1] + hole[2]) / 2 - 0.12, (hole[1] + hole[2]) / 2 + 0.12, hole[3], hole[4], 0.2, 0.4, trim, M.SmoothPlastic, false)
				-- (pièce pas encore meublée : on voit une lumière douce de la couleur de la pièce)
				if index > 1 then
					local slot = (floor - 1) * dims.Columns + (index - 1)
					local room = roomsBySlot[slot]
					local fill = localBox(self, folder, "Fill", hole[1] - 0.5, hole[2] + 0.5, hole[3] - 0.5, hole[4] + 0.5, 2.6, 2.8,
						room and wallpaperColor(room) or Color3.fromRGB(240, 236, 244), M.SmoothPlastic, false)
					fill.CastShadow = false
					local state = self.Rooms[slot]
					if not state then
						state = { Slot = slot, Data = room, Shell = nil, Items = {}, State = "None", Signature = roomSignature(room), Fill = nil, Prompts = {}, Token = 0 }
						self.Rooms[slot] = state
					end
					state.Data = room
					state.Fill = fill
					if state.State ~= "None" then
						fill.Transparency = 1
					end
				end
			end
		end
	end
	-- Mur du fond (derrière les coques), bouts gauche / droite (façade)
	localBox(self, folder, "Back", left - 0.3, right + 0.3, WorldLayout.SLAB - 0.05, height, depth - T + 0.05, depth + 0.3, facade)
	localBox(self, folder, "EndLeft", left - 0.3, left + T, WorldLayout.SLAB - 0.05, height, 0, depth, facade)
	localBox(self, folder, "EndRight", right - T + 0.05, right + 0.3, WorldLayout.SLAB - 0.05, height, 0, depth, facade)
	-- Coins et corniche (moulures blanches)
	for _, x in ipairs({ left - 0.3, right + 0.3 }) do
		localBox(self, folder, "Corner", x - 0.35, x + 0.35, WorldLayout.SLAB - 0.05, height, -0.65, 0.3, trim, M.SmoothPlastic, false)
	end
	for floor = 2, dims.Floors do
		local y = WorldLayout.FloorY(floor) - WorldLayout.SLAB
		localBox(self, folder, "Band", left - 0.4, right + 0.4, y - 0.2, y + 0.4, -0.7, -0.25, trim, M.SmoothPlastic, false)
	end
	localBox(self, folder, "Cornice", left - 0.6, right + 0.6, height - 0.1, height + 0.6, -0.9, depth + 0.6, trim)

	-- Cage d'escalier : sols (avec trémie), marches, rampe, plafond
	local stairX0 = hallX0 + T
	local stairX1 = stairX0 + WorldLayout.STAIR_W
	local hallFloor = Color3.fromRGB(236, 214, 196)
	for floor = 1, dims.Floors do
		local yTop = WorldLayout.FloorY(floor)
		local yBottom = yTop - WorldLayout.SLAB
		if floor == 1 then
			localBox(self, folder, "HallFloor", stairX0, hallX1, 0, yTop, T, depth - T, hallFloor, M.WoodPlanks)
		else
			localBox(self, folder, "HallFloor", stairX1, hallX1, yBottom, yTop, T, depth - T, hallFloor, M.WoodPlanks)
			localBox(self, folder, "Landing", stairX0, stairX1, yBottom, yTop, T, WorldLayout.STAIR_HOLE_D0, hallFloor, M.WoodPlanks)
			localBox(self, folder, "Landing", stairX0, stairX1, yBottom, yTop, WorldLayout.STAIR_D1, depth - T, hallFloor, M.WoodPlanks)
		end
		if floor < dims.Floors then
			local steps = 14
			local run = (WorldLayout.STAIR_D1 - WorldLayout.STAIR_D0) / steps
			local rise = WorldLayout.STORY / steps
			for i = 0, steps - 1 do
				local top = yTop + (i + 1) * rise
				local d0 = WorldLayout.STAIR_D0 + i * run
				localBox(self, folder, "Step", stairX0, stairX1, top - 1.1, top, d0, d0 + run + 0.02, i % 2 == 0 and Color3.fromRGB(255, 226, 236) or CREAM, M.WoodPlanks)
			end
			-- rampe (côté couloir), inclinée comme la volée
			local a = WorldLayout.ToWorld(self.HouseCF, stairX1 - 0.2, yTop + 3.2, WorldLayout.STAIR_D0)
			local b = WorldLayout.ToWorld(self.HouseCF, stairX1 - 0.2, yTop + WorldLayout.STORY + 3.2, WorldLayout.STAIR_D1)
			local rail = newPart(folder, "Rail", Vector3.new(0.3, 0.3, (b - a).Magnitude), CFrame.lookAt((a + b) / 2, b), WOOD, M.Wood, false)
			rail.CastShadow = false
			for _, t in ipairs({ 0.15, 0.5, 0.85 }) do
				local p = a:Lerp(b, t)
				newPart(folder, "Baluster", Vector3.new(0.2, 3, 0.2), CFrame.new(p - Vector3.new(0, 1.5, 0)), WHITE, M.SmoothPlastic, false)
			end
		end
	end
	localBox(self, folder, "HallCeiling", stairX0, hallX1, height - 0.6, height, T, depth - T, CREAM)
	-- Porte d'entrée : chambranle, battant (pivote autour de sa charnière), perron, allée
	local doorY0 = WorldLayout.SLAB
	local doorW, doorH = WorldLayout.DOOR_W, WorldLayout.DOOR_H
	for _, sx in ipairs({ -1, 1 }) do
		localBox(self, folder, "DoorFrame", doorX + sx * (doorW / 2) - 0.25, doorX + sx * (doorW / 2) + 0.25, doorY0, doorY0 + doorH + 0.3, -0.7, 0.2, trim, M.Wood, false)
	end
	localBox(self, folder, "DoorFrame", doorX - doorW / 2 - 0.3, doorX + doorW / 2 + 0.3, doorY0 + doorH, doorY0 + doorH + 0.5, -0.7, 0.2, trim, M.Wood, false)
	local doorColor = roofColor:Lerp(Color3.new(0, 0, 0), 0.08)
	local leaf = localBox(self, folder, "DoorLeaf", doorX - doorW / 2 + 0.05, doorX + doorW / 2 - 0.05, doorY0, doorY0 + doorH - 0.05, 0.15, 0.55, doorColor, M.Wood, true)
	-- (charnière au bord gauche ; le battant s'ouvre vers l'intérieur)
	self.DoorHinge = self.HouseCF * CFrame.new(doorX - doorW / 2 + 0.05, doorY0, -0.35)
	self.Door = leaf
	local knob = newPart(folder, "DoorKnob", Vector3.new(0.35, 0.35, 0.35), leaf.CFrame * CFrame.new(doorW / 2 - 0.7, -0.2, 0.3), Color3.fromRGB(255, 214, 110), M.Metal, false)
	;(knob :: Part).Shape = Enum.PartType.Ball
	local weld = Instance.new("WeldConstraint")
	weld.Part0 = leaf
	weld.Part1 = knob
	weld.Parent = leaf
	knob.Anchored = false
	-- 🔒 sur la porte (visible quand le propriétaire ne reçoit pas ce joueur)
	local lockGui = Instance.new("SurfaceGui")
	lockGui.Name = "Lock"
	lockGui.Face = Enum.NormalId.Back
	lockGui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	lockGui.PixelsPerStud = 30
	lockGui.LightInfluence = 0
	lockGui.MaxDistance = 120
	lockGui.Parent = leaf
	local lock = Instance.new("TextLabel")
	lock.Name = "Text"
	lock.BackgroundTransparency = 1
	lock.Size = UDim2.fromScale(1, 0.3)
	lock.Position = UDim2.fromScale(0, 0.25)
	lock.Font = Enum.Font.GothamBold
	lock.Text = ""
	lock.TextScaled = true
	lock.TextColor3 = WHITE
	lock.Parent = lockGui
	self.DoorLock = lock
	localBox(self, folder, "Porch", doorX - 4, doorX + 4, 0, WorldLayout.SLAB - 0.06, -3.2, 0, Color3.fromRGB(255, 236, 226), M.Slate)
	-- allée : de l'allée de la parcelle (x = 0) jusqu'au perron
	local pathX0, pathX1 = math.min(0, doorX) - 2.5, math.max(0, doorX) + 2.5
	localBox(self, folder, "Walkway", pathX0, pathX1, 0.4, 0.52, -6.5, -3.2, Color3.fromRGB(255, 240, 222), M.Pebble, false)
	-- plaque au nom du propriétaire au-dessus de la porte
	local plate = localBox(self, folder, "NamePlate", doorX - 4, doorX + 4, doorY0 + doorH + 0.7, doorY0 + doorH + 2.3, -0.75, -0.35, WHITE, M.SmoothPlastic, false)
	local plateGui = Instance.new("SurfaceGui")
	plateGui.Name = "Name"
	plateGui.Face = Enum.NormalId.Back
	plateGui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	plateGui.PixelsPerStud = 40
	plateGui.LightInfluence = 0.3
	plateGui.MaxDistance = 220
	plateGui.Parent = plate
	local plateText = Instance.new("TextLabel")
	plateText.BackgroundTransparency = 1
	plateText.Size = UDim2.fromScale(0.94, 0.86)
	plateText.Position = UDim2.fromScale(0.03, 0.07)
	plateText.Font = Enum.Font.FredokaOne
	plateText.TextScaled = true
	plateText.TextColor3 = Color3.fromRGB(236, 72, 140)
	plateText.Text = "🏠 " .. tostring(snapshot.DisplayName or snapshot.Name or "")
	plateText.Parent = plateGui

	-- Toit à deux pans (faîte le long de la façade) + motif + cheminée
	local roofH = WorldLayout.ROOF_H + (dims.Floors - 1) * 0.8
	local roofW = dims.Width + 2
	local half = depth / 2 + 1
	local roofY = height + 0.6
	local frontCF = self.HouseCF * CFrame.new(0, roofY + roofH / 2, -(-1 + half / 2)) * CFrame.Angles(0, math.pi, 0)
	local backCF = self.HouseCF * CFrame.new(0, roofY + roofH / 2, -(depth / 2 + half / 2))
	local frontRoof = newPart(folder, "Roof", Vector3.new(roofW, roofH, half), frontCF, roofColor, M.SmoothPlastic, true, "WedgePart")
	newPart(folder, "Roof", Vector3.new(roofW, roofH, half), backCF, roofColor, M.SmoothPlastic, true, "WedgePart")
	local accent = roofColor:Lerp(WHITE, 0.45)
	newPart(folder, "Ridge", Vector3.new(roofW + 0.4, 0.6, 0.9), self.HouseCF * CFrame.new(0, roofY + roofH + 0.1, -depth / 2), accent, M.SmoothPlastic, false)
	local chimney = self.HouseCF * CFrame.new(right - 6, roofY + roofH * 0.55, -(depth * 0.72))
	newPart(folder, "Chimney", Vector3.new(2.6, roofH * 0.9, 2.6), chimney, Color3.fromRGB(214, 150, 150), M.Brick, false)
	newPart(folder, "ChimneyCap", Vector3.new(3.2, 0.5, 3.2), chimney * CFrame.new(0, roofH * 0.45 + 0.25, 0), CREAM, M.SmoothPlastic, false)
	-- motif du toit (RoofStyle.Pattern) : petits reliefs sur le pan avant
	local style = lookEntry("RoofStyle", snapshot.RoofStyle)
	local pattern = style and tostring(style.Pattern) or "None"
	if pattern ~= "None" then
		local slope = math.atan2(roofH, half)
		local motifColor = ({
			Hearts = Color3.fromRGB(255, 110, 170),
			Dots = WHITE,
			Stripes = Color3.fromRGB(255, 255, 255),
			Stars = Color3.fromRGB(255, 226, 110),
			Flowers = Color3.fromRGB(255, 170, 214),
			Snow = WHITE,
			Scales = Color3.fromRGB(120, 220, 214),
			Checkered = Color3.fromRGB(40, 40, 50),
			Bolts = Color3.fromRGB(255, 214, 60),
			Camo = Color3.fromRGB(96, 120, 80),
			Flames = Color3.fromRGB(255, 120, 50),
		} :: { [string]: Color3 })[pattern] or accent
		local count = math.clamp(math.floor(roofW / 7), 3, 16)
		for row = 1, 2 do
			for i = 1, count do
				local x = -roofW / 2 + (i - 0.5) * roofW / count + (row == 2 and roofW / count / 2 or 0)
				if x < roofW / 2 - 1 then
					local u = row == 1 and 0.3 or 0.62
					-- point sur la pente (repère du pan avant : -Z = bas du toit)
					local onSlope = frontCF * CFrame.new(-x, -roofH / 2 + u * roofH, -half / 2 + u * half) * CFrame.Angles(-slope, 0, 0)
					local shape = (pattern == "Stripes" or pattern == "Snow" or pattern == "Checkered") and Vector3.new(roofW / count * 0.5, 0.25, 1.4)
						or Vector3.new(1.2, 0.3, 1.2)
					local bump = newPart(folder, "RoofMotif", shape, onSlope * CFrame.new(0, 0.15, 0), motifColor,
						(pattern == "Stars" or pattern == "Bolts" or pattern == "Flames") and M.Neon or M.SmoothPlastic, false)
					bump.CastShadow = false
					if pattern == "Dots" or pattern == "Hearts" or pattern == "Flowers" or pattern == "Stars" then
						local ballPart = bump :: Part
						ballPart.Shape = Enum.PartType.Ball
						ballPart.Size = Vector3.new(1.1, 1.1, 1.1)
					end
				end
			end
		end
	end
	frontRoof:SetAttribute("Roof", true)

	-- Jardin : déco choisie (6 max), buissons fleuris le long de la façade
	local garden = type(snapshot.Garden) == "table" and snapshot.Garden or {}
	local spots = { -18, 18, -30, 30, -42, 42 }
	for index, id in ipairs(garden) do
		local entry = lookEntry("Garden", id)
		if entry and spots[index] then
			local x = math.clamp(spots[index], left + 4, right - 4)
			local d = -12 - (index % 2) * 6
			local base = WorldLayout.ToWorld(self.HouseCF, x, 0.4, d)
			local mound = newPart(folder, "GardenMound", Vector3.new(0.8, 5, 5), CFrame.new(base + Vector3.new(0, 0.3, 0)) * CFrame.Angles(0, 0, math.rad(90)),
				Color3.fromRGB(150, 210, 140), M.Grass, false)
			;(mound :: Part).Shape = Enum.PartType.Cylinder
			local billboard = Instance.new("BillboardGui")
			billboard.Name = "GardenDecor"
			billboard.Size = UDim2.fromScale(5, 5)
			billboard.StudsOffsetWorldSpace = Vector3.new(0, 2.8, 0)
			billboard.MaxDistance = 160
			billboard.LightInfluence = 0
			billboard.Adornee = mound
			billboard.Parent = mound
			local icon = Instance.new("TextLabel")
			icon.BackgroundTransparency = 1
			icon.Size = UDim2.fromScale(1, 1)
			icon.Font = Enum.Font.GothamBold
			icon.TextScaled = true
			icon.Text = tostring(entry.Icon or "🌷")
			icon.Parent = billboard
		end
	end
	local bushColors = { Color3.fromRGB(140, 214, 150), Color3.fromRGB(255, 190, 220), Color3.fromRGB(196, 176, 250) }
	local bushCount = math.clamp(math.floor(dims.Width / 14), 2, 10)
	for i = 1, bushCount do
		local x = left + (i - 0.5) * dims.Width / bushCount
		if math.abs(x - doorX) > 5 then
			local p = WorldLayout.ToWorld(self.HouseCF, x, 1.2, -1.6)
			local bush = newPart(folder, "Bush", Vector3.new(2.8, 2.4, 2.4), CFrame.new(p), bushColors[i % #bushColors + 1], M.SmoothPlastic, false)
			;(bush :: Part).Shape = Enum.PartType.Ball
		end
	end
end

----------------------------------------------------------------------
-- Intérieurs (en flux)
----------------------------------------------------------------------

local function roomDoors(size: any, slot: number): { string }
	local dims = WorldLayout.Dims(size)
	local _, column = WorldLayout.SlotCell(size, slot)
	local doors = { "Left" }
	if column < dims.Columns then
		table.insert(doors, "Right")
	end
	return doors
end

-- Coque de secours (si House3DScene n'est pas disponible) : sol, murs, plafond
local function fallbackShell(room: any, size: any): Model
	local model = Instance.new("Model")
	model.Name = "RoomShell"
	local W, D, WH, T = WorldLayout.RoomWidth(size), WorldLayout.DEPTH, WorldLayout.WALL_H, WorldLayout.WALL_T
	local wall = wallpaperColor(room)
	local floorStyle = room and Config.HouseFloorsById[room.Floor]
	local floorColor = floorStyle and typeof(floorStyle.A) == "Color3" and floorStyle.A or Color3.fromRGB(220, 200, 240)
	local floorPart = newPart(model, "Floor", Vector3.new(W + 2 * T, 1, D + 2 * T), CFrame.new(0, -0.5, 0), floorColor)
	model.PrimaryPart = floorPart
	newPart(model, "WallBack", Vector3.new(W + 2 * T, WH, T), CFrame.new(0, WH / 2, -D / 2 - T / 2), wall)
	local pass, passH = WorldLayout.PASS_W, WorldLayout.PASS_H
	for _, sx in ipairs({ -1, 1 }) do
		local x = sx * (W / 2 + T / 2)
		local seg = (D - pass) / 2
		newPart(model, "WallSide", Vector3.new(T, WH, seg), CFrame.new(x, WH / 2, -D / 2 + seg / 2), wall)
		newPart(model, "WallSide", Vector3.new(T, WH, seg), CFrame.new(x, WH / 2, D / 2 - seg / 2), wall)
		newPart(model, "WallSide", Vector3.new(T, WH - passH, pass), CFrame.new(x, passH + (WH - passH) / 2, 0), wall)
	end
	newPart(model, "Ceiling", Vector3.new(W + 2 * T, 0.6, D + 2 * T), CFrame.new(0, WH + 0.3, 0), CREAM)
	model.WorldPivot = CFrame.new()
	return model
end

function HouseBuilder.DestroyRoom(self: House, slot: number)
	local state = self.Rooms[slot]
	if not state then
		return
	end
	state.Token += 1
	if state.Shell then
		state.Shell:Destroy()
		state.Shell = nil
	end
	for _, prompt in ipairs(state.Prompts) do
		prompt:Destroy()
	end
	table.clear(state.Prompts)
	table.clear(state.Items)
	state.State = "None"
	if state.Fill then
		state.Fill.Transparency = 0
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
	local roomData = room or { Id = "", Slot = slot, Placed = {} }
	local shell: Model? = nil
	if Scene and type(Scene.BuildRoomShell) == "function" then
		local ok, result = pcall(Scene.BuildRoomShell, roomData, size, {
			Scale = WorldLayout.PX,
			Depth = WorldLayout.DEPTH,
			WallHeight = WorldLayout.WALL_H,
			Doors = roomDoors(size, slot),
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
	s.Parent = self.Interiors
	state.Shell = s
	if state.Fill then
		state.Fill.Transparency = 1
	end
	-- pièce vide : panneau "à acheter"
	if not room then
		local sign = newPart(s, "EmptySign", Vector3.new(8, 3, 0.3), WorldLayout.ShellPivot(self.HouseCF, size, slot) * CFrame.new(0, 5, -WorldLayout.DEPTH / 2 + 0.4), WHITE, M.SmoothPlastic, false)
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
		return
	end
	-- objets (vrais modèles 3D, placés comme la vue 3D)
	if Scene and type(Scene.PlaceItems) == "function" then
		local ok, models = pcall(Scene.PlaceItems, s, room, { Collide = true, Query = true, Yield = true, Night = self.Night })
		if state.Token ~= token or not self.Alive then
			return
		end
		if ok and type(models) == "table" then
			state.Items = models
		elseif not ok then
			warn("[World] PlaceItems : " .. tostring(models))
		end
	end
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
	return WorldLayout.ToWorld(self.HouseCF, WorldLayout.DoorX(self.Size), 3, 0)
end

-- Nouvel instantané : extérieur reconstruit si besoin, pièces changées vidées
function HouseBuilder.Update(self: House, snapshot: any)
	self.Snapshot = snapshot
	local newSize = sizeDefOf(snapshot)
	local sizeChanged = newSize ~= self.Size
	self.Size = newSize
	local bySlot: { [number]: any } = {}
	if type(snapshot.Rooms) == "table" then
		for _, room in ipairs(snapshot.Rooms) do
			if type(room) == "table" and tonumber(room.Slot) then
				bySlot[tonumber(room.Slot) :: number] = room
			end
		end
	end
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

function HouseBuilder.Destroy(self: House)
	self.Alive = false
	for slot in pairs(self.Rooms) do
		self:DestroyRoom(slot)
	end
	self.Model:Destroy()
end

return HouseBuilder
