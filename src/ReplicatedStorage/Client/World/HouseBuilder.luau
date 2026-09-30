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
	(v9.8 HOUSE98) :
	  - porte d'entrée DOUBLE (6,5 x 9,5) et porte de DERRIÈRE vers le jardin
	    (s'ouvre toute seule quand quelqu'un approche, fermée si 🔒) ;
	  - VRAIES fenêtres des deux côtés (le mur du fond de chaque pièce est
	    percé : on voit le jardin) ;
	  - 🪟 rideaux animés sur chaque fenêtre (devant + fond) et 💡 un
	    interrupteur mural par pièce (près du passage vers la cage) : le
	    propriétaire clique (invites "Fermer les rideaux" / "Éteindre") ->
	    animation tout de suite + sauvegarde (House "setRoomState") ; tout le
	    monde voit l'état (attributs du propriétaire "HouseLightsOff" /
	    "HouseCurtainsClosed", HouseService) ; l'interrupteur commande le
	    plafonnier ET les lampes posées dans la pièce ;
	  house:ToggleRoom(slot, "Lights" | "Curtains") ; house:BackDoorPosition()
	(v9.9 HOUSE99) :
	  - HALL / ESCALIER refaits (HouseStairs) : l'escalier longe le mur de
	    droite, couloir d'entrée libre et meublé ; la COQUE du hall (sols,
	    murs) est construite avec l'extérieur, l'INTÉRIEUR du hall (escalier,
	    meubles, lampes) en flux comme une pièce : NextToBuild renvoie 0 pour
	    le hall, BuildRoom(0) / DestroyRoom(0) (aucun changement pour TownClient) ;
	  - manoir : le passage de la cage vers les pièces de DROITE est au fond
	    (WorldLayout.PassageSpan) : la coque de la pièce est percée là ;
	  - 💡 fenêtres qui BRILLENT la nuit, vues de dehors, quand la lumière de
	    la pièce est allumée (état du propriétaire : pareil pour tout le
	    monde), même si la pièce n'est pas construite ; teinte des rideaux
	    s'ils sont fermés ; les fenêtres du hall brillent toute la nuit ;
	  - rideaux réalistes jusqu'au sol (HouseToggles) ; touches : E pour les
	    rideaux ET pour l'interrupteur (plus de G / Q).
	(v10 HOUSE10) :
	  - 🏡 extérieur PERSONNALISÉ (Shared/HouseOptions) : instantané .Ext ou
	    attribut répliqué "HouseExt" du propriétaire (changé en direct :
	    l'extérieur est reconstruit, les pièces aussi car leurs fenêtres
	    suivent la façade : HouseFacade.WindowRects) ;
	  - NIVEAUX DE DÉTAIL (50 maisons) choisis ici, dans StepDoor (appelé
	    par TownClient pour chaque maison) : "Full" (extérieur complet, à
	    moins de LOD_FULL x GraphicsQuality.DetailScale() de la caméra),
	    "Mid" (HouseLod, jusqu'à LOD_MID x ...), "Far" (imposteur) ; marge
	    anti-battement ; au plus UNE construction complète toutes les
	    FULL_GAP secondes ; pièces / hall seulement en "Full" (BuildRoom
	    repasse en "Full" tout de suite si besoin) ;
	    house:HoldFull(true) (CONSTRUCT10 : animation de construction) force
	    le complet tout de suite et bloque le LOD ; house:SetLod(niveau) ;
	    house.Lod ; attribut "Lod" du modèle.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Players = game:GetService("Players")
local Lighting = game:GetService("Lighting")

local Config = require(ReplicatedStorage.Shared.Config)
local WorldLayout = require(ReplicatedStorage.Shared.WorldLayout)
local Locale = require(ReplicatedStorage.Shared.Locale)
local Net = require(ReplicatedStorage.Shared.Net)
local HouseKit = require(script.Parent.HouseKit)
local HouseFacade = require(script.Parent.HouseFacade)
local HouseStairs = require(script.Parent.HouseStairs)
local HouseToggles = require(script.Parent.HouseToggles)
local HouseOptions = require(ReplicatedStorage.Shared.HouseOptions) -- (v10 HOUSE10) 🏡 extérieur personnalisé
local GraphicsQuality = require(ReplicatedStorage.Shared.GraphicsQuality)
local HouseLod = require(script.Parent.HouseLod) -- (v10 HOUSE10) maisons lointaines

local HouseFolder = script.Parent.Parent.Components.House

local HouseBuilder = {}
HouseBuilder.__index = HouseBuilder

-- (v9.5) crochets facultatifs : un modèle d'objet vient d'être construit /
-- va disparaître (house, slot, model, entry, itemId)
HouseBuilder.OnItemAttach = nil :: ((house: any, slot: number, model: Model, entry: any, itemId: string) -> ())?
HouseBuilder.OnItemDetach = nil :: ((house: any, slot: number, model: Model, entry: any, itemId: string) -> ())?

-- (v10) Niveaux de détail : distances de base (x GraphicsQuality.DetailScale())
HouseBuilder.LOD_FULL = 250
HouseBuilder.LOD_MID = 600
local LOD_MARGIN = 25 -- (studs) marge anti-battement
local LOD_INTERVAL = 0.3 -- (s) contrôle du LOD d'une maison
local FULL_GAP = 0.2 -- (s) entre deux constructions complètes (toutes maisons)
local lastFullBuild = -math.huge

local NEAR = 62 -- (studs) une pièce plus proche que ça est meublée
local FAR = 90 -- plus loin : on la vide
local BACK_RANGE = 8.5 -- (v9.8, studs) la porte de derrière s'ouvre quand un avatar est plus près
local DOOR_SWING = math.rad(100)
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
	BackFill: BasePart?, -- (v9.8) idem, fenêtre du fond (côté jardin)
	Prompts: { ProximityPrompt },
	Token: number,
	Toggles: RoomToggles?, -- (v9.8) rideaux / interrupteur / lumières de la pièce construite
}

-- (v9.8 HOUSE98) ce qui s'allume / s'ouvre dans une pièce construite
export type RoomToggles = {
	Curtains: { any },
	Switch: any?,
	Lights: any,
	CurtainsOpen: boolean,
	LightsOn: boolean,
	CurtainPrompts: { ProximityPrompt },
	SwitchPrompt: ProximityPrompt?,
}

-- (v9.9 HOUSE99) intérieur du hall (escalier, meubles, lampes), en flux
export type HallState = { State: string, Model: Model?, Ramps: { BasePart }, Parts: number }

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
	Leaves: { any }, -- (v9.8) battants de la porte d'entrée (HouseFacade.Leaf)
	BackLeaves: { any }, -- (v9.8) battants de la porte de derrière
	BackDoorOpen: boolean,
	FlagKey: string, -- (v9.8) attributs 💡 / 🪟 du propriétaire déjà appliqués
	Ramps: { BasePart },
	Hall: HallState, -- (v9.9) intérieur du hall en flux
	Glows: { [number]: { any } }, -- (v9.9) lueurs de nuit des fenêtres (HouseFacade.Glow ; 0 = cage)
	GlowKey: string,
	Style: string,
	Chimneys: number,
	ChimneysExpected: number?, -- (v10) cheminées voulues (option "Chimney")
	Lod: string, -- (v10) "Full" | "Mid" | "Far"
	Hold: boolean, -- (v10) HoldFull : pas de changement de LOD
	LodAt: number,
	ExtText: string, -- (v10) options d'extérieur appliquées (HouseOptions.Encode)
	Spec: any?, -- (v10) look résolu de l'extérieur (HouseFacade.Resolve)
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

-- (v10 HOUSE10) Options d'extérieur : instantané (Ext) sinon attribut
-- répliqué du propriétaire "HouseExt" (HouseService) ; (table, texte)
local function extOf(snapshot: any): ({ [string]: any }, string)
	if type(snapshot) == "table" and type(snapshot.Ext) == "table" then
		local text = HouseOptions.Encode(snapshot.Ext)
		return HouseOptions.Decode(text), text
	end
	local owner = type(snapshot) == "table" and Players:GetPlayerByUserId(tonumber(snapshot.UserId) or 0) or nil
	local text = owner and owner:GetAttribute("HouseExt")
	if type(text) ~= "string" then
		text = ""
	end
	return HouseOptions.Decode(text), text :: string
end

local function exteriorKey(snapshot: any): string
	local _, extText = extOf(snapshot)
	local parts = { extText, tostring(snapshot.Size), tostring(snapshot.Facade), tostring(snapshot.Roof), tostring(snapshot.RoofStyle), tostring(snapshot.Plot),
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

-- (v9.8) Battants d'une porte double (HouseFacade.Leaf) : ouverts / fermés,
-- en tournant autour de leurs gonds (Sign = sens de rotation)
local function swingLeaves(leaves: { any }, open: boolean)
	for _, leaf in ipairs(leaves) do
		local part: BasePart = leaf.Part
		if part.Parent then
			local offset = CFrame.new(leaf.Sign * leaf.Width / 2, leaf.Height / 2, 0)
			local target = if open then leaf.Hinge * CFrame.Angles(0, leaf.Sign * DOOR_SWING, 0) * offset else leaf.Hinge * offset
			part.CanCollide = not open
			local ok = pcall(function()
				TweenService:Create(part, TweenInfo.new(0.45, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { CFrame = target }):Play()
			end)
			if not ok then
				part.CFrame = target
			end
		end
	end
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
		Leaves = {},
		BackLeaves = {},
		BackDoorOpen = false,
		FlagKey = "",
		Ramps = {},
		Hall = { State = "None", Model = nil, Ramps = {}, Parts = 0 },
		Glows = {},
		GlowKey = "",
		Style = "Cottage",
		Chimneys = 0,
		ChimneysExpected = nil,
		Spec = nil,
		Lod = "Full",
		Hold = false,
		LodAt = -math.huge,
		ExtText = "",
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
	-- (v10) niveau de détail de départ (sa propre maison : toujours complète)
	local level = if userId == (Players.LocalPlayer and Players.LocalPlayer.UserId) then "Full" else self:WantedLod()
	if level == "Full" then
		self:BuildExterior()
	else
		self:BuildLite(level)
	end
	model.Parent = parent
	return self
end

-- Apparence de l'instantané (couleurs 2D, jardin, nom, options d'extérieur)
local function looksOf(snapshot: any): HouseFacade.Looks
	local style = lookEntry("RoofStyle", snapshot.RoofStyle)
	return {
		Wall = lookColor("Facade", snapshot.Facade),
		Roof = lookColor("Roof", snapshot.Roof),
		Pattern = style and tostring(style.Pattern) or "None",
		Garden = type(snapshot.Garden) == "table" and snapshot.Garden or {},
		Rooms = roomsBySlot(snapshot),
		Name = tostring(snapshot.DisplayName or snapshot.Name or ""),
		Garage = if type(snapshot.Garage) == "boolean" then snapshot.Garage else nil, -- v9.6 🏎️ garage du manoir (CarService)
		Ext = (extOf(snapshot)), -- (v10 HOUSE10) 🏡 options d'extérieur
		Plot = tonumber(snapshot.Plot),
	}
end

function HouseBuilder.BuildExterior(self: House)
	local snapshot = self.Snapshot
	local size = self.Size
	local dims = WorldLayout.Dims(size)
	local folder = self.Exterior
	folder:ClearAllChildren()
	self.ExteriorKey = exteriorKey(snapshot)
	self.ExtText = select(2, extOf(snapshot))
	self.Lod = "Full"
	self.Model:SetAttribute("Lod", "Full")
	lastFullBuild = os.clock()
	self.Door = nil
	self.DoorHinge = nil
	self.DoorLock = nil
	self.DoorOpen = false
	local bySlot = roomsBySlot(snapshot)
	local kit = HouseKit.new(self.HouseCF, folder, 6)
	local looks = looksOf(snapshot)
	looks.Rooms = bySlot
	local oldKey = self.Spec and self.Spec.Key
	local okFacade, built = pcall(HouseFacade.Build, kit, size, looks)
	if not okFacade then
		warn("[World] Façade : " .. tostring(built))
		built = { Fills = {}, Chimneys = 0, Style = WorldLayout.StyleOf(size) }
	end
	-- (v10) le look a changé (fenêtres de la façade) : les pièces construites sont refaites
	if oldKey and built.Spec and built.Spec.Key ~= oldKey then
		for slot in pairs(self.Rooms) do
			self:DestroyRoom(slot)
		end
	end
	-- (v9.9) coque du hall (sols, trémies, murs) ; son intérieur est en flux
	kit.Stats.Phase = "Walls"
	local okStairs, stairs = pcall(HouseStairs.BuildShell, kit, size)
	kit.Stats.Phase = nil
	if not okStairs then
		warn("[World] Hall : " .. tostring(stairs))
	end
	self:DestroyHall()
	self.Ramps = {}
	self.Glows = built.Glows or {}
	self.GlowKey = ""
	self.Door = built.Door
	self.DoorHinge = built.Hinge
	self.DoorLock = built.Lock
	self.Leaves = built.Leaves or {}
	self.BackLeaves = built.BackLeaves or {}
	self.BackDoorOpen = false
	self.Style = built.Style
	self.Chimneys = built.Chimneys
	self.ChimneysExpected = built.ChimneysExpected or built.Chimneys
	self.Spec = built.Spec
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
			state = { Slot = slot, Data = room, Shell = nil, Items = {}, State = "None", Signature = roomSignature(room), Fill = nil, BackFill = nil, Prompts = {}, Token = 0,
				Toggles = nil }
			self.Rooms[slot] = state
		end
		state.Data = room
		local fill = built.Fills[slot]
		state.Fill = fill
		if fill and state.State ~= "None" then
			fill.Transparency = 1
		end
		local backFill = built.BackFills and built.BackFills[slot]
		state.BackFill = backFill
		if backFill and state.State ~= "None" then
			backFill.Transparency = 1
		end
	end
end

----------------------------------------------------------------------
-- (v10 HOUSE10) Niveaux de détail
----------------------------------------------------------------------

-- Extérieur SIMPLIFIÉ ("Mid" / "Far") : pas de pièces, pas de hall, pas de porte
function HouseBuilder.BuildLite(self: House, level: string)
	local snapshot = self.Snapshot
	for slot in pairs(self.Rooms) do
		self:DestroyRoom(slot)
	end
	self:DestroyHall()
	local folder = self.Exterior
	folder:ClearAllChildren()
	self.ExteriorKey = exteriorKey(snapshot)
	self.ExtText = select(2, extOf(snapshot))
	self.Lod = level
	self.Model:SetAttribute("Lod", level)
	self.Door = nil
	self.DoorHinge = nil
	self.DoorLock = nil
	self.DoorOpen = false
	self.Leaves = {}
	self.BackLeaves = {}
	self.BackDoorOpen = false
	self.Ramps = {}
	local kit = HouseKit.new(self.HouseCF, folder, 0)
	local looks = looksOf(snapshot)
	looks.Rooms = roomsBySlot(snapshot)
	local ok, result = pcall(HouseLod.Build, kit, self.Size, looks, level)
	if not ok then
		warn("[World] LOD : " .. tostring(result))
		result = { Glows = {}, Style = WorldLayout.StyleOf(self.Size), Arch = "Classic" }
	end
	self.Glows = result.Glows
	self.GlowKey = ""
	self.ExteriorParts = kit.Stats.Count
	self.ExteriorLights = 0
	self.Model:SetAttribute("ExteriorParts", kit.Stats.Count)
	local dims = WorldLayout.Dims(self.Size)
	local bySlot = roomsBySlot(snapshot)
	for slot = 1, dims.Floors * dims.Columns do
		local state = self.Rooms[slot]
		if not state then
			state = { Slot = slot, Data = bySlot[slot], Shell = nil, Items = {}, State = "None", Signature = roomSignature(bySlot[slot]), Fill = nil, BackFill = nil, Prompts = {},
				Token = 0, Toggles = nil }
			self.Rooms[slot] = state
		end
		state.Data = bySlot[slot]
		state.Fill = nil
		state.BackFill = nil
	end
end

-- Distance (plan horizontal) de la caméra au centre de la maison
local function cameraDistance(self: House): number
	local camera = workspace.CurrentCamera
	if not camera then
		return 0
	end
	local dims = WorldLayout.Dims(self.Size)
	local center = WorldLayout.ToWorld(self.HouseCF, 0, 10, dims.Depth / 2)
	local offset = camera.CFrame.Position - center
	return Vector3.new(offset.X, 0, offset.Z).Magnitude
end

-- Niveau voulu (avec la marge anti-battement autour du niveau actuel)
function HouseBuilder.WantedLod(self: House): string
	if self.Hold then
		return "Full"
	end
	local scale = 1
	local okScale, value = pcall(GraphicsQuality.DetailScale)
	if okScale and type(value) == "number" and value > 0 then
		scale = value
	end
	local distance = cameraDistance(self)
	local full, mid = HouseBuilder.LOD_FULL * scale, HouseBuilder.LOD_MID * scale
	local current = self.Lod
	-- (on garde le niveau le plus détaillé tant qu'on n'est pas franchement au-delà)
	if distance < full - (if current == "Full" then -LOD_MARGIN else LOD_MARGIN) then
		return "Full"
	end
	if distance < mid - (if current ~= "Far" then -LOD_MARGIN else LOD_MARGIN) then
		return "Mid"
	end
	return "Far"
end

function HouseBuilder.SetLod(self: House, level: string)
	if not self.Alive or level == self.Lod then
		return
	end
	if level == "Full" then
		self:BuildExterior()
	else
		self:BuildLite(level)
	end
end

-- Contrôle du LOD (StepDoor) ; force = sans attendre ni respecter FULL_GAP
function HouseBuilder.StepLod(self: House, force: boolean?)
	local now = os.clock()
	if not force and now - self.LodAt < LOD_INTERVAL then
		return
	end
	self.LodAt = now
	local wanted = self:WantedLod()
	if wanted == self.Lod then
		return
	end
	if wanted == "Full" and not force and now - lastFullBuild < FULL_GAP then
		return
	end
	self:SetLod(wanted)
end

-- (CONSTRUCT10) extérieur complet tout de suite et LOD bloqué tant que `on`
function HouseBuilder.HoldFull(self: House, on: boolean)
	self.Hold = on == true
	if self.Hold and self.Lod ~= "Full" then
		self:SetLod("Full")
	end
end

----------------------------------------------------------------------
-- Intérieurs (en flux)
----------------------------------------------------------------------

-- Coque de secours (si House3DScene n'est pas disponible) : sol, murs, plafond
local function fallbackShell(room: any, size: any, column: number): Model
	local model = Instance.new("Model")
	model.Name = "RoomShell"
	local W, D, WH, T = WorldLayout.RoomWidth(size), WorldLayout.DEPTH, WorldLayout.WALL_H, WorldLayout.WALL_T
	local wall = wallpaperColor(room)
	local floorStyle = room and Config.HouseFloorsById[room.Floor]
	local floorColor = floorStyle and typeof(floorStyle.A) == "Color3" and floorStyle.A or Color3.fromRGB(220, 200, 240)
	local floorPart = newPart(model, "Floor", Vector3.new(W + 2 * T, 1, D + 2 * T), CFrame.new(0, -0.5, 0), floorColor, nil, true)
	model.PrimaryPart = floorPart
	newPart(model, "WallBack", Vector3.new(W + 2 * T, WH, T), CFrame.new(0, WH / 2, -D / 2 - T / 2), wall, nil, true)
	local passH = WorldLayout.PASS_H
	local doors = WorldLayout.RoomDoors(size, column)
	local mid = WorldLayout.WALL_T + D / 2
	for _, side in ipairs({ "Left", "Right" }) do
		local x = (if side == "Left" then -1 else 1) * (W / 2 + T / 2)
		if table.find(doors, side) then
			-- (v9.9) passage placé comme la cage l'attend (WorldLayout.PassageSpan) ; z = mid - d
			local d0, d1 = WorldLayout.PassageSpan(size, column, side)
			local z0, z1 = mid - d1, mid - d0
			newPart(model, "WallSide", Vector3.new(T, WH, z0 + D / 2), CFrame.new(x, WH / 2, (-D / 2 + z0) / 2), wall, nil, true)
			newPart(model, "WallSide", Vector3.new(T, WH, D / 2 - z1), CFrame.new(x, WH / 2, (z1 + D / 2) / 2), wall, nil, true)
			newPart(model, "WallSide", Vector3.new(T, WH - passH, z1 - z0), CFrame.new(x, passH + (WH - passH) / 2, (z0 + z1) / 2), wall, nil, true)
		else
			newPart(model, "WallSide", Vector3.new(T, WH, D), CFrame.new(x, WH / 2, 0), wall, nil, true)
		end
	end
	newPart(model, "Ceiling", Vector3.new(W + 2 * T, 0.6, D + 2 * T), CFrame.new(0, WH + 0.3, 0), CREAM, nil, true)
	model.WorldPivot = CFrame.new()
	return model
end

-- (v9.9 HOUSE99) Perce un passage dans le mur de côté PLEIN d'une coque
-- House3DScene (repère de la coque : pivot au centre du dessus du sol, +Z
-- vers l'avant) entre z0 et z1 : le mur, la plinthe et la corniche sont
-- recoupés (copies : mêmes matières / couleurs), chambranle ajouté
local function cutPassage(shell: Model, size: any, side: string, z0: number, z1: number)
	local W, D = WorldLayout.RoomWidth(size), WorldLayout.DEPTH
	local T = WorldLayout.WALL_T
	local sx = if side == "Left" then -1 else 1
	local pivot = shell:GetPivot()
	local passH = WorldLayout.PASS_H
	local trimColor = CREAM
	local function relative(part: BasePart): CFrame
		return pivot:ToObjectSpace(part.CFrame)
	end
	local function clonePiece(part: BasePart, zA: number, zB: number, yA: number?, yB: number?)
		if zB - zA < 0.05 then
			return
		end
		local rel = relative(part)
		local y0 = yA or (rel.Y - part.Size.Y / 2)
		local y1 = yB or (rel.Y + part.Size.Y / 2)
		local copy = part:Clone()
		copy.Size = Vector3.new(part.Size.X, y1 - y0, zB - zA)
		copy.CFrame = pivot * CFrame.new(rel.X, (y0 + y1) / 2, (zA + zB) / 2)
		copy.Parent = part.Parent
	end
	for _, child in ipairs(shell:GetChildren()) do
		if child:IsA("BasePart") then
			local rel = relative(child)
			local alongZ = child.Size.Z > D * 0.9
			if alongZ and child.Name == ("Wall" .. side) and math.abs(rel.X - sx * (W / 2 + T / 2)) < 0.1 then
				clonePiece(child, -D / 2, z0)
				clonePiece(child, z1, D / 2)
				clonePiece(child, z0, z1, passH, rel.Y + child.Size.Y / 2)
				child:Destroy()
			elseif alongZ and (child.Name == "Skirting" or child.Name == "Crown") and math.abs(rel.X - sx * (W / 2 - 0.1)) < 0.12 then
				trimColor = child.Color
				if child.Name == "Skirting" then
					clonePiece(child, -D / 2, z0)
					clonePiece(child, z1, D / 2)
					child:Destroy()
				end
			end
		end
	end
	-- chambranle (comme House3DScene : 0,5 de large, 0,3 d'épaisseur, côté pièce)
	local fx = sx * (W / 2 - 0.1)
	for _, z in ipairs({ z0 - 0.25, z1 + 0.25 }) do
		newPart(shell, "DoorFrame", Vector3.new(0.3, passH + 0.5, 0.5), pivot * CFrame.new(fx, (passH + 0.5) / 2, z), trimColor, M.Wood, false)
	end
	newPart(shell, "DoorFrame", Vector3.new(0.3, 0.5, z1 - z0 + 1), pivot * CFrame.new(fx, passH + 0.25, (z0 + z1) / 2), trimColor, M.Wood, false)
end

-- Mur avant INTÉRIEUR d'une pièce (la façade vue de dedans) : papier peint
-- autour de la vraie fenêtre, plinthe, corniche, appui, rideaux ; plafonnier
local function roomFront(self: House, shell: Model, room: any, slot: number)
	local size = self.Size
	local floor, column = WorldLayout.SlotCell(size, slot)
	local xMin, xMax, yFloor = WorldLayout.RoomInterior(size, slot)
	local T = WorldLayout.WALL_T
	local kit = HouseKit.new(self.HouseCF, shell, 1)
	-- (v10) 2 fenêtres par pièce (ou une baie) : mêmes trous que la façade
	local rects = HouseFacade.WindowRects(size, column, floor, self.Spec)
	local paper = wallpaperColor(room)
	local trimEntry = Config.HouseTrimsById and Config.HouseTrimsById[tostring(room and room.Trim or "Cream")]
	local trim = trimEntry and typeof(trimEntry.Color) == "Color3" and trimEntry.Color or CREAM
	local top = yFloor + WorldLayout.WALL_H
	kit:WallX("FrontWall", xMin, xMax, yFloor, top, T, T + 0.12, rects, paper, M.SmoothPlastic, { Solid = false, Shadow = false })
	kit:Box("FrontSkirting", xMin, xMax, yFloor, yFloor + 0.7, T + 0.12, T + 0.32, trim, M.SmoothPlastic, { Shadow = false })
	kit:Box("FrontCrown", xMin, xMax, top - 0.5, top, T + 0.12, T + 0.32, trim, M.SmoothPlastic, { Shadow = false })
	-- (v9.6 anti-scintillement : dessus 0,04 au-dessus du bas de la fenêtre du mur)
	for _, rect in ipairs(rects) do
		kit:Box("InnerSill", rect[1] - 0.5, rect[2] + 0.5, rect[3] - 0.3, rect[3] + 0.04, T, T + 0.7, trim, M.Wood, { Shadow = false })
	end
	-- (v9.8) les rideaux (animés) sont posés par roomToggles
	-- plafonnier : vraie lumière chaude
	local cx = (xMin + xMax) / 2
	local cd = T + WorldLayout.DEPTH * 0.5
	kit:Box("LampCord", cx - 0.06, cx + 0.06, top - 2, top, cd - 0.06, cd + 0.06, Color3.fromRGB(92, 58, 96), M.SmoothPlastic, { Shadow = false })
	kit:CylY("LampShade", cx, top - 2.8, cd, 2.2, 1, trim:Lerp(WHITE, 0.4), M.Fabric, { Shadow = false })
	local bulb = kit:Ball("LampBulb", cx, top - 2.9, cd, 0.8, Color3.fromRGB(255, 236, 190), M.Neon, { Shadow = false })
	-- (v9.6 "flash bang" : portée 30 -> 16, la lumière ne traverse plus 3 pièces ; 0.9 -> 0.75)
	local light = kit:Light(bulb, Color3.fromRGB(255, 226, 184), 16, 0.75)
	return bulb, light
end

----------------------------------------------------------------------
-- (v9.8 HOUSE98) 🪟 rideaux + 💡 interrupteur + lumières d'une pièce
----------------------------------------------------------------------

local function localIsOwner(self: House): boolean
	local me = Players.LocalPlayer
	return me ~= nil and me.UserId == self.UserId
end

-- Id des pièces listés dans un attribut du propriétaire ("R1,R4")
local function flagSet(text: any): { [string]: boolean }
	local set: { [string]: boolean } = {}
	if type(text) == "string" then
		for id in string.gmatch(text, "[^,]+") do
			set[id] = true
		end
	end
	return set
end

-- Attributs 💡 / 🪟 du propriétaire (HouseService) : (lumières éteintes, rideaux fermés, clé)
local function ownerFlags(self: House): ({ [string]: boolean }, { [string]: boolean }, string)
	local owner = Players:GetPlayerByUserId(self.UserId)
	local off = owner and owner:GetAttribute("HouseLightsOff")
	local closed = owner and owner:GetAttribute("HouseCurtainsClosed")
	return flagSet(off), flagSet(closed), tostring(off) .. "|" .. tostring(closed)
end

local function roomWanted(self: House, room: any): (boolean, boolean)
	local off, closed = ownerFlags(self)
	local id = room and tostring(room.Id) or ""
	return not off[id], not closed[id]
end

local function prompt(parent: Instance, action: string, object: string, key: Enum.KeyCode, enabled: boolean): ProximityPrompt
	local p = Instance.new("ProximityPrompt")
	p.Name = "TogglePrompt"
	p.ActionText = action
	p.ObjectText = object
	p.MaxActivationDistance = 9
	p.RequiresLineOfSight = false
	p.HoldDuration = 0
	p.KeyboardKeyCode = key
	p.Enabled = enabled
	p.Parent = parent
	return p
end

local function curtainTexts(open: boolean): string
	return if open then Locale.T("Close the curtains") else Locale.T("Open the curtains")
end

local function switchTexts(on: boolean): string
	return if on then Locale.T("Turn off") else Locale.T("Turn on")
end

-- Côté (Left / Right) du passage vers la cage d'escalier : l'interrupteur y va
local function switchSide(size: any, column: number): string
	local doors = WorldLayout.RoomDoors(size, column)
	local towardHall = if column <= WorldLayout.HallAfter(size) then "Right" else "Left"
	if table.find(doors, towardHall) then
		return towardHall
	end
	return doors[1] or "Right"
end

-- Est-ce une lampe (commandée par l'interrupteur) ?
local function isLamp(itemId: string): boolean
	local item = Config.HouseItemsById and Config.HouseItemsById[itemId]
	if type(item) == "table" and item.Category == "Lights" then
		return true
	end
	return string.find(itemId, "Lamp", 1, true) ~= nil or string.find(itemId, "Chandelier", 1, true) ~= nil or string.find(itemId, "Candle", 1, true) ~= nil
end

local function roomToggles(self: House, shell: Model, room: any, slot: number, bulb: BasePart?, lamp: Light?): RoomToggles
	local size = self.Size
	local floor, column = WorldLayout.SlotCell(size, slot)
	local owner = localIsOwner(self)
	local lightsOn, curtainsOpen = roomWanted(self, room)
	local style = wallpaperOf(room)
	local fabric = style and typeof(style.B) == "Color3" and style.B or Color3.fromRGB(255, 190, 214)
	local brass = Color3.fromRGB(214, 170, 96)
	local toggles: RoomToggles = {
		Curtains = {},
		Switch = nil,
		Lights = HouseToggles.Lights(),
		CurtainsOpen = curtainsOpen,
		LightsOn = lightsOn,
		CurtainPrompts = {},
		SwitchPrompt = nil,
	}
	-- 🪟 fenêtres de devant (sur la façade vue de dedans) ; (v10) une paire
	-- de rideaux par fenêtre
	local T = WorldLayout.WALL_T
	-- (v9.9 : rideaux jusqu'au sol : ourlet 0,15 au-dessus du plancher)
	local yFloor = WorldLayout.FloorY(floor)
	for _, rect in ipairs(HouseFacade.WindowRects(size, column, floor, self.Spec)) do
		local front = self.HouseCF * CFrame.new((rect[1] + rect[2]) / 2, (rect[3] + rect[4]) / 2, -(T + 0.12)) * CFrame.Angles(0, math.pi, 0)
		table.insert(toggles.Curtains, HouseToggles.Curtains(shell, front, rect[2] - rect[1], rect[4] - rect[3], fabric, brass, curtainsOpen,
			{ Drop = (rect[3] + rect[4]) / 2 - yFloor - 0.15 }))
	end
	-- 🪟 fenêtre du fond (côté jardin)
	local b0, b1, b2, b3 = WorldLayout.BackWindowRect(size, Config.House.WallRatio)
	local back = shell:GetPivot() * CFrame.new((b0 + b1) / 2, (b2 + b3) / 2, -WorldLayout.DEPTH / 2 + 0.06)
	-- (fenêtre du fond : rideaux jusque sous l'appui, pas au sol : les meubles de la 2D sont contre ce mur)
	table.insert(toggles.Curtains, HouseToggles.Curtains(shell, back, b1 - b0, b3 - b2, fabric, brass, curtainsOpen))
	for _, curtain in ipairs(toggles.Curtains) do
		local p = prompt(curtain.Anchor, curtainTexts(curtainsOpen), Locale.T("🪟 Curtains"), Enum.KeyCode.E, owner)
		p.Triggered:Connect(function()
			self:ToggleRoom(slot, "Curtains")
		end)
		table.insert(toggles.CurtainPrompts, p)
	end
	-- 💡 interrupteur, à côté du passage vers la cage (face intérieure du mur de côté)
	local W = WorldLayout.RoomWidth(size)
	local side = switchSide(size, column)
	local sx = if side == "Right" then 1 else -1
	-- (v9.9 : à côté du passage, du côté de la façade, où qu'il soit : PassageSpan ; z = milieu - d)
	local pd0 = WorldLayout.PassageSpan(size, column, side)
	local z = WorldLayout.WALL_T + WorldLayout.DEPTH / 2 - pd0 + 1.05
	local switchCF = shell:GetPivot() * CFrame.new(sx * W / 2, 4.3, z) * CFrame.Angles(0, -sx * math.pi / 2, 0)
	local switch = HouseToggles.Switch(shell, switchCF, lightsOn)
	toggles.Switch = switch
	local sp = prompt(switch.Plate, switchTexts(lightsOn), Locale.T("💡 Lights"), Enum.KeyCode.E, owner)
	sp.MaxActivationDistance = 8
	sp.Triggered:Connect(function()
		self:ToggleRoom(slot, "Lights")
	end)
	toggles.SwitchPrompt = sp
	-- 💡 lumières commandées : plafonnier + lampes posées
	local lights = toggles.Lights
	if lamp then
		lights:Add(lamp)
	end
	if bulb then
		lights:AddGlow(bulb)
	end
	local items = shell:FindFirstChild("Items")
	for _, model in ipairs(items and items:GetChildren() or {}) do
		if isLamp(tostring(model:GetAttribute("ItemId"))) then
			lights:Collect(model, true)
		end
	end
	lights:Set(lightsOn, false)
	shell:SetAttribute("LightsOn", lightsOn)
	shell:SetAttribute("CurtainsOpen", curtainsOpen)
	return toggles
end

-- Applique un état (animé) à une pièce construite
local function applyToggles(state: RoomState, lightsOn: boolean, curtainsOpen: boolean, animate: boolean)
	local t = state.Toggles
	if not t then
		return
	end
	if t.CurtainsOpen ~= curtainsOpen then
		t.CurtainsOpen = curtainsOpen
		for _, curtain in ipairs(t.Curtains) do
			curtain:Set(curtainsOpen, animate)
		end
		for _, p in ipairs(t.CurtainPrompts) do
			p.ActionText = curtainTexts(curtainsOpen)
		end
	end
	if t.LightsOn ~= lightsOn then
		t.LightsOn = lightsOn
		if t.Switch then
			t.Switch:Set(lightsOn, animate)
		end
		t.Lights:Set(lightsOn, animate)
		if t.SwitchPrompt then
			t.SwitchPrompt.ActionText = switchTexts(lightsOn)
		end
	end
	local shell = state.Shell
	if shell then
		shell:SetAttribute("LightsOn", lightsOn)
		shell:SetAttribute("CurtainsOpen", curtainsOpen)
	end
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

----------------------------------------------------------------------
-- (v9.9 HOUSE99) Intérieur du hall en flux (escalier, meubles, lampes)
----------------------------------------------------------------------

function HouseBuilder.DestroyHall(self: House)
	local hall = self.Hall
	if hall.Model then
		hall.Model:Destroy()
	end
	hall.Model = nil
	hall.State = "None"
	hall.Ramps = {}
	self.Ramps = {}
end

function HouseBuilder.BuildHall(self: House)
	if not self.Alive then
		return
	end
	self:DestroyHall()
	local model = Instance.new("Model")
	model.Name = "Hall"
	local kit = HouseKit.new(self.HouseCF, model, 2)
	local ok, result = pcall(HouseStairs.BuildInterior, kit, self.Size)
	local hall = self.Hall
	if ok then
		hall.Ramps = result.Ramps
		self.Ramps = result.Ramps
	else
		warn("[World] Escalier : " .. tostring(result))
	end
	hall.Parts = kit.Stats.Count
	model:SetAttribute("Parts", kit.Stats.Count)
	model.Parent = self.Model
	hall.Model = model
	hall.State = "Built"
end

-- Distance de `focus` au hall (boîte de la cage, tous les étages)
local function hallDistance(self: House, focus: Vector3): number
	local x, y, d = WorldLayout.ToLocal(self.HouseCF, focus)
	local h0, h1 = WorldLayout.HallSpan(self.Size)
	local dims = WorldLayout.Dims(self.Size)
	local cx = math.clamp(x, h0, h1)
	local cy = math.clamp(y, 0, dims.Height)
	local cd = math.clamp(d, 0, dims.Depth)
	return Vector3.new(x - cx, y - cy, d - cd).Magnitude
end

function HouseBuilder.DestroyRoom(self: House, slot: number)
	if slot == 0 then
		self:DestroyHall()
		return
	end
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
	state.Toggles = nil
	if state.Fill then
		state.Fill.Transparency = 0
	end
	if state.BackFill then
		state.BackFill.Transparency = 0
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
	-- (v10) les pièces n'existent qu'avec l'extérieur complet
	if self.Lod ~= "Full" and self.Alive then
		self:SetLod("Full")
	end
	if slot == 0 then
		self:BuildHall()
		return
	end
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
	-- (v9.9) passages hors du milieu (manoir : cage -> pièces de droite, au
	-- fond) : la coque les construit pleins, on les perce ensuite
	local shellDoors, moved = {}, {}
	local mid = WorldLayout.WALL_T + WorldLayout.DEPTH / 2
	for _, side in ipairs(WorldLayout.RoomDoors(size, column)) do
		local d0, d1 = WorldLayout.PassageSpan(size, column, side)
		if math.abs((d0 + d1) / 2 - mid) > 0.05 or math.abs((d1 - d0) - WorldLayout.PASS_W) > 0.05 then
			table.insert(moved, { side, mid - d1, mid - d0 })
		else
			table.insert(shellDoors, side)
		end
	end
	if Scene and type(Scene.BuildRoomShell) == "function" then
		local ok, result = pcall(Scene.BuildRoomShell, roomData, size, {
			Scale = WorldLayout.PX,
			Depth = WorldLayout.DEPTH,
			WallHeight = WorldLayout.WALL_H,
			Doors = shellDoors,
			DoorWidth = WorldLayout.PASS_W,
			DoorHeight = WorldLayout.PASS_H,
			Front = false,
			Ceiling = true,
			Patterns = true,
			-- (v9.8) vraie fenêtre côté jardin (même trou que la façade : HouseFacade.BackWindowRect)
			BackWindow = { WorldLayout.BackWindowRect(size, Config.House.WallRatio) },
		})
		if ok and typeof(result) == "Instance" and result:IsA("Model") then
			shell = result
			for _, m in ipairs(moved) do
				local okCut, err = pcall(cutPassage, result, size, m[1], m[2], m[3])
				if not okCut then
					warn("[World] Passage : " .. tostring(err))
				end
			end
		elseif not ok then
			warn("[World] BuildRoomShell : " .. tostring(result))
		end
	end
	if not shell then
		shell = fallbackShell(room, size, column)
	end
	local s = shell :: Model
	s.Name = "Room_" .. slot
	s:SetAttribute("Slot", slot)
	s:PivotTo(WorldLayout.ShellPivot(self.HouseCF, size, slot))
	local okFront, bulbOrErr, lamp = pcall(roomFront, self, s, room, slot)
	if not okFront then
		warn("[World] Mur avant : " .. tostring(bulbOrErr))
	end
	s.Parent = self.Interiors
	state.Shell = s
	if state.Fill then
		state.Fill.Transparency = 1
	end
	if state.BackFill then
		state.BackFill.Transparency = 1
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
			-- (v9.8 : sur un lit / un hamac -> "S'allonger" ; SEAT98 y joue la sieste)
			local sitId = tostring(itemModel:GetAttribute("ItemId"))
			local lying = false
			if sitId == "Hammock" then
				lying = true
			elseif sitId ~= "PetBed" then
				lying = string.find(sitId, "Bed", 1, true) ~= nil
			end
			prompt.ActionText = if lying then Locale.T("Lie down") else Locale.T("Sit")
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
	-- (v9.8) 🪟 rideaux + 💡 interrupteur + lumières (après les objets : les lampes posées suivent l'interrupteur)
	local okToggles, toggles = pcall(roomToggles, self, s, room, slot, if okFront and typeof(bulbOrErr) == "Instance" then bulbOrErr :: BasePart else nil,
		if okFront and typeof(lamp) == "Instance" then lamp :: Light else nil)
	if okToggles then
		state.Toggles = toggles
	else
		warn("[World] Rideaux / interrupteur : " .. tostring(toggles))
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
	if self.Lod ~= "Full" then
		return nil, math.huge
	end
	local best: number? = nil
	local bestDistance = math.huge
	-- (v9.9) le hall d'abord (on y entre par la porte) : "emplacement" 0
	local hallD = hallDistance(self, focus)
	if self.Hall.State == "None" and hallD < NEAR - 20 then
		best = 0
		bestDistance = hallD
	elseif self.Hall.State ~= "None" and hallD > FAR - 20 then
		self:DestroyHall()
	end
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
	-- (v10) niveau de détail + options d'extérieur changées par le propriétaire
	self:StepLod()
	local _, extText = extOf(self.Snapshot)
	if extText ~= self.ExtText and self.Alive then
		if self.Lod == "Full" then
			self:BuildExterior()
		else
			self:BuildLite(self.Lod)
		end
	end
	if self.Lod ~= "Full" then
		local night = HouseBuilder.IsNight()
		local _, _, key = ownerFlags(self)
		local glowKey = tostring(night) .. "|" .. key
		if glowKey ~= self.GlowKey then
			self.GlowKey = glowKey
			self:ApplyGlows(night)
		end
		return
	end
	local leaf = self.Door
	local hinge = self.DoorHinge
	if not leaf or not hinge then
		return
	end
	local lock = self.DoorLock
	if lock then
		lock.Text = locked and "🔒" or ""
	end
	-- (v9.8) porte de derrière : ouverte si quelqu'un (n'importe quel avatar) en est proche
	if #self.BackLeaves > 0 then
		local backDoor = self:BackDoorPosition()
		local near = false
		for _, player in ipairs(Players:GetPlayers()) do
			local character = player.Character
			local root = character and character:FindFirstChild("HumanoidRootPart")
			if root and root:IsA("BasePart") and (root.Position - backDoor).Magnitude < BACK_RANGE then
				near = true
				break
			end
		end
		local wantBack = near and not locked
		if wantBack ~= self.BackDoorOpen then
			self.BackDoorOpen = wantBack
			swingLeaves(self.BackLeaves, wantBack)
		end
	end
	-- (v9.8) 💡 / 🪟 changés par le propriétaire (ou refus du serveur) : appliqués ici (5 fois / s)
	local _, _, key = ownerFlags(self)
	if key ~= self.FlagKey then
		self.FlagKey = key
		self:ApplyRoomFlags(true)
	end
	-- (v9.9) fenêtres qui brillent la nuit (vues de dehors)
	local night = HouseBuilder.IsNight()
	local glowKey = tostring(night) .. "|" .. key
	if glowKey ~= self.GlowKey then
		self.GlowKey = glowKey
		self:ApplyGlows(night)
	end
	local want = open and not locked
	if want == self.DoorOpen then
		return
	end
	self.DoorOpen = want
	if #self.Leaves > 0 then
		swingLeaves(self.Leaves, want)
		return
	end
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

-- (v9.9 HOUSE99) Nuit (même règle que les lanternes du jardin ; suit aussi
-- le réglage "Heure du jour" : Lighting.ClockTime du client)
function HouseBuilder.IsNight(): boolean
	local clock = Lighting.ClockTime
	return clock < 6.4 or clock > 17.6
end

local GLOW_WARM = Color3.fromRGB(255, 206, 140)

-- (v9.9) Allume / éteint la lueur de nuit de chaque fenêtre : pièce qui
-- existe + lumière allumée (attribut du propriétaire) ; rideaux fermés =
-- lueur teintée par le tissu, un peu plus douce ; hall : toujours la nuit
function HouseBuilder.ApplyGlows(self: House, night: boolean)
	local off, closed = ownerFlags(self)
	local bySlot = roomsBySlot(self.Snapshot)
	for slot, list in pairs(self.Glows) do
		local on, color, alpha = false, GLOW_WARM, 0.3
		if slot == 0 then
			on = night
			alpha = 0.4
		else
			local room = bySlot[slot]
			if room then
				local id = tostring(room.Id)
				on = night and not off[id]
				if closed[id] then
					local style = wallpaperOf(room)
					local fabric = style and typeof(style.B) == "Color3" and style.B or Color3.fromRGB(255, 190, 214)
					color = GLOW_WARM:Lerp(fabric, 0.55)
					alpha = 0.42
				end
			end
		end
		for _, glow in ipairs(list) do
			if glow.Gui and glow.Fill then
				glow.Gui.Enabled = on
				glow.Fill.BackgroundColor3 = color
				glow.Fill.BackgroundTransparency = alpha
			elseif glow.Part then
				-- (v10 LOD) vitre simplifiée : teinte chaude douce (Neon sombre) la nuit
				local part: BasePart = glow.Part
				if on then
					part.Color = color:Lerp(Color3.new(0, 0, 0), 0.25)
					part.Material = M.Neon
				else
					part.Color = glow.Day or part.Color
					part.Material = glow.DayMat or M.SmoothPlastic
				end
			end
		end
	end
end

-- (v9.8) Milieu de la porte de derrière (monde), côté jardin
function HouseBuilder.BackDoorPosition(self: House): Vector3
	return WorldLayout.ToWorld(self.HouseCF, WorldLayout.BackDoorX(self.Size), WorldLayout.FloorY(1) + 2, WorldLayout.BackDoorD(self.Size) - 0.4)
end

-- (v9.8) Applique les attributs 💡 / 🪟 du propriétaire à toutes les pièces construites
function HouseBuilder.ApplyRoomFlags(self: House, animate: boolean)
	local off, closed, key = ownerFlags(self)
	self.FlagKey = key
	for _, state in pairs(self.Rooms) do
		if state.Toggles and state.Data then
			local id = tostring(state.Data.Id)
			applyToggles(state, not off[id], not closed[id], animate)
		end
	end
end

-- (v9.8) Le propriétaire bascule les rideaux ou les lumières d'une pièce :
-- animation tout de suite, puis sauvegarde (en cas de refus : retour à
-- l'état du serveur)
function HouseBuilder.ToggleRoom(self: House, slot: number, what: string): boolean
	local state = self.Rooms[slot]
	local t = state and state.Toggles
	if not state or not t or not state.Data or not localIsOwner(self) then
		return false
	end
	local lightsOn, curtainsOpen = t.LightsOn, t.CurtainsOpen
	local argument: { [string]: any } = { Room = tostring(state.Data.Id) }
	if what == "Lights" then
		lightsOn = not lightsOn
		argument.LightsOn = lightsOn
	elseif what == "Curtains" then
		curtainsOpen = not curtainsOpen
		argument.CurtainsOpen = curtainsOpen
	else
		return false
	end
	applyToggles(state, lightsOn, curtainsOpen, true)
	task.spawn(function()
		local ok, success = pcall(function()
			return Net.Function("House"):InvokeServer("setRoomState", argument)
		end)
		if not (ok and success == true) and self.Alive then
			self:ApplyRoomFlags(true)
		end
	end)
	return true
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
		if self.Lod == "Full" then
			self:BuildExterior()
		else
			self:BuildLite(self.Lod)
		end
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
	local expected = self.ChimneysExpected or HouseFacade.Chimneys[self.Style] or 0
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
	self:DestroyHall()
	for slot in pairs(self.Rooms) do
		self:DestroyRoom(slot)
	end
	self.Model:Destroy()
end

return HouseBuilder
