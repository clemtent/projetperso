--[[
	WorldService (ModuleScript)
	Emplacement : ServerScriptService > Services > WorldService

	🚶 Dopamine Town : mode "on se promène en 3D avec son avatar".
	  - au démarrage : la ville (TownMap) avec une parcelle par joueur
	    possible (WorldLayout.PlotCount(Players.MaxPlayers), 4..12) ;
	  - chaque joueur reçoit une parcelle à son arrivée (libérée à son
	    départ : panneau remis à "✨ Free plot") ;
	  - les MAISONS sont construites par les clients (HouseBuilder) à partir
	    d'un petit "instantané" de data.House envoyé par ce service (le
	    serveur ne porte pas des dizaines de milliers de Parts) ; il est
	    renvoyé aux joueurs EN VILLE seulement quand il change (signature
	    JSON vérifiée toutes les 1,5 s) ;
	  - entrer en ville : le serveur charge le personnage (LoadCharacter,
	    Players.CharacterAutoLoads reste false) et le pose devant sa porte ;
	    sortir : le personnage est détruit (retour au clicker). Les gains
	    passifs continuent (GameService n'est pas concerné) ;
	  - visites (porte d'un autre joueur), réglage d'ouverture de sa maison
	    (Everyone / Friends / Nobody, défaut Everyone) respecté par le client
	    (porte verrouillée) ET par le serveur (ronde 1 fois / s : un intrus
	    est reposé devant la porte) ;
	  - ❤️ "j'aime" : 1 par maison et par jour, 10 par jour et par visiteur ;
	    le propriétaire gagne 60 s de sa production (30 fois / jour), le
	    visiteur 20 s de la sienne ; compteur sur le panneau de la parcelle ;
	  - s'asseoir sur un meuble (les meubles sont côté client) : le client
	    envoie la position du siège, le serveur la vérifie (pièce de la maison
	    visée, accès autorisé, à portée du personnage) et crée un vrai Seat
	    invisible (CanTouch = false) puis Seat:Sit(humanoid) : la pose assise
	    est répliquée à tout le monde comme un siège normal ; le Seat est
	    détruit dès que le joueur se lève.
	Tout est dans des pcall, chaque action a sa limite de fréquence.

	Données : data.Town = { Open, Likes, Visits, LikeDay, Liked = { [UserId] = true },
	LikesGiven, LikedRewards, RewardDay } (WorldLayout.SanitizeTown).

	RemoteFunction World (action, argument) -> (succès, résultat | message) :
	  "enter" { Visit = UserId?, Slot = number? } | "leave" | "home"
	  "visit" UserId | "room" { Owner = UserId, Slot } | "setOpen" "Everyone" | "Friends" | "Nobody"
	  "like" UserId | "sit" { Owner = UserId, Slot, CFrame } | "houses" (-> liste des instantanés)
	RemoteEvent WorldEvent (S -> C) :
	  ("Houses", { instantané, ... }) | ("House", instantané) | ("Gone", UserId)
	  ("Liked", { Owner, By, Likes }) | ("Toast", texte) | ("Spawned", { Slot?, Owner })
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local HttpService = game:GetService("HttpService")
local RunService = game:GetService("RunService")
local TextChatService = game:GetService("TextChatService")

local Config = require(ReplicatedStorage.Shared.Config)
local Net = require(ReplicatedStorage.Shared.Net)
local WorldLayout = require(ReplicatedStorage.Shared.WorldLayout)
local NumberFormatter = require(ReplicatedStorage.Shared.NumberFormatter)
local RateLimiter = require(script.Parent.RateLimiter)
local TownMap = require(script.Parent:WaitForChild("World"):WaitForChild("TownMap"))

local WorldService = {}

local services

local SNAPSHOT_INTERVAL = 1.5
local PATROL_INTERVAL = 1
local RESPAWN_DELAY = 3
local WALK_SPEED = 22
local SIT_RANGE = 14 -- (studs) distance max personnage -> siège
local SEAT_LIFETIME = 900 -- (s) un siège oublié disparaît
local MAX_ITEMS = 60 -- objets par pièce dans un instantané (garde-fou)

type State = {
	InTown: boolean,
	Plot: number?,
	Seat: Seat?,
	Friends: { [number]: boolean },
	FriendPending: { [number]: boolean },
	Visited: { [number]: boolean },
	Signature: string,
	Loading: boolean,
	Generation: number,
}

local town: TownMap.Town? = nil
local plotOwners: { [number]: Player } = {}
local states: { [Player]: State } = {}

----------------------------------------------------------------------
-- Utilitaires
----------------------------------------------------------------------

local function T(player: Player, text: string, ...): string
	local ok, result = pcall(function(...)
		return services.GameService:T(player, text, ...)
	end, ...)
	if ok and type(result) == "string" then
		return result
	end
	return string.format(text, ...)
end

local function stateOf(player: Player): State
	local state = states[player]
	if not state then
		state = {
			InTown = false,
			Plot = nil,
			Seat = nil,
			Friends = {},
			FriendPending = {},
			Visited = {},
			Signature = "",
			Loading = false,
			Generation = 0,
		}
		states[player] = state
	end
	return state
end

local function dataOf(player: Player): any
	local ok, data = pcall(function()
		return services.DataService:GetData(player)
	end)
	return ok and data or nil
end

local function townOf(player: Player): WorldLayout.TownData?
	local data = dataOf(player)
	if not data then
		return nil
	end
	if type(data.Town) ~= "table" or data.Town.LikeDay ~= WorldLayout.DayNumber(os.time()) then
		data.Town = WorldLayout.SanitizeTown(data.Town, os.time())
	end
	return data.Town
end

local function sizeDefOf(data: any): any
	local house = type(data) == "table" and data.House or nil
	local id = type(house) == "table" and house.Size or nil
	return Config.HouseSizesById[id] or Config.House.Sizes[1]
end

local function playerById(userId: any): Player?
	if type(userId) ~= "number" or userId ~= userId then
		return nil
	end
	local ok, player = pcall(Players.GetPlayerByUserId, Players, userId)
	if ok and player and states[player] then
		return player
	end
	return nil
end

local function plotInfo(player: Player): TownMap.PlotInfo?
	local state = states[player]
	local current = town
	if not state or not state.Plot or not current then
		return nil
	end
	return current.Plots[state.Plot]
end

local function characterParts(player: Player): (Model?, Humanoid?, BasePart?)
	local character = player.Character
	if not character or not character.Parent then
		return nil, nil, nil
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local root = character:FindFirstChild("HumanoidRootPart")
	if root and not root:IsA("BasePart") then
		root = nil
	end
	return character, humanoid, root :: BasePart?
end

local function toast(player: Player, text: string)
	pcall(function()
		Net.Event("WorldEvent"):FireClient(player, "Toast", text)
	end)
end

-- Amitié Roblox (mise en cache ; `wait` = on peut attendre la réponse)
local function isFriend(player: Player, ownerId: number, wait: boolean): boolean
	local state = stateOf(player)
	local cached = state.Friends[ownerId]
	if cached ~= nil then
		return cached
	end
	local function fetch()
		local ok, result = pcall(player.IsFriendsWith, player, ownerId)
		state.Friends[ownerId] = ok and result == true
		state.FriendPending[ownerId] = nil
	end
	if wait then
		fetch()
		return state.Friends[ownerId] == true
	end
	if not state.FriendPending[ownerId] then
		state.FriendPending[ownerId] = true
		task.spawn(fetch)
	end
	return false
end

local function canEnter(visitor: Player, owner: Player, wait: boolean): boolean
	if visitor == owner then
		return true
	end
	local ownerTown = townOf(owner)
	local mode = ownerTown and ownerTown.Open or WorldLayout.DEFAULT_OPEN
	if mode == "Friends" then
		return WorldLayout.CanEnter(mode, false, isFriend(visitor, owner.UserId, wait))
	end
	return WorldLayout.CanEnter(mode, false, false)
end

----------------------------------------------------------------------
-- Panneaux des parcelles
----------------------------------------------------------------------

local OPEN_ICONS = { Everyone = "🔓", Friends = "👥", Nobody = "🔒" }

local function refreshSign(index: number)
	local current = town
	if not current then
		return
	end
	local plot = current.Plots[index]
	if not plot then
		return
	end
	local owner = plotOwners[index]
	local data = owner and dataOf(owner)
	if not owner or not data then
		pcall(TownMap.SetPlotSign, plot, "✨ Free plot", "", "")
		plot.Model:SetAttribute("OwnerId", 0)
		plot.Model:SetAttribute("OwnerName", "")
		plot.Model:SetAttribute("Likes", 0)
		return
	end
	local ownerTown = townOf(owner)
	local size = sizeDefOf(data)
	local likes = ownerTown and ownerTown.Likes or 0
	local visits = ownerTown and ownerTown.Visits or 0
	local open = ownerTown and ownerTown.Open or WorldLayout.DEFAULT_OPEN
	-- (noms Roblox : pas de filtre nécessaire ; titre en anglais neutre + emoji)
	pcall(TownMap.SetPlotSign, plot, "🏠 " .. owner.DisplayName,
		string.format("%s %s · 🌊 %s", tostring(size.Icon or "🏠"), tostring(size.Name or ""), tostring(tonumber(data.Rebirths) or 0)),
		string.format("❤️ %s   👀 %s   %s", NumberFormatter.Format(likes), NumberFormatter.Format(visits), OPEN_ICONS[open] or "🔓"))
	plot.Model:SetAttribute("OwnerId", owner.UserId)
	plot.Model:SetAttribute("OwnerName", owner.DisplayName)
	plot.Model:SetAttribute("Likes", likes)
end

----------------------------------------------------------------------
-- Instantanés des maisons
----------------------------------------------------------------------

local function copyPlaced(list: any): { any }
	local placed = {}
	if type(list) ~= "table" then
		return placed
	end
	for _, entry in ipairs(list) do
		if #placed >= MAX_ITEMS then
			break
		end
		if type(entry) == "table" and type(entry.I) == "string" then
			table.insert(placed, {
				I = entry.I,
				X = tonumber(entry.X) or 0.5,
				Y = tonumber(entry.Y) or 0.8,
				S = tonumber(entry.S) or 1,
				Z = tonumber(entry.Z) or 0,
				F = entry.F == true or nil,
				C = type(entry.C) == "string" and entry.C or nil,
				R = WorldLayout.NormalizeRotation(entry.R),
			})
		end
	end
	return placed
end

local function snapshotOf(player: Player): any?
	local data = dataOf(player)
	local state = states[player]
	if not data or not state or type(data.House) ~= "table" then
		return nil
	end
	local house = data.House
	local rooms = {}
	if type(house.Rooms) == "table" then
		for _, room in ipairs(house.Rooms) do
			if type(room) == "table" then
				table.insert(rooms, {
					Id = tostring(room.Id),
					Type = room.Type,
					Slot = tonumber(room.Slot) or 1,
					Wallpaper = room.Wallpaper,
					Floor = room.Floor,
					Trim = room.Trim,
					Mood = room.Mood,
					View = room.View,
					Placed = copyPlaced(room.Placed),
				})
			end
		end
	end
	local garden = {}
	if type(house.Garden) == "table" then
		for _, id in ipairs(house.Garden) do
			if type(id) == "string" then
				table.insert(garden, id)
			end
		end
	end
	local ownerTown = townOf(player)
	return {
		UserId = player.UserId,
		Name = player.Name,
		DisplayName = player.DisplayName,
		Rebirths = tonumber(data.Rebirths) or 0,
		Plot = state.Plot,
		InTown = state.InTown,
		Open = ownerTown and ownerTown.Open or WorldLayout.DEFAULT_OPEN,
		Likes = ownerTown and ownerTown.Likes or 0,
		Visits = ownerTown and ownerTown.Visits or 0,
		Size = house.Size,
		Facade = house.Facade,
		Roof = house.Roof,
		RoofStyle = house.RoofStyle,
		Garden = garden,
		Rooms = rooms,
	}
end

local function townPlayers(): { Player }
	local list = {}
	for player, state in pairs(states) do
		if state.InTown and player.Parent then
			table.insert(list, player)
		end
	end
	return list
end

local function fireTown(kind: string, payload: any, except: Player?)
	local remote = Net.Event("WorldEvent")
	for _, player in ipairs(townPlayers()) do
		if player ~= except then
			pcall(remote.FireClient, remote, player, kind, payload)
		end
	end
end

local function allSnapshots(): { any }
	local list = {}
	for player in pairs(states) do
		local ok, snap = pcall(snapshotOf, player)
		if ok and snap then
			table.insert(list, snap)
		end
	end
	return list
end

-- Renvoie l'instantané d'un joueur à la ville s'il a changé
local function pushIfChanged(player: Player, force: boolean?)
	local state = states[player]
	if not state then
		return
	end
	local ok, snap = pcall(snapshotOf, player)
	if not ok or not snap then
		return
	end
	local okJson, signature = pcall(HttpService.JSONEncode, HttpService, snap)
	if not okJson or type(signature) ~= "string" then
		signature = tostring(os.clock())
	end
	if force or signature ~= state.Signature then
		state.Signature = signature
		fireTown("House", snap)
	end
end

----------------------------------------------------------------------
-- Personnage
----------------------------------------------------------------------

local function destroySeat(state: State)
	local seat = state.Seat
	state.Seat = nil
	if seat then
		pcall(seat.Destroy, seat)
	end
end

local function removeCharacter(player: Player)
	local character = player.Character
	if character then
		pcall(function()
			player.Character = nil
		end)
		pcall(character.Destroy, character)
	end
end

local function spawnPoint(player: Player, target: Player?): CFrame
	local current = town
	local owner = target or player
	local ownerState = states[owner]
	local data = dataOf(owner)
	if current and ownerState and ownerState.Plot and data then
		local plot = current.Plots[ownerState.Plot]
		return WorldLayout.DoorSpawn(plot.HouseCFrame, sizeDefOf(data))
	end
	return current and current.PlazaCFrame or CFrame.new(WorldLayout.Origin() + Vector3.new(0, 4, 0))
end

local function teleport(player: Player, cf: CFrame)
	local character = player.Character
	if character and character.Parent then
		pcall(function()
			character:PivotTo(cf)
		end)
	end
end

local function spawnCharacter(player: Player, target: CFrame)
	local state = stateOf(player)
	if state.Loading then
		return
	end
	state.Loading = true
	state.Generation += 1
	local generation = state.Generation
	task.spawn(function()
		local current = town
		if current then
			pcall(function()
				player.RespawnLocation = current.Spawn
			end)
		end
		local ok, err = pcall(player.LoadCharacter, player)
		state.Loading = false
		if not ok then
			warn("[WorldService] LoadCharacter : " .. tostring(err))
			return
		end
		if not state.InTown or state.Generation ~= generation or not player.Parent then
			removeCharacter(player)
			return
		end
		local character, humanoid = characterParts(player)
		if not character then
			return
		end
		if humanoid then
			pcall(function()
				humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
				humanoid.WalkSpeed = WALK_SPEED
				humanoid.NameDisplayDistance = 0
			end)
			humanoid.Died:Connect(function()
				destroySeat(state)
				task.delay(RESPAWN_DELAY, function()
					if state.InTown and player.Parent and player.Character == character then
						spawnCharacter(player, spawnPoint(player))
					end
				end)
			end)
		end
		teleport(player, target)
	end)
end

----------------------------------------------------------------------
-- Actions
----------------------------------------------------------------------

local function enter(player: Player, argument: any): (boolean, any)
	local state = stateOf(player)
	if not RateLimiter.Check(player, "WorldEnter", 2) then
		return false, T(player, "Slow down!")
	end
	state.InTown = true
	local target: Player? = nil
	if type(argument) == "table" and argument.Visit ~= nil then
		target = playerById(argument.Visit)
	end
	local spawnAt = spawnPoint(player, target)
	spawnCharacter(player, spawnAt)
	-- le nouvel arrivant reçoit toutes les maisons ; les autres apprennent qu'il est là
	pcall(function()
		Net.Event("WorldEvent"):FireClient(player, "Houses", allSnapshots())
	end)
	pushIfChanged(player, true)
	return true, { Plot = state.Plot, Owner = target and target.UserId or player.UserId }
end

local function leave(player: Player): (boolean, any)
	local state = stateOf(player)
	state.InTown = false
	state.Generation += 1
	destroySeat(state)
	removeCharacter(player)
	pushIfChanged(player, true)
	return true, nil
end

local function visit(player: Player, argument: any): (boolean, any)
	local state = stateOf(player)
	if not state.InTown then
		return false, T(player, "Invalid request")
	end
	local owner = playerById(argument)
	if not owner or not states[owner].Plot then
		return false, T(player, "This player has no house here")
	end
	destroySeat(state)
	teleport(player, spawnPoint(player, owner))
	local allowed = canEnter(player, owner, true)
	if owner ~= player and not state.Visited[owner.UserId] then
		state.Visited[owner.UserId] = true
		local ownerTown = townOf(owner)
		if ownerTown then
			ownerTown.Visits += 1
		end
		if states[owner] and states[owner].Plot then
			refreshSign(states[owner].Plot :: number)
		end
		toast(owner, T(owner, "👋 %s is visiting your house!", player.DisplayName))
	end
	return true, { Owner = owner.UserId, Locked = not allowed }
end

local function goRoom(player: Player, argument: any): (boolean, any)
	local state = stateOf(player)
	if not state.InTown or type(argument) ~= "table" then
		return false, T(player, "Invalid request")
	end
	local owner = playerById(argument.Owner)
	local slot = tonumber(argument.Slot)
	if not owner or not states[owner].Plot or not slot or slot ~= slot then
		return false, T(player, "Invalid request")
	end
	if not canEnter(player, owner, true) then
		return false, T(player, "🔒 This house is closed to visitors")
	end
	local data = dataOf(owner)
	local current = town
	if not data or not current then
		return false, T(player, "Loading...")
	end
	local size = sizeDefOf(data)
	slot = math.clamp(math.floor(slot), 1, (tonumber(size.Floors) or 1) * (tonumber(size.Columns) or 1))
	destroySeat(state)
	teleport(player, WorldLayout.RoomSpawn(current.Plots[states[owner].Plot :: number].HouseCFrame, size, slot))
	return true, { Owner = owner.UserId, Slot = slot }
end

local function setOpen(player: Player, argument: any): (boolean, any)
	if type(argument) ~= "string" or not table.find(WorldLayout.OPEN_MODES, argument) then
		return false, T(player, "Invalid request")
	end
	local ownerTown = townOf(player)
	if not ownerTown then
		return false, T(player, "Loading...")
	end
	ownerTown.Open = argument
	local state = stateOf(player)
	if state.Plot then
		refreshSign(state.Plot)
	end
	pushIfChanged(player)
	local texts = {
		Everyone = "🔓 Your house is open to everyone",
		Friends = "👥 Your house is open to your friends only",
		Nobody = "🔒 Your house is closed to visitors",
	}
	return true, T(player, texts[argument])
end

local function like(player: Player, argument: any): (boolean, any)
	local state = stateOf(player)
	local owner = playerById(argument)
	if not state.InTown or not owner or not states[owner].Plot then
		return false, T(player, "Invalid request")
	end
	local likerTown, ownerTown = townOf(player), townOf(owner)
	if not likerTown or not ownerTown then
		return false, T(player, "Loading...")
	end
	-- il faut être venu près de la maison (sur la parcelle ou dedans)
	local _, _, root = characterParts(player)
	local plot = plotInfo(owner)
	if not root or not plot or (root.Position - plot.CFrame.Position).Magnitude > WorldLayout.PLOT_W * 0.75 then
		return false, T(player, "Walk to the house to like it")
	end
	local ok, reason = WorldLayout.CanLike(likerTown, player.UserId, owner.UserId)
	if not ok then
		if reason == "Self" then
			return false, T(player, "That's your own house!")
		elseif reason == "Already" then
			return false, T(player, "❤️ You already liked this house today")
		end
		return false, T(player, "❤️ No likes left today (max %s), come back tomorrow!", tostring(WorldLayout.LIKES_PER_DAY))
	end
	local rewarded = WorldLayout.ApplyLike(likerTown, ownerTown, owner.UserId)
	-- petites récompenses (secondes de production de chacun)
	local okStats, stats = pcall(function()
		return services.GameService:GetStats(player)
	end)
	local gift = okStats and WorldLayout.RewardAmount(stats and stats.PerSecond, WorldLayout.LIKE_REWARD_SECONDS) or 0
	if gift > 0 then
		pcall(function()
			services.GameService:AddDopamine(player, gift, false)
		end)
	end
	if rewarded then
		local okOwner, ownerStats = pcall(function()
			return services.GameService:GetStats(owner)
		end)
		local bonus = okOwner and WorldLayout.RewardAmount(ownerStats and ownerStats.PerSecond, WorldLayout.LIKED_REWARD_SECONDS) or 0
		if bonus > 0 then
			pcall(function()
				services.GameService:AddDopamine(owner, bonus, false)
			end)
		end
		local text = T(owner, "❤️ %s liked your house! (+%s Dopamine)", player.DisplayName, NumberFormatter.Format(bonus))
		if states[owner].InTown then
			toast(owner, text)
		else
			pcall(function()
				services.GameService:Notify(owner, { Type = "Info", Text = text })
			end)
		end
	end
	refreshSign(states[owner].Plot :: number)
	pushIfChanged(owner)
	fireTown("Liked", { Owner = owner.UserId, By = player.DisplayName, Likes = ownerTown.Likes })
	local left = WorldLayout.LIKES_PER_DAY - likerTown.LikesGiven
	return true, T(player, "❤️ Liked! +%s Dopamine · %s likes left today", NumberFormatter.Format(gift), tostring(left))
end

local function sit(player: Player, argument: any): (boolean, any)
	local state = stateOf(player)
	if not state.InTown or type(argument) ~= "table" or typeof(argument.CFrame) ~= "CFrame" then
		return false, T(player, "Invalid request")
	end
	local owner = playerById(argument.Owner)
	local slot = tonumber(argument.Slot)
	local current = town
	if not owner or not states[owner].Plot or not slot or not current then
		return false, T(player, "Invalid request")
	end
	if not canEnter(player, owner, false) then
		return false, T(player, "🔒 This house is closed to visitors")
	end
	local _, humanoid, root = characterParts(player)
	if not humanoid or not root or humanoid.Health <= 0 then
		return false, T(player, "Invalid request")
	end
	local cf = argument.CFrame :: CFrame
	local position = cf.Position
	if position.X ~= position.X or position.Y ~= position.Y or position.Z ~= position.Z then
		return false, T(player, "Invalid request")
	end
	-- le siège est bien dans cette pièce de cette maison, et à portée
	local size = sizeDefOf(dataOf(owner))
	local houseCF = current.Plots[states[owner].Plot :: number].HouseCFrame
	local x, y, d = WorldLayout.ToLocal(houseCF, position)
	local xMin, xMax, yFloor, dMin, dMax = WorldLayout.RoomInterior(size, math.floor(slot))
	if x < xMin - 0.5 or x > xMax + 0.5 or d < dMin - 0.5 or d > dMax + 0.5 or y < yFloor - 0.5 or y > yFloor + 7 then
		return false, T(player, "Invalid request")
	end
	if (root.Position - position).Magnitude > SIT_RANGE then
		return false, T(player, "Get closer to sit down")
	end
	destroySeat(state)
	-- orientation : seulement la rotation autour de la verticale
	local look = cf.LookVector
	local flat = Vector3.new(look.X, 0, look.Z)
	if flat.Magnitude < 0.01 then
		flat = Vector3.new(0, 0, -1)
	end
	local seat = Instance.new("Seat")
	seat.Name = "TownSeat_" .. player.UserId
	seat.Size = Vector3.new(2, 0.2, 2)
	seat.Transparency = 1
	seat.CanCollide = false
	seat.CanTouch = false -- personne ne s'assoit dessus par accident
	seat.Anchored = true
	seat.CFrame = CFrame.lookAt(position, position + flat.Unit)
	seat.Parent = current.Seats
	state.Seat = seat
	local okSit = pcall(seat.Sit, seat, humanoid)
	if not okSit then
		destroySeat(state)
		return false, T(player, "Invalid request")
	end
	seat:GetPropertyChangedSignal("Occupant"):Connect(function()
		if seat.Occupant == nil then
			task.delay(0.3, function()
				if state.Seat == seat and seat.Occupant == nil then
					destroySeat(state)
				elseif state.Seat ~= seat then
					pcall(seat.Destroy, seat)
				end
			end)
		end
	end)
	task.delay(SEAT_LIFETIME, function()
		if state.Seat == seat then
			destroySeat(state)
		end
	end)
	return true, nil
end

local ACTION_INTERVALS = { like = 1, sit = 0.4, visit = 1, room = 0.5, setOpen = 0.5, houses = 2, home = 1, leave = 1 }

local function onWorld(player: Player, action: any, argument: any): (boolean, any)
	if type(action) ~= "string" or #action > 16 then
		return false, T(player, "Invalid request")
	end
	local data = dataOf(player)
	if not data or not services.GameService:IsReady(player) or not states[player] then
		return false, T(player, "Loading...")
	end
	if action == "enter" then
		return enter(player, argument)
	end
	local interval = ACTION_INTERVALS[action]
	if not interval then
		return false, T(player, "Invalid request")
	end
	if not RateLimiter.Check(player, "World_" .. action, interval) then
		return false, T(player, "Slow down!")
	end
	if action == "leave" then
		return leave(player)
	elseif action == "home" then
		if not stateOf(player).InTown then
			return false, T(player, "Invalid request")
		end
		destroySeat(stateOf(player))
		teleport(player, spawnPoint(player))
		return true, nil
	elseif action == "visit" then
		return visit(player, argument)
	elseif action == "room" then
		return goRoom(player, argument)
	elseif action == "setOpen" then
		return setOpen(player, argument)
	elseif action == "like" then
		return like(player, argument)
	elseif action == "sit" then
		return sit(player, argument)
	elseif action == "houses" then
		return true, allSnapshots()
	end
	return false, T(player, "Invalid request")
end

----------------------------------------------------------------------
-- Ronde : intrus, chutes
----------------------------------------------------------------------

local function patrol()
	local current = town
	if not current then
		return
	end
	local originY = WorldLayout.Origin().Y
	for player, state in pairs(states) do
		if state.InTown and not state.Loading then
			local _, humanoid, root = characterParts(player)
			if root and humanoid and humanoid.Health > 0 then
				local position = root.Position
				if position.Y < originY - 40 then
					teleport(player, current.PlazaCFrame)
				else
					for index, owner in pairs(plotOwners) do
						if owner ~= player then
							local plot = current.Plots[index]
							local data = dataOf(owner)
							if plot and data then
								local size = sizeDefOf(data)
								local x, y, d = WorldLayout.ToLocal(plot.HouseCFrame, position)
								if WorldLayout.InsideHouse(size, x, y, d, -0.8) and not canEnter(player, owner, false) then
									destroySeat(state)
									teleport(player, WorldLayout.DoorSpawn(plot.HouseCFrame, size))
									toast(player, T(player, "🔒 This house is closed to visitors"))
								end
							end
						end
					end
				end
			end
		end
	end
end

----------------------------------------------------------------------
-- Cycle de vie
----------------------------------------------------------------------

function WorldService:Init(allServices)
	services = allServices
end

function WorldService:Start()
	local okBuild, result = pcall(TownMap.Build, WorldLayout.PlotCount(Players.MaxPlayers))
	if okBuild then
		town = result
	else
		warn("[WorldService] Construction de la ville : " .. tostring(result))
	end
	-- Bulles de chat au-dessus des avatars (réplique aux clients)
	pcall(function()
		local bubbles = TextChatService:FindFirstChildOfClass("BubbleChatConfiguration")
		if bubbles then
			bubbles.Enabled = true
		end
	end)

	Net.Function("World").OnServerInvoke = function(player: Player, action: any, argument: any)
		local ok, success, value = pcall(onWorld, player, action, argument)
		if not ok then
			warn("[WorldService] Erreur pour " .. player.Name .. " :", success)
			return false, T(player, "Invalid request")
		end
		return success, value
	end

	local snapshotClock, patrolClock = 0, 0
	RunService.Heartbeat:Connect(function(dt: number)
		snapshotClock += dt
		patrolClock += dt
		if patrolClock >= PATROL_INTERVAL then
			patrolClock = 0
			local ok, err = pcall(patrol)
			if not ok then
				warn("[WorldService] Ronde : " .. tostring(err))
			end
		end
		if snapshotClock >= SNAPSHOT_INTERVAL then
			snapshotClock = 0
			if #townPlayers() > 0 then
				for player in pairs(states) do
					pushIfChanged(player)
				end
			end
		end
	end)
end

function WorldService:PlayerReady(player: Player, data)
	data.Town = WorldLayout.SanitizeTown(data.Town, os.time())
	local state = stateOf(player)
	local current = town
	if current and not state.Plot then
		for index = 1, #current.Plots do
			if not plotOwners[index] then
				plotOwners[index] = player
				state.Plot = index
				break
			end
		end
	end
	if state.Plot then
		refreshSign(state.Plot)
	end
	pushIfChanged(player, true)
end

function WorldService:PlayerRemoving(player: Player)
	local state = states[player]
	if not state then
		return
	end
	state.InTown = false
	state.Generation += 1
	destroySeat(state)
	if state.Plot and plotOwners[state.Plot] == player then
		plotOwners[state.Plot] = nil
		refreshSign(state.Plot)
	end
	states[player] = nil
	fireTown("Gone", player.UserId)
end

-- (tests / autres services) le joueur est-il en ville ?
function WorldService:IsInTown(player: Player): boolean
	local state = states[player]
	return state ~= nil and state.InTown
end

return WorldService
