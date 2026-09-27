--[[
	TownClient (ModuleScript)
	Emplacement : ReplicatedStorage > Client > World > TownClient

	🚶 Dopamine Town, côté client (lancé par ClientMain : TownClient.Init()).
	  - Entrer (WorldLink.Enter, bouton de la colonne centrale ou de la
	    fenêtre Maison) : les fenêtres du clicker se ferment, TOUTES les
	    ScreenGui du joueur sont masquées (sauf le HUD de la ville) et remises
	    EXACTEMENT à la sortie ; le serveur charge le personnage devant sa
	    porte (WorldService) ; éclairage pastel de la ville (Lighting +
	    Atmosphere / ciel / couleurs / halo, tout remis à la sortie), caméra
	    Roblox par défaut qui suit l'avatar (zoom 0,5 à 40 studs), manette
	    tactile et saut sur mobile, chat + bulles au-dessus des têtes ;
	  - maisons de TOUS les joueurs construites ici (HouseBuilder) d'après les
	    instantanés du serveur ; intérieurs en flux autour du joueur (une
	    pièce à la fois, sur plusieurs images) ;
	  - portes (s'ouvrent à l'approche si le propriétaire accueille ce
	    joueur), bandeau de la maison où l'on est, ❤️, visites, émotes,
	    s'asseoir (invite -> le serveur crée un Seat), étiquettes de nom
	    (pseudo + 🌊 visites à l'océan + ❤️) ;
	  - édition des meubles de SA maison (FurnitureEdit) ;
	  - Sortir ("⬅ Clicker") : le personnage est retiré, tout est remis.
	Les gains passifs continuent (serveur) ; le bouton 👆 du HUD clique comme
	le gros bouton (ClientState.Click).
	Travail par image : presque rien (compteur 10 fois / s, portes et bandeau
	5 fois / s, flux 4 fois / s, étiquettes 1 fois / s).
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local GuiService = game:GetService("GuiService")
local StarterGui = game:GetService("StarterGui")
local TextChatService = game:GetService("TextChatService")

local Client = script.Parent.Parent
local Components = Client:WaitForChild("Components")
local ClientState = require(Client.ClientState)
local Net = require(ReplicatedStorage.Shared.Net)
local Locale = require(ReplicatedStorage.Shared.Locale)
local WorldLayout = require(ReplicatedStorage.Shared.WorldLayout)
local NumberFormatter = require(ReplicatedStorage.Shared.NumberFormatter)
local WorldLink = require(script.Parent.WorldLink)
local HouseBuilder = require(script.Parent.HouseBuilder)
local TownHud = require(script.Parent.TownHud)
local FurnitureEdit = require(script.Parent.FurnitureEdit)
local TownEmotes = require(script.Parent.TownEmotes)
local TownAtmosphere = require(script.Parent.TownAtmosphere)
local TownArrival = require(script.Parent.TownArrival)

local TownClient = {}

local LocalPlayer = Players.LocalPlayer

local HOUSES_FOLDER = "TownHouses"
local COUNTER_EVERY = 0.1
local DOOR_EVERY = 0.2
local STREAM_EVERY = 0.25
local TAG_EVERY = 1
local DOOR_RANGE = 9
local MAX_ZOOM = 40
local MIN_ZOOM = 0.5

local GUIDE_EVERY = 0.25
local GUIDE_DONE = 18 -- (studs) arrivé devant sa porte : l'arc s'éteint
local FADE_COLOR = Color3.fromRGB(255, 190, 220)

type Saved = {
	Guis: { ScreenGui },
	Lighting: { [string]: any },
	Effects: { { Instance: Instance, Enabled: boolean } },
	Moved: { { Instance: Instance, Parent: Instance } }, -- ciels / atmosphères / nuages du lieu mis de côté
	CameraType: Enum.CameraType?,
	Touch: boolean?,
	ChatWindow: boolean?,
	ChatInput: boolean?,
	CoreChat: boolean?,
	MaxZoom: number?,
	MinZoom: number?,
}

local inTown = false
local busy = false
local hud: any = nil
local edit: any = nil
local snapshots: { [number]: any } = {}
local houses: { [number]: any } = {}
local housesFolder: Folder? = nil
local saved: Saved? = nil
local connections: { RBXScriptConnection } = {}
local friendCache: { [number]: boolean } = {}
local friendPending: { [number]: boolean } = {}
local roomBuilding = false
local creating = false
local contextKey = ""
local currentContext: any = nil
local clocks = { Counter = 0, Door = 0, Stream = 0, Tag = 0, Guide = 0 }
local emotes: any = nil
local guide: any = nil
local guidePending = false
local intro: any = nil
local introSeen = false -- (survol : 1re arrivée de la session seulement)

----------------------------------------------------------------------
-- Utilitaires
----------------------------------------------------------------------

local function invoke(action: string, argument: any): (boolean, any)
	local ok, success, value = pcall(function()
		return Net.Function("World"):InvokeServer(action, argument)
	end)
	if not ok then
		return false, Locale.T("Network error, try again.")
	end
	return success == true, value
end

local function toast(text: string, color: Color3?)
	if hud then
		hud:Toast(text, color)
	end
end

local function rootPart(player: Player): BasePart?
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if root and root:IsA("BasePart") then
		return root
	end
	return nil
end

local function plotCount(): number
	local folder = workspace:FindFirstChild("DopamineTown")
	local count = folder and folder:GetAttribute("PlotCount")
	return type(count) == "number" and count or WorldLayout.PlotCount(Players.MaxPlayers)
end

-- Ami Roblox ? (cache ; la 1re fois la réponse arrive un peu plus tard)
local function isFriend(userId: number): boolean
	local cached = friendCache[userId]
	if cached ~= nil then
		return cached
	end
	if not friendPending[userId] then
		friendPending[userId] = true
		task.spawn(function()
			local ok, result = pcall(function()
				return LocalPlayer:IsFriendsWithAsync(userId)
			end)
			friendCache[userId] = ok and result == true
			friendPending[userId] = nil
		end)
	end
	return false
end

-- Le joueur local peut-il entrer dans cette maison ?
local function canEnter(snapshot: any): boolean
	local userId = tonumber(snapshot.UserId) or 0
	if userId == LocalPlayer.UserId then
		return true
	end
	local mode = WorldLayout.NormalizeOpen(snapshot.Open)
	return WorldLayout.CanEnter(mode, false, mode == "Friends" and isFriend(userId))
end

----------------------------------------------------------------------
-- Maisons
----------------------------------------------------------------------

local function onSeat(house: any, slot: number, _model: Model, seatPart: BasePart)
	if edit and edit:IsEnabled() then
		return
	end
	local cf = seatPart.CFrame * CFrame.new(0, seatPart.Size.Y / 2, 0)
	if emotes then
		emotes:Stop("sit")
	end
	task.spawn(function()
		local ok, message = invoke("sit", { Owner = house.UserId, Slot = slot, CFrame = cf })
		if not ok and type(message) == "string" then
			toast(message, Color3.fromRGB(226, 80, 90))
		end
	end)
end

local function syncHouses()
	local folder = housesFolder
	if not inTown or not folder then
		return
	end
	local count = plotCount()
	for userId, house in pairs(houses) do
		local snapshot = snapshots[userId]
		if not snapshot or not snapshot.Plot or tonumber(house.Model:GetAttribute("Plot")) ~= snapshot.Plot then
			house:Destroy()
			houses[userId] = nil
		end
	end
	local missing = false
	for userId, snapshot in pairs(snapshots) do
		local plot = tonumber(snapshot.Plot)
		if plot then
			local house = houses[userId]
			if house then
				local ok, err = pcall(house.Update, house, snapshot)
				if not ok then
					warn("[Town] Maison " .. tostring(userId) .. " : " .. tostring(err))
				end
			else
				missing = true
			end
		end
	end
	-- nouvelles maisons : une par image (jamais des milliers de pièces d'un coup)
	if missing and not creating then
		creating = true
		task.spawn(function()
			while inTown and housesFolder == folder do
				local nextId: number? = nil
				local nextPlot = 0
				-- (la sienne d'abord, puis les autres)
				for userId, snapshot in pairs(snapshots) do
					if not houses[userId] and tonumber(snapshot.Plot) and (nextId == nil or userId == LocalPlayer.UserId) then
						nextId, nextPlot = userId, tonumber(snapshot.Plot) :: number
					end
				end
				if not nextId then
					break
				end
				local snapshot = snapshots[nextId :: number]
				local ok, result = pcall(HouseBuilder.new, snapshot, WorldLayout.PlotCFrame(nextPlot, count), folder)
				if ok then
					result.Model:SetAttribute("Plot", nextPlot)
					result.OnSeat = onSeat
					houses[nextId :: number] = result
				else
					warn("[Town] Maison " .. tostring(nextId) .. " : " .. tostring(result))
					snapshots[nextId :: number] = nil
				end
				task.wait()
			end
			creating = false
		end)
	end
end

local function myHouse(): any
	return houses[LocalPlayer.UserId]
end

----------------------------------------------------------------------
-- Événements du serveur
----------------------------------------------------------------------

local function heartsAt(position: Vector3)
	local folder = housesFolder
	if not folder then
		return
	end
	local anchor = Instance.new("Part")
	anchor.Name = "Hearts"
	anchor.Anchored = true
	anchor.CanCollide = false
	anchor.CanQuery = false
	anchor.CanTouch = false
	anchor.Transparency = 1
	anchor.Size = Vector3.new(1, 1, 1)
	anchor.CFrame = CFrame.new(position)
	anchor.Parent = folder
	local emitter = Instance.new("ParticleEmitter")
	emitter.Color = ColorSequence.new(Color3.fromRGB(255, 90, 150), Color3.fromRGB(255, 180, 210))
	emitter.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.8), NumberSequenceKeypoint.new(1, 1.6) })
	emitter.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(1, 1) })
	emitter.Lifetime = NumberRange.new(1, 1.6)
	emitter.Speed = NumberRange.new(6, 10)
	emitter.SpreadAngle = Vector2.new(40, 40)
	emitter.Acceleration = Vector3.new(0, 4, 0)
	emitter.Rate = 0
	emitter.Parent = anchor
	pcall(function()
		emitter:Emit(24)
	end)
	task.delay(2.5, function()
		anchor:Destroy()
	end)
end

local function onEvent(kind: any, payload: any)
	if kind == "Houses" and type(payload) == "table" then
		table.clear(snapshots)
		for _, snapshot in ipairs(payload) do
			if type(snapshot) == "table" and tonumber(snapshot.UserId) then
				snapshots[tonumber(snapshot.UserId) :: number] = snapshot
			end
		end
		syncHouses()
	elseif kind == "House" and type(payload) == "table" and tonumber(payload.UserId) then
		snapshots[tonumber(payload.UserId) :: number] = payload
		syncHouses()
		contextKey = ""
	elseif kind == "Gone" and tonumber(payload) then
		snapshots[tonumber(payload) :: number] = nil
		syncHouses()
	elseif kind == "Liked" and type(payload) == "table" then
		local house = houses[tonumber(payload.Owner) or 0]
		if house then
			heartsAt(house:DoorPosition() + Vector3.new(0, 6, 0))
		end
	elseif kind == "Toast" and type(payload) == "string" then
		toast(payload)
	end
end

----------------------------------------------------------------------
-- Ambiance (éclairage, interfaces, contrôles) : sauvegarde / remise
----------------------------------------------------------------------

-- Interfaces de Roblox (manette tactile, invites, chat...) : jamais masquées
local KEEP_GUIS: { [string]: boolean } = {
	TownHud = true,
	TownOverlay = true,
	TouchGui = true,
	ProximityPrompts = true,
	BubbleChat = true,
	Chat = true,
	Freecam = true,
}
local function keepGui(name: string): boolean
	return KEEP_GUIS[name] == true or string.find(name, "Touch", 1, true) ~= nil or string.find(name, "Prompt", 1, true) ~= nil
		or string.find(name, "Chat", 1, true) ~= nil
end

local function hideGui(s: Saved, gui: Instance)
	if gui:IsA("ScreenGui") and not keepGui(gui.Name) and gui.Enabled then
		table.insert(s.Guis, gui)
		gui.Enabled = false
	end
end

local function applyControls(s: Saved)
	local playerGui = LocalPlayer:FindFirstChildOfClass("PlayerGui")
	if playerGui then
		for _, gui in ipairs(playerGui:GetChildren()) do
			hideGui(s, gui)
		end
		-- une interface qui apparaît pendant la promenade est masquée aussi
		table.insert(connections, playerGui.ChildAdded:Connect(function(child)
			if inTown and saved then
				task.defer(function()
					if inTown and saved and child.Parent then
						hideGui(saved, child)
					end
				end)
			end
		end))
	end
	pcall(function()
		s.Touch = GuiService.TouchControlsEnabled
		GuiService.TouchControlsEnabled = true
	end)
	pcall(function()
		s.ChatWindow = TextChatService.ChatWindowConfiguration.Enabled
		TextChatService.ChatWindowConfiguration.Enabled = true
	end)
	pcall(function()
		s.ChatInput = TextChatService.ChatInputBarConfiguration.Enabled
		TextChatService.ChatInputBarConfiguration.Enabled = true
	end)
	pcall(function()
		local bubbles = TextChatService:FindFirstChildOfClass("BubbleChatConfiguration")
		if bubbles then
			bubbles.Enabled = true
		end
	end)
	pcall(function()
		s.CoreChat = StarterGui:GetCoreGuiEnabled(Enum.CoreGuiType.Chat)
		StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Chat, true)
	end)
	pcall(function()
		s.MaxZoom = LocalPlayer.CameraMaxZoomDistance
		s.MinZoom = LocalPlayer.CameraMinZoomDistance
		LocalPlayer.CameraMaxZoomDistance = MAX_ZOOM
		LocalPlayer.CameraMinZoomDistance = MIN_ZOOM
	end)
end

local function restoreControls(s: Saved)
	for _, gui in ipairs(s.Guis) do
		if gui.Parent then
			gui.Enabled = true
		end
	end
	table.clear(s.Guis)
	pcall(function()
		if s.Touch ~= nil then
			GuiService.TouchControlsEnabled = s.Touch
		end
	end)
	pcall(function()
		if s.ChatWindow ~= nil then
			TextChatService.ChatWindowConfiguration.Enabled = s.ChatWindow
		end
	end)
	pcall(function()
		if s.ChatInput ~= nil then
			TextChatService.ChatInputBarConfiguration.Enabled = s.ChatInput
		end
	end)
	pcall(function()
		if s.CoreChat ~= nil then
			StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Chat, s.CoreChat)
		end
	end)
	pcall(function()
		if s.MaxZoom then
			LocalPlayer.CameraMaxZoomDistance = s.MaxZoom
		end
		if s.MinZoom then
			LocalPlayer.CameraMinZoomDistance = s.MinZoom
		end
	end)
end

----------------------------------------------------------------------
-- Avatars : étiquettes, émotes
----------------------------------------------------------------------

local function refreshTags()
	for _, player in ipairs(Players:GetPlayers()) do
		local character = player.Character
		local head = character and character:FindFirstChild("Head")
		local snapshot = snapshots[player.UserId]
		if head and head:IsA("BasePart") then
			local humanoid = character and character:FindFirstChildOfClass("Humanoid")
			if humanoid then
				humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
			end
			local tag = head:FindFirstChild("TownTag")
			if not tag then
				local billboard = Instance.new("BillboardGui")
				billboard.Name = "TownTag"
				-- (taille en studs : l'étiquette rapetisse avec la distance, comme le monde)
				billboard.Size = UDim2.new(7, 0, 1.9, 0)
				billboard.StudsOffset = Vector3.new(0, 2.4, 0)
				billboard.MaxDistance = 90
				billboard.LightInfluence = 0
				billboard.AlwaysOnTop = false
				billboard.Adornee = head
				local name = Instance.new("TextLabel")
				name.Name = "Name"
				name.BackgroundTransparency = 1
				name.Size = UDim2.fromScale(1, 0.56)
				name.Font = Enum.Font.FredokaOne
				name.TextScaled = true
				name.TextColor3 = Color3.new(1, 1, 1)
				name.TextStrokeColor3 = Color3.fromRGB(150, 60, 120)
				name.TextStrokeTransparency = 0.2
				name.Parent = billboard
				local info = Instance.new("TextLabel")
				info.Name = "Info"
				info.BackgroundColor3 = Color3.fromRGB(255, 120, 180)
				info.BackgroundTransparency = 0.15
				info.AnchorPoint = Vector2.new(0.5, 0)
				info.Position = UDim2.fromScale(0.5, 0.58)
				info.Size = UDim2.fromScale(0.62, 0.4)
				info.Font = Enum.Font.GothamBold
				info.TextScaled = true
				info.TextColor3 = Color3.new(1, 1, 1)
				info.Parent = billboard
				local corner = Instance.new("UICorner")
				corner.CornerRadius = UDim.new(1, 0)
				corner.Parent = info
				local padding = Instance.new("UIPadding")
				padding.PaddingLeft = UDim.new(0, 6)
				padding.PaddingRight = UDim.new(0, 6)
				padding.PaddingTop = UDim.new(0, 2)
				padding.PaddingBottom = UDim.new(0, 2)
				padding.Parent = info
				billboard.Parent = head
				tag = billboard
			end
			local nameLabel = tag:FindFirstChild("Name") :: TextLabel?
			local infoLabel = tag:FindFirstChild("Info") :: TextLabel?
			if nameLabel then
				nameLabel.Text = player.DisplayName
			end
			if infoLabel then
				local rebirths = snapshot and tonumber(snapshot.Rebirths) or 0
				local likes = snapshot and tonumber(snapshot.Likes) or 0
				infoLabel.Text = string.format("🌊 %s   ❤️ %s", NumberFormatter.Format(rebirths), NumberFormatter.Format(likes))
			end
		end
	end
end

-- Émotes : TownEmotes garde la piste et l'arrête (bouger, sauter, bouton…)
local function playEmote(name: string)
	if not emotes then
		return
	end
	if edit and edit:IsEnabled() and name ~= "sit" then
		edit:SetEnabled(false)
	end
	emotes:Play(name)
end

----------------------------------------------------------------------
-- Contexte : dans quelle maison (ou devant laquelle) est le joueur
----------------------------------------------------------------------

local function computeContext(): any
	local root = rootPart(LocalPlayer)
	if not root then
		return nil
	end
	local position = root.Position
	local best: any = nil
	for userId, house in pairs(houses) do
		local snapshot = snapshots[userId]
		if snapshot then
			local x, y, d = WorldLayout.ToLocal(house.HouseCF, position)
			local inside = WorldLayout.InsideHouse(house.Size, x, y, d, 0)
			local onPlot = false
			if not inside then
				local rel = house.PlotCF:PointToObjectSpace(position)
				onPlot = math.abs(rel.X) <= WorldLayout.PLOT_W / 2 and math.abs(rel.Z) <= WorldLayout.PLOT_D / 2 + 10
			end
			if inside or onPlot then
				best = {
					Snapshot = snapshot,
					IsOwner = userId == LocalPlayer.UserId,
					Locked = not canEnter(snapshot),
					InHouse = inside,
					House = house,
				}
				if inside then
					break
				end
			end
		end
	end
	return best
end

local function refreshContext()
	local context = computeContext()
	currentContext = context
	local snapshot = context and context.Snapshot
	local key = context and table.concat({ tostring(snapshot.UserId), tostring(context.InHouse), tostring(context.Locked), tostring(snapshot.Likes),
		tostring(snapshot.Visits), tostring(snapshot.Open) }, "|") or ""
	if key ~= contextKey then
		contextKey = key
		if hud then
			hud:SetContext(context)
		end
	end
	if edit and edit:IsEnabled() and not (context and context.IsOwner and context.InHouse) and not edit:IsHolding() then
		edit:SetEnabled(false)
	end
end

----------------------------------------------------------------------
-- Boucle
----------------------------------------------------------------------

local function stepDoors()
	local positions: { Vector3 } = {}
	for _, player in ipairs(Players:GetPlayers()) do
		local root = rootPart(player)
		if root then
			table.insert(positions, root.Position)
		end
	end
	for userId, house in pairs(houses) do
		local snapshot = snapshots[userId]
		if snapshot then
			local door = house:DoorPosition()
			local near = false
			for _, p in ipairs(positions) do
				if (p - door).Magnitude < DOOR_RANGE then
					near = true
					break
				end
			end
			house:StepDoor(near, not canEnter(snapshot))
		end
	end
end

local function stepStream()
	if roomBuilding then
		return
	end
	local root = rootPart(LocalPlayer)
	local camera = workspace.CurrentCamera
	local focus = root and root.Position or (camera and camera.Focus.Position)
	if not focus then
		return
	end
	local bestHouse, bestSlot, bestDistance = nil, nil, math.huge
	for _, house in pairs(houses) do
		local slot, distance = house:NextToBuild(focus)
		if slot and distance < bestDistance then
			bestHouse, bestSlot, bestDistance = house, slot, distance
		end
	end
	if bestHouse and bestSlot then
		roomBuilding = true
		task.spawn(function()
			local ok, err = pcall(bestHouse.BuildRoom, bestHouse, bestSlot)
			if not ok then
				warn("[Town] Pièce : " .. tostring(err))
			end
			roomBuilding = false
		end)
	end
end

----------------------------------------------------------------------
-- Arrivée : guide vers sa maison, boussole
----------------------------------------------------------------------

-- Porte de ENTRÉE de la ville (TownMap via l'attribut "EntranceCF")
local function townCFrame(attribute: string): CFrame?
	local folder = workspace:FindFirstChild("DopamineTown")
	local value = folder and folder:GetAttribute(attribute)
	if typeof(value) == "CFrame" then
		return value
	end
	return nil
end

local function plazaCenter(): Vector3
	local plaza = townCFrame("PlazaCF")
	return plaza and plaza.Position or WorldLayout.Origin()
end

local function startGuide()
	local house = myHouse()
	if not house or not housesFolder then
		guidePending = true
		return
	end
	guidePending = false
	if not guide then
		guide = TownArrival.Guide(housesFolder)
	end
	local ok, err = pcall(function()
		guide:Start(LocalPlayer.Character, house:DoorPosition())
	end)
	if not ok then
		warn("[Town] Guide : " .. tostring(err))
	end
end

local function stepGuide()
	local house = myHouse()
	local root = rootPart(LocalPlayer)
	if guidePending and house then
		startGuide()
	end
	local context = currentContext
	local home = context ~= nil and context.IsOwner
	if guide and guide:IsActive() then
		local distance = guide:Update(root and root.Position)
		if home or distance < GUIDE_DONE then
			guide:Stop()
			toast(Locale.T("🏠 Here's your house! Walk in, it's all yours"), Color3.fromRGB(236, 72, 140))
		end
	end
	-- boussole : visible dès qu'on n'est pas chez soi (et pas pendant le survol)
	local camera = workspace.CurrentCamera
	local showing = house ~= nil and root ~= nil and camera ~= nil and not home and not (intro and intro:IsRunning())
	if showing and house and root and camera then
		local door = house:DoorPosition()
		hud:SetCompass(true, TownArrival.Bearing(camera, root.Position, door), (Vector3.new(door.X, 0, door.Z) - Vector3.new(root.Position.X, 0, root.Position.Z)).Magnitude)
	else
		hud:SetCompass(false)
	end
end

local function step(dt: number)
	if not inTown then
		return
	end
	clocks.Counter += dt
	clocks.Door += dt
	clocks.Stream += dt
	clocks.Tag += dt
	clocks.Guide += dt
	TownAtmosphere.Step(dt)
	if clocks.Counter >= COUNTER_EVERY then
		clocks.Counter = 0
		if hud then
			hud:UpdateCounter()
		end
		if emotes then
			local ok, err = pcall(emotes.Step, emotes)
			if not ok then
				warn("[Town] Émotes : " .. tostring(err))
			end
		end
	end
	if clocks.Guide >= GUIDE_EVERY then
		clocks.Guide = 0
		local ok, err = pcall(stepGuide)
		if not ok then
			warn("[Town] Guide : " .. tostring(err))
		end
	end
	if clocks.Door >= DOOR_EVERY then
		clocks.Door = 0
		local ok, err = pcall(function()
			stepDoors()
			refreshContext()
		end)
		if not ok then
			warn("[Town] " .. tostring(err))
		end
	end
	if clocks.Stream >= STREAM_EVERY then
		clocks.Stream = 0
		local ok, err = pcall(stepStream)
		if not ok then
			warn("[Town] Flux : " .. tostring(err))
		end
	end
	if clocks.Tag >= TAG_EVERY then
		clocks.Tag = 0
		pcall(refreshTags)
	end
end

----------------------------------------------------------------------
-- Entrer / sortir
----------------------------------------------------------------------

local function closeClickerWindows()
	pcall(function()
		local PanelManager = require(Components:WaitForChild("PanelManager")) :: any
		if PanelManager.IsOpen() then
			PanelManager.Close()
		end
	end)
	pcall(function()
		local module = Components:FindFirstChild("House") and Components.House:FindFirstChild("House3D")
		if module then
			local House3D = require(module) :: any
			if House3D.IsOpen() then
				House3D.Close()
			end
		end
	end)
end

local function waitCharacter(timeout: number): Model?
	local started = os.clock()
	while os.clock() - started < timeout do
		local character = LocalPlayer.Character
		if character and character:FindFirstChild("HumanoidRootPart") then
			return character
		end
		task.wait(0.1)
	end
	return nil
end

local leave: () -> ()

-- Aller dans une pièce (sa maison ou celle d'un autre) : on la construit d'abord
local function goRoom(ownerId: number, slot: number)
	local house = houses[ownerId]
	if house and house.Rooms[slot] and house.Rooms[slot].State ~= "Built" then
		roomBuilding = true
		pcall(house.BuildRoom, house, slot)
		roomBuilding = false
	end
	local ok, message = invoke("room", { Owner = ownerId, Slot = slot })
	if not ok and type(message) == "string" then
		toast(message, Color3.fromRGB(226, 80, 90))
	end
end

-- Caméra de Roblox qui suit l'avatar
local function followCamera(character: Model?)
	local camera = workspace.CurrentCamera
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if camera and humanoid then
		camera.CameraType = Enum.CameraType.Custom
		camera.CameraSubject = humanoid
	end
end

-- Survol de la ville (1re arrivée de la session), puis le guide
local function playIntro(character: Model)
	local camera = workspace.CurrentCamera
	local entrance = townCFrame("EntranceCF")
	local root = character:FindFirstChild("HumanoidRootPart")
	if not entrance and root and root:IsA("BasePart") then
		entrance = root.CFrame
	end
	if not camera or not entrance then
		followCamera(character)
		startGuide()
		return
	end
	-- (l'avatar arrive exactement là où le survol se termine)
	if root and root:IsA("BasePart") then
		entrance = CFrame.new(root.Position) * entrance.Rotation
	end
	introSeen = true
	local path = TownArrival.MakePath(entrance :: CFrame, plazaCenter())
	hud:SetCinematic(true, Locale.T("Welcome, %s!", LocalPlayer.DisplayName))
	intro = TownArrival.Intro({
		Camera = camera,
		Path = path,
		OnProgress = function(t: number)
			hud:SetIntroProgress(t)
		end,
		OnDone = function(_skipped: boolean)
			intro = nil
			hud:SetCinematic(false)
			if inTown then
				followCamera(LocalPlayer.Character)
				startGuide()
				toast(Locale.T("🚶 Welcome to Dopamine Town!"), Color3.fromRGB(236, 72, 140))
				toast(Locale.T("Follow the glowing arc to your house 🏠"))
			end
		end,
	})
end

local function onCharacter(character: Model)
	if not inTown then
		return
	end
	character:WaitForChild("Humanoid", 5)
	if not inTown or LocalPlayer.Character ~= character then
		return
	end
	if not (intro and intro:IsRunning()) then
		followCamera(character)
	end
	if emotes then
		emotes:Attach(character)
	end
	if guide and guide:IsActive() then
		guide:Attach(character)
	end
end

local function enter(options: any)
	if busy then
		return
	end
	if inTown then
		if type(options) == "table" and tonumber(options.Slot) then
			task.spawn(goRoom, LocalPlayer.UserId, tonumber(options.Slot) :: number)
		end
		return
	end
	busy = true
	closeClickerWindows()
	local s: Saved = { Guis = {}, Lighting = {}, Effects = {}, Moved = {} }
	saved = s
	hud:SetVisible(true)
	hud:ShowLoading(true, Locale.T("Building the town…"), 0.08)
	applyControls(s)
	local camera = workspace.CurrentCamera
	s.CameraType = camera and camera.CameraType or nil
	local visit = type(options) == "table" and options.Visit or nil
	local slot = type(options) == "table" and tonumber(options.Slot) or nil
	task.spawn(function()
		local ok, result = invoke("enter", { Visit = visit, Slot = slot })
		if not ok then
			restoreControls(s)
			saved = nil
			hud:ShowLoading(false)
			hud:SetVisible(false)
			busy = false
			warn("[Town] " .. tostring(result))
			pcall(function()
				local Notifications = require(Components:WaitForChild("Notifications")) :: any
				Notifications.Show({ Text = tostring(result or Locale.T("Network error, try again.")), Icon = "🚶", Duration = 4 })
			end)
			return
		end
		inTown = true
		TownAtmosphere.SetNight(ClientState.IsUserDarkMode())
		TownAtmosphere.Apply(s)
		local folder = Instance.new("Folder")
		folder.Name = HOUSES_FOLDER
		folder.Parent = workspace
		housesFolder = folder
		-- (les instantanés arrivent par l'événement "Houses" ; secours si besoin)
		if next(snapshots) == nil then
			local okList, list = invoke("houses", nil)
			if okList and type(list) == "table" then
				onEvent("Houses", list)
			end
		end
		syncHouses()
		table.insert(connections, RunService.Heartbeat:Connect(step))
		table.insert(connections, LocalPlayer.CharacterAdded:Connect(onCharacter))
		table.insert(connections, LocalPlayer.CharacterRemoving:Connect(function()
			if emotes then
				emotes:Detach()
			end
		end))
		-- nuit en ville = réglage ⚙️ "Mode sombre" du joueur (source "User")
		local function syncNight()
			TownAtmosphere.SetNight(ClientState.IsUserDarkMode())
		end
		table.insert(connections, ClientState.DarkModeChanged:Connect(syncNight))
		table.insert(connections, ClientState.DarkSourcesChanged:Connect(syncNight))
		-- chargement : personnage + maisons (barre de progression)
		local started = os.clock()
		local character: Model? = nil
		while inTown and os.clock() - started < 10 do
			local current = LocalPlayer.Character
			if current and current:FindFirstChild("HumanoidRootPart") then
				character = current
			end
			local total, built = 0, 0
			for userId, snapshot in pairs(snapshots) do
				if snapshot.Plot then
					total += 1
					if houses[userId] then
						built += 1
					end
				end
			end
			local ratio = total > 0 and built / total or 1
			hud:SetLoadingProgress(0.15 + 0.6 * ratio + (character and 0.25 or 0))
			if total > 0 and built < total then
				hud:ShowLoading(true, Locale.T("Building the houses… %s/%s", tostring(built), tostring(total)))
			end
			if character and ratio >= 1 and os.clock() - started > 0.5 then
				break
			end
			task.wait(0.1)
		end
		if not inTown then
			return
		end
		hud:ShowLoading(true, Locale.T("Here we go!"), 1)
		task.wait(0.25)
		character = character or waitCharacter(4)
		if not inTown then
			return
		end
		if character then
			if emotes then
				emotes:Attach(character)
			end
		end
		local arrival = type(result) == "table" and result.Arrival == "Entrance"
		hud:ShowLoading(false)
		busy = false
		if arrival and character and not introSeen then
			playIntro(character)
		else
			followCamera(character)
			if arrival then
				startGuide()
				toast(Locale.T("🚶 Welcome to Dopamine Town!"), Color3.fromRGB(236, 72, 140))
				toast(Locale.T("Follow the glowing arc to your house 🏠"))
			else
				toast(Locale.T("🚶 Welcome to Dopamine Town!"), Color3.fromRGB(236, 72, 140))
			end
		end
		if slot and inTown then
			goRoom(LocalPlayer.UserId, slot)
		end
	end)
end

-- Remise à l'état du clicker (après le fondu)
local function teardown()
	inTown = false
	if intro then
		intro:Cancel()
		intro = nil
	end
	if emotes then
		emotes:Stop("leave")
		emotes:Detach()
	end
	if guide then
		guide:Destroy()
		guide = nil
	end
	guidePending = false
	if edit then
		edit:SetEnabled(false)
	end
	for _, connection in ipairs(connections) do
		connection:Disconnect()
	end
	table.clear(connections)
	for _, house in pairs(houses) do
		pcall(house.Destroy, house)
	end
	table.clear(houses)
	if housesFolder then
		housesFolder:Destroy()
		housesFolder = nil
	end
	roomBuilding = false
	contextKey = ""
	currentContext = nil
	local s = saved
	if s then
		TownAtmosphere.Restore(s)
		restoreControls(s)
		local camera = workspace.CurrentCamera
		if camera and s.CameraType then
			pcall(function()
				camera.CameraType = s.CameraType :: Enum.CameraType
			end)
		end
	end
	saved = nil
	hud:SetVisible(false)
	task.spawn(invoke, "leave", nil)
end

leave = function()
	if not inTown or busy then
		return
	end
	busy = true
	-- l'émote s'arrête tout de suite ; fondu, remise, puis le clicker réapparaît
	if emotes then
		emotes:Stop("leave")
	end
	hud:Fade(0, 0.3, FADE_COLOR)
	task.delay(0.32, function()
		local ok, err = pcall(teardown)
		if not ok then
			warn("[Town] Sortie : " .. tostring(err))
			inTown = false
		end
		hud:Fade(1, 0.45)
		busy = false
	end)
end

----------------------------------------------------------------------
-- Actions du HUD
----------------------------------------------------------------------

local OPEN_NEXT = { Everyone = "Friends", Friends = "Nobody", Nobody = "Everyone" }

local function openVisit()
	local rows = {}
	for userId, snapshot in pairs(snapshots) do
		if snapshot.Plot then
			table.insert(rows, { Snapshot = snapshot, IsSelf = userId == LocalPlayer.UserId, Locked = not canEnter(snapshot) })
		end
	end
	table.sort(rows, function(a, b)
		if a.IsSelf ~= b.IsSelf then
			return a.IsSelf
		end
		if (a.Snapshot.InTown == true) ~= (b.Snapshot.InTown == true) then
			return a.Snapshot.InTown == true
		end
		return (tonumber(a.Snapshot.Likes) or 0) > (tonumber(b.Snapshot.Likes) or 0)
	end)
	hud:OpenVisit(rows)
end

local function callbacks(): any
	return {
		Back = function()
			leave()
		end,
		Home = function()
			task.spawn(function()
				local ok, message = invoke("home", nil)
				if not ok and type(message) == "string" then
					toast(message)
				end
			end)
		end,
		OpenVisit = openVisit,
		Visit = function(userId: number)
			task.spawn(function()
				local ok, result = invoke("visit", userId)
				if not ok then
					toast(tostring(result), Color3.fromRGB(226, 80, 90))
				elseif type(result) == "table" and result.Locked then
					toast(Locale.T("🔒 This house is closed to visitors"))
				else
					local snapshot = snapshots[userId]
					toast(Locale.T("🚶 Welcome to %s's house!", tostring(snapshot and snapshot.DisplayName or "?")))
				end
			end)
		end,
		Emote = playEmote,
		ToggleEdit = function()
			if not edit then
				return
			end
			local context = currentContext
			if not edit:IsEnabled() and not (context and context.IsOwner and context.InHouse) then
				toast(Locale.T("Go inside your house to move your furniture"))
				return
			end
			if not edit:IsEnabled() and emotes then
				-- (mode édition : l'émote s'arrête)
				emotes:Stop("edit")
			end
			edit:SetEnabled(not edit:IsEnabled())
		end,
		Rotate = function()
			edit:Rotate(45)
		end,
		Snap = function()
			edit:ToggleSnap()
		end,
		PutAway = function()
			edit:PutAway()
		end,
		Drop = function()
			edit:Drop()
		end,
		Cancel = function()
			edit:Cancel()
		end,
		Like = function()
			local context = currentContext
			if not context or context.IsOwner then
				return
			end
			task.spawn(function()
				local ok, message = invoke("like", tonumber(context.Snapshot.UserId))
				toast(tostring(message or ""), ok and Color3.fromRGB(255, 90, 140) or Color3.fromRGB(150, 110, 170))
			end)
		end,
		Click = function(): number?
			local ok, gain = pcall(ClientState.Click)
			return ok and gain or nil
		end,
		StopEmote = function()
			if emotes then
				emotes:Stop("button")
			end
		end,
		GetUp = function()
			if not emotes then
				return
			end
			local humanoid = emotes.Humanoid
			local seat = humanoid and humanoid.SeatPart
			emotes:StandUp()
			-- (siège créé par le serveur : il le détruit, on est sûr d'être debout)
			if seat and string.sub(seat.Name, 1, 9) == "TownSeat_" then
				task.spawn(invoke, "stand", nil)
			end
		end,
		SkipIntro = function()
			if intro then
				intro:Skip()
			end
		end,
		CycleOpen = function()
			local mine = snapshots[LocalPlayer.UserId]
			local nextMode = OPEN_NEXT[WorldLayout.NormalizeOpen(mine and mine.Open)]
			task.spawn(function()
				local ok, message = invoke("setOpen", nextMode)
				if ok and mine then
					mine.Open = nextMode
					contextKey = ""
				end
				toast(tostring(message or ""))
			end)
		end,
	}
end

----------------------------------------------------------------------

function TownClient.IsInTown(): boolean
	return inTown
end

function TownClient.Enter(options: any?)
	enter(options or {})
end

function TownClient.Leave()
	leave()
end

-- (tests) état interne
function TownClient.Debug(): any
	return { Houses = houses, Snapshots = snapshots, Hud = hud, Edit = edit, Emotes = emotes, Atmosphere = TownAtmosphere, Context = function()
		return currentContext
	end, Guide = function()
		return guide
	end, Intro = function()
		return intro
	end, Step = step, Event = onEvent }
end

function TownClient.Init()
	hud = TownHud.new(callbacks())
	emotes = TownEmotes.new({
		OnChanged = function(state: string?)
			hud:SetAction(state)
		end,
		Toast = function(text: string)
			toast(Locale.T(text))
		end,
	})
	edit = FurnitureEdit.new({
		GetHouse = myHouse,
		Hud = hud,
		Toast = toast,
		Save = function(_slot: number, roomId: string, placed: { any }, onResult: (boolean, string?) -> ())
			task.spawn(function()
				local ok, success, message = pcall(function()
					return Net.Function("House"):InvokeServer("saveLayout", { Room = roomId, Placed = placed })
				end)
				if not ok then
					onResult(false, Locale.T("Network error, try again."))
				else
					onResult(success == true, message ~= nil and tostring(message) or nil)
				end
			end)
		end,
	})
	Net.Event("WorldEvent").OnClientEvent:Connect(onEvent)
	WorldLink.SetHandler(TownClient.Enter, TownClient.IsInTown)
end

return TownClient
