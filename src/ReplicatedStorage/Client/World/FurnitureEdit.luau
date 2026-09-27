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
	  - un petit objet (Formulas.CanGoOnFurniture) lâché au-dessus d'un meuble
	    qui a un dessus (HouseSurfaces) se pose DESSUS ; ce qui est posé sur un
	    meuble et les chaises rangées à une table suivent le meuble ;
	  - à la pose : conversion 3D -> 2D (WorldLayout.FloorInverse /
	    WallInverse, dessus : HouseSurfaces.Of), la pièce est reconstruite
	    tout de suite (même rendu qu'après un rechargement) et la disposition
	    part au serveur par l'action existante "saveLayout" (tout y est vérifié :
	    objets possédés, zones, rotation) ; refus -> retour en arrière.
	La maison 2D et la maison 3D restent donc toujours la même maison.
	Entrées : ContextActionService (priorité haute) pendant l'édition : le
	doigt qui déplace un meuble ne fait pas tourner la caméra.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local ContextActionService = game:GetService("ContextActionService")
local RunService = game:GetService("RunService")

local WorldLayout = require(ReplicatedStorage.Shared.WorldLayout)
local Locale = require(ReplicatedStorage.Shared.Locale)

local HouseFolder = script.Parent.Parent.Components.House
local HouseCommon = require(HouseFolder.HouseCommon)

local FurnitureEdit = {}
FurnitureEdit.__index = FurnitureEdit

local ACTION = "DopamineTownEdit"
local RENDER = "DopamineTownEditFollow"
local GRID = 1 -- (studs) aimant
local ROTATE_STEP = 45
local TURN = CFrame.Angles(0, math.pi, 0) -- modèle (devant -Z) <-> repère des recettes (devant +Z)

export type Context = {
	GetHouse: () -> any?, -- maison du joueur (HouseBuilder) ou nil
	Hud: any,
	Toast: (text: string, color: Color3?) -> (),
	Save: (slot: number, roomId: string, placed: { any }, onResult: (ok: boolean, message: string?) -> ()) -> (),
}

type Held = {
	House: any,
	Slot: number,
	Index: number, -- index dans room.Placed
	Model: Model,
	Start: CFrame,
	Entry: any,
	Item: any,
	Wall: boolean,
	FW: number,
	FD: number,
	H: number,
	R: number?,
	Frame: CFrame, -- repère de la pièce
	X: number,
	Y: number,
	Z: number,
	Support: Model?,
	Followers: { { Model: Model, Offset: CFrame, Start: CFrame, Index: number } },
	Moved: boolean,
}

local surfacesModule: any = nil
local function surfaces(): any
	if surfacesModule == nil then
		local ok, result = pcall(require, HouseFolder:FindFirstChild("HouseSurfaces") :: ModuleScript)
		surfacesModule = ok and result or false
	end
	return surfacesModule or nil
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

function FurnitureEdit.new(ctx: Context)
	local self = setmetatable({
		Ctx = ctx,
		Enabled = false,
		Held = nil :: Held?,
		Snap = true,
		Pointer = nil :: Vector2?,
		Highlight = nil :: Highlight?,
		Hover = nil :: Model?,
		Dragging = false,
		PressAt = nil :: Vector2?,
		Connections = {} :: { RBXScriptConnection },
		Saving = false,
	}, FurnitureEdit)
	return self
end

----------------------------------------------------------------------
-- Surbrillance
----------------------------------------------------------------------

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
		local h = Instance.new("Highlight")
		h.Name = "TownEditHighlight"
		h.DepthMode = Enum.HighlightDepthMode.Occluded
		h.FillTransparency = 0.7
		h.OutlineTransparency = 0
		h.Parent = workspace
		highlight = h
		self.Highlight = h
	end
	local h = highlight :: Highlight
	h.Adornee = model
	h.Enabled = true
	h.FillColor = holding and Color3.fromRGB(110, 230, 170) or Color3.fromRGB(255, 180, 220)
	h.OutlineColor = holding and Color3.fromRGB(40, 170, 110) or Color3.fromRGB(236, 72, 140)
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
	end
	self.Ctx.Hud:SetEditing(enabled, false)
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
		FW = fw,
		FD = fd,
		H = h,
		R = WorldLayout.NormalizeRotation(entry.R),
		Frame = frame,
		X = rel.X,
		Y = rel.Y,
		Z = rel.Z,
		Support = nil,
		Followers = {},
		Moved = false,
	}
	-- ce qui suit le meuble (posé dessus, chaises à table)
	local S = surfaces()
	if S and type(S.Dependents) == "function" then
		local dims = WorldLayout.RoomDims(house.Size, HouseCommon.Config.WallRatio)
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
	local dims = WorldLayout.RoomDims(house.Size, HouseCommon.Config.WallRatio)
	local frame = held.Frame
	local halfW = dims.W / 2
	if held.Wall then
		local p = hitPlane(frame, ray.Origin, ray.Direction, "z")
		if not p then
			return
		end
		local x = math.clamp(p.X, -halfW + held.FW / 2 + 0.1, halfW - held.FW / 2 - 0.1)
		local y = math.clamp(p.Y - held.H / 2, 0.3, math.max(0.3, dims.WH - held.H - 0.2))
		if self.Snap then
			x = WorldLayout.Snap(x, GRID)
			y = WorldLayout.Snap(y, GRID / 2)
		end
		held.X, held.Y, held.Z = x, y, 0.02
		held.Support = nil
	else
		-- au-dessus d'un meuble avec un dessus ? (petits objets seulement)
		local support: Model? = nil
		local topY = 0
		local canStand = HouseCommon.CanGoOnFurniture(held.Item)
		local p: Vector3? = nil
		if canStand then
			local params = RaycastParams.new()
			params.FilterType = Enum.RaycastFilterType.Include
			local room = house.Rooms[held.Slot]
			local include: { Instance } = {}
			for _, other in ipairs(room and room.Items or {}) do
				if other ~= held.Model and other.Parent then
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
			local S = surfaces()
			if model and hit and S and S.Has(tostring(model:GetAttribute("ItemId"))) then
				local top = model:GetAttribute("TopHeight")
				if type(top) == "number" and top > 0.3 then
					support = model
					topY = frame:PointToObjectSpace(model:GetPivot().Position).Y + top
					p = frame:PointToObjectSpace(hit.Position)
				end
			end
		end
		if not p then
			p = hitPlane(frame, ray.Origin, ray.Direction, "y")
		end
		if not p then
			return
		end
		local point = p :: Vector3
		local x = math.clamp(point.X, -halfW + held.FW / 2 + 0.1, halfW - held.FW / 2 - 0.1)
		local z = math.clamp(point.Z, held.FD / 2 + 0.08, dims.D - held.FD / 2 - 0.1)
		if self.Snap and not support then
			x = WorldLayout.Snap(x, GRID)
			z = WorldLayout.Snap(z, GRID)
		end
		held.X, held.Y, held.Z = x, support and topY or 0, z
		held.Support = support
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

function FurnitureEdit.Cancel(self: any)
	local held: Held? = self.Held
	if not held then
		return
	end
	self.Held = nil
	if held.Model.Parent then
		held.Model:PivotTo(held.Start)
	end
	for _, follower in ipairs(held.Followers) do
		if follower.Model.Parent then
			follower.Model:PivotTo(follower.Start)
		end
	end
	self:SetHighlight(nil, false)
	self.Ctx.Hud:SetEditing(self.Enabled, false)
end

-- Copie d'une liste d'objets posés (format du serveur, avec R)
local function copyList(list: { any }): { any }
	local result = {}
	for index, e in ipairs(list) do
		result[index] = { I = e.I, X = e.X, Y = e.Y, S = e.S, Z = e.Z, F = e.F, C = e.C, R = e.R }
	end
	return result
end

-- Nouvelle position 2D (X, Y, Z) de l'objet tenu
function FurnitureEdit.Compute2D(self: any, held: Held, list: { any }): (number, number, number)
	local house = held.House
	local dims = WorldLayout.RoomDims(house.Size, HouseCommon.Config.WallRatio)
	local entry = list[held.Index]
	if held.Wall then
		local k = (tonumber(held.Item.Size) or 80) * (tonumber(entry.S) or 1) * WorldLayout.PX / 100
		local X, Y = WorldLayout.WallInverse(dims, held.X, held.Y, k)
		return X, Y, entry.Z
	end
	local support = held.Support
	local S = surfaces()
	if support and S then
		local supportIndex = tonumber(support:GetAttribute("EntryIndex"))
		local supportEntry = supportIndex and list[supportIndex]
		if supportEntry then
			local ok, tops = pcall(S.Of, supportEntry, dims.RoomWpx, dims.RoomHpx)
			local top = ok and type(tops) == "table" and tops[1] or nil
			if top then
				local supportRel = held.Frame:PointToObjectSpace(support:GetPivot().Position)
				local centerX = (top.L + top.R) / 2
				local X = math.clamp(centerX + (held.X - supportRel.X) / (dims.RoomWpx * dims.PX), top.L, top.R)
				return X, top.Y, math.min(HouseCommon.MAX_Z, (tonumber(supportEntry.Z) or 100) + 1)
			end
		end
	end
	local X, Y = WorldLayout.FloorInverse(dims, held.X, held.Z, held.FD)
	return X, Y, entry.Z
end

function FurnitureEdit.Commit(self: any, held: Held, list: { any }, message: string)
	local house = held.House
	local room = house.Rooms[held.Slot]
	if not room or not room.Data then
		return
	end
	local previous = copyList(room.Data.Placed)
	-- la pièce est reconstruite tout de de suite (même rendu qu'après un rechargement)
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
	-- ce qui suit (posé dessus, chaises) : même décalage en 2D
	local dx, dy = entry.X - oldX, entry.Y - oldY
	for _, follower in ipairs(held.Followers) do
		local other = list[follower.Index]
		if other then
			other.X = WorldLayout.Round4(math.clamp((tonumber(other.X) or 0.5) + dx, 0, 1))
			other.Y = WorldLayout.Round4(math.clamp((tonumber(other.Y) or 0.8) + dy, 0, 1))
		end
	end
	self.Held = nil
	self:SetHighlight(nil, false)
	self.Ctx.Hud:SetEditing(self.Enabled, false)
	if not held.Moved and held.R == WorldLayout.NormalizeRotation(room.Data.Placed[held.Index].R) then
		return
	end
	self:Commit(held, list, Locale.T("🏠 Layout saved"))
end

function FurnitureEdit.PutAway(self: any)
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
	-- ce qui est posé DESSUS part aussi dans l'inventaire (les chaises restent)
	local remove: { [number]: boolean } = { [held.Index] = true }
	local S = surfaces()
	if S then
		local dims = WorldLayout.RoomDims(held.House.Size, HouseCommon.Config.WallRatio)
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
	self.Held = nil
	self:SetHighlight(nil, false)
	self.Ctx.Hud:SetEditing(self.Enabled, false)
	self:Commit(held, kept, Locale.T("📦 Put back in your inventory"))
end

function FurnitureEdit.IsHolding(self: any): boolean
	return self.Held ~= nil
end

function FurnitureEdit.Destroy(self: any)
	self:SetEnabled(false)
	local highlight = self.Highlight
	if highlight then
		highlight:Destroy()
		self.Highlight = nil
	end
end

return FurnitureEdit
