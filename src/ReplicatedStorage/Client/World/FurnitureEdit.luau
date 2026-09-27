--[[
	FurnitureEdit (ModuleScript)
	Emplacement : ReplicatedStorage > Client > World > FurnitureEdit

	🚶 Dopamine Town : déplacer ses meubles avec son avatar, DANS SA maison.
	  - mode édition (bouton ✏️ du HUD) : un clic / un appui sur un meuble le
	    prend en main (surligné) ; il suit la souris (PC) ou le doigt (on le
	    fait glisser) sur le sol de sa pièce, ou sur le mur du fond pour les
	    objets muraux ; aimant de grille (1 stud) activable ;
	  - R (ou 🔄) tourne de 45° (champ R de l'objet posé), Maj+R dans l'autre
	    sens ; clic (PC) ou ✅ pose ; Échap / ❌ annule ; Suppr / 📦 range
	    (retour à l'inventaire) ;
	  - (v9.6) un petit objet (Formulas.CanGoOnFurniture) lâché au-dessus d'un
	    meuble qui a un dessus (HouseSurfaces) se pose DESSUS, sur le NIVEAU visé
	    (rayons d'une bibliothèque, étagères murales, lit superposé...),
	    n'importe où le long du rayon, à côté des objets déjà posés (sans
	    chevauchement) ; le rayon visé s'allume ; ce qui est posé sur un
	    meuble et les chaises rangées à une table suivent le meuble ;
	  - (v9.6) ZONE VALIDE partagée avec l'éditeur 2D et le serveur
	    (WorldLayout.PlacementArea) : le fantôme 3D est TOUJOURS l'image 2D -> 3D
	    de la position qui sera sauvée (WorldLayout.FloorClamp / WallClamp,
	    dessus : même calcul que House3DLayout) -> ce qu'on voit en 3D est
	    exactement ce qui est permis, et la 2D ne déborde plus jamais ;
	  - (v9.6) 📦 INVENTAIRE en 3D : un plateau liste les objets possédés mais
	    pas posés (icône, nombre, filtre par catégorie) ; on en choisit un -> un
	    fantôme suit la souris / le doigt dans la pièce où l'on est (sol, mur
	    ou dessus d'un meuble selon l'objet) -> clic / ✅ pour le poser ;
	    "🛍️ Acheter" ouvre le catalogue de la ville (ShopUI de SHOPS96, sinon
	    une petite liste d'achat ici) et l'objet acheté arrive directement
	    dans le fantôme ;
	  - à la pose : la pièce est reconstruite tout de suite (même rendu qu'après
	    un rechargement) et la disposition part au serveur par l'action
	    existante "saveLayout" (tout y est vérifié : objets possédés, zones,
	    rotation) ; refus -> retour en arrière.
	La maison 2D et la maison 3D restent donc toujours la même maison.
	Entrées : ContextActionService (priorité haute) pendant l'édition : le
	doigt qui déplace un meuble ne fait pas tourner la caméra.
	Interface : ScreenGui "TownInventoryGui" (créé désactivé à new(), à garder
	par TownClient : KEEP_GUIS).
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local ContextActionService = game:GetService("ContextActionService")
local RunService = game:GetService("RunService")

local WorldLayout = require(ReplicatedStorage.Shared.WorldLayout)
local Locale = require(ReplicatedStorage.Shared.Locale)
local NumberFormatter = require(ReplicatedStorage.Shared.NumberFormatter)

local Client = script.Parent.Parent
local UIUtil = require(Client.UIUtil)
local Theme = require(Client.Theme)
local ClientState = require(Client.ClientState)

local HouseFolder = Client.Components.House
local HouseCommon = require(HouseFolder.HouseCommon)

local FurnitureEdit = {}
FurnitureEdit.__index = FurnitureEdit

local ACTION = "DopamineTownEdit"
local RENDER = "DopamineTownEditFollow"
local GUI_NAME = "TownInventoryGui"
local GRID = 1 -- (studs) aimant
local ROTATE_STEP = 45
local TURN = CFrame.Angles(0, math.pi, 0) -- modèle (devant -Z) <-> repère des recettes (devant +Z)
local LEVEL_REACH = 0.35 -- (studs) on vise un rayon un peu au-dessus de sa planche
local GHOST_ALPHA = 0.35 -- transparence du fantôme d'un objet de l'inventaire

local PINK_DEEP = Color3.fromRGB(236, 72, 140)
local LILAC = Color3.fromRGB(170, 140, 245)
local MINT = Color3.fromRGB(80, 200, 160)
local SKY = Color3.fromRGB(96, 170, 245)
local INK = Color3.fromRGB(92, 58, 96)
local CARD = Color3.fromRGB(255, 250, 253)
local WHITE = Color3.new(1, 1, 1)

export type Context = {
	GetHouse: () -> any?, -- maison du joueur (HouseBuilder) ou nil
	Hud: any,
	Toast: (text: string, color: Color3?) -> (),
	Save: (slot: number, roomId: string, placed: { any }, onResult: (ok: boolean, message: string?) -> ()) -> (),
}

type Held = {
	House: any,
	Slot: number,
	Index: number, -- index dans room.Placed (objet neuf : #Placed + 1)
	Model: Model,
	Start: CFrame,
	Entry: any,
	Item: any,
	Wall: boolean,
	AgainstWall: boolean,
	FW: number,
	FD: number,
	H: number,
	R: number?,
	Frame: CFrame, -- repère de la pièce
	X: number, -- position 3D montrée (repère de la pièce)
	Y: number,
	Z: number,
	TX: number?, -- (v9.6) position 2D qui sera sauvée (X, Y, couche Z)
	TY: number?,
	TZ: number?,
	Support: Model?,
	Level: number?, -- n° du dessus visé (meuble à plusieurs niveaux)
	Followers: { { Model: Model, Offset: CFrame, Start: CFrame, Index: number } },
	Moved: boolean,
	New: boolean, -- (v9.6) objet sorti de l'inventaire (fantôme)
}

local surfacesModule: any = nil
local function surfaces(): any
	if surfacesModule == nil then
		local ok, result = pcall(require, HouseFolder:FindFirstChild("HouseSurfaces") :: ModuleScript)
		surfacesModule = ok and result or false
	end
	return surfacesModule or nil
end

local recipesModule: any = nil
local function recipes(): any
	if recipesModule == nil then
		local module = HouseFolder:FindFirstChild("House3DRecipes")
		local ok, result = false, nil
		if module then
			ok, result = pcall(require, module :: ModuleScript)
		end
		recipesModule = ok and result or false
	end
	return recipesModule or nil
end

-- Catalogue de la ville (SHOPS96) : facultatif
local shopModule: any = nil
local function shopUI(): any
	if shopModule == nil then
		local module = script.Parent:FindFirstChild("ShopUI")
		local ok, result = false, nil
		if module then
			ok, result = pcall(require, module :: ModuleScript)
		end
		shopModule = (ok and type(result) == "table") and result or false
	end
	return shopModule or nil
end

local function footprint(model: Model): (number, number, number)
	local value = model:GetAttribute("Footprint")
	if typeof(value) == "Vector3" then
		return math.max(0.2, value.X), math.max(0.2, value.Y), math.max(0.2, value.Z)
	end
	return 2, 2, 2
end

-- Modèle d'objet (attribut EntryIndex) qui contient une pièce touchée
local function itemModelOf(part: Instance?): Model?
	local node = part
	while node and node ~= workspace do
		if node:IsA("Model") and node:GetAttribute("EntryIndex") ~= nil then
			return node
		end
		node = node.Parent
	end
	return nil
end

-- Rayon (monde) -> point d'un plan du repère `frame` (axe "y" = sol, "z" = mur du fond)
local function hitPlane(frame: CFrame, origin: Vector3, direction: Vector3, axis: string): Vector3?
	local o = frame:PointToObjectSpace(origin)
	local d = frame:VectorToObjectSpace(direction)
	local component = axis == "y" and d.Y or d.Z
	if math.abs(component) < 1e-4 then
		return nil
	end
	local t = -(axis == "y" and o.Y or o.Z) / component
	if t < 0 then
		return nil
	end
	return o + d * t
end

-- Dimensions 2D <-> 3D d'une pièce de la maison
local function dimsOf(house: any): WorldLayout.RoomDims
	return WorldLayout.RoomDims(house.Size, HouseCommon.Config.WallRatio)
end

-- Taille d'un objet posé (px de maquette -> studs par unité de sa boîte)
local function unitK(item: any, scale: number): number
	return (tonumber(item.Size) or 80) * scale * WorldLayout.PX / 100
end

-- (v9.6) Dessus n° `index` d'un meuble 3D, dans le repère de son modèle
-- (attribut "Top<i>" de House3DRecipes.BuildModel ; sinon les nombres 2D de
-- HouseSurfaces, comme le fait House3DRecipes quand la recette n'en a pas)
local function topLocal(model: Model, index: number, supportEntry: any, supportItem: any): Vector3?
	local value = model:GetAttribute("Top" .. tostring(index))
	if typeof(value) == "Vector3" then
		return value
	end
	if index == 1 then
		local center = model:GetAttribute("TopCenter")
		if typeof(center) == "Vector3" then
			return center
		end
	end
	local S = surfaces()
	local raw = S and S.Raw(supportEntry.I)
	local s = raw and raw[index]
	if not s then
		return nil
	end
	local k = unitK(supportItem, tonumber(supportEntry.S) or 1)
	local x = ((tonumber(s[1]) or 10) + (tonumber(s[2]) or 90)) / 2 - 50
	if supportEntry.F == true then
		x = -x
	end
	local _, _, fd = footprint(model)
	return Vector3.new(-x * k, (100 - (tonumber(s[3]) or 50)) * k, -(tonumber(s[4]) or 0) * fd)
end

function FurnitureEdit.new(ctx: Context)
	local self = setmetatable({
		Ctx = ctx,
		Enabled = false,
		Held = nil :: Held?,
		Snap = true,
		Pointer = nil :: Vector2?,
		Highlight = nil :: Highlight?,
		TargetHighlight = nil :: Highlight?,
		Plate = nil :: BasePart?,
		Hover = nil :: Model?,
		Dragging = false,
		PressAt = nil :: Vector2?,
		Connections = {} :: { any },
		Saving = false,
		Buying = false,
		-- (v9.6) plateau d'inventaire
		Tray = nil :: any,
		TrayOpen = true,
		TrayView = "Inventory", -- "Inventory" | "Buy"
		Filter = nil :: string?, -- catégorie (nil = tout)
		TraySignature = "",
		AwaitBuy = false, -- le catalogue a été ouvert depuis le plateau
		ShopConnection = nil :: any,
	}, FurnitureEdit)
	pcall(function()
		self:BuildTray()
	end)
	return self
end

----------------------------------------------------------------------
-- Surbrillance
----------------------------------------------------------------------

local function newHighlight(name: string): Highlight
	local h = Instance.new("Highlight")
	h.Name = name
	h.DepthMode = Enum.HighlightDepthMode.Occluded
	h.FillTransparency = 0.7
	h.OutlineTransparency = 0
	h.Enabled = false
	h.Parent = workspace
	return h
end

function FurnitureEdit.SetHighlight(self: any, model: Model?, holding: boolean)
	local highlight: Highlight? = self.Highlight
	if not model then
		if highlight then
			highlight.Adornee = nil
			highlight.Enabled = false
		end
		return
	end
	if not highlight then
		highlight = newHighlight("TownEditHighlight")
		self.Highlight = highlight
	end
	local h = highlight :: Highlight
	h.Adornee = model
	h.Enabled = true
	h.FillColor = holding and Color3.fromRGB(110, 230, 170) or Color3.fromRGB(255, 180, 220)
	h.OutlineColor = holding and Color3.fromRGB(40, 170, 110) or Color3.fromRGB(236, 72, 140)
end

-- (v9.6) Meuble visé (contour rose) + plaque lumineuse sur le rayon visé
function FurnitureEdit.SetTarget(self: any, model: Model?, plateCF: CFrame?, plateSize: Vector2?)
	local h: Highlight? = self.TargetHighlight
	if model and not h then
		h = newHighlight("TownEditTarget")
		self.TargetHighlight = h
	end
	if h then
		h.Adornee = model
		h.Enabled = model ~= nil
		h.FillColor = Color3.fromRGB(255, 200, 230)
		h.FillTransparency = 0.85
		h.OutlineColor = PINK_DEEP
	end
	local plate: BasePart? = self.Plate
	if plateCF and plateSize then
		if not plate then
			local p = Instance.new("Part")
			p.Name = "TownEditSurface"
			p.Anchored = true
			p.CanCollide = false
			p.CanQuery = false
			p.CanTouch = false
			p.CastShadow = false
			p.Material = Enum.Material.SmoothPlastic
			p.Color = Color3.fromRGB(120, 240, 190)
			p.Transparency = 0.45
			p.Parent = workspace
			plate = p
			self.Plate = p
		end
		local part = plate :: BasePart
		part.Size = Vector3.new(math.max(0.2, plateSize.X), 0.05, math.max(0.2, plateSize.Y))
		part.CFrame = plateCF * CFrame.new(0, 0.03, 0)
		part.Transparency = 0.45
	elseif plate then
		plate.Transparency = 1
	end
end

----------------------------------------------------------------------
-- Activer / désactiver
----------------------------------------------------------------------

function FurnitureEdit.IsEnabled(self: any): boolean
	return self.Enabled
end

function FurnitureEdit.SetEnabled(self: any, enabled: boolean)
	if enabled == self.Enabled then
		return
	end
	if not enabled and self.Held then
		self:Cancel()
	end
	self.Enabled = enabled
	local house = self.Ctx.GetHouse()
	self:SetPrompts(house, not enabled)
	if enabled then
		pcall(function()
			ContextActionService:BindActionAtPriority(ACTION, function(_name: string, state: Enum.UserInputState, input: InputObject)
				return self:OnAction(state, input)
			end, false, 3000, Enum.UserInputType.MouseButton1, Enum.UserInputType.Touch, Enum.KeyCode.R, Enum.KeyCode.Delete, Enum.KeyCode.Escape)
		end)
		table.insert(self.Connections, UserInputService.InputChanged:Connect(function(input: InputObject)
			if input.UserInputType == Enum.UserInputType.MouseMovement then
				self.Pointer = Vector2.new(input.Position.X, input.Position.Y)
			end
		end))
		-- (v9.6) inventaire à jour (achat, pose, rangement)
		table.insert(self.Connections, ClientState.Changed:Connect(function()
			self:RefreshTray(false)
		end))
		pcall(function()
			RunService:BindToRenderStep(RENDER, Enum.RenderPriority.Input.Value + 1, function()
				self:Follow()
			end)
		end)
		self.Ctx.Toast(Locale.T("✏️ Edit mode: pick a piece of furniture"), Color3.fromRGB(96, 170, 245))
	else
		pcall(function()
			ContextActionService:UnbindAction(ACTION)
		end)
		pcall(function()
			RunService:UnbindFromRenderStep(RENDER)
		end)
		for _, connection in ipairs(self.Connections) do
			connection:Disconnect()
		end
		table.clear(self.Connections)
		self:SetHighlight(nil, false)
		self:SetTarget(nil)
		self.AwaitBuy = false
	end
	self.Ctx.Hud:SetEditing(enabled, false)
	self:ShowTray(enabled)
end

-- Invites "S'asseoir" coupées pendant l'édition
function FurnitureEdit.SetPrompts(_self: any, house: any, enabled: boolean)
	if not house then
		return
	end
	for _, room in pairs(house.Rooms) do
		for _, prompt in ipairs(room.Prompts) do
			prompt.Enabled = enabled
		end
	end
end

----------------------------------------------------------------------
-- Entrées
----------------------------------------------------------------------

local function overHud(position: Vector2): boolean
	local playerGui = Players.LocalPlayer:FindFirstChildOfClass("PlayerGui")
	if not playerGui then
		return false
	end
	local ok, objects = pcall(function()
		return playerGui:GetGuiObjectsAtPosition(position.X, position.Y)
	end)
	if not ok or type(objects) ~= "table" then
		return false
	end
	for _, object in ipairs(objects) do
		if object:IsA("GuiObject") and object.Visible and (object:FindFirstAncestor(GUI_NAME) or object:FindFirstAncestor("TownShopGui")) then
			return true
		end
		if object:IsA("GuiButton") and object.Visible and object:FindFirstAncestor("TownHud") then
			return true
		end
	end
	return false
end

function FurnitureEdit.OnAction(self: any, state: Enum.UserInputState, input: InputObject): Enum.ContextActionResult
	local pass = Enum.ContextActionResult.Pass
	local sink = Enum.ContextActionResult.Sink
	if not self.Enabled then
		return pass
	end
	if input.UserInputType == Enum.UserInputType.Keyboard then
		if state ~= Enum.UserInputState.Begin or not self.Held then
			return pass
		end
		if input.KeyCode == Enum.KeyCode.R then
			local shift = UserInputService:IsKeyDown(Enum.KeyCode.LeftShift) or UserInputService:IsKeyDown(Enum.KeyCode.RightShift)
			self:Rotate(shift and -ROTATE_STEP or ROTATE_STEP)
		elseif input.KeyCode == Enum.KeyCode.Delete then
			self:PutAway()
		elseif input.KeyCode == Enum.KeyCode.Escape then
			self:Cancel()
		end
		return sink
	end
	local position = Vector2.new(input.Position.X, input.Position.Y)
	if overHud(position) then
		return pass
	end
	local touch = input.UserInputType == Enum.UserInputType.Touch
	if state == Enum.UserInputState.Begin then
		self.PressAt = position
		if not self.Held then
			if self:Pick(position) then
				self.Dragging = touch
				return sink
			end
			return pass
		end
		self.Pointer = position
		self.Dragging = true
		return sink
	elseif state == Enum.UserInputState.Change then
		if self.Held and self.Dragging then
			self.Pointer = position
			return sink
		end
		return pass
	elseif state == Enum.UserInputState.End then
		local wasDragging = self.Dragging
		self.Dragging = false
		if self.Held and not touch and wasDragging then
			-- PC : 2e clic = poser ici
			self.Pointer = position
			self:Follow()
			self:Drop()
			return sink
		end
		return self.Held and sink or pass
	end
	return pass
end

----------------------------------------------------------------------
-- Prendre / suivre
----------------------------------------------------------------------

function FurnitureEdit.Raycast(self: any, position: Vector2): (RaycastResult?, any)
	local house = self.Ctx.GetHouse()
	local camera = workspace.CurrentCamera
	if not house or not camera then
		return nil, nil
	end
	local ray = camera:ViewportPointToRay(position.X, position.Y)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	local include: { Instance } = {}
	for _, room in pairs(house.Rooms) do
		if room.Shell then
			local items = room.Shell:FindFirstChild("Items")
			if items then
				table.insert(include, items)
			end
		end
	end
	params.FilterDescendantsInstances = include
	local result = workspace:Raycast(ray.Origin, ray.Direction * 250, params)
	return result, house
end

function FurnitureEdit.Pick(self: any, position: Vector2): boolean
	local result, house = self:Raycast(position)
	local model = result and itemModelOf(result.Instance)
	if not model or not house then
		return false
	end
	self.Pointer = position
	return self:Hold(house, model)
end

-- Prend en main le modèle d'objet `model` de la maison `house`
function FurnitureEdit.Hold(self: any, house: any, model: Model): boolean
	-- pièce : la coque qui contient le modèle (coque > Items > modèle)
	local shell = model.Parent and model.Parent.Parent
	local slot = shell and tonumber(shell:GetAttribute("Slot")) or nil
	local room = slot and house.Rooms[slot]
	local index = tonumber(model:GetAttribute("EntryIndex"))
	if not slot or not room or not room.Data or not index or not room.Data.Placed[index] then
		return false
	end
	local entry = room.Data.Placed[index]
	local item = HouseCommon.ItemsById[entry.I]
	if not item then
		return false
	end
	local fw, h, fd = footprint(model)
	local frame = WorldLayout.RoomFrame(house.HouseCF, house.Size, slot)
	local rel = frame:ToObjectSpace(model:GetPivot())
	local held: Held = {
		House = house,
		Slot = slot,
		Index = index,
		Model = model,
		Start = model:GetPivot(),
		Entry = entry,
		Item = item,
		Wall = item.Placement == "Wall",
		AgainstWall = model:GetAttribute("AgainstWall") == true,
		FW = fw,
		FD = fd,
		H = h,
		R = WorldLayout.NormalizeRotation(entry.R),
		Frame = frame,
		X = rel.X,
		Y = rel.Y,
		Z = rel.Z,
		TX = nil,
		TY = nil,
		TZ = nil,
		Support = nil,
		Level = nil,
		Followers = {},
		Moved = false,
		New = false,
	}
	-- ce qui suit le meuble (posé dessus, chaises à table)
	local S = surfaces()
	if S and type(S.Dependents) == "function" then
		local dims = dimsOf(house)
		local ok, deps = pcall(S.Dependents, entry, room.Data.Placed, dims.RoomWpx, dims.RoomHpx)
		if ok and type(deps) == "table" then
			local wanted: { [any]: boolean } = {}
			for _, dep in ipairs(deps) do
				wanted[dep] = true
			end
			for _, other in ipairs(room.Items) do
				local otherIndex = tonumber(other:GetAttribute("EntryIndex"))
				local otherEntry = otherIndex and room.Data.Placed[otherIndex]
				if otherIndex and otherEntry and wanted[otherEntry] and other.Parent then
					table.insert(held.Followers, { Model = other, Offset = model:GetPivot():ToObjectSpace(other:GetPivot()), Start = other:GetPivot(), Index = otherIndex })
				end
			end
		end
	end
	self.Held = held
	self:SetHighlight(model, true)
	self.Ctx.Hud:SetEditing(true, true, Locale.T(item.Name))
	return true
end

-- (v9.6) Pièce de sa maison où se trouve son avatar (nil = cage d'escalier / dehors)
function FurnitureEdit.CurrentSlot(_self: any, house: any): number?
	local character = Players.LocalPlayer.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not root or not root:IsA("BasePart") or type(house.RoomAt) ~= "function" then
		return nil
	end
	local ok, slot = pcall(house.RoomAt, house, root.Position)
	if ok and type(slot) == "number" and house.Rooms[slot] and house.Rooms[slot].Data then
		return slot
	end
	return nil
end

-- (v9.6) Sort un objet de l'inventaire : un fantôme à poser dans la pièce où l'on est
function FurnitureEdit.HoldNew(self: any, itemId: string, fromPurchase: boolean?): boolean
	local item = HouseCommon.ItemsById[itemId]
	local house = self.Ctx.GetHouse()
	if not item or not house or not self.Enabled or self.Saving then
		return false
	end
	if self.Held then
		self:Cancel()
	end
	local slot = self:CurrentSlot(house)
	local room = slot and house.Rooms[slot]
	if not slot or not room or not room.Data then
		self.Ctx.Toast(Locale.T("Go inside one of your rooms to place it"), Color3.fromRGB(255, 170, 90))
		return false
	end
	local data = HouseCommon.GetHouse(ClientState.Data)
	if not fromPurchase and HouseCommon.Available(data, itemId) <= 0 then
		self.Ctx.Toast(Locale.T("Buy one in the shop first!"), Color3.fromRGB(255, 170, 90))
		return false
	end
	local maxItems = tonumber(house.Size and house.Size.RoomItems) or 30
	if #room.Data.Placed >= maxItems then
		self.Ctx.Toast(Locale.T("This room is full (%d items)! Decorate another room 🏡", maxItems), Color3.fromRGB(255, 170, 90))
		return false
	end
	local R = recipes()
	local entry = { I = itemId, X = 0.5, Y = 0.8, S = 1, Z = HouseCommon.DEFAULT_Z }
	local model: Model? = nil
	if R and type(R.BuildItem) == "function" then
		model = R.BuildItem(itemId, entry, { Scale = WorldLayout.PX, Collide = false, Query = false, Shadows = false })
	end
	if not model then
		return false
	end
	local ghost = model :: Model
	ghost.Name = "TownEditGhost"
	for _, part in ipairs(ghost:GetDescendants()) do
		if part:IsA("BasePart") then
			part.CanCollide = false
			part.CanQuery = false
			part.CanTouch = false
			if part.Transparency < 1 then
				part.Transparency = math.max(part.Transparency, GHOST_ALPHA)
			end
		end
	end
	local fw, h, fd = footprint(ghost)
	local frame = WorldLayout.RoomFrame(house.HouseCF, house.Size, slot)
	ghost:PivotTo(frame * CFrame.new(0, 0, WorldLayout.DEPTH / 2) * TURN)
	ghost.Parent = workspace
	self.Held = {
		House = house,
		Slot = slot,
		Index = #room.Data.Placed + 1,
		Model = ghost,
		Start = ghost:GetPivot(),
		Entry = entry,
		Item = item,
		Wall = item.Placement == "Wall",
		AgainstWall = ghost:GetAttribute("AgainstWall") == true,
		FW = fw,
		FD = fd,
		H = h,
		R = nil,
		Frame = frame,
		X = 0,
		Y = 0,
		Z = WorldLayout.DEPTH / 2,
		TX = nil,
		TY = nil,
		TZ = nil,
		Support = nil,
		Level = nil,
		Followers = {},
		Moved = true,
		New = true,
	} :: Held
	-- point de départ : la souris (PC) ou le milieu de l'écran (doigt)
	local camera = workspace.CurrentCamera
	if UserInputService.TouchEnabled and not UserInputService.MouseEnabled and camera then
		self.Pointer = camera.ViewportSize / 2
	elseif not self.Pointer then
		local ok, mouse = pcall(function()
			return UserInputService:GetMouseLocation()
		end)
		self.Pointer = ok and typeof(mouse) == "Vector2" and mouse or (camera and camera.ViewportSize / 2) or Vector2.new(400, 300)
	end
	self:SetHighlight(ghost, true)
	self.Ctx.Hud:SetEditing(true, true, item.Icon .. " " .. Locale.T(item.Name))
	self:Follow()
	return true
end

-- (v9.6) Dessus visé : le meuble `model` touché au point `hit` (monde).
-- Choisit le NIVEAU (la planche juste sous le point visé), la position le
-- long du rayon (libre, sans chevaucher les voisins) ; renvoie la position
-- 3D montrée (repère de la pièce, = House3DLayout) et la 2D à sauvegarder.
function FurnitureEdit.SurfaceTarget(self: any, held: Held, model: Model, hit: Vector3): any?
	local S = surfaces()
	local room = held.House.Rooms[held.Slot]
	local supportIndex = tonumber(model:GetAttribute("EntryIndex"))
	local list = room and room.Data and room.Data.Placed
	local supportEntry = list and supportIndex and list[supportIndex]
	local supportItem = supportEntry and HouseCommon.ItemsById[supportEntry.I]
	if not S or not supportEntry or not supportItem or supportEntry == held.Entry then
		return nil
	end
	local dims = dimsOf(held.House)
	local item = held.Item
	local scale = tonumber(held.Entry.S) or 1
	local height = item.Size * scale / math.max(1, dims.RoomHpx)
	local ok, levels = pcall(S.Of, supportEntry, dims.RoomWpx, dims.RoomHpx)
	if not ok or type(levels) ~= "table" then
		return nil
	end
	local pivot = model:GetPivot()
	local localHit = pivot:PointToObjectSpace(hit)
	local minY = S.MinY()
	local best, bestTop = nil, nil
	local lowest, lowestTop = nil, nil
	for _, level in ipairs(levels) do
		local top = topLocal(model, level.Index, supportEntry, supportItem)
		local _, clampedY = HouseCommon.ClampPosition(item, (level.L + level.R) / 2, level.Y, scale, dims.RoomWpx, dims.RoomHpx, true)
		if top and level.Y >= minY and S.Fits(level, height) and level.R - level.L > 0.005 and math.abs(clampedY - level.Y) < 0.004 then
			if top.Y <= localHit.Y + LEVEL_REACH and (not bestTop or top.Y > bestTop.Y) then
				best, bestTop = level, top
			end
			if not lowestTop or top.Y < lowestTop.Y then
				lowest, lowestTop = level, top
			end
		end
	end
	if not best then
		best, bestTop = lowest, lowestTop
	end
	if not best or not bestTop then
		return nil
	end
	local level = best
	local top = bestTop :: Vector3
	-- le long du rayon : axe "droite de la pièce" = -X du modèle (devant -Z)
	local roomW = math.max(0.1, dims.W)
	local centerX = (level.L + level.R) / 2
	local X = centerX + (-(localHit.X - top.X)) / roomW
	if self.Snap then
		X = centerX + WorldLayout.Snap((X - centerX) * roomW, GRID / 2) / roomW
	end
	X = math.clamp(X, level.L, level.R)
	local skip: { [any]: boolean } = { [held.Entry] = true }
	for _, follower in ipairs(held.Followers) do
		local other = list[follower.Index]
		if other then
			skip[other] = true
		end
	end
	X = S.FreeX(level, list, item, scale, X, dims.RoomWpx, dims.RoomHpx, skip)
	local Y
	X, Y = HouseCommon.ClampPosition(item, X, level.Y, scale, dims.RoomWpx, dims.RoomHpx, true)
	X, Y = WorldLayout.Round4(X), WorldLayout.Round4(Y)
	-- 3D : même calcul que House3DLayout (dessus du meuble + décalage le long du rayon)
	local half = (level.R - level.L) / 2 * roomW
	local dx = math.clamp((X - centerX) * roomW, -half, half)
	local world = (pivot * CFrame.new(top)).Position + (-pivot.RightVector) * dx
	local rel = held.Frame:PointToObjectSpace(world)
	local plateCF = pivot * CFrame.new(top)
	return {
		X = rel.X,
		Y = rel.Y,
		Z = rel.Z,
		TX = X,
		TY = Y,
		TZ = math.min(HouseCommon.MAX_Z, (tonumber(supportEntry.Z) or 100) + 1),
		Level = level.Index,
		Plate = plateCF,
		PlateSize = Vector2.new(half * 2, math.min(3, math.max(0.4, held.FD * 1.2))),
	}
end

-- (v9.6) Le rayon passe juste au-dessus d'un dessus (plan horizontal de
-- chaque dessus, avec une petite marge) : (meuble, point sur le dessus)
local TOP_MARGIN = 0.35
function FurnitureEdit.NearTop(_self: any, held: Held, ray: Ray, models: { Instance }): (Model?, Vector3?)
	local room = held.House.Rooms[held.Slot]
	local list = room and room.Data and room.Data.Placed
	local S = surfaces()
	if not list or not S then
		return nil, nil
	end
	local bestModel, bestPoint, bestT = nil, nil, math.huge
	for _, instance in ipairs(models) do
		local model = instance :: Model
		local index = tonumber(model:GetAttribute("EntryIndex"))
		local entry = index and list[index]
		local item = entry and HouseCommon.ItemsById[entry.I]
		local raw = entry and S.Raw(entry.I)
		if entry and item and raw and entry ~= held.Entry then
			local pivot = model:GetPivot()
			local _, _, fd = footprint(model)
			local k = unitK(item, tonumber(entry.S) or 1)
			for level = 1, #raw do
				local top = topLocal(model, level, entry, item)
				if top then
					local world = pivot * top
					local dy = ray.Direction.Y
					if math.abs(dy) > 1e-4 then
						local t = (world.Y - ray.Origin.Y) / dy
						if t > 0 and t < bestT then
							local p = ray.Origin + ray.Direction * t
							local rel = pivot:PointToObjectSpace(p)
							local s = raw[level]
							local halfW = ((tonumber(s[2]) or 90) - (tonumber(s[1]) or 10)) * k / 2
							if math.abs(rel.X - top.X) <= halfW + TOP_MARGIN and math.abs(rel.Z - top.Z) <= fd * 0.5 + TOP_MARGIN then
								bestModel, bestPoint, bestT = model, p + Vector3.new(0, 0.01, 0), t
							end
						end
					end
				end
			end
		end
	end
	return bestModel, bestPoint
end

-- Chaque image (seulement en main) : le meuble suit le pointeur
function FurnitureEdit.Follow(self: any)
	local held: Held? = self.Held
	if not held then
		-- survol (PC) : on montre ce qu'on peut prendre
		local pointer = self.Pointer
		if pointer and not (UserInputService.TouchEnabled and not UserInputService.MouseEnabled) then
			local result = self:Raycast(pointer)
			local model = result and itemModelOf(result.Instance)
			if model ~= self.Hover then
				self.Hover = model
				self:SetHighlight(model, false)
			end
		end
		return
	end
	local pointer = self.Pointer
	local camera = workspace.CurrentCamera
	if not pointer or not camera then
		return
	end
	local ray = camera:ViewportPointToRay(pointer.X, pointer.Y)
	local house = held.House
	local dims = dimsOf(house)
	local frame = held.Frame
	local item = held.Item
	local scale = tonumber(held.Entry.S) or 1
	if held.Wall then
		local p = hitPlane(frame, ray.Origin, ray.Direction, "z")
		if not p then
			return
		end
		local x, y = p.X, p.Y - held.H / 2
		if self.Snap then
			x = WorldLayout.Snap(x, GRID)
			y = WorldLayout.Snap(y, GRID / 2)
		end
		-- (v9.6) borné à la zone murale de la 2D (le fantôme = ce qui sera sauvé)
		local x0, x1, y0, y1 = HouseCommon.PlacementArea(item, scale, dims.RoomWpx, dims.RoomHpx)
		local X, Y
		x, y, X, Y = WorldLayout.WallClamp(dims, x, y, held.FW, unitK(item, scale), x0, x1, y0, y1)
		held.X, held.Y, held.Z = x, y, 0.02
		held.TX, held.TY, held.TZ = X, Y, tonumber(held.Entry.Z) or HouseCommon.DEFAULT_Z
		held.Support, held.Level = nil, nil
		self:SetTarget(nil)
	else
		-- au-dessus d'un meuble avec un dessus ? (petits objets seulement)
		local target: any = nil
		local supportModel: Model? = nil
		local S = surfaces()
		if HouseCommon.CanGoOnFurniture(item) and S then
			local params = RaycastParams.new()
			params.FilterType = Enum.RaycastFilterType.Include
			local room = house.Rooms[held.Slot]
			local include: { Instance } = {}
			-- (v9.6) seulement les meubles qui ont un dessus : le rayon traverse
			-- les petits objets déjà posés et trouve le rayon / la table dessous
			for _, other in ipairs(room and room.Items or {}) do
				if other ~= held.Model and other.Parent and S.Has(tostring(other:GetAttribute("ItemId"))) then
					local isFollower = false
					for _, f in ipairs(held.Followers) do
						if f.Model == other then
							isFollower = true
						end
					end
					if not isFollower then
						table.insert(include, other)
					end
				end
			end
			params.FilterDescendantsInstances = include
			local hit = workspace:Raycast(ray.Origin, ray.Direction * 250, params)
			local model = hit and itemModelOf(hit.Instance)
			if model and hit and S.Has(tostring(model:GetAttribute("ItemId"))) then
				target = self:SurfaceTarget(held, model, hit.Position)
				supportModel = target and model or nil
			end
			-- (v9.6) pointeur juste AU-DESSUS d'un dessus (table basse vue de
			-- face, le rayon passe au-dessus) : on le "voit" quand même
			if not target then
				local near, point = self:NearTop(held, ray, include)
				if near and point then
					target = self:SurfaceTarget(held, near, point)
					supportModel = target and near or nil
				end
			end
		end
		if target then
			held.X, held.Y, held.Z = target.X, target.Y, target.Z
			held.TX, held.TY, held.TZ = target.TX, target.TY, target.TZ
			held.Support, held.Level = supportModel, target.Level
			self:SetTarget(supportModel, target.Plate, target.PlateSize)
		else
			local p = hitPlane(frame, ray.Origin, ray.Direction, "y")
			if not p then
				return
			end
			local x, z = p.X, p.Z
			if self.Snap then
				x = WorldLayout.Snap(x, GRID)
				z = WorldLayout.Snap(z, GRID)
			end
			-- (v9.6) borné à ce qui retombe DANS la bande du sol de la 2D
			local x0, x1, y0, y1 = HouseCommon.PlacementArea(item, scale, dims.RoomWpx, dims.RoomHpx, false)
			local X, Y
			x, z, X, Y = WorldLayout.FloorClamp(dims, x, z, held.FW, held.FD, x0, x1, y0, y1, held.AgainstWall)
			held.X, held.Y, held.Z = x, 0, z
			held.TX, held.TY, held.TZ = X, Y, tonumber(held.Entry.Z) or HouseCommon.DEFAULT_Z
			held.Support, held.Level = nil, nil
			self:SetTarget(nil)
		end
	end
	held.Moved = true
	self:Place()
end

-- Pose le modèle tenu (et ses suiveurs) à sa position actuelle
function FurnitureEdit.Place(self: any)
	local held: Held? = self.Held
	if not held then
		return
	end
	local yaw = held.Wall and 0 or math.rad(held.R or 0)
	local pivot = held.Frame * CFrame.new(held.X, held.Y, held.Z) * CFrame.Angles(0, yaw, 0) * TURN
	held.Model:PivotTo(pivot)
	for _, follower in ipairs(held.Followers) do
		if follower.Model.Parent then
			follower.Model:PivotTo(pivot * follower.Offset)
		end
	end
end

----------------------------------------------------------------------
-- Actions
----------------------------------------------------------------------

function FurnitureEdit.Rotate(self: any, delta: number?)
	local held: Held? = self.Held
	if not held or held.Wall then
		return
	end
	held.R = WorldLayout.Rotate(held.R, delta or ROTATE_STEP)
	-- les suiveurs tournent avec le meuble
	self:Place()
end

function FurnitureEdit.ToggleSnap(self: any)
	self.Snap = not self.Snap
	self.Ctx.Hud:SetSnap(self.Snap)
end

-- Lâche le modèle tenu (le fantôme d'un objet neuf disparaît)
function FurnitureEdit.Release(self: any, held: Held)
	self.Held = nil
	if held.New and held.Model.Parent then
		held.Model:Destroy()
	end
	self:SetHighlight(nil, false)
	self:SetTarget(nil)
	self.Ctx.Hud:SetEditing(self.Enabled, false)
end

function FurnitureEdit.Cancel(self: any)
	local held: Held? = self.Held
	if not held then
		return
	end
	if not held.New then
		if held.Model.Parent then
			held.Model:PivotTo(held.Start)
		end
		for _, follower in ipairs(held.Followers) do
			if follower.Model.Parent then
				follower.Model:PivotTo(follower.Start)
			end
		end
	end
	self:Release(held)
end

-- Copie d'une liste d'objets posés (format du serveur, avec R)
local function copyList(list: { any }): { any }
	local result = {}
	for index, e in ipairs(list) do
		result[index] = { I = e.I, X = e.X, Y = e.Y, S = e.S, Z = e.Z, F = e.F, C = e.C, R = e.R }
	end
	return result
end

-- Nouvelle position 2D (X, Y, Z) de l'objet tenu : celle calculée en le
-- suivant (déjà dans la zone valide) ; sinon sa position actuelle
function FurnitureEdit.Compute2D(_self: any, held: Held, list: { any }): (number, number, number)
	local entry = list[held.Index] or held.Entry
	if held.TX and held.TY then
		return held.TX, held.TY, held.TZ or tonumber(entry.Z) or HouseCommon.DEFAULT_Z
	end
	return tonumber(entry.X) or 0.5, tonumber(entry.Y) or 0.8, tonumber(entry.Z) or HouseCommon.DEFAULT_Z
end

function FurnitureEdit.Commit(self: any, held: Held, list: { any }, message: string)
	local house = held.House
	local room = house.Rooms[held.Slot]
	if not room or not room.Data then
		return
	end
	local previous = copyList(room.Data.Placed)
	-- la pièce est reconstruite tout de suite (même rendu qu'après un rechargement)
	house:SetRoomPlaced(held.Slot, list)
	self.Saving = true
	self.Ctx.Save(held.Slot, tostring(room.Data.Id), list, function(ok: boolean, reply: string?)
		self.Saving = false
		if ok then
			self.Ctx.Toast(message, Color3.fromRGB(80, 200, 160))
		else
			self.Ctx.Toast(reply or Locale.T("Network error, try again."), Color3.fromRGB(226, 80, 90))
			if house.Alive then
				house:SetRoomPlaced(held.Slot, previous)
			end
		end
		self:RefreshTray(true)
	end)
end

function FurnitureEdit.Drop(self: any)
	local held: Held? = self.Held
	if not held then
		return
	end
	local room = held.House.Rooms[held.Slot]
	if not room or not room.Data or self.Saving then
		self:Cancel()
		return
	end
	local list = copyList(room.Data.Placed)
	if held.New then
		-- (v9.6) objet de l'inventaire : une nouvelle entrée dans la pièce
		if not held.TX then
			self:Follow()
		end
		local X, Y, Z = self:Compute2D(held, list)
		table.insert(list, { I = held.Item.Id, X = WorldLayout.Round4(X), Y = WorldLayout.Round4(Y), S = 1, Z = Z, R = not held.Wall and held.R or nil })
		self:Release(held)
		self:Commit(held, list, Locale.T("✨ %s placed!", held.Item.Icon .. " " .. Locale.T(held.Item.Name)))
		return
	end
	local entry = list[held.Index]
	if not entry then
		self:Cancel()
		return
	end
	local oldX, oldY = tonumber(entry.X) or 0.5, tonumber(entry.Y) or 0.8
	local X, Y, Z = self:Compute2D(held, list)
	entry.X = WorldLayout.Round4(X)
	entry.Y = WorldLayout.Round4(Y)
	entry.Z = Z
	entry.R = not held.Wall and held.R or entry.R
	-- ce qui suit (posé dessus, chaises) : même décalage en 2D, dans sa zone
	local dx, dy = entry.X - oldX, entry.Y - oldY
	local dims = dimsOf(held.House)
	for _, follower in ipairs(held.Followers) do
		local other = list[follower.Index]
		local otherItem = other and HouseCommon.ItemsById[other.I]
		if other and otherItem then
			local x, y = (tonumber(other.X) or 0.5) + dx, (tonumber(other.Y) or 0.8) + dy
			x, y = HouseCommon.ClampPosition(otherItem, x, y, tonumber(other.S) or 1, dims.RoomWpx, dims.RoomHpx, HouseCommon.CanGoOnFurniture(otherItem))
			other.X = WorldLayout.Round4(x)
			other.Y = WorldLayout.Round4(y)
		end
	end
	local moved = held.Moved
	self:Release(held)
	if not moved and held.R == WorldLayout.NormalizeRotation(room.Data.Placed[held.Index].R) then
		return
	end
	self:Commit(held, list, Locale.T("🏠 Layout saved"))
end

function FurnitureEdit.PutAway(self: any)
	local held: Held? = self.Held
	if not held then
		return
	end
	if held.New then
		-- (fantôme : il retourne simplement dans l'inventaire)
		self:Release(held)
		return
	end
	local room = held.House.Rooms[held.Slot]
	if not room or not room.Data or self.Saving then
		self:Cancel()
		return
	end
	local list = copyList(room.Data.Placed)
	-- ce qui est posé DESSUS part aussi dans l'inventaire (les chaises restent)
	local remove: { [number]: boolean } = { [held.Index] = true }
	local S = surfaces()
	if S then
		local dims = dimsOf(held.House)
		for _, follower in ipairs(held.Followers) do
			local other = room.Data.Placed[follower.Index]
			local ok, support = pcall(S.SupportOf, other, room.Data.Placed, dims.RoomWpx, dims.RoomHpx)
			if ok and support then
				remove[follower.Index] = true
			end
		end
	end
	local kept = {}
	for index, e in ipairs(list) do
		if not remove[index] then
			table.insert(kept, e)
		end
	end
	self:Release(held)
	self:Commit(held, kept, Locale.T("📦 Put back in your inventory"))
end

function FurnitureEdit.IsHolding(self: any): boolean
	return self.Held ~= nil
end

----------------------------------------------------------------------
-- (v9.6) 📦 Plateau d'inventaire (objets possédés mais pas posés) + achat
----------------------------------------------------------------------

type Tray = {
	Gui: ScreenGui,
	Root: Frame,
	Scale: UIScale,
	Panel: Frame,
	Title: TextLabel,
	Toggle: TextButton,
	BuyButton: TextButton,
	BackButton: TextButton,
	Chips: ScrollingFrame,
	Grid: ScrollingFrame,
	Empty: TextLabel,
	Tiles: { Instance },
	ChipButtons: { Instance },
}

-- Objets rangés (possédés - posés dans toutes les pièces), triés par catégorie
local function inventory(): { { Item: any, Count: number } }
	local house = HouseCommon.GetHouse(ClientState.Data)
	local result = {}
	for _, item in ipairs(HouseCommon.Config.Items) do
		local count = HouseCommon.Available(house, item.Id)
		if count > 0 then
			table.insert(result, { Item = item, Count = count })
		end
	end
	return result
end

local function categoryOrder(id: string): number
	for index, category in ipairs(HouseCommon.Config.Categories) do
		if category.Id == id then
			return index
		end
	end
	return 999
end

function FurnitureEdit.BuildTray(self: any)
	local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")
	local old = playerGui:FindFirstChild(GUI_NAME)
	if old then
		old:Destroy()
	end
	local gui = Instance.new("ScreenGui")
	gui.Name = GUI_NAME
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = false
	gui.ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.DisplayOrder = 21
	gui.Enabled = false
	gui.Parent = playerGui
	-- (comme TownHud : une toile "Root" à l'échelle de l'écran)
	local root = UIUtil.Create("Frame", {
		Name = "Root",
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(1100, 620),
		Parent = gui,
	})
	local scale = UIUtil.Create("UIScale", { Parent = root })

	local panel = UIUtil.Create("Frame", {
		Name = "InventoryTray",
		Position = UDim2.fromOffset(10, 66),
		Size = UDim2.fromOffset(300, 420),
		BackgroundColor3 = CARD,
		Parent = root,
	})
	UIUtil.Corner(panel, 20)
	UIUtil.Stroke(panel, LILAC, 2, 0.1)
	UIUtil.Shadow(panel, 3, 0.8)
	UIUtil.SinkClicks(panel)
	UIUtil.Gradient(panel, ColorSequence.new(Color3.fromRGB(255, 255, 255), Color3.fromRGB(246, 238, 255)), 90)

	local title = UIUtil.Create("TextLabel", {
		Name = "Title",
		BackgroundTransparency = 1,
		Font = Theme.Fonts.Title,
		TextColor3 = INK,
		TextSize = 19,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextTruncate = Enum.TextTruncate.AtEnd,
		Text = "",
		Position = UDim2.fromOffset(14, 8),
		Size = UDim2.new(1, -60, 0, 34),
		ZIndex = 2,
		Parent = panel,
	})
	local toggle = UIUtil.PillButton({ Name = "TrayToggle", Text = "▾", Color = WHITE, TextColor3 = INK, Height = 30, Round = true, TextSize = 18, Parent = panel })
	toggle.AnchorPoint = Vector2.new(1, 0)
	toggle.Position = UDim2.new(1, -10, 0, 10)
	toggle.ZIndex = 3
	-- (en bas, toute la largeur : "🛍️ Acheter" / retour à l'inventaire)
	local buy = UIUtil.PillButton({ Name = "TrayBuy", Text = Locale.T("🛍️ Buy"), Color = PINK_DEEP, Height = 40, TextSize = 18, Parent = panel })
	buy.AutomaticSize = Enum.AutomaticSize.None
	buy.AnchorPoint = Vector2.new(0.5, 1)
	buy.Position = UDim2.new(0.5, 0, 1, -10)
	buy.Size = UDim2.new(1, -24, 0, 40)
	buy.ZIndex = 3
	local back = UIUtil.PillButton({ Name = "TrayBack", Text = Locale.T("📦 Inventory"), Color = SKY, Height = 40, TextSize = 18, Parent = panel })
	back.AutomaticSize = Enum.AutomaticSize.None
	back.AnchorPoint = Vector2.new(0.5, 1)
	back.Position = UDim2.new(0.5, 0, 1, -10)
	back.Size = UDim2.new(1, -24, 0, 40)
	back.ZIndex = 3
	back.Visible = false

	local chips = UIUtil.Create("ScrollingFrame", {
		Name = "Chips",
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Position = UDim2.fromOffset(10, 46),
		Size = UDim2.new(1, -20, 0, 34),
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.X,
		ScrollingDirection = Enum.ScrollingDirection.X,
		ScrollBarThickness = 0,
		ZIndex = 2,
		Parent = panel,
	})
	UIUtil.Create("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		VerticalAlignment = Enum.VerticalAlignment.Center,
		Padding = UDim.new(0, 6),
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = chips,
	})
	UIUtil.Create("UIPadding", { PaddingLeft = UDim.new(0, 3), PaddingRight = UDim.new(0, 3), Parent = chips })

	local grid = UIUtil.Create("ScrollingFrame", {
		Name = "Grid",
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Position = UDim2.fromOffset(8, 86),
		Size = UDim2.new(1, -16, 1, -144),
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollingDirection = Enum.ScrollingDirection.Y,
		ScrollBarThickness = 5,
		ScrollBarImageColor3 = LILAC,
		ZIndex = 2,
		Parent = panel,
	})
	UIUtil.Create("UIGridLayout", {
		CellSize = UDim2.fromOffset(84, 92),
		CellPadding = UDim2.fromOffset(6, 6),
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = grid,
	})
	UIUtil.Create("UIPadding", { PaddingTop = UDim.new(0, 2), PaddingBottom = UDim.new(0, 6), Parent = grid })
	local empty = UIUtil.Create("TextLabel", {
		Name = "Empty",
		BackgroundTransparency = 1,
		Font = Theme.Fonts.Body,
		TextColor3 = INK,
		TextSize = 16,
		TextWrapped = true,
		Text = "",
		Position = UDim2.fromOffset(20, 110),
		Size = UDim2.new(1, -40, 0, 80),
		Visible = false,
		ZIndex = 3,
		Parent = panel,
	})

	local tray: Tray = {
		Gui = gui,
		Root = root,
		Scale = scale,
		Panel = panel,
		Title = title,
		Toggle = toggle,
		BuyButton = buy,
		BackButton = back,
		Chips = chips,
		Grid = grid,
		Empty = empty,
		Tiles = {},
		ChipButtons = {},
	}
	self.Tray = tray
	toggle.Activated:Connect(function()
		self.TrayOpen = not self.TrayOpen
		self:LayoutTray()
	end)
	buy.Activated:Connect(function()
		self:OpenBuy()
	end)
	back.Activated:Connect(function()
		self.TrayView = "Inventory"
		self:RefreshTray(true)
	end)
	gui:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
		self:LayoutTray()
	end)
	self:LayoutTray()
end

-- Taille / place du plateau (PC : à gauche ; téléphone : compact, au-dessus du joystick)
function FurnitureEdit.LayoutTray(self: any)
	local tray: Tray? = self.Tray
	if not tray then
		return
	end
	local size = tray.Gui.AbsoluteSize
	if size.X < 10 or size.Y < 10 then
		-- (pas encore mesuré : la taille de l'écran)
		local camera = workspace.CurrentCamera
		size = camera and camera.ViewportSize or Vector2.new(1280, 720)
	end
	local touch = UserInputService.TouchEnabled and not UserInputService.MouseEnabled
	local phone = touch and math.min(size.X, size.Y) < 500
	local designW, designH = phone and 820 or 1100, phone and 430 or 620
	local scale = math.clamp(math.min(size.X / designW, size.Y / designH), 0.45, 1.35)
	tray.Scale.Scale = scale
	tray.Root.Size = UDim2.fromOffset(size.X / scale, size.Y / scale)
	local h = size.Y / scale
	-- (bas : la barre d'édition du HUD au PC, le joystick au téléphone)
	local top = phone and 62 or 66
	local bottom = phone and 150 or 96
	local width = phone and 250 or 300
	local height = self.TrayOpen and math.max(170, math.min(480, h - top - bottom)) or 50
	tray.Panel.Position = UDim2.fromOffset(phone and 8 or 10, top)
	tray.Panel.Size = UDim2.fromOffset(width, height)
	tray.Toggle.Text = self.TrayOpen and "▾" or "▸"
	tray.Chips.Visible = self.TrayOpen
	tray.Grid.Visible = self.TrayOpen
	tray.Empty.Visible = self.TrayOpen and tray.Empty.Text ~= ""
	local buying = self.TrayView == "Buy"
	tray.BuyButton.Visible = self.TrayOpen and not buying
	tray.BackButton.Visible = self.TrayOpen and buying
	local grid = tray.Grid:FindFirstChildOfClass("UIGridLayout")
	if grid then
		local cell = phone and 70 or 84
		grid.CellSize = UDim2.fromOffset(cell, cell + 8)
	end
end

function FurnitureEdit.ShowTray(self: any, visible: boolean)
	local tray: Tray? = self.Tray
	if not tray then
		return
	end
	tray.Gui.Enabled = visible
	if visible then
		self.TrayView = "Inventory"
		self:LayoutTray()
		self:RefreshTray(true)
	end
end

local function clearList(list: { Instance })
	for _, child in ipairs(list) do
		child:Destroy()
	end
	table.clear(list)
end

-- Une case (icône, nom, nombre en pastille ou prix sous l'icône)
local function makeTile(parent: Instance, item: any, badge: string, badgeColor: Color3, order: number, dim: boolean, price: boolean?): TextButton
	local tile = UIUtil.Create("TextButton", {
		Name = "Tile_" .. item.Id,
		Text = "",
		AutoButtonColor = false,
		BackgroundColor3 = dim and Color3.fromRGB(238, 234, 244) or WHITE,
		LayoutOrder = order,
		ZIndex = 3,
		Parent = parent,
	})
	UIUtil.Corner(tile, 14)
	UIUtil.Stroke(tile, HouseCommon.CategoryTint(item.Category), 2, dim and 0.6 or 0.15)
	UIUtil.Create("TextLabel", {
		Name = "Icon",
		BackgroundTransparency = 1,
		Font = Theme.Fonts.Title,
		Text = item.Icon,
		TextSize = price and 28 or 34,
		TextTransparency = dim and 0.45 or 0,
		Position = UDim2.fromOffset(0, price and 2 or 6),
		Size = UDim2.new(1, 0, 0, price and 36 or 42),
		ZIndex = 4,
		Parent = tile,
	})
	UIUtil.Create("TextLabel", {
		Name = "Name",
		BackgroundTransparency = 1,
		Font = Theme.Fonts.Body,
		Text = Locale.T(item.Name),
		TextColor3 = INK,
		TextSize = 12,
		TextTruncate = Enum.TextTruncate.AtEnd,
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -4),
		Size = UDim2.new(1, -8, 0, 16),
		ZIndex = 4,
		Parent = tile,
	})
	local pill = UIUtil.Create("TextLabel", {
		Name = "Badge",
		BackgroundColor3 = badgeColor,
		Font = Theme.Fonts.Number,
		Text = badge,
		TextColor3 = WHITE,
		TextSize = 12,
		AutomaticSize = Enum.AutomaticSize.X,
		AnchorPoint = price and Vector2.new(0.5, 0) or Vector2.new(1, 0),
		Position = price and UDim2.new(0.5, 0, 0, 40) or UDim2.new(1, -4, 0, 4),
		Size = UDim2.fromOffset(0, 18),
		ZIndex = 5,
		Parent = tile,
	})
	UIUtil.Corner(pill, UDim.new(1, 0))
	UIUtil.Create("UIPadding", { PaddingLeft = UDim.new(0, 5), PaddingRight = UDim.new(0, 5), Parent = pill })
	UIUtil.AnimateButton(tile, 1.05, 0.93)
	return tile
end

-- Rafraîchit le plateau (force = même si rien n'a changé)
function FurnitureEdit.RefreshTray(self: any, force: boolean?)
	local tray: Tray? = self.Tray
	if not tray or not tray.Gui.Enabled then
		return
	end
	local buying = self.TrayView == "Buy"
	local items = inventory()
	local total = 0
	local signature = { self.TrayView, tostring(self.Filter) }
	for _, entry in ipairs(items) do
		total += entry.Count
		table.insert(signature, entry.Item.Id .. "=" .. entry.Count)
	end
	if buying then
		table.insert(signature, tostring(math.floor(HouseCommon.Dopamine())))
	end
	local key = table.concat(signature, ",")
	if not force and key == self.TraySignature then
		return
	end
	self.TraySignature = key
	tray.Title.Text = buying and Locale.T("🛍️ Buy") or Locale.T("📦 Inventory (%d)", total)
	-- catégories présentes
	clearList(tray.ChipButtons)
	local present: { [string]: boolean } = {}
	local source: { any } = {}
	if buying then
		local data = ClientState.Data
		local house = HouseCommon.GetHouse(data)
		for _, item in ipairs(HouseCommon.Config.Items) do
			local owned = HouseCommon.Owned(house, item.Id)
			if HouseCommon.IsUnlocked(data, item) and not HouseCommon.IsMaxed(item, owned) then
				table.insert(source, { Item = item, Price = HouseCommon.Price(item, owned) })
			end
		end
	else
		source = items
	end
	for _, entry in ipairs(source) do
		present[entry.Item.Category] = true
	end
	if self.Filter and not present[self.Filter] then
		self.Filter = nil
	end
	local chipSpecs = { { Id = nil, Text = Locale.T("All") } }
	for _, category in ipairs(HouseCommon.Config.Categories) do
		if present[category.Id] then
			table.insert(chipSpecs, { Id = category.Id, Text = category.Icon })
		end
	end
	for order, spec in ipairs(chipSpecs) do
		local selected = spec.Id == self.Filter
		local chip = UIUtil.PillButton({ Name = "Chip_" .. tostring(spec.Id or "All"), Text = spec.Text, Color = selected and LILAC or WHITE,
			TextColor3 = selected and WHITE or INK, Height = 28, TextSize = 15, LayoutOrder = order, Shadow = false, Parent = tray.Chips })
		chip.ZIndex = 3
		chip.Activated:Connect(function()
			self.Filter = spec.Id
			self:RefreshTray(true)
		end)
		table.insert(tray.ChipButtons, chip)
	end
	-- cases
	clearList(tray.Tiles)
	local shown = {}
	for _, entry in ipairs(source) do
		if self.Filter == nil or entry.Item.Category == self.Filter then
			table.insert(shown, entry)
		end
	end
	table.sort(shown, function(a, b)
		if buying and a.Price ~= b.Price then
			return a.Price < b.Price
		end
		local ca, cb = categoryOrder(a.Item.Category), categoryOrder(b.Item.Category)
		if ca ~= cb then
			return ca < cb
		end
		return (a.Item.Order or 0) < (b.Item.Order or 0)
	end)
	local dopamine = HouseCommon.Dopamine()
	for order, entry in ipairs(shown) do
		if order > 120 then
			break
		end
		local item = entry.Item
		local tile
		if buying then
			local affordable = dopamine >= entry.Price
			tile = makeTile(tray.Grid, item, "🧠 " .. NumberFormatter.Format(entry.Price), affordable and MINT or Color3.fromRGB(190, 180, 200), order, not affordable, true)
			tile.Activated:Connect(function()
				self:Buy(item.Id, entry.Price)
			end)
		else
			tile = makeTile(tray.Grid, item, "x" .. tostring(entry.Count), PINK_DEEP, order, false)
			tile.Activated:Connect(function()
				self:HoldNew(item.Id)
			end)
		end
		table.insert(tray.Tiles, tile)
	end
	if #shown == 0 then
		tray.Empty.Text = buying and Locale.T("Nothing to buy here for now") or Locale.T("Everything is placed! 🛍️ Buy something new")
	else
		tray.Empty.Text = ""
	end
	self:LayoutTray()
end

-- "🛍️ Acheter" : le catalogue de la ville (sinon la petite liste d'ici)
function FurnitureEdit.OpenBuy(self: any)
	local shop = shopUI()
	if shop and type(shop.OpenCategory) == "function" then
		-- catégorie : le filtre du plateau, sinon la préférée du type de la pièce
		local category = self.Filter
		if not category then
			local house = self.Ctx.GetHouse()
			local slot = house and self:CurrentSlot(house)
			local room = slot and house.Rooms[slot]
			local roomType = room and room.Data and HouseCommon.RoomTypesById[tostring(room.Data.Type)]
			category = roomType and roomType.Categories[1] or nil
		end
		self.AwaitBuy = true
		if not self.ShopConnection and shop.Bought and type(shop.Bought.Connect) == "function" then
			self.ShopConnection = shop.Bought:Connect(function(itemId: any, kind: any)
				if self.AwaitBuy and self.Enabled and kind == "Item" and type(itemId) == "string" then
					self.AwaitBuy = false
					pcall(function()
						shop.Close()
					end)
					self:HoldNew(itemId, true)
				end
			end)
		end
		local ok = pcall(shop.OpenCategory, category)
		if ok then
			return
		end
		self.AwaitBuy = false
	end
	self.TrayView = "Buy"
	self.TrayOpen = true
	self:RefreshTray(true)
end

-- Achat direct (liste de secours) : action existante "buyItem", puis fantôme
function FurnitureEdit.Buy(self: any, itemId: string, price: number)
	local item = HouseCommon.ItemsById[itemId]
	if not item or self.Buying then
		return
	end
	if HouseCommon.Dopamine() < price then
		self.Ctx.Toast(Locale.T("Not enough Dopamine"), Color3.fromRGB(255, 170, 90))
		return
	end
	self.Buying = true
	task.spawn(function()
		local ok, message = HouseCommon.Invoke("buyItem", itemId)
		self.Buying = false
		if ok then
			self.Ctx.Toast(message or Locale.T("%s is yours!", item.Icon .. " " .. Locale.T(item.Name)), Color3.fromRGB(80, 200, 160))
			self.TrayView = "Inventory"
			self:RefreshTray(true)
			self:HoldNew(itemId, true)
		else
			self.Ctx.Toast(message or Locale.T("Network error, try again."), Color3.fromRGB(226, 80, 90))
		end
	end)
end

function FurnitureEdit.Destroy(self: any)
	self:SetEnabled(false)
	for _, name in ipairs({ "Highlight", "TargetHighlight", "Plate" }) do
		local instance = self[name]
		if instance then
			instance:Destroy()
			self[name] = nil
		end
	end
	if self.ShopConnection then
		pcall(function()
			self.ShopConnection:Disconnect()
		end)
		self.ShopConnection = nil
	end
	local tray: Tray? = self.Tray
	if tray then
		tray.Gui:Destroy()
		self.Tray = nil
	end
end

return FurnitureEdit
