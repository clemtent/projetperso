--[[
	TownDisplays (ModuleScript)
	Emplacement : ReplicatedStorage > Client > World > TownDisplays

	🏛️ Dopamine Town (v9.9, SHOPS99) : les écrans et horloges de la ville,
	côté client (les pièces du serveur restent ; on les habille localement) :
	  - MAIRIE, GRAND ÉCRAN « 🏆 Meilleurs joueurs du serveur » : écran de
	    régie télé (BoardKit) qui alterne deux pages toutes les 12 s :
	      1. les joueurs du serveur, classés par Dopamine EN DIRECT (ta
	         ligne suit tes compteurs), le N°1 en vedette « ⭐ Meilleur
	         joueur du serveur » avec couronne et vraie photo ;
	      2. « ❤️ Maisons les plus aimées » (j'aime des parcelles) ;
	    la SurfaceGui du serveur est masquée LOCALEMENT (jamais modifiée
	    côté serveur) ; un liseré chromé et une plaque « DOPA TV » finissent
	    le cadre ;
	  - HORLOGE de la tour de la mairie : vrai cadran (chiffres romains,
	    minutes, aiguilles 3D, trotteuse) à l'heure réelle (ClockKit) ; les
	    deux aiguilles fixes du serveur sont masquées localement ;
	  - toute pièce de DopamineTown portant l'attribut "TownClock" (true ou
	    un style "Tower" | "Wall" | "Station") reçoit un vrai cadran sur sa
	    face avant (-Z), diamètre = min(largeur, hauteur) : c'est ainsi que
	    la place (CITY99) ou d'autres bâtiments ajoutent une horloge.
	Mise à jour : aiguilles à 30 i/s de près (≤ 120 studs), 4 i/s plus loin,
	rien au-delà de 400 ; écran animé à 30 i/s de près (≤ 160 studs).
	Aucune lumière, aucun son.

	API (TownClient, via optionalModule) :
	  TownDisplays.Start()   à l'entrée en ville
	  TownDisplays.Stop()    à la sortie (tout est détruit / restauré)
	  TownDisplays.Debug() -> table
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local Client = script.Parent.Parent
local ClientState = require(Client.ClientState)
local Locale = require(game:GetService("ReplicatedStorage").Shared.Locale)
local NumberFormatter = require(game:GetService("ReplicatedStorage").Shared.NumberFormatter)
local BoardKit = require(script.Parent.BoardKit)
local ClockKit = require(script.Parent.ClockKit)
local okHall, TownHallInterior = pcall(require, script.Parent.TownHallInterior) -- (v11, CITY11) intérieur de la mairie

local TownDisplays = {}

local FOLDER_NAME = "TownDisplaysClient"
local PAGE_TIME = 12
local CLOCK_NEAR, CLOCK_FAR = 120, 400
local BOARD_NEAR, BOARD_FAR = 160, 420

type Hidden = { Instance: Instance, Property: string, Value: any }

local started = false
local folder: Folder? = nil
local conns: { RBXScriptConnection } = {}
local clocks: { any } = {}
local board: any = nil
local boardPos: Vector3? = nil
local hidden: { Hidden } = {}
local hallDone = false
local seen: { [Instance]: boolean } = {}
local clockTimer, boardTimer, dataTimer, discoverTimer = 0, 0, 0, 0
local stats: any = { Clocks = 0, Board = false, Page = "", Refreshes = 0 }

local function hide(instance: Instance, property: string, value: any)
	local ok, old = pcall(function()
		return (instance :: any)[property]
	end)
	if ok then
		table.insert(hidden, { Instance = instance, Property = property, Value = old })
		pcall(function()
			(instance :: any)[property] = value
		end)
	end
end

----------------------------------------------------------------------
-- Données de l'écran de la mairie
----------------------------------------------------------------------

local function num(value: any, default: number): number
	local n = tonumber(value)
	if n == nil or n ~= n or n == math.huge or n == -math.huge then
		return default
	end
	return n
end

local function formatValue(value: number): string
	if value < 1e6 then
		return NumberFormatter.WithSpaces(math.floor(value))
	end
	return NumberFormatter.Format(value)
end

local function ordinal(rank: number): string
	if Locale.IsFrench() then
		return rank == 1 and "1er" or (tostring(rank) .. "e")
	end
	local lastTwo = rank % 100
	local suffix = "th"
	if lastTwo < 11 or lastTwo > 13 then
		local last = rank % 10
		suffix = last == 1 and "st" or (last == 2 and "nd" or (last == 3 and "rd" or "th"))
	end
	return tostring(rank) .. suffix
end

-- Page 1 : joueurs du serveur par Dopamine (ta ligne en direct)
local function playerRows(): { BoardKit.Row }
	local me = Players.LocalPlayer
	local rows: { BoardKit.Row } = {}
	local data = ClientState.Data
	local myDopamine = type(data) == "table" and num(data.Dopamine, 0) or 0
	local found = false
	for _, raw in ipairs(type(ClientState.ServerLeaderboard) == "table" and ClientState.ServerLeaderboard or {}) do
		if type(raw) == "table" then
			local userId = math.floor(num(raw.UserId, 0))
			local value = num(raw.Dopamine, num(raw.Value, 0))
			if userId == me.UserId and type(data) == "table" then
				found = true
				value = myDopamine
			end
			table.insert(rows, { UserId = userId, Name = tostring(raw.Name or "?"), Value = value, ValueText = "", Rank = 0, Mine = userId == me.UserId })
		end
	end
	if not found and type(data) == "table" then
		table.insert(rows, { UserId = me.UserId, Name = me.DisplayName, Value = myDopamine, ValueText = "", Rank = 0, Mine = true })
	end
	table.sort(rows, function(a, b)
		if a.Value ~= b.Value then
			return a.Value > b.Value
		end
		return a.UserId < b.UserId
	end)
	for i, r in ipairs(rows) do
		r.Rank = i
		r.ValueText = formatValue(r.Value) .. " 💧"
	end
	return rows
end

-- Page 2 : maisons les plus aimées (attributs des parcelles)
local function houseRows(): { BoardKit.Row }
	local rows: { BoardKit.Row } = {}
	local town = workspace:FindFirstChild("DopamineTown")
	local plots = town and town:FindFirstChild("Plots")
	local me = Players.LocalPlayer.UserId
	if plots then
		for _, plot in ipairs(plots:GetChildren()) do
			local ownerId = plot:GetAttribute("OwnerId")
			local name = plot:GetAttribute("OwnerName")
			if type(ownerId) == "number" and ownerId ~= 0 and type(name) == "string" and name ~= "" then
				local likes = plot:GetAttribute("Likes")
				table.insert(rows, { UserId = ownerId, Name = name, Value = type(likes) == "number" and likes or 0, ValueText = "", Rank = 0, Mine = ownerId == me })
			end
		end
	end
	table.sort(rows, function(a, b)
		if a.Value ~= b.Value then
			return a.Value > b.Value
		end
		return a.Name < b.Name
	end)
	for i, r in ipairs(rows) do
		r.Rank = i
		r.ValueText = "❤️ " .. formatValue(r.Value)
	end
	return rows
end

local function refreshBoard(now: number)
	local b = board
	if not b then
		return
	end
	local page = math.floor(now / PAGE_TIME) % 2
	local rows = page == 0 and playerRows() or houseRows()
	if page == 1 and #rows == 0 then
		page = 0
		rows = playerRows()
	end
	stats.Page = page == 0 and "Players" or "Houses"
	stats.Refreshes += 1
	local mine: BoardKit.Row? = nil
	for _, r in ipairs(rows) do
		if r.Mine then
			mine = r
		end
	end
	local footer
	if mine then
		footer = Locale.T("You: %s · %s", ordinal(mine.Rank), mine.ValueText)
	elseif page == 1 then
		footer = Locale.T("❤️ Like houses to climb the board!")
	else
		footer = Locale.T("You: not in the top yet · %s", "—")
	end
	BoardKit.SetData(b, {
		Rows = rows,
		Title = page == 0 and Locale.T("🏆 Top players of the server") or Locale.T("❤️ Most-loved houses"),
		Scope = "🏠 " .. Locale.T("This server"),
		HeroCaption = page == 0 and Locale.T("⭐ Best player on the server") or Locale.T("🏡 Most-loved house"),
		Footer = footer,
	})
end

----------------------------------------------------------------------
-- Mairie : écran + horloge
----------------------------------------------------------------------

local function dressHall(hall: Instance, parent: Instance)
	-- GRAND ÉCRAN
	local screen = hall:FindFirstChild("Screen")
	if screen and screen:IsA("BasePart") then
		for _, gui in ipairs(screen:GetChildren()) do
			if gui:IsA("SurfaceGui") then
				hide(gui, "Enabled", false)
			end
		end
		board = BoardKit.Build(screen, {
			Face = Enum.NormalId.Front,
			PPS = 26,
			MaxDistance = 420,
			Title = "🏆 Top players of the server",
			Theme = "Hall",
			Rows = 6,
			HeroCaption = "⭐ Best player on the server",
			Ticker = {
				"🏆 Best players of this server, live",
				"❤️ Like houses in town to climb the board",
				"♻️ Rebirth to multiply your Dopamine",
				"🛒 MegaDopa: everything for your home",
			},
		})
		boardPos = screen.Position
		-- liseré chromé autour de l'écran + plaque « DOPA TV » (devant le cadre du serveur)
		BoardKit.Frame(parent, screen, { Lip = 0.22, PlateH = 0.35 })
		refreshBoard(os.clock())
	end
	-- HORLOGE de la tour
	local dial = hall:FindFirstChild("Clock")
	if dial and dial:IsA("BasePart") then
		local tower = hall:FindFirstChild("Tower")
		local axis = dial.CFrame.RightVector
		local away = tower and tower:IsA("BasePart") and (dial.Position - tower.Position) or axis
		if axis:Dot(away) < 0 then
			axis = -axis
		end
		local center = dial.Position + axis * (dial.Size.X / 2)
		local diameter = math.min(dial.Size.Y, dial.Size.Z)
		for _, name in ipairs({ "HandHour", "HandMinute" }) do
			local handPart = hall:FindFirstChild(name)
			if handPart and handPart:IsA("BasePart") then
				hide(handPart, "Transparency", 1)
			end
		end
		local frame = CFrame.lookAt(center, center + axis)
		local clock = ClockKit.Build(parent, frame, diameter, { Style = "Tower", Numerals = "Roman", Brand = "Dopamine Town", Name = "HallClock", MaxDistance = 500 })
		table.insert(clocks, clock)
	end
end

----------------------------------------------------------------------
-- Horloges marquées "TownClock"
----------------------------------------------------------------------

local function dressTagged(p: Instance, parent: Instance)
	if seen[p] or not p:IsA("BasePart") then
		return
	end
	local tag = p:GetAttribute("TownClock")
	if tag == nil or tag == false then
		return
	end
	seen[p] = true
	local style = type(tag) == "string" and tag or "Tower"
	local diameter = math.min(p.Size.X, p.Size.Y)
	local frame = p.CFrame * CFrame.new(0, 0, -p.Size.Z / 2)
	local ok, clock = pcall(ClockKit.Build, parent, frame, diameter, { Style = style, Numerals = p:GetAttribute("Numerals") == "Arabic" and "Arabic" or "Roman", Name = "TaggedClock", MaxDistance = 400 })
	if ok then
		table.insert(clocks, clock)
	end
end

local function discover()
	local town = workspace:FindFirstChild("DopamineTown")
	local f = folder
	if not town or not f then
		return
	end
	if not hallDone then
		local hall = town:FindFirstChild("TownHall", true)
		if hall then
			hallDone = true
			local ok, err = pcall(dressHall, hall, f)
			if not ok then
				warn("[TownDisplays] mairie : " .. tostring(err))
			end
			-- (v11, CITY11) intérieur complet de la mairie (en flux, voir TownHallInterior)
			if okHall and type(TownHallInterior) == "table" and hall:IsA("Model") then
				pcall(TownHallInterior.Attach, hall, f, { Players = playerRows, Houses = houseRows })
			end
		end
	end
	for _, d in ipairs(town:GetDescendants()) do
		if d:IsA("BasePart") and d:GetAttribute("TownClock") ~= nil then
			dressTagged(d, f)
		end
	end
end

----------------------------------------------------------------------
-- Boucle
----------------------------------------------------------------------

local function viewPosition(): Vector3?
	local camera = workspace.CurrentCamera
	if camera then
		return camera.CFrame.Position
	end
	local character = Players.LocalPlayer.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	return root and (root :: BasePart).Position or nil
end

local function heartbeat(dt: number)
	if not started then
		return
	end
	local position = viewPosition()
	if not position then
		return
	end
	local now = os.clock()
	discoverTimer += dt
	if discoverTimer >= 5 and not hallDone then
		discoverTimer = 0
		discover()
	end
	-- (v11, CITY11) intérieur de la mairie
	if okHall and type(TownHallInterior) == "table" then
		local okStep, errStep = pcall(TownHallInterior.Step, position, dt)
		if not okStep and not stats.HallWarned then
			stats.HallWarned = true
			warn("[TownDisplays] intérieur de la mairie : " .. tostring(errStep))
		end
	end
	-- aiguilles
	clockTimer += dt
	local nearest = math.huge
	for _, c in ipairs(clocks) do
		nearest = math.min(nearest, (c.Pos - position).Magnitude)
	end
	local every = nearest <= CLOCK_NEAR and 1 / 30 or 0.25
	if clockTimer >= every and nearest <= CLOCK_FAR then
		clockTimer = 0
		for _, c in ipairs(clocks) do
			local d = (c.Pos - position).Magnitude
			if d <= CLOCK_FAR then
				ClockKit.Update(c)
			end
		end
	end
	-- écran de la mairie
	local b = board
	local bp = boardPos
	if b and bp then
		local d = (bp - position).Magnitude
		if d <= BOARD_FAR then
			boardTimer += dt
			dataTimer += dt
			if dataTimer >= 1.5 then
				dataTimer = 0
				pcall(refreshBoard, now)
			end
			local stepEvery = d <= BOARD_NEAR and 1 / 30 or 0.5
			if boardTimer >= stepEvery then
				boardTimer = 0
				BoardKit.SetProgress(b, (now % PAGE_TIME) / PAGE_TIME)
				BoardKit.Step(b, now)
			end
		end
	end
end

function TownDisplays.Start()
	if started then
		return
	end
	started = true
	local f = Instance.new("Folder")
	f.Name = FOLDER_NAME
	f.Parent = workspace
	folder = f
	discover()
	table.insert(conns, RunService.Heartbeat:Connect(function(dt)
		local ok, err = pcall(heartbeat, dt)
		if not ok then
			warn("[TownDisplays] " .. tostring(err))
		end
	end))
	table.insert(conns, ClientState.LeaderboardChanged:Connect(function()
		dataTimer = 99
	end))
	local town = workspace:FindFirstChild("DopamineTown")
	if town then
		table.insert(conns, town.DescendantAdded:Connect(function(d)
			if d:IsA("BasePart") and d:GetAttribute("TownClock") ~= nil and folder then
				task.defer(dressTagged, d, folder)
			end
		end))
	end
	stats.Clocks = #clocks
	stats.Board = board ~= nil
end

function TownDisplays.Stop()
	if not started then
		return
	end
	started = false
	for _, c in ipairs(conns) do
		c:Disconnect()
	end
	conns = {}
	if okHall and type(TownHallInterior) == "table" then
		pcall(TownHallInterior.Detach)
	end
	if board then
		pcall(BoardKit.Destroy, board)
	end
	board = nil
	boardPos = nil
	for i = #hidden, 1, -1 do
		local h = hidden[i]
		pcall(function()
			(h.Instance :: any)[h.Property] = h.Value
		end)
	end
	hidden = {}
	clocks = {}
	seen = {}
	hallDone = false
	if folder then
		folder:Destroy()
	end
	folder = nil
end

function TownDisplays.Debug(): any
	stats.Clocks = #clocks
	stats.Board = board ~= nil
	return {
		Stats = stats,
		Board = board,
		Clocks = clocks,
		Folder = folder,
		Refresh = function(now: number?)
			refreshBoard(now or os.clock())
		end,
		Step = function(dt: number)
			heartbeat(dt)
		end,
	}
end

return TownDisplays
