--[[
	GardenEdit (ModuleScript)
	Emplacement : ReplicatedStorage > Client > World > GardenEdit

	🌷 Dopamine Town (v9.8, GARDEN98) : le MODE ÉDITION DU JARDIN, comme
	FurnitureEdit pour les meubles, mais dehors, dans SON jardin (devant et
	derrière la maison) :
	  - bouton "🌷 Jardin" (à gauche) quand on est sur sa parcelle ;
	  - un clic / un appui sur un objet du jardin le prend (parterres de
	    Dopamine, déco du jardin, pots, massifs, banc, kiosque..., panneau,
	    allées, lanternes, moulin, bonus des agrandissements) ; il suit la
	    souris (PC) ou le doigt sur la pelouse, aimant de grille 0,5 stud ;
	    R (ou 🔄) tourne de 15° (Maj+R dans l'autre sens) ; clic / ✅ pose ;
	    Échap / ❌ annule ; Suppr / 📦 range (déco et objets de jardin) ;
	  - l'empreinte au sol est verte (place libre) ou rouge (hors du jardin,
	    sur l'allée d'une porte, sur un autre objet, dans un mur) ; les zones
	    du jardin (celles du niveau) sont dessinées en vert pâle sur la
	    pelouse pendant l'édition, les allées des portes en rouge ;
	  - plateau du bas : 📦 Rangés (objets possédés pas posés, déco du jardin
	    rangée) -> un fantôme à poser ; 🛍️ Acheter (Config.Garden.Pieces :
	    prix, verrou des visites, nombre possédé) -> l'objet acheté arrive
	    directement dans le fantôme ; 🌳 Agrandir (niveau suivant du jardin :
	    prix, verrou, ce qu'il apporte ; les zones du niveau suivant sont
	    dessinées en doré) ;
	  - chaque pose : affichage tout de suite (GardenBuilder:ApplyLocal), puis
	    sauvegarde au serveur (RemoteFunction "Garden", "saveLayout" ; tout
	    y est revérifié) ; la réponse du serveur fait foi.
	Règles de place : Shared/GardenSnapshot (Fits, Footprint, Zones...),
	les mêmes que le serveur.

	API (branchée par TownClient) :
	  GardenEdit.Start(ctx)   ctx = { Toast = (text, color?) -> (), GetGarden = () -> garden?,
	                                  IsBusy = (() -> boolean)? }
	  GardenEdit.Step(dt)     (bouton visible / caché, ~4 fois par seconde suffit)
	  GardenEdit.Stop()
	  GardenEdit.IsActive() -> boolean ; GardenEdit.SetEnabled(on)
	Interface : ScreenGui "GardenEditGui" (à garder par TownClient : KEEP_GUIS).
	AUCUN son.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage.Shared.Config)
local Locale = require(ReplicatedStorage.Shared.Locale)
local Net = require(ReplicatedStorage.Shared.Net)
local NumberFormatter = require(ReplicatedStorage.Shared.NumberFormatter)
local GardenSnapshot = require(ReplicatedStorage.Shared.GardenSnapshot)

local Client = script.Parent.Parent
local ClientState = require(Client.ClientState)

local GardenEdit = {}

local LocalPlayer = Players.LocalPlayer
local GUI_NAME = "GardenEditGui"
local RENDER = "DopamineGardenEdit"
local LAWN_TOP = 0.45
local GRID = GardenSnapshot.GRID
local STEP = GardenSnapshot.ROTATION_STEP
local SAVE_DELAY = 0.6

local PINK = Color3.fromRGB(236, 72, 140)
local GREEN = Color3.fromRGB(86, 176, 96)
local GREEN_DARK = Color3.fromRGB(52, 120, 64)
local GOLD = Color3.fromRGB(240, 180, 60)
local INK = Color3.fromRGB(70, 52, 60)
local CARD = Color3.fromRGB(255, 252, 246)
local WHITE = Color3.new(1, 1, 1)
local RED = Color3.fromRGB(226, 80, 90)

type State = {
	Ctx: any,
	Gui: ScreenGui?,
	Toggle: TextButton?,
	Panel: Frame?,
	Top: Frame?,
	TopTitle: TextLabel?,
	Actions: Frame?,
	List: ScrollingFrame?,
	Tab: string,
	Tabs: { [string]: TextButton },
	Active: boolean,
	Garden: any,
	Holding: any?, -- { Key, X, D, R, New = bool, Ghost = Model?, Model = Model? }
	Plate: Part?,
	Zones: { Part },
	Layout: { [string]: any },
	Decor: { string },
	SaveAt: number?,
	Saving: boolean,
	Connections: { RBXScriptConnection },
	Started: boolean,
	Pointer: Vector2?,
	Clock: number,
}

local state: State = {
	Ctx = {},
	Tab = "Stored",
	Tabs = {},
	Active = false,
	Garden = nil,
	Zones = {},
	Layout = {},
	Decor = {},
	Saving = false,
	Connections = {},
	Started = false,
	Clock = 0,
}

----------------------------------------------------------------------
-- Utilitaires
----------------------------------------------------------------------

local function toast(text: string, color: Color3?)
	local fn = state.Ctx.Toast
	if type(fn) == "function" then
		pcall(fn, text, color)
	end
end

local function garden(): any?
	local fn = state.Ctx.GetGarden
	if type(fn) ~= "function" then
		return nil
	end
	local ok, result = pcall(fn)
	if ok and type(result) == "table" and not result.Destroyed then
		return result
	end
	return nil
end

local function data(): any
	return ClientState.Data or {}
end

local function level(): number
	local g = state.Garden
	if g and g.State then
		return GardenSnapshot.Level(g.State.Level)
	end
	return GardenSnapshot.Level(data())
end

local function ownedPieces(): { [string]: number }
	return GardenSnapshot.OwnedPieces(data())
end

local function ownedDecor(): { [string]: boolean }
	local house = data().House
	return type(house) == "table" and type(house.OwnedGarden) == "table" and house.OwnedGarden or {}
end

local function nameOf(key: string): (string, string)
	local kind, id = GardenSnapshot.Parse(key)
	if kind == "B" then
		return "🪴", Locale.T("Flower bed")
	elseif kind == "D" then
		local entry = Config.HouseLooksById and Config.HouseLooksById.Garden and Config.HouseLooksById.Garden[id :: string]
		return entry and tostring(entry.Icon) or "🌷", entry and Locale.T(entry.Name) or tostring(id)
	elseif kind == "P" then
		local piece = GardenSnapshot.PiecesById[id :: string]
		return piece and tostring(piece.Icon) or "🪴", piece and Locale.T(piece.Name) or tostring(id)
	end
	return "🌳", Locale.T("Garden decor")
end

local function newInstance(className: string, props: { [string]: any }, parent: Instance?): any
	local inst = Instance.new(className)
	for key, value in pairs(props) do
		(inst :: any)[key] = value
	end
	if parent then
		inst.Parent = parent
	end
	return inst
end

local function corner(parent: Instance, radius: number)
	newInstance("UICorner", { CornerRadius = UDim.new(0, radius) }, parent)
end

local function button(parent: Instance, name: string, text: string, color: Color3, size: UDim2, position: UDim2?, anchor: Vector2?): TextButton
	local b = newInstance("TextButton", {
		Name = name,
		Text = text,
		Font = Enum.Font.FredokaOne,
		TextScaled = true,
		TextColor3 = WHITE,
		BackgroundColor3 = color,
		AutoButtonColor = true,
		Size = size,
		Position = position or UDim2.new(),
		AnchorPoint = anchor or Vector2.zero,
		BorderSizePixel = 0,
	}, parent)
	corner(b, 12)
	newInstance("UIStroke", { Color = color:Lerp(Color3.new(0, 0, 0), 0.25), Thickness = 2, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, b)
	newInstance("UIPadding", { PaddingLeft = UDim.new(0, 8), PaddingRight = UDim.new(0, 8), PaddingTop = UDim.new(0, 4), PaddingBottom = UDim.new(0, 4) }, b)
	return b
end

----------------------------------------------------------------------
-- Disposition courante (instantané + ce qui a déjà été bougé ici)
----------------------------------------------------------------------

-- Tout ce qui est affiché (Arrange) -> disposition complète { [clé] = { X, D, R } }
local function fullLayout(g: any): { [string]: any }
	local layout = {}
	for _, entry in ipairs(g.Arranged or {}) do
		if entry.Key ~= "G" then
			layout[entry.Key] = { X = entry.X, D = entry.D, R = entry.R }
		end
	end
	return layout
end

local function countPlacedPieces(layout: { [string]: any }): number
	local n = 0
	for key in pairs(layout) do
		if string.sub(key, 1, 2) == "P:" then
			n += 1
		end
	end
	return n
end

----------------------------------------------------------------------
-- Validité d'une place (mêmes règles que le serveur + objets voisins + murs)
----------------------------------------------------------------------

local function overlapsOthers(g: any, key: string, x: number, d: number, r: number): boolean
	local w, dp, flat = GardenSnapshot.Footprint(key)
	if flat then
		return false
	end
	local hx, hd = GardenSnapshot.HalfExtents(w, dp, r)
	for otherKey, entry in pairs(state.Layout) do
		if otherKey ~= key then
			local ow, odp, oflat = GardenSnapshot.Footprint(otherKey)
			if not oflat then
				local ox, od = GardenSnapshot.HalfExtents(ow, odp, entry.R or 0)
				if math.abs(entry.X - x) < hx + ox - 0.1 and math.abs(entry.D - d) < hd + od - 0.1 then
					return true
				end
			end
		end
	end
	-- murs / clôtures / fontaine de la façade (pièces solides de la maison)
	local house = g.Model and g.Model.Parent
	if house then
		local ok, hit = pcall(function()
			local params = OverlapParams.new()
			params.FilterType = Enum.RaycastFilterType.Include
			local exterior = house:FindFirstChild("Exterior")
			params.FilterDescendantsInstances = { exterior or house }
			local cf = g:PlaceCF(x, d, r) * CFrame.new(0, 1.6, 0)
			for _, part in ipairs(workspace:GetPartBoundsInBox(cf, Vector3.new(math.max(0.4, w - 0.3), 2.6, math.max(0.4, dp - 0.3)), params)) do
				if part.CanCollide and part.Transparency < 1 and not part:IsDescendantOf(g.Model) then
					return true
				end
			end
			return false
		end)
		if ok and hit then
			return true
		end
	end
	return false
end

local function isValid(g: any, key: string, x: number, d: number, r: number): boolean
	local st = g.State
	if not GardenSnapshot.Fits(level(), st.Size, key, x, d, r) then
		return false
	end
	return not overlapsOthers(g, key, x, d, r)
end

----------------------------------------------------------------------
-- Dessins au sol : zones, empreinte
----------------------------------------------------------------------

local function clearZones()
	for _, part in ipairs(state.Zones) do
		part:Destroy()
	end
	table.clear(state.Zones)
end

local function plate(g: any, x0: number, x1: number, d0: number, d1: number, color: Color3, y: number, transparency: number): Part
	local part = newInstance("Part", {
		Name = "GardenZone",
		Anchored = true,
		CanCollide = false,
		CanQuery = false,
		CanTouch = false,
		CastShadow = false,
		Material = Enum.Material.SmoothPlastic,
		Color = color,
		Transparency = transparency,
		Size = Vector3.new(math.max(0.2, x1 - x0), 0.04, math.max(0.2, d1 - d0)),
		CFrame = g.HouseCF * CFrame.new((x0 + x1) / 2, LAWN_TOP + y, -(d0 + d1) / 2),
	}, workspace)
	table.insert(state.Zones, part)
	return part
end

local function drawZones(showNext: boolean?)
	clearZones()
	local g = state.Garden
	if not g then
		return
	end
	local lv = level()
	-- (hauteurs différentes : jamais deux plaques dans le même plan)
	for index, zone in ipairs(GardenSnapshot.Zones(lv, g.State.Size)) do
		plate(g, zone[1], zone[2], zone[3], zone[4], GREEN, 0.03 + index * 0.004, 0.82)
	end
	for index, lane in ipairs(GardenSnapshot.Corridors(g.State.Size)) do
		plate(g, lane[1], lane[2], math.max(lane[3], -29), lane[4], RED, 0.06 + index * 0.004, 0.72)
	end
	if showNext and lv < GardenSnapshot.MAX_LEVEL then
		for index, zone in ipairs(GardenSnapshot.Zones(lv + 1, g.State.Size)) do
			plate(g, zone[1], zone[2], zone[3], zone[4], GOLD, 0.015 + index * 0.004, 0.78)
		end
	end
end

local function updatePlate(g: any, hold: any, valid: boolean)
	local w, dp = GardenSnapshot.Footprint(hold.Key)
	local p = state.Plate
	if not p then
		p = newInstance("Part", {
			Name = "GardenFootprint",
			Anchored = true,
			CanCollide = false,
			CanQuery = false,
			CanTouch = false,
			CastShadow = false,
			Material = Enum.Material.Neon,
			Transparency = 0.55,
		}, workspace)
		state.Plate = p
	end
	local plateP = p :: Part
	plateP.Size = Vector3.new(w, 0.05, dp)
	plateP.CFrame = g:PlaceCF(hold.X, hold.D, hold.R) * CFrame.new(0, 0.1, 0)
	plateP.Color = valid and Color3.fromRGB(120, 230, 130) or Color3.fromRGB(255, 90, 90)
end

----------------------------------------------------------------------
-- Tenir / poser / ranger
----------------------------------------------------------------------

local function refreshActions()
	local top = state.Top
	local help = top and top:FindFirstChild("Help") :: TextLabel?
	if help then
		if state.Holding then
			local icon, name = nameOf(state.Holding.Key)
			help.Text = "✋ " .. icon .. " " .. name .. "  ·  " .. Locale.T("R: rotate · click: place · Del: put away · Esc: cancel")
		else
			help.Text = Locale.T("Click something to move it · R: rotate · Del: put away · Esc: cancel")
		end
	end
	local actions = state.Actions
	if actions then
		actions.Visible = state.Holding ~= nil
		local putAway = actions:FindFirstChild("PutAway") :: TextButton?
		if putAway and state.Holding then
			local kind = GardenSnapshot.Parse(state.Holding.Key)
			putAway.Visible = kind == "D" or kind == "P"
		end
	end
end

local function releaseHold(restore: boolean)
	local hold = state.Holding
	state.Holding = nil
	if hold then
		if hold.Ghost then
			hold.Ghost:Destroy()
		elseif restore and state.Garden then
			state.Garden:ResetPreview(hold.Key)
		end
	end
	if state.Plate then
		state.Plate:Destroy()
		state.Plate = nil
	end
	refreshActions()
end

local function ghostify(model: Model)
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") then
			d.Transparency = math.max(d.Transparency, 0.35)
			d.CastShadow = false
		end
	end
end

local function hold(key: string, isNew: boolean)
	local g = state.Garden
	if not g then
		return
	end
	releaseHold(true)
	local entry = state.Layout[key]
	local x, d, r = 0, GardenSnapshot.BACK_CENTER, 0
	if entry then
		x, d, r = entry.X, entry.D, entry.R or 0
	else
		-- nouvel objet : devant l'avatar
		local character = LocalPlayer.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		if root and root:IsA("BasePart") then
			local lx, ld = g:ToLocal((root.CFrame * CFrame.new(0, 0, -6)).Position)
			x, d = lx, ld
		end
	end
	local h: any = { Key = key, X = x, D = d, R = r, New = isNew, X0 = x, D0 = d, R0 = r }
	if isNew then
		local ghost = g:MakeGhost(key)
		if not ghost then
			toast(Locale.T("This can't go in the garden"), RED)
			return
		end
		ghostify(ghost)
		ghost.Parent = workspace
		h.Ghost = ghost
	end
	state.Holding = h
	refreshActions()
end

local function scheduleSave()
	state.SaveAt = os.clock() + SAVE_DELAY
end

local function applyLocal()
	local g = state.Garden
	if g then
		g:ApplyLocal(table.clone(state.Layout), table.clone(state.Decor))
	end
end

local function drop()
	local g = state.Garden
	local h = state.Holding
	if not g or not h then
		return
	end
	if not isValid(g, h.Key, h.X, h.D, h.R) then
		toast(Locale.T("🚫 Not here: pick a free green spot"), RED)
		return
	end
	local kind, id = GardenSnapshot.Parse(h.Key)
	if h.New then
		if kind == "P" and countPlacedPieces(state.Layout) >= GardenSnapshot.PieceCap(level()) then
			toast(Locale.T("Your garden is full (max %d): put something away first", GardenSnapshot.PieceCap(level())), RED)
			return
		end
		if kind == "D" then
			if #state.Decor >= GardenSnapshot.DecorSlots(level()) then
				toast(Locale.T("Your garden is full (max %d): put something away first", GardenSnapshot.DecorSlots(level())), RED)
				return
			end
			table.insert(state.Decor, id :: string)
		end
	end
	state.Layout[h.Key] = { X = h.X, D = h.D, R = h.R }
	local ghost = h.Ghost
	state.Holding = nil
	if ghost then
		ghost:Destroy()
	end
	if state.Plate then
		state.Plate:Destroy()
		state.Plate = nil
	end
	applyLocal()
	scheduleSave()
	refreshActions()
end

local function putAway()
	local h = state.Holding
	if not h then
		return
	end
	local kind, id = GardenSnapshot.Parse(h.Key)
	if kind ~= "D" and kind ~= "P" then
		toast(Locale.T("This stays in the garden (move it instead)"))
		return
	end
	local wasNew = h.New
	releaseHold(false)
	if not wasNew then
		state.Layout[h.Key] = nil
		if kind == "D" then
			local index = table.find(state.Decor, id :: string)
			if index then
				table.remove(state.Decor, index)
			end
		end
		applyLocal()
		scheduleSave()
	end
	toast("📦 " .. Locale.T("Put away"))
	GardenEdit._refreshList()
end

local function rotate(delta: number)
	local h = state.Holding
	if h then
		h.R = GardenSnapshot.Rotation(h.R + delta)
	end
end

----------------------------------------------------------------------
-- Serveur
----------------------------------------------------------------------

local function invoke(action: string, arg: any): (boolean, any)
	local ok, success, result = pcall(function()
		return Net.Function("Garden"):InvokeServer(action, arg)
	end)
	if not ok then
		return false, Locale.T("Network error, try again.")
	end
	return success == true, result
end

-- La réponse du serveur fait foi (disposition, déco sortie, objets, niveau)
local function adopt(result: any)
	if type(result) ~= "table" then
		return
	end
	local d = ClientState.Data
	if type(d) == "table" then
		d.Garden = type(d.Garden) == "table" and d.Garden or {}
		if type(result.Pieces) == "table" then
			d.Garden.Pieces = result.Pieces
		end
		if result.Level ~= nil then
			d.Garden.Level = result.Level
		end
		if type(result.Layout) == "table" then
			d.Garden.Layout = result.Layout
		end
		if type(d.House) == "table" and type(result.Decor) == "table" then
			d.House.Garden = result.Decor
		end
	end
	local g = state.Garden
	if g and type(result.Layout) == "table" then
		g.State.Level = GardenSnapshot.Level(result.Level)
		state.Layout = table.clone(result.Layout)
		state.Decor = type(result.Decor) == "table" and table.clone(result.Decor) or state.Decor
		-- (garder la place de ce qui n'a pas été renvoyé : places par défaut)
		g:ApplyLocal(table.clone(state.Layout), table.clone(state.Decor))
		state.Layout = fullLayout(g)
	end
end

local function saveNow()
	if state.Saving or not state.Garden then
		return
	end
	state.Saving = true
	state.SaveAt = nil
	local layout = table.clone(state.Layout)
	local decor = table.clone(state.Decor)
	task.spawn(function()
		local ok, result = invoke("saveLayout", { Layout = layout, Decor = decor })
		state.Saving = false
		if ok then
			if type(result) == "table" and (tonumber(result.Dropped) or 0) > 0 then
				toast(Locale.T("Some things didn't fit and went back to storage"), RED)
			end
			adopt(result)
			GardenEdit._refreshList()
		else
			toast(tostring(result or Locale.T("The garden is resting 🌙")), RED)
			if state.Garden and type(result) == "string" and string.find(result, "Slow", 1, true) then
				scheduleSave()
			end
		end
	end)
end

local function buyPiece(id: string)
	task.spawn(function()
		local ok, result = invoke("buyPiece", id)
		if ok and type(result) == "table" then
			toast(tostring(result.Message or "🪴"), GREEN)
			adopt({ Pieces = result.Pieces, Level = result.Level })
			GardenEdit._refreshList()
			-- l'objet acheté arrive dans le fantôme
			local n = tonumber(result.Count) or 1
			local key = "P:" .. id .. ":" .. tostring(n)
			if state.Active and not state.Layout[key] then
				hold(key, true)
			end
		else
			toast(tostring(result), RED)
		end
	end)
end

local function expand()
	task.spawn(function()
		local ok, result = invoke("expand", nil)
		if ok and type(result) == "table" then
			toast(tostring(result.Message or "🌳"), GREEN)
			adopt(result)
			local g = state.Garden
			if g then
				g:Float(g.HouseCF * Vector3.new(0, 8, -GardenSnapshot.BACK_CENTER), "🌳 " .. Locale.T("Bigger garden!"), GOLD)
			end
			drawZones(state.Tab == "Expand")
			GardenEdit._refreshList()
		else
			toast(tostring(result), RED)
		end
	end)
end

----------------------------------------------------------------------
-- Interface
----------------------------------------------------------------------

local function card(parent: Instance, order: number, icon: string, title: string, sub: string, actionText: string?, actionColor: Color3?, onAction: (() -> ())?)
	local frame = newInstance("Frame", {
		Name = "Card",
		LayoutOrder = order,
		BackgroundColor3 = CARD,
		Size = UDim2.new(0, 150, 1, -8),
		BorderSizePixel = 0,
	}, parent)
	corner(frame, 12)
	newInstance("UIStroke", { Color = Color3.fromRGB(220, 200, 190), Thickness = 1.5 }, frame)
	newInstance("TextLabel", {
		Name = "Icon", BackgroundTransparency = 1, Text = icon, TextScaled = true, Font = Enum.Font.GothamBold,
		Size = UDim2.new(1, 0, 0.36, 0), Position = UDim2.fromScale(0, 0.03), TextColor3 = INK,
	}, frame)
	newInstance("TextLabel", {
		Name = "Title", BackgroundTransparency = 1, Text = title, TextScaled = true, Font = Enum.Font.FredokaOne,
		Size = UDim2.new(1, -10, 0.18, 0), Position = UDim2.new(0, 5, 0.4, 0), TextColor3 = INK,
	}, frame)
	newInstance("TextLabel", {
		Name = "Sub", BackgroundTransparency = 1, Text = sub, TextScaled = true, Font = Enum.Font.GothamBold,
		Size = UDim2.new(1, -10, 0.14, 0), Position = UDim2.new(0, 5, 0.58, 0), TextColor3 = Color3.fromRGB(140, 110, 110),
	}, frame)
	if actionText then
		local b = button(frame, "Action", actionText, actionColor or PINK, UDim2.new(1, -14, 0.22, 0), UDim2.new(0, 7, 0.75, 0))
		if onAction then
			b.Activated:Connect(onAction)
		end
	end
	return frame
end

function GardenEdit._refreshList()
	local list = state.List
	local g = state.Garden
	if not list or not g then
		return
	end
	for _, child in ipairs(list:GetChildren()) do
		if child:IsA("Frame") then
			child:Destroy()
		end
	end
	local order = 0
	local lv = level()
	local d = data()
	local rebirths = tonumber(d.Rebirths) or 0
	if state.Tab == "Stored" then
		-- objets de jardin possédés pas posés
		local owned = ownedPieces()
		for _, piece in ipairs(Config.Garden.Pieces or {}) do
			local n = owned[piece.Id] or 0
			local free: number? = nil
			local placed = 0
			for k = 1, n do
				if state.Layout["P:" .. piece.Id .. ":" .. k] then
					placed += 1
				elseif not free then
					free = k
				end
			end
			if free then
				order += 1
				local key = "P:" .. piece.Id .. ":" .. tostring(free)
				card(list, order, tostring(piece.Icon), Locale.T(piece.Name), string.format("📦 %d", n - placed), Locale.T("Place"), GREEN, function()
					hold(key, true)
				end)
			end
		end
		-- déco du jardin rangée
		local decorOwned = ownedDecor()
		for _, entry in ipairs(Config.House.GardenDecor or {}) do
			if decorOwned[entry.Id] and not table.find(state.Decor, entry.Id) then
				order += 1
				card(list, order, tostring(entry.Icon), Locale.T(entry.Name), "🌷", Locale.T("Place"), GREEN, function()
					hold("D:" .. entry.Id, true)
				end)
			end
		end
		if order == 0 then
			order += 1
			card(list, order, "🛍️", Locale.T("Nothing stored"), Locale.T("Buy pots and more!"), Locale.T("🛍️ Buy"), PINK, function()
				GardenEdit._setTab("Shop")
			end)
		end
	elseif state.Tab == "Shop" then
		local owned = ownedPieces()
		for _, piece in ipairs(Config.Garden.Pieces or {}) do
			order += 1
			local n = owned[piece.Id] or 0
			local needed = tonumber(piece.RequiresRebirths) or 0
			local maxN = tonumber(piece.Max) or 10
			if rebirths < needed then
				card(list, order, tostring(piece.Icon), Locale.T(piece.Name), Locale.T("🔒 %d visits to the ocean", needed), nil)
			elseif n >= maxN then
				card(list, order, tostring(piece.Icon), Locale.T(piece.Name), string.format("✅ %d/%d", n, maxN), nil)
			else
				local cost = GardenSnapshot.PieceCost(piece, n)
				card(list, order, tostring(piece.Icon), Locale.T(piece.Name), string.format("%d/%d", n, maxN), "💧 " .. NumberFormatter.Format(cost), PINK, function()
					buyPiece(piece.Id)
				end)
			end
		end
	else
		-- Agrandir
		local info = GardenSnapshot.LevelInfo(lv + 1)
		order += 1
		local current = GardenSnapshot.LevelInfo(lv)
		card(list, order, current and tostring(current.Icon) or "🌱", current and Locale.T(current.Name) or Locale.T("Small garden"),
			Locale.T("Level %d/%d", lv, GardenSnapshot.MAX_LEVEL), nil)
		if info then
			order += 1
			local needed = tonumber(info.RequiresRebirths) or 0
			local sub = Locale.T("🌷 %d decor · 🪴 %d items", GardenSnapshot.DecorSlots(lv + 1), GardenSnapshot.PieceCap(lv + 1))
			if rebirths < needed then
				card(list, order, tostring(info.Icon), Locale.T(info.Name), Locale.T("🔒 %d visits to the ocean", needed), nil)
			else
				card(list, order, tostring(info.Icon), Locale.T(info.Name), sub, "💧 " .. NumberFormatter.Format(tonumber(info.Cost) or 0), GOLD, expand)
			end
			if type(info.Bonus) == "string" then
				order += 1
				local bonusNames = { RoseArch = { "🌸", "Rose arch" }, Greenhouse = { "🏡", "Greenhouse" }, KoiPond = { "🐟", "Koi pond" } }
				local b = bonusNames[info.Bonus] or { "🎁", info.Bonus }
				card(list, order, b[1], Locale.T(b[2]), Locale.T("🎁 Free with this level"), nil)
			end
		else
			order += 1
			card(list, order, "🏆", Locale.T("Your garden is already at its biggest!"), "", nil)
		end
	end
	if state.TopTitle then
		local current = GardenSnapshot.LevelInfo(lv)
		state.TopTitle.Text = Locale.T("🌷 My garden") .. "  ·  " .. (current and (tostring(current.Icon) .. " " .. Locale.T(current.Name)) or Locale.T("Small garden"))
			.. string.format("  ·  🪴 %d/%d", countPlacedPieces(state.Layout), GardenSnapshot.PieceCap(lv))
	end
end

function GardenEdit._setTab(tab: string)
	state.Tab = tab
	for name, b in pairs(state.Tabs) do
		b.BackgroundColor3 = name == tab and PINK or Color3.fromRGB(190, 160, 170)
	end
	if state.Active then
		drawZones(tab == "Expand")
	end
	GardenEdit._refreshList()
end

local function buildGui()
	local playerGui = LocalPlayer:FindFirstChildOfClass("PlayerGui")
	if not playerGui then
		return
	end
	local old = playerGui:FindFirstChild(GUI_NAME)
	if old then
		old:Destroy()
	end
	local gui = newInstance("ScreenGui", { Name = GUI_NAME, ResetOnSpawn = false, IgnoreGuiInset = false, DisplayOrder = 6, Enabled = true }, playerGui)
	state.Gui = gui
	-- bouton 🌷 Jardin (à gauche)
	-- (à gauche, sous le bouton "Retour" : la colonne des voitures du HUD est plus bas)
	local toggle = button(gui, "GardenToggle", "🌷 " .. Locale.T("Garden"), GREEN, UDim2.fromOffset(128, 46), UDim2.new(0, 12, 0.3, 0), Vector2.new(0, 0.5))
	toggle.Visible = false
	toggle.Activated:Connect(function()
		GardenEdit.SetEnabled(not state.Active)
	end)
	state.Toggle = toggle
	-- barre du haut (mode édition)
	local top = newInstance("Frame", {
		Name = "Top", BackgroundColor3 = CARD, BackgroundTransparency = 0.05, BorderSizePixel = 0, Visible = false,
		AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 178), Size = UDim2.new(0.92, 0, 0, 58), -- (sous le compteur et la plaque de la maison du HUD)
	}, gui)
	newInstance("UISizeConstraint", { MaxSize = Vector2.new(760, 58) }, top)
	corner(top, 14)
	state.TopTitle = newInstance("TextLabel", {
		Name = "Title", BackgroundTransparency = 1, Text = "", TextScaled = true, Font = Enum.Font.FredokaOne, TextColor3 = INK,
		Position = UDim2.new(0, 12, 0, 4), Size = UDim2.new(1, -150, 0, 28), TextXAlignment = Enum.TextXAlignment.Left,
	}, top)
	newInstance("TextLabel", {
		Name = "Help", BackgroundTransparency = 1, TextScaled = true, Font = Enum.Font.GothamBold, TextColor3 = Color3.fromRGB(140, 110, 110),
		Text = Locale.T("Click something to move it · R: rotate · Del: put away · Esc: cancel"),
		Position = UDim2.new(0, 12, 0, 32), Size = UDim2.new(1, -150, 0, 20), TextXAlignment = Enum.TextXAlignment.Left,
	}, top)
	local done = button(top, "Done", "✅ " .. Locale.T("Done"), GREEN_DARK, UDim2.fromOffset(124, 44), UDim2.new(1, -8, 0.5, 0), Vector2.new(1, 0.5))
	done.Activated:Connect(function()
		GardenEdit.SetEnabled(false)
	end)
	state.Top = top
	-- boutons quand on tient un objet
	local actions = newInstance("Frame", {
		Name = "Actions", BackgroundTransparency = 1, Visible = false,
		AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -236), Size = UDim2.fromOffset(4 * 130 + 3 * 8, 46),
	}, gui)
	-- (rangée au-dessus du plateau : les boutons du HUD à droite restent libres)
	newInstance("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, HorizontalAlignment = Enum.HorizontalAlignment.Center, Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder }, actions)
	local specs = {
		{ "Drop", "✅ " .. Locale.T("Place"), GREEN_DARK, drop },
		{ "Rotate", "🔄 " .. Locale.T("Rotate"), Color3.fromRGB(96, 150, 230), function() rotate(STEP) end },
		{ "PutAway", "📦 " .. Locale.T("Put away"), Color3.fromRGB(170, 130, 90), putAway },
		{ "Cancel", "❌ " .. Locale.T("Cancel"), RED, function() releaseHold(true) end },
	}
	for index, spec in ipairs(specs) do
		local b = button(actions, spec[1], spec[2], spec[3], UDim2.fromOffset(130, 46))
		b.LayoutOrder = index
		b.Activated:Connect(spec[4])
	end
	state.Actions = actions
	-- plateau du bas
	local panel = newInstance("Frame", {
		Name = "Panel", BackgroundColor3 = Color3.fromRGB(255, 244, 236), BackgroundTransparency = 0.04, BorderSizePixel = 0, Visible = false,
		AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -10), Size = UDim2.new(0.96, 0, 0, 216),
	}, gui)
	newInstance("UISizeConstraint", { MaxSize = Vector2.new(980, 216) }, panel)
	corner(panel, 16)
	local tabs = newInstance("Frame", { Name = "Tabs", BackgroundTransparency = 1, Position = UDim2.fromOffset(10, 8), Size = UDim2.new(1, -20, 0, 36) }, panel)
	newInstance("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder }, tabs)
	for index, spec in ipairs({ { "Stored", "📦 " .. Locale.T("Stored") }, { "Shop", "🛍️ " .. Locale.T("Buy") }, { "Expand", "🌳 " .. Locale.T("Enlarge") } }) do
		local b = button(tabs, spec[1], spec[2], Color3.fromRGB(190, 160, 170), UDim2.fromOffset(150, 36))
		b.LayoutOrder = index
		b.Activated:Connect(function()
			GardenEdit._setTab(spec[1])
		end)
		state.Tabs[spec[1]] = b
	end
	local list = newInstance("ScrollingFrame", {
		Name = "List", BackgroundTransparency = 1, BorderSizePixel = 0, Position = UDim2.fromOffset(10, 50), Size = UDim2.new(1, -20, 1, -58),
		ScrollingDirection = Enum.ScrollingDirection.X, CanvasSize = UDim2.new(), AutomaticCanvasSize = Enum.AutomaticSize.X, ScrollBarThickness = 6,
	}, panel)
	newInstance("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder }, list)
	state.List = list
	state.Panel = panel
end

----------------------------------------------------------------------
-- Pointeur -> pelouse
----------------------------------------------------------------------

local function pointerToLawn(g: any, screen: Vector2): (number?, number?)
	local camera = workspace.CurrentCamera
	if not camera then
		return nil, nil
	end
	local ray = camera:ViewportPointToRay(screen.X, screen.Y)
	local planeY = (g.HouseCF * CFrame.new(0, LAWN_TOP, 0)).Position.Y
	local dir = ray.Direction
	if math.abs(dir.Y) < 1e-4 then
		return nil, nil
	end
	local t = (planeY - ray.Origin.Y) / dir.Y
	if t <= 0 or t > 400 then
		return nil, nil
	end
	local hit = ray.Origin + dir * t
	local x, d = g:ToLocal(hit)
	return math.floor(x / GRID + 0.5) * GRID, math.floor(d / GRID + 0.5) * GRID
end

local function pick(g: any, screen: Vector2): string?
	local camera = workspace.CurrentCamera
	if not camera then
		return nil
	end
	local ray = camera:ViewportPointToRay(screen.X, screen.Y)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = { g.Model }
	local result = workspace:Raycast(ray.Origin, ray.Direction * 300, params)
	if result and result.Instance then
		return g:KeyOf(result.Instance)
	end
	return nil
end

local function follow()
	local g = state.Garden
	local h = state.Holding
	if not g or not h then
		return
	end
	local x, d = nil, nil
	if state.Pointer then
		x, d = pointerToLawn(g, state.Pointer :: Vector2)
	end
	if x and d then
		-- (on garde l'écart entre le point cliqué et le centre de l'objet)
		h.X = math.floor((x + (h.OffX or 0)) / GRID + 0.5) * GRID
		h.D = math.floor((d + (h.OffD or 0)) / GRID + 0.5) * GRID
	end
	local cf = g:PlaceCF(h.X, h.D, h.R)
	if h.Ghost then
		h.Ghost:PivotTo(cf)
	else
		g:Preview(h.Key, h.X, h.D, h.R)
	end
	updatePlate(g, h, isValid(g, h.Key, h.X, h.D, h.R))
end

local function onPress(screen: Vector2)
	local g = state.Garden
	if not g then
		return
	end
	state.Pointer = screen
	if state.Holding then
		follow()
		drop()
		return
	end
	local key = pick(g, screen)
	if key and key ~= "G" then
		hold(key, false)
		local h = state.Holding
		local x, d = pointerToLawn(g, screen)
		if h and x and d then
			h.OffX, h.OffD = h.X - x, h.D - d
		end
		follow()
	end
end

----------------------------------------------------------------------
-- Activer / quitter
----------------------------------------------------------------------

local function connectInputs()
	table.insert(state.Connections, UserInputService.InputBegan:Connect(function(input, processed)
		if not state.Active then
			return
		end
		if input.UserInputType == Enum.UserInputType.Keyboard then
			if processed then
				return
			end
			if input.KeyCode == Enum.KeyCode.R then
				local shift = UserInputService:IsKeyDown(Enum.KeyCode.LeftShift) or UserInputService:IsKeyDown(Enum.KeyCode.RightShift)
				rotate(shift and -STEP or STEP)
			elseif input.KeyCode == Enum.KeyCode.Delete or input.KeyCode == Enum.KeyCode.Backspace then
				putAway()
			elseif input.KeyCode == Enum.KeyCode.Escape then
				if state.Holding then
					releaseHold(true)
				else
					GardenEdit.SetEnabled(false)
				end
			end
			return
		end
		if processed then
			return
		end
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			onPress(Vector2.new(input.Position.X, input.Position.Y))
		end
	end))
	table.insert(state.Connections, UserInputService.InputChanged:Connect(function(input, processed)
		if not state.Active or processed then
			return
		end
		if input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch then
			state.Pointer = Vector2.new(input.Position.X, input.Position.Y)
		end
	end))
end

function GardenEdit.IsActive(): boolean
	return state.Active
end

function GardenEdit.SetEnabled(on: boolean)
	if on == state.Active then
		return
	end
	if on then
		local g = garden()
		if not g then
			toast(Locale.T("Go to your garden first"))
			return
		end
		local busy = state.Ctx.IsBusy
		if type(busy) == "function" then
			local okBusy, isBusy = pcall(busy)
			if okBusy and isBusy then
				return
			end
		end
		state.Active = true
		state.Garden = g
		g:SetEditing(true)
		state.Layout = fullLayout(g)
		state.Decor = table.clone(g.State.Decor or {})
		if not state.Gui or not state.Gui.Parent then
			buildGui()
		end
		if state.Gui then
			state.Gui.Enabled = true
		end
		if state.Top then
			state.Top.Visible = true
		end
		if state.Panel then
			state.Panel.Visible = true
		end
		if state.Toggle then
			state.Toggle.Visible = false -- (le bouton ✅ Terminé est dans la barre du haut)
		end
		connectInputs()
		pcall(function()
			RunService:BindToRenderStep(RENDER, Enum.RenderPriority.Input.Value + 1, function()
				follow()
			end)
		end)
		GardenEdit._setTab(state.Tab)
		drawZones(state.Tab == "Expand")
		toast(Locale.T("🌷 Garden edit: click something to move it"))
	else
		state.Active = false
		releaseHold(true)
		pcall(function()
			RunService:UnbindFromRenderStep(RENDER)
		end)
		for _, connection in ipairs(state.Connections) do
			connection:Disconnect()
		end
		table.clear(state.Connections)
		clearZones()
		if state.SaveAt then
			saveNow()
		end
		local g = state.Garden
		if g and not g.Destroyed then
			g:SetEditing(false)
		end
		state.Garden = nil
		if state.Top then
			state.Top.Visible = false
		end
		if state.Panel then
			state.Panel.Visible = false
		end
		if state.Actions then
			state.Actions.Visible = false
		end
		if state.Toggle then
			state.Toggle.Text = "🌷 " .. Locale.T("Garden")
		end
	end
end

-- Sur sa parcelle (dehors ou dedans) ?
local function onOwnPlot(g: any): boolean
	local character = LocalPlayer.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not root or not root:IsA("BasePart") then
		return false
	end
	local x, d = g:ToLocal(root.Position)
	return math.abs(x) < 90 and d > -32 and d < 56
end

function GardenEdit.Start(ctx: any?)
	state.Ctx = type(ctx) == "table" and ctx or {}
	state.Started = true
	buildGui()
end

function GardenEdit.Step(dt: number?)
	if not state.Started then
		return
	end
	state.Clock += dt or 0
	-- sauvegarde différée (plusieurs poses de suite = un seul envoi)
	if state.SaveAt and os.clock() >= state.SaveAt then
		saveNow()
	end
	local g = garden()
	if state.Active then
		if not g or g ~= state.Garden then
			GardenEdit.SetEnabled(false)
		end
		return
	end
	if state.Toggle then
		local show = g ~= nil and onOwnPlot(g)
		state.Toggle.Visible = show
		if show and state.Gui and not state.Gui.Enabled then
			state.Gui.Enabled = true
		end
	end
end

function GardenEdit.Stop()
	if state.Active then
		GardenEdit.SetEnabled(false)
	end
	state.Started = false
	if state.Gui then
		state.Gui:Destroy()
	end
	state.Gui = nil
	state.Toggle = nil
	state.Top = nil
	state.Panel = nil
	state.List = nil
	state.Actions = nil
	state.TopTitle = nil
	table.clear(state.Tabs)
end

-- (tests) état interne + actions directes
function GardenEdit.Debug(): any
	return {
		State = state,
		Hold = hold,
		Drop = drop,
		PutAway = putAway,
		Rotate = rotate,
		Follow = follow,
		SaveNow = saveNow,
		IsValid = isValid,
		Pick = pick,
		SetPointer = function(v: Vector2)
			state.Pointer = v
		end,
		SetTab = GardenEdit._setTab,
		Buy = buyPiece,
		Expand = expand,
	}
end

return GardenEdit
