--[[
	RaceClient (ModuleScript)
	Emplacement : ReplicatedStorage > Client > World > RaceClient

	🏁 Courses de rue, côté client (v10 RACE10, v11 RACE11). Le serveur
	(RaceService) décide de tout ; ici on MONTRE :
	  - le QG des courses (zone "RaceMeet") en flux : stands + tour de
	    contrôle, comptoir avec invite E "Courses de rue" (ouvre le menu),
	    GRAND ÉCRAN des records (avatars) + pilotes par rang, tribune,
	    voiture d'exposition sur un PLATEAU TOURNANT, podium et coupe ;
	  - les portiques de départ (feux + écrans LED synchronisés sur l'heure
	    du serveur : 5 rouges puis VERT au GO, 3-2-1 géant), cases de grille,
	    murets, commissaire qui agite le drapeau ; arche d'arrivée du sprint ;
	  - les PILOTES IA : voiture CarModels ("Mid" + PILOTE NPCModels.Driver de
	    NPC11 de près — mains sur le volant qui tourne —, "Low" plus loin, rien
	    au-delà de 700 studs), roues qui tournent et braquent, caisse qui
	    s'incline, position lissée entre deux instantanés (5 fois / s) ;
	    boîte de collision SOLIDE (groupe "DopamineCars", "DopamineMover") ;
	    FLAMMES de nitro (IA et humains) ;
	  - SA course : CAMÉRA DE PRÉSENTATION pendant la mise en grille (vue du
	    portique -> travelling le long de la grille -> derrière ta voiture au
	    GO), arches des 3 prochaines portes (la prochaine brille ; franchie :
	    elle s'affaisse), PANNEAUX À CHEVRONS dans les virages qui arrivent,
	    FANTÔME de ton meilleur tour (voiture translucide), NITRO (Maj / N /
	    bouton : le serveur valide, l'attribut local "RaceBoost" de ta voiture
	    est lu par CarClient), HUD (tour des temps, écart avec le fantôme à
	    chaque porte, dernier / meilleur tour, dérapages, places gagnées,
	    dernier tour, mauvais sens, mini-carte), touche F / bouton 🔄 = retour
	    à la dernière porte, 🏳️ abandon ; course de NUIT : la ville passe en nuit ;
	  - SPECTATEUR : "👁️ Regarder" une course en cours (caméra de poursuite,
	    ◀ ▶ pour changer de pilote, tour des temps) ;
	  - RÉSULTATS : podium, classement, médaille, XP / rang (RaceHud) ;
	  - MENU / STATS / CLASSEMENT (RaceMenu).
	Aucune lumière réelle, aucun son.

	Crochets TownClient (via optionalModule, comme FairFx / MusicStage) :
	  RaceClient.Start({ Toast = toast })  à l'entrée en ville
	  RaceClient.Step(dt)                   chaque image
	  RaceClient.Stop()                     à la sortie
	  RaceClient.Debug() -> table (tests)
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local CollectionService = game:GetService("CollectionService")

local Client = script.Parent.Parent
local ClientState = require(Client.ClientState)
local Config = require(ReplicatedStorage.Shared.Config)
local Net = require(ReplicatedStorage.Shared.Net)
local Locale = require(ReplicatedStorage.Shared.Locale)
local NumberFormatter = require(ReplicatedStorage.Shared.NumberFormatter)
local WorldLayout = require(ReplicatedStorage.Shared.WorldLayout)
local CarModels = require(ReplicatedStorage.Shared.CarModels)
local NPCModels = require(ReplicatedStorage.Shared.NPCModels)
local RaceRules = require(ReplicatedStorage.Shared.RaceRules)
local RaceRoutes = require(ReplicatedStorage.Shared.RaceRoutes)
local RaceProps = require(script.Parent.RaceProps)
local RaceHud = require(script.Parent.RaceHud)
local RaceMenu = require(script.Parent.RaceMenu)

local LocalPlayer = Players.LocalPlayer

local RaceClient = {}

RaceClient.FOLDER_NAME = "RaceClient"
RaceClient.HQ_IN, RaceClient.HQ_OUT = 450, 520
RaceClient.GANTRY_IN, RaceClient.GANTRY_OUT = 420, 500
RaceClient.AI_MID, RaceClient.AI_FAR = 140, 700
RaceClient.FX_RANGE = 220 -- flammes de nitro / drapeau du commissaire
RaceClient.CHEVRON_AHEAD = 420
RaceClient.MOVER_TAG = "DopamineMover"
RaceClient.CAR_GROUP = "DopamineCars"
RaceClient.CARS_FOLDER = "DopamineCars" -- (CarService) voitures des joueurs "Car_<UserId>"

local rgb = Color3.fromRGB
local GOLD = rgb(255, 214, 90)
local MINT = rgb(130, 236, 190)
local CYAN = rgb(90, 220, 240)
local SOFT = rgb(214, 196, 236)
local RED = rgb(255, 120, 130)

type AICar = {
	Key: string,
	Kind: string,
	Model: Model?,
	Lod: number, -- 2 = Mid (+ pilote), 1 = Low, 0 = rien
	Rig: any?,
	Driver: Model?,
	SeatCF: CFrame,
	Extra: { BasePart },
	ExtraOff: { CFrame },
	D: number,
	V: number,
	Lane: number,
	Spin: number,
	Steer: number,
	Wheel: number,
	Heading: Vector3?,
	Pitch: number,
	Roll: number,
	Seen: number,
	Name: string,
	Color: string,
	Seed: number,
	Pivot: CFrame?,
}

type RaceView = {
	Snap: any,
	At: number, -- heure (client) de réception
	ServerAt: number,
	Route: any,
	Ai: { [string]: AICar },
}

local started = false
local folder: Folder? = nil
local opts: { [string]: any } = {}
local conns: { RBXScriptConnection } = {}
local count = 4
local lobbies: { [string]: any } = {}
local board: { [string]: any } = {}
local pilots: { any } = {}
local me: { [string]: any } = { Rewarded = 0, Daily = 8, Best = {}, Xp = 0, History = {}, Routes = {}, Ghost = {} }
local views: { [string]: RaceView } = {}
local hq: { [string]: any } = {}
local gantries: { [string]: any } = {}
local joined: { Route: string?, RaceId: number? } = {}
local mine: { [string]: any } = {} -- ma course (HUD local)
local gates: { [number]: Model } = {}
local chevrons: { [number]: Model } = {}
local ghost: { [string]: any } = {}
local flames: { [string]: { BasePart } } = {}
local camState: { [string]: any }? = nil
local spectate: { [string]: any }? = nil
local streamClock = 0
local hudClock = 0
local menuClock = 0
local lastCountdown: string? = nil
local nightForced = false
local boardDirty = true
local previews: { [string]: { { number } } } = {}
local resultsShownFor: number? = nil
local clockT = 0

----------------------------------------------------------------------
-- Outils
----------------------------------------------------------------------

local function T(text: string, ...): string
	return Locale.T(text, ...)
end

local function now(): number
	local ok, t = pcall(function()
		return workspace:GetServerTimeNow()
	end)
	if ok and type(t) == "number" then
		return t
	end
	return os.clock()
end

local function toast(text: string?)
	if text and text ~= "" and type(opts.Toast) == "function" then
		pcall(opts.Toast, text)
	end
end

local function send(kind: string, arg: any?)
	pcall(function()
		Net.Event("RaceEvent"):FireServer(kind, arg)
	end)
end

local function routeOf(id: string): any?
	return RaceRoutes.Get(id, count)
end

local fmt = RaceRules.FormatTime

local function rootPart(): BasePart?
	local character = LocalPlayer.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if root and root:IsA("BasePart") then
		return root
	end
	return nil
end

-- Ma voiture (si je conduis) : racine de la voiture
local function myCarRoot(): BasePart?
	local character = LocalPlayer.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local seat = humanoid and humanoid.SeatPart
	if seat and seat:IsA("VehicleSeat") then
		local model = seat:FindFirstAncestorOfClass("Model")
		local root = model and (model.PrimaryPart or model:FindFirstChild("Root"))
		if root and root:IsA("BasePart") then
			return root
		end
	end
	return nil
end

local function myCarModel(): Model?
	local root = myCarRoot()
	return root and root:FindFirstAncestorOfClass("Model") or nil
end

local function isDriving(): boolean
	return myCarRoot() ~= nil
end

local function focus(): Vector3?
	local camera = workspace.CurrentCamera
	if spectate and camera then
		return camera.CFrame.Position
	end
	local car = myCarRoot()
	if car then
		return car.Position
	end
	local root = rootPart()
	if root then
		return root.Position
	end
	return camera and camera.CFrame.Position or nil
end

local function lineS(route: any, d: number): number
	if route.Closed then
		return d % route.Total
	end
	return route.StartS + d
end

local function routeColor(def: any): Color3
	local c = def and def.Color
	if type(c) == "table" then
		return rgb(c[1] or 255, c[2] or 255, c[3] or 255)
	end
	return GOLD
end

local function rankLabel(r: any): string
	local roman = { "I", "II", "III" }
	local base = T(r.Name or "")
	if (r.Division or 0) > 0 then
		return base .. " " .. roman[r.Division]
	end
	if (r.Stars or 0) > 0 then
		return base .. " " .. string.rep("★", math.min(5, r.Stars))
	end
	return base
end

-- Voiture d'un humain (CarService : Workspace.DopamineCars.Car_<UserId>)
local function humanCar(userId: number): Model?
	local f = workspace:FindFirstChild(RaceClient.CARS_FOLDER)
	local m = f and f:FindFirstChild("Car_" .. tostring(userId))
	if m and m:IsA("Model") then
		return m
	end
	return nil
end

----------------------------------------------------------------------
-- Menu (RaceMenu) : données
----------------------------------------------------------------------

local function statusOf(id: string): (string, Color3, boolean, boolean)
	local lobby = lobbies[id]
	if not lobby then
		return T("Open: start a race!"), MINT, true, false
	end
	if lobby.Phase == "Lobby" then
		local left = math.max(0, math.ceil((lobby.EndsAt or 0) - now()))
		return T("%d waiting · starts in %d s", lobby.Count or 0, left), GOLD, true, false
	elseif lobby.Phase == "Results" then
		return T("Finishing…"), SOFT, false, false
	end
	return T("Race in progress…"), RED, false, true
end

local function preview(route: any): { { number } }
	local key = route.Id
	if previews[key] then
		return previews[key]
	end
	local line = route.Line
	local minX, maxX, minZ, maxZ = math.huge, -math.huge, math.huge, -math.huge
	for i = 1, line.N do
		minX, maxX = math.min(minX, line.X[i]), math.max(maxX, line.X[i])
		minZ, maxZ = math.min(minZ, line.Z[i]), math.max(maxZ, line.Z[i])
	end
	local span = math.max(maxX - minX, maxZ - minZ, 1)
	local cx, cz = (minX + maxX) / 2, (minZ + maxZ) / 2
	local pts = {}
	local n = math.clamp(math.floor(line.N / 8), 12, 90)
	local s0 = route.StartS or 0
	local s1 = if route.Closed then s0 + line.Total else line.Total
	for k = 0, n - 1 do
		local x, z = RaceRules.PointAt(line, s0 + (s1 - s0) * k / n)
		table.insert(pts, { 0.5 + (x - cx) / span, 0.5 + (z - cz) / span })
	end
	if not route.Closed then
		local x, z = RaceRules.PointAt(line, line.Total)
		table.insert(pts, { 0.5 + (x - cx) / span, 0.5 + (z - cz) / span })
	end
	previews[key] = pts
	route.MiniBox = { cx, cz, span }
	return pts
end

local function nearHQ(): boolean
	local p = rootPart()
	if not p then
		return false
	end
	local meet = RaceRoutes.MeetCFrame(count).Position
	local flat = Vector3.new(p.Position.X - meet.X, 0, p.Position.Z - meet.Z)
	return flat.Magnitude <= ((Config.Race and Config.Race.JoinRange) or 45) - 2
end

local MEDAL_ICONS = { "🥇", "🥈", "🥉" }

local function statsKey(): string
	return string.format("%d|%d|%d|%d|%d", me.Xp or 0, me.Races or 0, #(me.History or {}), me.Wins or 0, count)
end

local function boardKey(): string
	local parts = { tostring(#pilots) }
	for _, p in ipairs(pilots) do
		table.insert(parts, tostring(p.UserId) .. ":" .. tostring(p.Xp))
	end
	for id, rows in pairs(board) do
		table.insert(parts, id .. ":" .. tostring(rows[1] and rows[1].Time or 0) .. ":" .. tostring(#rows))
	end
	table.sort(parts)
	return table.concat(parts, ",")
end

local function menuData(): any
	local can = nearHQ() or isDriving()
	local cards = {}
	local routeStats = {}
	local records = {}
	for _, def in ipairs((Config.Race and Config.Race.Routes) or {}) do
		local route = routeOf(def.Id)
		if route then
			local status, color, isOpen, running = statusOf(def.Id)
			local km = route.RaceDistance * 0.28 / 1000
			local rows = board[def.Id] or {}
			local stat = me.Routes and me.Routes[def.Id] or nil
			local myLap = me.Best and me.Best[def.Id]
			local myMedal = stat and stat.M or 0
			local lapsText = if route.Closed and route.Laps > 1 then T("%d laps", route.Laps) elseif route.Closed then T("1 lap") else T("Sprint")
			local isMine = joined.Route == def.Id
			local mineText = ""
			if stat and stat.T then
				mineText = T("⏱️ Your best: %s", fmt(stat.T)) .. (if myMedal > 0 then " " .. MEDAL_ICONS[myMedal] else "")
				if myLap and route.Laps > 1 then
					mineText ..= "  ·  " .. T("Best lap: %s", fmt(myLap))
				end
			else
				mineText = T("Beat the medal times to earn XP!")
			end
			local top = {}
			for k = 1, math.min(5, #rows) do
				table.insert(top, { Name = rows[k].Name, UserId = rows[k].UserId, Time = rows[k].Time })
			end
			table.insert(cards, {
				Id = def.Id,
				Icon = def.Icon,
				Name = T(def.Name),
				Desc = T(def.Desc or ""),
				Color = routeColor(def),
				Short = string.format("%s · %.1f km", lapsText, km),
				Chips = string.format("<b>%s</b> · %.1f km · %s · %s", lapsText, km, T("%d corners", #(route.Corners or {})), T("%d gates", #route.Checkpoints)),
				Status = if isMine then T("✅ You are signed up!") else status,
				StatusColor = if isMine then MINT else color,
				CanJoin = isOpen and (can or isMine),
				Joined = isMine,
				CanWatch = running and not isMine,
				Preview = preview(route),
				PreviewKey = route.Id .. ":" .. count,
				Closed = route.Closed,
				Medals = route.Medals,
				MyMedal = myMedal,
				MyMedalIcon = if myMedal > 0 then MEDAL_ICONS[myMedal] else "",
				Mine = mineText,
				Record = top[1],
				Top = top,
				FormatTime = fmt,
			})
			table.insert(routeStats, {
				Icon = def.Icon,
				Name = T(def.Name),
				Races = stat and stat.R or 0,
				Wins = stat and stat.W or 0,
				Best = if stat and stat.T then fmt(stat.T) else "-",
				Extra = (if myMedal > 0 then MEDAL_ICONS[myMedal] else "") .. (if stat and stat.C then " 🚗" else ""),
			})
			local rtop = {}
			for k = 1, math.min(3, #rows) do
				table.insert(rtop, { Name = rows[k].Name, UserId = rows[k].UserId, Text = fmt(rows[k].Time) })
			end
			table.insert(records, { Icon = def.Icon, Name = T(def.Name), Color = routeColor(def), Top = rtop })
		end
	end
	-- rang
	local r = RaceRules.Rank(me.Xp or 0)
	local ranks = (Config.Race and Config.Race.Ranks) or {}
	local nextTier = ranks[r.Index + 1]
	local rank = {
		Icon = r.Icon,
		LabelText = rankLabel(r),
		Color = r.Color,
		Progress = r.Progress,
		XpText = string.format("%s XP", NumberFormatter.Format(math.floor(me.Xp or 0))),
		NextText = if nextTier then T("Next: %s at %s XP", T(nextTier.Name), NumberFormatter.Format(nextTier.Min)) .. string.format(" · %d / %d", math.floor(me.Xp or 0), r.Next or 0)
			else T("Top rank! A star every 2000 XP"),
	}
	local races = me.Races or 0
	local wins = me.Wins or 0
	local records_ = 0
	for _ in pairs(me.Best or {}) do
		records_ += 1
	end
	local tiles = {
		{ tostring(races), T("Races") },
		{ tostring(wins), T("Wins") },
		{ tostring(me.Podiums or 0), T("Podiums") },
		{ if races > 0 then string.format("%d %%", math.floor(wins / races * 100 + 0.5)) else "-", T("Win rate") },
		{ tostring(me.Overtakes or 0), T("Overtakes") },
		{ NumberFormatter.Format(me.DriftBest or 0), T("Best drift") },
		{ string.format("%.1f km", (me.Distance or 0) * 0.28 / 1000), T("Distance") },
		{ tostring(records_), T("Routes with a time") },
	}
	local hist = {}
	for _, e in ipairs(me.History or {}) do
		table.insert(hist, { P = e.P, Icon = if (e.M or 0) > 0 then MEDAL_ICONS[e.M] else nil })
	end
	local pilotRows = {}
	for _, p in ipairs(pilots) do
		local pr = RaceRules.Rank(p.Xp or 0)
		table.insert(pilotRows, {
			Name = p.Name,
			UserId = p.UserId,
			Me = p.UserId == LocalPlayer.UserId,
			RankText = (pr.Icon or "") .. " " .. rankLabel(pr),
			RankColor = pr.Color,
			Right = string.format("%s XP<br/>%s", NumberFormatter.Format(math.floor(p.Xp or 0)), T("%d wins", p.Wins or 0)),
		})
	end
	local secs = (Config.Race and Config.Race.Rewards and Config.Race.Rewards.Seconds) or { 120, 80, 55 }
	return {
		Sub = T("Win Dopamine: 🥇 %d s · 🥈 %d s · 🥉 %d s of production · rewarded today: %d/%d", secs[1], secs[2], secs[3], me.Rewarded or 0, me.Daily or 8),
		Foot = if can then T("AI racers fill the grid. Gates in order · F = last gate · Shift/N = nitro (charge it by drifting and drafting).")
			else T("Sign up at the 🏁 Race HQ (on foot, E) or from your car."),
		Routes = cards,
		Rank = rank,
		Tiles = tiles,
		History = hist,
		RouteStats = routeStats,
		Pilots = pilotRows,
		Records = records,
		StatsKey = statsKey(),
		BoardKey = boardKey(),
	}
end

local function refreshMenu()
	if not RaceMenu.IsOpen() then
		return
	end
	RaceMenu.Update(menuData())
end

local function openMenu(open: boolean)
	if open then
		RaceMenu.SetOpen(true)
		refreshMenu()
		send("sync")
	else
		RaceMenu.SetOpen(false)
	end
end

----------------------------------------------------------------------
-- QG : grand écran (records + pilotes), voiture d'exposition
----------------------------------------------------------------------

local function fillBoard()
	local parts = hq.Parts
	if not parts or not parts.BoardGui then
		return
	end
	local sg: SurfaceGui = parts.BoardGui
	for _, child in ipairs(sg:GetChildren()) do
		child:Destroy()
	end
	local text, frame = RaceProps.Text, RaceProps.Frame
	local bg = frame(sg, { Name = "Bg", BackgroundColor3 = rgb(16, 16, 30), Size = UDim2.fromScale(1, 1) })
	local band = frame(bg, { Name = "Band", BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 10) })
	RaceProps.Checker(band, 60, 2, rgb(34, 30, 40), rgb(246, 244, 240), 2)
	text(bg, { Name = "T", Text = T("🏆 Best laps on this server"), TextColor3 = GOLD, Size = UDim2.new(0.58, 0, 0.09, 0), Position = UDim2.new(0.02, 0, 0, 16) })
	local list = (Config.Race and Config.Race.Routes) or {}
	for k, def in ipairs(list) do
		local col = (k - 1) % 2
		local row = (k - 1) // 2
		local card = frame(bg, { Name = "Route_" .. def.Id, BackgroundColor3 = rgb(36, 32, 58), Size = UDim2.new(0.29, 0, 0.19, 0),
			Position = UDim2.new(0.015 + col * 0.3, 0, 0.13 + row * 0.215, 0) })
		RaceProps.Corner(card, 10)
		frame(card, { Name = "Stripe", BackgroundColor3 = routeColor(def), Size = UDim2.new(0, 6, 1, -12), Position = UDim2.fromOffset(6, 6) })
		text(card, { Name = "N", Text = def.Icon .. " " .. T(def.Name), Font = Enum.Font.GothamBold, TextColor3 = Color3.new(1, 1, 1), Size = UDim2.new(0.9, -14, 0.36, 0),
			Position = UDim2.new(0, 18, 0.06, 0), TextXAlignment = Enum.TextXAlignment.Left })
		local r = (board[def.Id] or {})[1]
		if r then
			local av = Instance.new("ImageLabel")
			av.Name = "Av"
			av.BackgroundColor3 = Color3.new(1, 1, 1)
			av.Size = UDim2.new(0, 40, 0, 40)
			av.Position = UDim2.new(0, 18, 0.48, 0)
			av.Image = string.format("rbxthumb://type=AvatarHeadShot&id=%d&w=150&h=150", math.floor(tonumber(r.UserId) or 1))
			av.Parent = card
			RaceProps.Corner(av, 20)
			text(card, { Name = "W", Text = "🥇 " .. tostring(r.Name), Font = Enum.Font.GothamBold, TextColor3 = rgb(236, 226, 255), Size = UDim2.new(0.62, -40, 0.3, 0),
				Position = UDim2.new(0, 64, 0.44, 0), TextXAlignment = Enum.TextXAlignment.Left })
			text(card, { Name = "Time", Text = fmt(r.Time), TextColor3 = MINT, Size = UDim2.new(0.38, -8, 0.3, 0), Position = UDim2.new(0.62, 0, 0.44, 0),
				TextXAlignment = Enum.TextXAlignment.Right })
		else
			text(card, { Name = "E", Text = T("No record yet: be the first!"), Font = Enum.Font.Gotham, TextColor3 = rgb(190, 176, 214), Size = UDim2.new(0.86, -10, 0.3, 0),
				Position = UDim2.new(0, 18, 0.5, 0), TextXAlignment = Enum.TextXAlignment.Left })
		end
	end
	-- pilotes (à droite)
	local side = frame(bg, { Name = "Pilots", BackgroundColor3 = rgb(30, 26, 50), Size = UDim2.new(0.38, 0, 0.84, 0), Position = UDim2.new(0.61, 0, 0.13, 0) })
	RaceProps.Corner(side, 12)
	text(bg, { Name = "PT", Text = T("🏎️ Drivers on this server"), TextColor3 = CYAN, Size = UDim2.new(0.36, 0, 0.09, 0), Position = UDim2.new(0.62, 0, 0, 16) })
	if #pilots == 0 then
		text(side, { Name = "E", Text = T("No driver yet: race to appear here!"), Font = Enum.Font.Gotham, TextColor3 = rgb(190, 176, 214), Size = UDim2.new(0.9, 0, 0.1, 0),
			Position = UDim2.new(0.05, 0, 0.1, 0) })
	end
	for k = 1, math.min(6, #pilots) do
		local p = pilots[k]
		local pr = RaceRules.Rank(p.Xp or 0)
		local y = 0.03 + (k - 1) * 0.16
		local av = Instance.new("ImageLabel")
		av.Name = "Av" .. k
		av.BackgroundColor3 = pr.Color
		av.Size = UDim2.new(0, 44, 0, 44)
		av.Position = UDim2.new(0.04, 0, y, 0)
		av.Image = string.format("rbxthumb://type=AvatarHeadShot&id=%d&w=150&h=150", math.floor(tonumber(p.UserId) or 1))
		av.Parent = side
		RaceProps.Corner(av, 22)
		text(side, { Name = "N" .. k, Text = string.format("%d. %s", k, tostring(p.Name)), Font = Enum.Font.GothamBold, Size = UDim2.new(0.66, 0, 0.07, 0),
			Position = UDim2.new(0.3, 0, y, 0), TextXAlignment = Enum.TextXAlignment.Left })
		text(side, { Name = "R" .. k, Text = string.format("%s %s · %s XP", pr.Icon, rankLabel(pr), NumberFormatter.Format(math.floor(p.Xp or 0))), Font = Enum.Font.Gotham,
			TextColor3 = pr.Color, Size = UDim2.new(0.66, 0, 0.06, 0), Position = UDim2.new(0.3, 0, y + 0.075, 0), TextXAlignment = Enum.TextXAlignment.Left })
	end
	-- écran du comptoir
	local screen = parts.Screen
	if screen then
		local label = screen:FindFirstChild("T")
		if label and label:IsA("TextLabel") then
			local waiting = 0
			for _, lobby in pairs(lobbies) do
				if lobby.Phase == "Lobby" then
					waiting += lobby.Count or 0
				end
			end
			label.Text = if waiting > 0 then T("🏁 %d waiting!", waiting) else "🏁 3 · 2 · 1 · GO"
		end
	end
end

local function destroyHQ()
	if hq.Model then
		hq.Model:Destroy()
	end
	table.clear(hq)
end

local function buildShowcase()
	local tt = hq.Parts and hq.Parts.Turntable
	if not tt or not hq.Model then
		return
	end
	local ok, car = pcall(CarModels.Build, "SportsCar", "Cherry", { Detail = "Mid", Plate = "RACE 1" })
	if not ok or not car then
		return
	end
	car.Name = "Showcase"
	for _, d in ipairs(car:GetDescendants()) do
		if d:IsA("BasePart") then
			d.Anchored = true
			d.CanCollide = false
			d.CanQuery = false
			d.CanTouch = false
		end
	end
	car:PivotTo(tt.Center)
	car.Parent = hq.Model
	local pivot = car:GetPivot()
	local list, offs = {}, {}
	for _, d in ipairs(car:GetDescendants()) do
		if d:IsA("BasePart") then
			table.insert(list, d)
			table.insert(offs, pivot:ToObjectSpace(d.CFrame))
		end
	end
	hq.Showcase = { Parts = list, Offsets = offs, Frames = table.create(#list), Center = tt.Center }
end

local function buildHQ()
	local f = folder
	if not f then
		return
	end
	local zoneW, zoneD = 64, 44
	local okZone, zone = pcall(function()
		return (WorldLayout :: any).Facility(count, "RaceMeet")
	end)
	if okZone and type(zone) == "table" then
		zoneW, zoneD = tonumber(zone.W) or zoneW, tonumber(zone.D) or zoneD
	end
	local cf = RaceRoutes.MeetCFrame(count)
	local model, parts = RaceProps.BuildHQ(cf, zoneW, zoneD)
	model.Parent = f
	hq.Model, hq.Parts = model, parts
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "RacePrompt"
	prompt.ActionText = T("Street races")
	prompt.ObjectText = T("🏁 Race HQ")
	prompt.KeyboardKeyCode = Enum.KeyCode.E
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = 14
	prompt.RequiresLineOfSight = false
	prompt.Parent = parts.Prompt
	prompt.Triggered:Connect(function()
		openMenu(true)
	end)
	hq.Prompt = prompt
	pcall(buildShowcase)
	fillBoard()
end

local function stepShowcase(dt: number, p: Vector3)
	local sc = hq.Showcase
	if not sc then
		return
	end
	if (sc.Center.Position - p).Magnitude > 180 then
		return
	end
	hq.Spin = ((hq.Spin or 0) + dt * 0.35) % (math.pi * 2)
	local pivot = sc.Center * CFrame.Angles(0, hq.Spin, 0)
	local frames = sc.Frames
	for i, off in ipairs(sc.Offsets) do
		frames[i] = pivot * off
	end
	workspace:BulkMoveTo(sc.Parts, frames, Enum.BulkMoveMode.FireCFrameChanged)
	-- (la plaque tourne avec)
	local base = hq.Parts and hq.Parts.Turntable and hq.Parts.Turntable.Base
	if base then
		base.CFrame = sc.Center * CFrame.new(0, -0.15, 0) * CFrame.Angles(0, hq.Spin, 0) * CFrame.Angles(0, 0, math.rad(90))
	end
end

----------------------------------------------------------------------
-- Portiques
----------------------------------------------------------------------

local function buildGantry(route: any): any
	local f = folder :: Folder
	local cf = RaceRoutes.CFrameAtD(route, 0)
	local gridLen = route.Grid[#route.Grid].Back + 12
	local model, info = RaceProps.BuildGantry(cf, math.max(route.Width, 16) + 2, route.Def.Icon .. " " .. T(route.Def.Name), false, { GridLength = gridLen })
	local cfs = {}
	for slot = 1, #route.Grid do
		table.insert(cfs, RaceRoutes.GridCFrame(route, slot))
	end
	RaceProps.GridMarks(model, cfs)
	model.Parent = f
	local finishModel = nil
	if not route.Closed then
		local fcf = RaceRoutes.CFrameAtD(route, route.RaceDistance)
		local fm = RaceProps.BuildGantry(fcf, math.max(route.Width, 16) + 2, "", true)
		fm.Parent = f
		finishModel = fm
	end
	RaceProps.SetLights(info.Lights, 0)
	RaceProps.SetScreen(info.Screens, "🏁", nil, GOLD)
	return { Model = model, Lights = info.Lights, Screens = info.Screens, Marshal = info.Marshal, Finish = finishModel, Stage = -1, Pos = cf.Position }
end

local function stream()
	local p = focus()
	if not p or not folder then
		return
	end
	-- QG
	local meet = RaceRoutes.MeetCFrame(count).Position
	local dHQ = (Vector3.new(p.X, 0, p.Z) - Vector3.new(meet.X, 0, meet.Z)).Magnitude
	if not hq.Model and dHQ < RaceClient.HQ_IN then
		local ok, err = pcall(buildHQ)
		if not ok then
			warn("[RaceClient] QG : " .. tostring(err))
			destroyHQ()
		end
	elseif hq.Model and dHQ > RaceClient.HQ_OUT then
		destroyHQ()
	end
	-- portiques (départ ; arrivée du sprint)
	for _, def in ipairs((Config.Race and Config.Race.Routes) or {}) do
		local route = routeOf(def.Id)
		if route then
			local start = RaceRoutes.CFrameAtD(route, 0).Position
			local d = (Vector3.new(p.X, 0, p.Z) - Vector3.new(start.X, 0, start.Z)).Magnitude
			if not route.Closed then
				local fin = RaceRoutes.CFrameAtD(route, route.RaceDistance).Position
				d = math.min(d, (Vector3.new(p.X, 0, p.Z) - Vector3.new(fin.X, 0, fin.Z)).Magnitude)
			end
			local g = gantries[def.Id]
			if not g and d < RaceClient.GANTRY_IN then
				local ok, result = pcall(buildGantry, route)
				if ok then
					gantries[def.Id] = result
				else
					warn("[RaceClient] Portique : " .. tostring(result))
				end
			elseif g and d > RaceClient.GANTRY_OUT then
				g.Model:Destroy()
				if g.Finish then
					g.Finish:Destroy()
				end
				gantries[def.Id] = nil
			end
		end
	end
	if boardDirty and hq.Model then
		boardDirty = false
		pcall(fillBoard)
	end
end

----------------------------------------------------------------------
-- Flammes de nitro (IA et humains)
----------------------------------------------------------------------

local function placeFlames(key: string, carCF: CFrame?, length: number, on: boolean)
	local list = flames[key]
	if not on or not carCF then
		if list then
			for _, part in ipairs(list) do
				part:Destroy()
			end
			flames[key] = nil
		end
		return
	end
	if not list then
		list = RaceProps.BuildFlames(folder :: Folder)
		flames[key] = list
	end
	local frames = {}
	local flick = 0.75 + 0.35 * math.abs(math.sin(clockT * 31 + #key))
	for k = 1, 2 do
		local side = if k == 1 then -0.95 else 0.95
		local base = carCF * CFrame.new(side, 1.0, length / 2 + 0.9 * flick) * CFrame.Angles(0, math.rad(90), 0)
		list[(k - 1) * 2 + 1].Size = Vector3.new(2.4 * flick, 0.9, 0.9)
		list[(k - 1) * 2 + 2].Size = Vector3.new(1.5 * flick, 0.5, 0.5)
		table.insert(frames, base)
		table.insert(frames, base * CFrame.new(-0.3, 0, 0))
	end
	workspace:BulkMoveTo(list, frames, Enum.BulkMoveMode.FireCFrameChanged)
end

local function clearFlames()
	for key in pairs(flames) do
		placeFlames(key, nil, 0, false)
	end
end

----------------------------------------------------------------------
-- Pilotes IA
----------------------------------------------------------------------

local DRIVER_STYLES = { "pedestrian", "jogger", "worker", "shopper" }

local function destroyAI(ai: AICar)
	if ai.Model then
		ai.Model:Destroy()
	end
	ai.Model = nil
	ai.Rig = nil
	ai.Driver = nil
	ai.Lod = 0
	table.clear(ai.Extra)
	table.clear(ai.ExtraOff)
	placeFlames(ai.Key, nil, 0, false)
end

local function buildAI(ai: AICar, lod: number)
	destroyAI(ai)
	local detail = if lod >= 2 then "Mid" else "Low"
	local model = CarModels.Build(ai.Kind, ai.Color ~= "" and ai.Color or nil, { Detail = detail, Plate = "RACE" })
	model.Name = "RaceAI_" .. ai.Key
	-- boîte de collision solide (la voiture du joueur rebondit dessus)
	local root = model.PrimaryPart
	if root then
		root.CanCollide = true
		root.CanQuery = true
		pcall(function()
			root.CollisionGroup = RaceClient.CAR_GROUP
		end)
	end
	model:SetAttribute("ClientMover", true)
	model:SetAttribute("OwnerId", 0)
	pcall(CollectionService.AddTag, CollectionService, model, RaceClient.MOVER_TAG)
	model:PivotTo(CFrame.new(0, -500, 0))
	model.Parent = folder
	ai.Model = model
	ai.Lod = lod
	local seatCF = model:GetAttribute("SeatCF")
	ai.SeatCF = if typeof(seatCF) == "CFrame" then seatCF else CFrame.new(-1.2, 1.6, 0.5)
	if lod >= 2 then
		local okRig, rig = pcall(CarModels.WheelRig, model)
		if okRig then
			ai.Rig = rig
		end
		-- pilote : NPCModels.Driver (NPC11, mains sur le volant) sinon assis figé
		local style = DRIVER_STYLES[(ai.Seed % #DRIVER_STYLES) + 1]
		local okNpc, npc = pcall(NPCModels.Build, style, { Seed = ai.Seed, Solid = false, Look = false, Name = "Driver" })
		if okNpc and npc then
			local driverFn = (NPCModels :: any).Driver
			npc.Parent = model
			for _, d in ipairs(npc:GetDescendants()) do
				if d:IsA("BasePart") then
					d.CanCollide = false
					d.CanQuery = false
					d.CanTouch = false
				end
			end
			if type(driverFn) == "function" then
				ai.Driver = npc
			else
				local pivot = CFrame.new(0, -500, 0)
				pcall(NPCModels.SetSeated, npc, 1.05)
				pcall(NPCModels.Place, npc, pivot * ai.SeatCF * CFrame.new(0, -1.05, 0))
				pcall(NPCModels.Animate, npc, "sit", 0)
				for _, d in ipairs(npc:GetDescendants()) do
					if d:IsA("BasePart") then
						table.insert(ai.Extra, d)
						table.insert(ai.ExtraOff, pivot:ToObjectSpace(d.CFrame))
					end
				end
			end
		end
	end
end

-- Pose d'une IA (distance de course, file) : CFrame du pivot au sol
local function aiPivot(route: any, ai: AICar, dt: number): CFrame
	local s = lineS(route, ai.D)
	local x, z, tx, tz, y = RaceRules.PointAt(route.Line, s)
	-- cap lissé (anticipe un peu : regarde 3 studs devant)
	local x2, z2 = RaceRules.PointAt(route.Line, s + 3)
	local dir = Vector3.new(x2 - x, 0, z2 - z)
	if dir.Magnitude < 1e-3 then
		dir = Vector3.new(tx, 0, tz)
	end
	dir = dir.Unit
	local prev = ai.Heading or dir
	local blend = math.clamp(dt * 10, 0, 1)
	local heading = prev:Lerp(dir, blend)
	if heading.Magnitude < 1e-3 then
		heading = dir
	end
	heading = heading.Unit
	-- vitesse de lacet (+ = vers la gauche) -> braquage des roues, volant, roulis
	local turn = math.asin(math.clamp(prev:Cross(heading).Y, -1, 1)) / math.max(dt, 1 / 120)
	ai.Heading = heading
	ai.Steer += (math.clamp(turn * 0.35, -0.5, 0.5) - ai.Steer) * math.clamp(dt * 6, 0, 1)
	ai.Wheel += (math.clamp(turn * 0.9, -2.2, 2.2) - ai.Wheel) * math.clamp(dt * 5, 0, 1)
	ai.Roll += (math.clamp(-turn * ai.V * 0.0025, -0.06, 0.06) - ai.Roll) * math.clamp(dt * 4, 0, 1)
	local right = Vector3.new(-heading.Z, 0, heading.X)
	local p = RaceRoutes.ToWorld(x, z, y) + right * ai.Lane
	return CFrame.lookAt(p, p + heading) * CFrame.Angles(ai.Pitch, 0, ai.Roll)
end

local function poseAI(route: any, ai: AICar, dt: number)
	local model = ai.Model
	if not model then
		return
	end
	local pivot = aiPivot(route, ai, dt)
	ai.Pivot = pivot
	local radius = tonumber(model:GetAttribute("WheelRadius")) or 1
	ai.Spin = (ai.Spin + ai.V * dt / math.max(radius, 0.3)) % (math.pi * 2)
	local moved = false
	if ai.Rig then
		local okPose, bparts, frames = pcall(CarModels.PoseRig, ai.Rig, pivot, ai.Spin, ai.Steer, nil)
		if okPose then
			if #ai.Extra > 0 then
				local allParts = table.clone(bparts)
				local allFrames = table.clone(frames)
				for i, part in ipairs(ai.Extra) do
					table.insert(allParts, part)
					table.insert(allFrames, pivot * ai.ExtraOff[i])
				end
				workspace:BulkMoveTo(allParts, allFrames, Enum.BulkMoveMode.FireCFrameChanged)
			else
				workspace:BulkMoveTo(bparts, frames, Enum.BulkMoveMode.FireCFrameChanged)
			end
			moved = true
		end
	end
	if not moved then
		model:PivotTo(pivot)
	end
	-- pilote (NPC11) : posé chaque image, mains sur le volant
	if ai.Driver then
		local fn = (NPCModels :: any).Driver
		if type(fn) == "function" then
			pcall(fn, ai.Driver, pivot * ai.SeatCF, ai.Wheel, { T = clockT + ai.Seed * 0.13 })
		end
	end
end

local function stepAI(view: RaceView, dt: number, p: Vector3?)
	local snap = view.Snap
	local route = view.Route
	local t = now()
	local seen: { [string]: boolean } = {}
	local racing = snap.Phase == "Racing"
	for _, row in ipairs(snap.Racers) do
		if row.AI then
			seen[row.K] = true
			local ai = view.Ai[row.K]
			if not ai then
				ai = {
					Key = row.K,
					Kind = tostring(row.C or "CityCar"),
					Model = nil,
					Lod = 0,
					Rig = nil,
					Driver = nil,
					SeatCF = CFrame.new(),
					Extra = {},
					ExtraOff = {},
					D = row.D,
					V = row.V,
					Lane = row.L or 0,
					Spin = 0,
					Steer = 0,
					Wheel = 0,
					Heading = nil,
					Pitch = 0,
					Roll = 0,
					Seen = t,
					Name = tostring(row.N or ""),
					Color = tostring(row.Col or ""),
					Seed = #tostring(row.K) * 131 + (snap.Id or 1) * 17 + (tonumber(string.match(tostring(row.K), "%d+")) or 0) * 7,
					Pivot = nil,
				}
				view.Ai[row.K] = ai
			end
			-- position visée : l'instantané + ce qui a été roulé depuis
			local age = math.clamp(t - view.ServerAt, 0, 0.6)
			local target = row.D + (if racing and not row.F then row.V * age else 0)
			local err = target - ai.D
			if math.abs(err) > 40 or not racing then
				ai.D = target
			else
				ai.D += (if racing and not row.F then row.V * dt else 0) + err * math.clamp(dt * 3, 0, 1)
			end
			local oldV = ai.V
			ai.V += ((if racing and not row.F then row.V else 0) - ai.V) * math.clamp(dt * 4, 0, 1)
			ai.Pitch += (math.clamp(-(ai.V - oldV) / math.max(dt, 1 / 120) * 0.0015, -0.03, 0.03) - ai.Pitch) * math.clamp(dt * 3, 0, 1)
			ai.Lane += ((row.L or 0) - ai.Lane) * math.clamp(dt * 3, 0, 1)
			-- niveau de détail selon la distance
			local lod = 0
			local d = math.huge
			if p then
				local s = lineS(route, ai.D)
				local x, z = RaceRules.PointAt(route.Line, s)
				local world = RaceRoutes.ToWorld(x, z, 0)
				d = (Vector3.new(world.X - p.X, 0, world.Z - p.Z)).Magnitude
				if d < RaceClient.AI_MID then
					lod = 2
				elseif d < RaceClient.AI_FAR then
					lod = 1
				end
				-- hystérésis
				if ai.Lod == 2 and lod == 1 and d < RaceClient.AI_MID + 25 then
					lod = 2
				end
			end
			if lod ~= ai.Lod then
				if lod == 0 then
					destroyAI(ai)
				else
					local ok, err2 = pcall(buildAI, ai, lod)
					if not ok then
						warn("[RaceClient] IA : " .. tostring(err2))
						destroyAI(ai)
					end
				end
			end
			if ai.Model then
				poseAI(route, ai, dt)
				-- flammes de nitro
				local boosting = racing and type(row.Bo) == "number" and t < row.Bo
				local len = tonumber(ai.Model:GetAttribute("Length")) or 14
				placeFlames(ai.Key, ai.Pivot, len, boosting and d < RaceClient.FX_RANGE)
			end
		end
	end
	for key, ai in pairs(view.Ai) do
		if not seen[key] then
			destroyAI(ai)
			view.Ai[key] = nil
		end
	end
	-- flammes des humains (leur voiture, répliquée)
	for _, row in ipairs(snap.Racers) do
		if not row.AI then
			local key = "H" .. tostring(row.U)
			local boosting = racing and type(row.Bo) == "number" and t < row.Bo
			local car = if boosting then humanCar(row.U) else nil
			if car and p and (car:GetPivot().Position - p).Magnitude < RaceClient.FX_RANGE then
				placeFlames(key, car:GetPivot(), tonumber(car:GetAttribute("Length")) or 14, true)
			else
				placeFlames(key, nil, 0, false)
			end
		end
	end
end

local function dropView(id: string)
	local view = views[id]
	if view then
		for _, ai in pairs(view.Ai) do
			destroyAI(ai)
		end
		for _, row in ipairs(view.Snap.Racers or {}) do
			if not row.AI then
				placeFlames("H" .. tostring(row.U), nil, 0, false)
			end
		end
		views[id] = nil
	end
end

----------------------------------------------------------------------
-- Caméras : présentation de la grille, spectateur
----------------------------------------------------------------------

local function smooth(u: number): number
	local x = math.clamp(u, 0, 1)
	return x * x * (3 - 2 * x)
end

local function restoreCamera()
	local camera = workspace.CurrentCamera
	if not camera then
		return
	end
	camera.CameraType = Enum.CameraType.Custom
	local character = LocalPlayer.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		camera.CameraSubject = if humanoid.SeatPart then humanoid.SeatPart else humanoid
	end
end

-- Présentation : du portique (vue d'ensemble de la grille) -> travelling sur
-- le côté de la grille -> derrière MA voiture au moment du GO
local function gridCamera(): CFrame?
	local cs = camState
	if not cs then
		return nil
	end
	local route = routeOf(cs.Route)
	if not route then
		return nil
	end
	local t = now()
	local endAt = cs.GoAt - 0.3
	local u = (t - cs.Start) / math.max(0.5, endAt - cs.Start)
	local G = RaceRoutes.CFrameAtD(route, 0)
	local M = RaceRoutes.GridCFrame(route, cs.Slot or 1)
	local keys = {
		{ G * Vector3.new(16, 15, -34), G * Vector3.new(0, 2, 40) },
		{ M * Vector3.new(15, 4.5, -20), M * Vector3.new(0, 2.5, 0) },
		{ M * Vector3.new(0, 7.5, 21), M * Vector3.new(0, 2.5, -22) },
	}
	local a, b, w
	if u < 0.5 then
		a, b, w = keys[1], keys[2], smooth(u / 0.5)
	else
		a, b, w = keys[2], keys[3], smooth((u - 0.5) / 0.5)
	end
	local pos = a[1]:Lerp(b[1], w)
	local at = a[2]:Lerp(b[2], w)
	return CFrame.lookAt(pos, at)
end

local function stepGridCamera()
	local cs = camState
	if not cs then
		return
	end
	local camera = workspace.CurrentCamera
	if not camera then
		return
	end
	if now() >= cs.GoAt - 0.3 or spectate then
		camState = nil
		restoreCamera()
		return
	end
	local cf = gridCamera()
	if cf then
		camera.CameraType = Enum.CameraType.Scriptable
		camera.CFrame = cf
	end
end

-- Cible du spectateur : (CFrame, nom, ligne de l'instantané)
local function spectateTarget(): (CFrame?, any?, any?)
	local sp = spectate
	if not sp then
		return nil
	end
	local view = views[sp.Route]
	if not view then
		return nil
	end
	local rows = view.Snap.Racers or {}
	local order = table.clone(rows)
	table.sort(order, function(x, y)
		return (x.Pl or 99) < (y.Pl or 99)
	end)
	if #order == 0 then
		return nil
	end
	sp.Index = ((sp.Index - 1) % #order) + 1
	local row = order[sp.Index]
	local cf: CFrame? = nil
	if row.AI then
		local ai = view.Ai[row.K]
		if ai and ai.Pivot then
			cf = ai.Pivot
		end
	else
		local car = humanCar(row.U)
		if car then
			cf = car:GetPivot()
		end
	end
	if not cf then
		local route = view.Route
		cf = RaceRoutes.CFrameAtD(route, row.D or 0, row.L or 0)
	end
	return cf, row, #order
end

local function stepSpectate(dt: number)
	local sp = spectate
	if not sp then
		return
	end
	local camera = workspace.CurrentCamera
	if not camera then
		return
	end
	local cf, row, n = spectateTarget()
	if not cf or not row then
		return
	end
	local target = cf :: CFrame
	local want = CFrame.lookAt((target * CFrame.new(0, 8, 22)).Position, (target * CFrame.new(0, 2, -14)).Position)
	camera.CameraType = Enum.CameraType.Scriptable
	local cur = sp.Cam or want
	if (cur.Position - want.Position).Magnitude > 120 then
		cur = want
	end
	sp.Cam = cur:Lerp(want, math.clamp(dt * 4, 0, 1))
	camera.CFrame = sp.Cam
	local view = views[sp.Route]
	local route = view and view.Route
	local lap = if route and route.Closed then math.clamp(math.floor(math.max(row.D or 0, 0) / route.Total) + 1, 1, route.Laps) else 1
	RaceHud.SetSpectate({
		Text = string.format("👁️ <b>%s</b> · P%d/%d%s", tostring(row.N), row.Pl or 1, n or 1, if route and route.Laps > 1 then " · " .. T("Lap %d/%d", lap, route.Laps) else ""),
	})
end

local function stopSpectate()
	if spectate then
		spectate = nil
		send("watch", nil)
		RaceHud.SetSpectate(nil)
		RaceHud.SetRace(nil)
		restoreCamera()
	end
end

local function startSpectate(routeId: string)
	if joined.Route then
		return
	end
	spectate = { Route = routeId, Index = 1 }
	send("watch", routeId)
	openMenu(false)
	toast(T("👁️ Watching the race: ◀ ▶ to switch driver"))
end

----------------------------------------------------------------------
-- Ma course : portes, chevrons, fantôme, HUD
----------------------------------------------------------------------

local function clearGates()
	for _, g in pairs(gates) do
		g:Destroy()
	end
	table.clear(gates)
end

local function clearChevrons()
	for _, c in pairs(chevrons) do
		c:Destroy()
	end
	table.clear(chevrons)
end

local function clearGhost()
	if ghost.Model then
		ghost.Model:Destroy()
	end
	table.clear(ghost)
end

local function restoreNight()
	if nightForced then
		nightForced = false
		pcall(function()
			local atmo = require(script.Parent:FindFirstChild("TownAtmosphere") :: ModuleScript) :: any
			atmo.SetNight(ClientState.IsUserDarkMode())
		end)
	end
end

local function setBoost(on: boolean)
	local car = myCarModel()
	if car then
		pcall(function()
			car:SetAttribute("RaceBoost", if on then RaceRules.BoostFactor() else nil)
		end)
	end
	mine.BoostOn = on
end

local function endMyRace()
	clearGates()
	clearChevrons()
	clearGhost()
	placeFlames("Me", nil, 0, false)
	if mine.BoostOn then
		setBoost(false)
	end
	table.clear(mine)
	lastCountdown = nil
	if camState then
		camState = nil
		restoreCamera()
	end
	RaceHud.SetRace(nil)
	restoreNight()
end

local function syncGates(route: any, nextIndex: number)
	local cps = route.Checkpoints
	local want: { [number]: boolean } = {}
	for k = nextIndex, math.min(#cps, nextIndex + 2) do
		want[k] = true
	end
	for k, model in pairs(gates) do
		if not want[k] then
			gates[k] = nil
			if k < nextIndex then
				-- franchie : elle s'affaisse et s'efface
				pcall(RaceProps.PassGate, model)
			else
				model:Destroy()
			end
		end
	end
	for k in pairs(want) do
		local cp = cps[k]
		if not gates[k] then
			local ok, model = pcall(function()
				local _, _, _, _, y = RaceRules.PointAt(route.Line, cp.S)
				local p = RaceRoutes.ToWorld(cp.X, cp.Z, y)
				local cf = CFrame.lookAt(p, p + Vector3.new(cp.TX, 0, cp.TZ))
				local m = RaceProps.BuildArch(cf, cp.W, if cp.Finish then 0 else k)
				if cp.Finish then
					m.Name = "RaceGate_Finish"
				end
				m.Parent = folder
				return m
			end)
			if ok and model then
				gates[k] = model
			end
		end
		if gates[k] then
			RaceProps.SetGateState(gates[k], if k == nextIndex then "next" else "later")
		end
	end
end

-- Panneaux à chevrons des virages à moins de CHEVRON_AHEAD studs devant
local function syncChevrons(route: any, myD: number)
	local want: { [number]: { D: number, Turn: number } } = {}
	local corners = route.Corners or {}
	for i, c in ipairs(corners) do
		-- distance de course de ce virage (la prochaine occurrence)
		local d
		if route.Closed then
			local lapBase = math.floor(math.max(myD, 0) / route.Total) * route.Total
			d = lapBase + c.S
			if d < myD - 20 then
				d += route.Total
			end
			if d > route.RaceDistance then
				d = math.huge
			end
		else
			d = c.S - route.StartS
		end
		if d >= myD - 20 and d <= myD + RaceClient.CHEVRON_AHEAD then
			want[i] = { D = d, Turn = c.Turn }
		end
	end
	for i, model in pairs(chevrons) do
		if not want[i] then
			model:Destroy()
			chevrons[i] = nil
		end
	end
	for i, w in pairs(want) do
		if not chevrons[i] then
			local ok, model = pcall(function()
				local lat = (route.Width / 2 + 5) * (if w.Turn > 0 then 1 else -1)
				local center = RaceRoutes.CFrameAtD(route, w.D, 0).Position
				local pos = RaceRoutes.CFrameAtD(route, w.D, lat).Position
				local m = RaceProps.BuildChevron(CFrame.lookAt(pos, Vector3.new(center.X, pos.Y, center.Z)), w.Turn)
				m.Parent = folder
				return m
			end)
			if ok and model then
				chevrons[i] = model
			end
		end
	end
end

-- Fantôme de mon meilleur tour (temps de passage du serveur, me.Ghost)
local function stepGhost(route: any, myRow: any, t: number)
	local data = me.Ghost and me.Ghost[route.Id]
	local running = type(myRow.LS) == "number" and t >= (myRow.LS :: number)
	if type(data) ~= "table" or not running or myRow.F or myRow.X then
		clearGhost()
		return
	end
	local tau = t - myRow.LS
	if tau > (data.Time or 0) + 1.5 then
		-- fantôme arrivé au bout du tour : on le range
		if ghost.Model then
			ghost.Model:PivotTo(CFrame.new(0, -500, 0))
		end
		return
	end
	if not ghost.Model then
		local ok, model = pcall(CarModels.Build, data.Car or "CityCar", nil, { Detail = "Low" })
		if not ok or not model then
			return
		end
		RaceProps.Ghostify(model)
		model.Parent = folder
		ghost.Model = model
	end
	local d = (tonumber(myRow.LD) or 0) + RaceRules.GhostAt(data, tau)
	local cf = RaceRoutes.CFrameAtD(route, math.min(d, route.RaceDistance), 0)
	ghost.Model:PivotTo(cf)
	ghost.D = d
end

-- Ma progression locale (même calcul que le serveur, pour un HUD fluide)
local function localProgress(route: any): (number?, number, Vector3?)
	local car = myCarRoot()
	if not car then
		return nil, 0, nil
	end
	local o = WorldLayout.Origin()
	local x, z = car.Position.X - o.X, car.Position.Z - o.Z
	local hint = mine.S or lineS(route, mine.D or 0)
	local s = RaceRules.Project(route.Line, x, z, hint, 220)
	local d = mine.D or 0
	if route.Closed then
		local delta = s - hint
		local half = route.Total / 2
		if delta > half then
			delta -= route.Total
		elseif delta < -half then
			delta += route.Total
		end
		d += delta
	else
		d = s - route.StartS
	end
	mine.S = s
	mine.D = d
	return d, car.AssemblyLinearVelocity.Magnitude, car.CFrame.LookVector
end

local function racerColor(row: any, isMe: boolean): Color3
	if isMe then
		return GOLD
	end
	if row.AI then
		local c = (Config.Cars and Config.Cars.Colors) or {}
		for _, def in ipairs(c) do
			if def.Id == row.Col then
				return def.Color
			end
		end
		return SOFT
	end
	return CYAN
end

local function stepMine(dt: number)
	local id = joined.Route
	local view = id and views[id]
	if not id or not view or view.Snap.Id ~= joined.RaceId then
		return
	end
	local snap = view.Snap
	local route = view.Route
	if snap.Phase == "Lobby" then
		return
	end
	local myRow = nil
	for _, row in ipairs(snap.Racers) do
		if row.U == LocalPlayer.UserId and not row.AI then
			myRow = row
		end
	end
	if not myRow then
		return
	end
	local t = now()
	-- course de nuit : la ville passe en nuit
	if route.Def.Night and not nightForced then
		nightForced = true
		pcall(function()
			local atmo = require(script.Parent:FindFirstChild("TownAtmosphere") :: ModuleScript) :: any
			atmo.SetNight(true)
		end)
	end
	-- 3-2-1-GO
	local remain = (snap.GoAt or 0) - t
	local cd: string? = nil
	if remain > 0 and remain <= 3 then
		cd = tostring(math.ceil(remain))
	elseif remain <= 0 and remain > -1.2 then
		cd = "GO"
	end
	if cd and cd ~= lastCountdown then
		lastCountdown = cd
		if cd == "GO" then
			RaceHud.Countdown(T("GO!"), rgb(110, 255, 140))
		else
			RaceHud.Countdown(cd, rgb(255, 90, 90))
		end
	end
	-- progression locale
	if mine.D == nil then
		mine.D = myRow.D
		mine.S = lineS(route, myRow.D)
	end
	local running = snap.Phase == "Racing" and not myRow.F and not myRow.X
	local speed, look = 0, nil
	if running then
		local d, v, lk = localProgress(route)
		if d then
			speed, look = v, lk
			-- le serveur a remis la voiture à une porte : on se recale
			if math.abs(d - myRow.D) > 120 then
				mine.D = myRow.D
				mine.S = lineS(route, myRow.D)
			end
		end
	else
		mine.D = myRow.D
	end
	local myD = mine.D or myRow.D
	-- portes (la prochaine selon le serveur)
	local nextIndex = myRow.Nx or 1
	mine.Next = nextIndex
	if running then
		syncGates(route, nextIndex)
		syncChevrons(route, myD)
		stepGhost(route, myRow, t)
	else
		clearGates()
		clearChevrons()
		clearGhost()
	end
	-- nitro : boost validé par le serveur (Bo) -> attribut local lu par CarClient + flammes
	local boostLeft = if type(myRow.Bo) == "number" then (myRow.Bo :: number) - t else 0
	local boosting = running and boostLeft > 0
	if boosting ~= (mine.BoostOn == true) then
		setBoost(boosting)
	end
	local car = myCarModel()
	placeFlames("Me", if car then car:GetPivot() else nil, if car then (tonumber(car:GetAttribute("Length")) or 14) else 0, boosting and car ~= nil)
	-- dérapage : points qui montent -> compteur
	local dr = tonumber(myRow.Dr) or 0
	if mine.DriftLast and dr > mine.DriftLast + 0.5 then
		if not mine.DriftCombo or t - (mine.DriftAt or 0) > 1 then
			mine.DriftCombo = 0
		end
		mine.DriftCombo += dr - mine.DriftLast
		mine.DriftAt = t
		if t - (mine.DriftShown or 0) > 0.18 then
			mine.DriftShown = t
			RaceHud.Drift(mine.DriftCombo)
		end
	end
	mine.DriftLast = dr
	-- mauvais sens
	local wrong = false
	if running and look and speed > 6 then
		local _, _, tx, tz = RaceRules.PointAt(route.Line, lineS(route, myD))
		if look.X * tx + look.Z * tz < -0.4 then
			mine.WrongFor = (mine.WrongFor or 0) + dt
		else
			mine.WrongFor = 0
		end
		wrong = (mine.WrongFor or 0) > 1.2
	end
	hudClock += dt
	if hudClock < 1 / 15 then
		return
	end
	hudClock = 0
	-- classement (mon D local à la place du mien)
	local list = {}
	for _, row in ipairs(snap.Racers) do
		local isMe = row == myRow
		local d = if isMe then myD else (if row.AI and view.Ai[row.K] then view.Ai[row.K].D else row.D)
		table.insert(list, { Key = row.K, Row = row, Finished = row.F, FinishTime = row.T, Progress = d, Dnf = row.X, Me = isMe })
	end
	local ranked = RaceRules.Standings(list)
	local place = 1
	for i, r in ipairs(ranked) do
		if r.Me then
			place = i
		end
	end
	if running and mine.Place and place ~= mine.Place and t - (snap.GoAt or t) > 2 then
		RaceHud.PlaceChange(place, place < mine.Place)
	end
	mine.Place = place
	local elapsed = if myRow.F and myRow.T then myRow.T elseif snap.Phase == "Racing" then math.max(0, t - (snap.GoAt or t)) else 0
	-- tour des temps : écart (s) avec le 1er (distance / vitesse de référence)
	local leader = ranked[1]
	local tower = {}
	local refSpeed = math.max(speed, 30)
	for i, r in ipairs(ranked) do
		local row = r.Row
		local gap = ""
		if i == 1 then
			gap = if row.F and row.T then fmt(row.T) else T("Lead")
		elseif row.X then
			gap = T("Out")
		elseif row.F and row.T and leader.Row.T then
			gap = string.format("+%.1f", math.max(0, row.T - leader.Row.T))
		else
			gap = string.format("+%.1f", math.max(0, (leader.Progress - r.Progress) / refSpeed))
		end
		table.insert(tower, { Pos = i, Name = tostring(row.N), Gap = gap, Color = racerColor(row, r.Me), Me = r.Me, Out = row.X == true })
	end
	-- flèche vers la prochaine porte (relative à la caméra)
	local cpText, arrow = nil, 0
	local cp = route.Checkpoints[math.clamp(nextIndex, 1, #route.Checkpoints)]
	local camera = workspace.CurrentCamera
	local carRoot = myCarRoot()
	if running and cp and camera and carRoot then
		local target = RaceRoutes.ToWorld(cp.X, cp.Z, 0)
		local to = Vector3.new(target.X - carRoot.Position.X, 0, target.Z - carRoot.Position.Z)
		local dist = to.Magnitude
		local cl = camera.CFrame.LookVector
		local fwd = Vector3.new(cl.X, 0, cl.Z)
		if fwd.Magnitude > 1e-3 and dist > 1e-3 then
			fwd = fwd.Unit
			local dir = to.Unit
			arrow = math.deg(math.atan2(fwd:Cross(dir).Y * -1, fwd:Dot(dir)))
		end
		cpText = if cp.Finish then T("🏁 Finish · %d m", math.floor(dist * 0.28 + 0.5))
			else T("Gate %d/%d · %d m", nextIndex, #route.Checkpoints, math.floor(dist * 0.28 + 0.5))
	end
	local lap = if route.Closed then math.floor(math.max(myD, 0) / route.Total) + 1 else 1
	local foot = {}
	if myRow.LL then
		table.insert(foot, T("Last lap: %s", fmt(myRow.LL)))
	end
	if myRow.B then
		table.insert(foot, "<font color=\"#FFD65A\">" .. T("Best lap: %s", fmt(myRow.B)) .. "</font>")
	end
	local ghostData = me.Ghost and me.Ghost[route.Id]
	if ghostData and ghostData.Time then
		table.insert(foot, "👻 " .. fmt(ghostData.Time))
	end
	local cfgN = (Config.Race and Config.Race.Nitro) or {}
	RaceHud.SetRace({
		Place = place,
		Count = #snap.Racers,
		Lap = math.min(lap, route.Laps),
		Laps = route.Laps,
		Time = fmt(elapsed),
		Tower = tower,
		Foot = table.concat(foot, "  ·  "),
		Cp = cpText,
		Arrow = arrow,
		Wrong = wrong,
		Running = running,
		Nitro = { Charges = myRow.Ni or 0, Max = cfgN.Max or 3, Gauge = myRow.Ga or 0, Boost = if boosting then boostLeft / (cfgN.Seconds or 2.6) else 0 },
	})
	-- mini-carte
	if not mine.MiniDrawn then
		mine.MiniDrawn = true
		RaceHud.SetMinimap(preview(route), nil, route.Closed)
	end
	local box = route.MiniBox
	if box then
		local dots = {}
		for _, r in ipairs(ranked) do
			local x, z = RaceRules.PointAt(route.Line, lineS(route, r.Progress))
			local color = if r.Me then GOLD elseif r.Row.AI then SOFT else CYAN
			table.insert(dots, { 0.5 + (x - box[1]) / box[3], 0.5 + (z - box[2]) / box[3], color, r.Me })
		end
		if ghost.D then
			local x, z = RaceRules.PointAt(route.Line, lineS(route, ghost.D))
			table.insert(dots, { 0.5 + (x - box[1]) / box[3], 0.5 + (z - box[2]) / box[3], rgb(150, 230, 255), false })
		end
		RaceHud.SetMinimap(nil, dots)
	end
end

-- Spectateur : tour des temps de la course regardée
local function stepSpectateHud()
	local sp = spectate
	if not sp then
		return
	end
	local view = views[sp.Route]
	if not view then
		stopSpectate()
		return
	end
	local snap = view.Snap
	local route = view.Route
	local order = table.clone(snap.Racers or {})
	table.sort(order, function(x, y)
		return (x.Pl or 99) < (y.Pl or 99)
	end)
	local _, watched = spectateTarget()
	local tower = {}
	for i, row in ipairs(order) do
		local gap = if row.F and row.T then fmt(row.T) elseif row.X then T("Out") else string.format("%.0f m", math.max(0, (order[1].D - row.D) * 0.28))
		if i == 1 and not row.F then
			gap = T("Lead")
		end
		table.insert(tower, { Pos = i, Name = tostring(row.N), Gap = gap, Color = racerColor(row, false), Me = watched ~= nil and row.K == watched.K, Out = row.X == true })
	end
	local lead = order[1]
	local lap = if route.Closed and lead then math.clamp(math.floor(math.max(lead.D or 0, 0) / route.Total) + 1, 1, route.Laps) else 1
	RaceHud.SetRace({
		Place = (watched and watched.Pl) or 1,
		Count = #order,
		Lap = lap,
		Laps = route.Laps,
		Time = fmt(math.max(0, now() - (snap.GoAt or now()))),
		Tower = tower,
		Running = false,
	})
	if not sp.MiniDrawn then
		sp.MiniDrawn = true
		RaceHud.SetMinimap(preview(route), nil, route.Closed)
	end
	local box = route.MiniBox
	if box then
		local dots = {}
		for _, row in ipairs(order) do
			local x, z = RaceRules.PointAt(route.Line, lineS(route, row.D or 0))
			local isW = watched ~= nil and row.K == watched.K
			table.insert(dots, { 0.5 + (x - box[1]) / box[3], 0.5 + (z - box[2]) / box[3], if isW then GOLD elseif row.AI then SOFT else CYAN, isW })
		end
		RaceHud.SetMinimap(nil, dots)
	end
end

----------------------------------------------------------------------
-- Réseau
----------------------------------------------------------------------

local function showResults(payload: any)
	local route = routeOf(tostring(payload.Route))
	local def = route and route.Def or Config.RaceRoutesById[tostring(payload.Route)]
	local rows = {}
	for _, row in ipairs(payload.Rows or {}) do
		local timeText = if row.Finished and row.Time then fmt(row.Time) elseif row.Dnf then T("Out") else T("Did not finish")
		table.insert(rows, {
			Place = row.Place,
			Name = row.Name,
			UserId = row.UserId,
			AI = row.AI,
			TimeText = timeText,
			GapText = if row.Gap then string.format("+%.2f", row.Gap) else "",
			LapText = if row.BestLap and route and route.Laps > 1 then fmt(row.BestLap) else "",
			Me = (not row.AI) and row.UserId == LocalPlayer.UserId,
		})
	end
	local m = payload.Mine or {}
	local place = tonumber(m.Place) or 0
	local suffix = if Locale.IsFrench() then (if place == 1 then "er" else "e") else (if place == 1 then "st" elseif place == 2 then "nd" elseif place == 3 then "rd" else "th")
	local mineText
	if m.Suspicious then
		mineText = T("No reward: the race was not valid")
	elseif (m.Reward or 0) > 0 then
		mineText = T("You finished %d%s · +%s Dopamine!", place, suffix, NumberFormatter.Format(m.Reward))
	elseif m.Capped then
		mineText = T("You finished %d%s · daily race rewards reached", place, suffix)
	else
		mineText = T("You finished %d%s", place, suffix)
	end
	local detail = {}
	if m.Time then
		table.insert(detail, "⏱️ " .. fmt(m.Time))
	end
	if m.PrevBest and m.Time and m.Finished then
		local dlt = m.Time - m.PrevBest
		table.insert(detail, string.format("<font color=\"%s\">%s%.2f s</font>", if dlt <= 0 then "#6EE2AA" else "#F04650", if dlt <= 0 then "−" else "+", math.abs(dlt)))
	end
	if (m.Overtakes or 0) > 0 then
		table.insert(detail, T("%d overtakes", m.Overtakes))
	end
	if (m.Drift or 0) > 0 then
		table.insert(detail, T("drift %s", NumberFormatter.Format(m.Drift)))
	end
	if m.Diamond then
		table.insert(detail, "💎 +1")
	end
	local medal = tonumber(m.Medal) or 0
	local medalText = if medal == 1 then T("Gold medal") elseif medal == 2 then T("Silver medal") elseif medal == 3 then T("Bronze medal") else T("No medal")
	if medal == 0 and m.Medals and m.Medals.Bronze then
		medalText = T("Bronze: %s", fmt(m.Medals.Bronze))
	end
	local stamp = ""
	if m.PB then
		stamp = T("NEW RECORD!")
	elseif m.BestLapPB then
		stamp = T("BEST LAP!")
	elseif place == 1 and m.Finished then
		stamp = T("VICTORY!")
	end
	local xp = nil
	if m.XpAfter then
		xp = {
			From = m.XpBefore or 0,
			To = m.XpAfter,
			Gain = m.Xp or 0,
			RankFrom = RaceRules.Rank(m.XpBefore or 0),
			RankTo = RaceRules.Rank(m.XpAfter),
		}
	end
	RaceHud.ShowResults({
		Title = (def and def.Icon or "🏁") .. " " .. T("Results") .. " · " .. (if def then T(def.Name) else ""),
		Route = if def then def.Id else nil,
		Rows = rows,
		Mine = mineText,
		Detail = table.concat(detail, "   ·   "),
		Medal = medal,
		MedalText = medalText,
		Stamp = stamp,
		Xp = xp,
	})
end

local function onEvent(kind: string, payload: any)
	if kind == "Lobbies" then
		lobbies = if type(payload) == "table" then payload else {}
		boardDirty = true
		-- plus inscrit ? (salle fermée sans moi)
		if joined.Route and not mine.D then
			local lobby = lobbies[joined.Route]
			if not lobby then
				joined.Route, joined.RaceId = nil, nil
			end
		end
		refreshMenu()
	elseif kind == "Board" then
		board = if type(payload) == "table" then payload else {}
		boardDirty = true
		refreshMenu()
	elseif kind == "Pilots" then
		pilots = if type(payload) == "table" then payload else {}
		boardDirty = true
		refreshMenu()
	elseif kind == "Me" then
		if type(payload) == "table" then
			me = payload
			me.Ghost = if type(me.Ghost) == "table" then me.Ghost else {}
			me.Routes = if type(me.Routes) == "table" then me.Routes else {}
		end
		refreshMenu()
	elseif kind == "Joined" then
		joined.Route = payload.Route
		joined.RaceId = payload.RaceId
		table.clear(mine)
		if spectate then
			stopSpectate()
		end
		refreshMenu()
		local def = Config.RaceRoutesById[tostring(payload.Route)]
		toast(T("🏁 Signed up: %s", def and T(def.Name) or ""))
	elseif kind == "Left" then
		if joined.Route == payload.Route then
			joined.Route, joined.RaceId = nil, nil
			endMyRace()
		end
		refreshMenu()
	elseif kind == "Grid" then
		joined.Route = payload.Route
		joined.RaceId = payload.RaceId
		openMenu(false)
		RaceHud.Flash(T("On the grid: slot %d", tonumber(payload.Slot) or 1), GOLD)
		-- caméra de présentation jusqu'au GO
		camState = { Route = tostring(payload.Route), GoAt = tonumber(payload.GoAt) or now() + 6, Start = now(), Slot = tonumber(payload.Slot) or 1 }
	elseif kind == "State" then
		if type(payload) ~= "table" then
			return
		end
		local seenIds: { [string]: boolean } = {}
		for _, snap in ipairs(payload) do
			local id = tostring(snap.Route)
			local route = routeOf(id)
			if route then
				seenIds[id] = true
				local view = views[id]
				if view and view.Snap.Id ~= snap.Id then
					dropView(id)
					view = nil
				end
				if not view then
					view = { Snap = snap, At = os.clock(), ServerAt = now(), Route = route, Ai = {} }
					views[id] = view
				end
				view.Snap = snap
				view.At = os.clock()
				view.ServerAt = tonumber(snap.Now) or now()
			end
		end
		for id in pairs(views) do
			if not seenIds[id] then
				dropView(id)
			end
		end
	elseif kind == "Split" then
		if type(payload) == "table" then
			local route = joined.Route and routeOf(joined.Route)
			if payload.Delta ~= nil then
				RaceHud.Delta(tonumber(payload.Delta))
			end
			if route then
				local cp = route.Checkpoints[tonumber(payload.Index) or 0]
				if cp and not cp.Finish then
					RaceHud.Flash(T("Checkpoint %d/%d ✓", payload.Index, #route.Checkpoints))
				end
			end
		end
	elseif kind == "Lap" then
		if type(payload) == "table" then
			local route = joined.Route and routeOf(joined.Route)
			local lapNo = tonumber(payload.Lap) or 1
			RaceHud.Flash(T("Lap %d: %s", lapNo, fmt(tonumber(payload.Time) or 0)), MINT)
			if payload.Delta ~= nil then
				RaceHud.Delta(tonumber(payload.Delta), "👻 " .. T("Lap") .. " ")
			end
			if route and route.Closed and route.Laps > 1 and lapNo == route.Laps - 1 then
				RaceHud.Banner(T("🏁 FINAL LAP"))
			end
		end
	elseif kind == "Nitro" then
		RaceHud.Banner(T("🔥 NITRO!"), rgb(120, 200, 255))
	elseif kind == "Finished" then
		RaceHud.Countdown(T("FINISH!"), GOLD)
		RaceHud.Flash(fmt(tonumber(payload.Time) or 0), MINT)
	elseif kind == "Result" then
		if resultsShownFor ~= payload.RaceId then
			resultsShownFor = payload.RaceId
			endMyRace()
			joined.Route, joined.RaceId = nil, nil
			local ok, err = pcall(showResults, payload)
			if not ok then
				warn("[RaceClient] résultats : " .. tostring(err))
			end
		end
	elseif kind == "Reset" then
		mine.D = tonumber(payload.D) or mine.D
		local route = joined.Route and routeOf(joined.Route)
		if route and mine.D then
			mine.S = lineS(route, mine.D)
		end
		RaceHud.Flash(T("Back to the last checkpoint"), CYAN)
	elseif kind == "Toast" then
		toast(tostring(payload))
	end
end

----------------------------------------------------------------------
-- Cycle de vie
----------------------------------------------------------------------

function RaceClient.Start(options: any?)
	if started then
		RaceClient.Stop()
	end
	started = true
	opts = if type(options) == "table" then options else {}
	count = WorldLayout.PlotCount(Players.MaxPlayers)
	local f = Instance.new("Folder")
	f.Name = RaceClient.FOLDER_NAME
	f.Parent = workspace
	folder = f
	RaceHud.Build({
		Leave = function()
			send("leave")
		end,
		Reset = function()
			send("reset")
		end,
		Nitro = function()
			send("nitro")
		end,
		Menu = openMenu,
		Spectate = function(dir: number)
			if spectate then
				spectate.Index += dir
				spectate.Cam = nil
			end
		end,
		StopSpectate = stopSpectate,
		Rematch = function(routeId: string)
			if nearHQ() or isDriving() then
				send("join", routeId)
			else
				openMenu(true)
				RaceMenu.Select(routeId)
			end
		end,
	})
	local root = RaceHud.Root()
	if root then
		RaceMenu.Build(root, {
			Join = function(routeId: string, isJoined: boolean?)
				if isJoined then
					send("leave")
				else
					send("join", routeId)
				end
			end,
			Watch = startSpectate,
			Close = function()
				openMenu(false)
			end,
		})
	end
	table.insert(conns, Net.Event("RaceEvent").OnClientEvent:Connect(function(kind: any, payload: any)
		if type(kind) ~= "string" then
			return
		end
		local ok, err = pcall(onEvent, kind, payload)
		if not ok then
			warn("[RaceClient] " .. kind .. " : " .. tostring(err))
		end
	end))
	-- F = retour à la dernière porte ; Maj / N = nitro (pendant SA course)
	table.insert(conns, UserInputService.InputBegan:Connect(function(input: InputObject, processed: boolean)
		if processed then
			return
		end
		if joined.Route and mine.D ~= nil then
			if input.KeyCode == Enum.KeyCode.F then
				send("reset")
			elseif input.KeyCode == Enum.KeyCode.LeftShift or input.KeyCode == Enum.KeyCode.N or input.KeyCode == Enum.KeyCode.ButtonL1 then
				send("nitro")
			end
		elseif spectate then
			if input.KeyCode == Enum.KeyCode.Left or input.KeyCode == Enum.KeyCode.Q then
				spectate.Index -= 1
				spectate.Cam = nil
			elseif input.KeyCode == Enum.KeyCode.Right or input.KeyCode == Enum.KeyCode.E then
				spectate.Index += 1
				spectate.Cam = nil
			end
		end
	end))
	-- parcours calculés d'avance (une fois par nombre de parcelles, en cache)
	task.spawn(function()
		pcall(RaceRoutes.All, count)
	end)
	send("sync")
end

function RaceClient.Step(dt: number)
	if not started then
		return
	end
	clockT += dt
	streamClock += dt
	if streamClock >= 0.25 then
		streamClock = 0
		local ok, err = pcall(stream)
		if not ok then
			warn("[RaceClient] flux : " .. tostring(err))
		end
	end
	local p = focus()
	local t = now()
	for id, view in pairs(views) do
		-- feux et écrans du portique (synchronisés sur l'heure du serveur)
		local g = gantries[id]
		if g then
			local remain = (view.Snap.GoAt or 0) - t
			local stage = 0
			local phase = view.Snap.Phase
			if phase == "Grid" or phase == "Countdown" or phase == "Racing" then
				if remain > 3 then
					stage = 0
				elseif remain > 0 then
					stage = math.clamp(math.floor((3 - remain) / 0.6) + 1, 1, 5)
				elseif remain > -4 then
					stage = 6
				else
					stage = 7
				end
			end
			if g.Stage ~= stage then
				g.Stage = stage
				RaceProps.SetLights(g.Lights, if stage == 7 then 0 else stage)
				local def = view.Route.Def
				if stage == 0 then
					RaceProps.SetScreen(g.Screens, "🏁", nil, GOLD)
				elseif stage <= 5 then
					RaceProps.SetScreen(g.Screens, tostring(math.max(1, math.ceil(remain))), nil, rgb(255, 80, 80))
				elseif stage == 6 then
					RaceProps.SetScreen(g.Screens, "GO!", nil, rgb(110, 255, 140))
				else
					RaceProps.SetScreen(g.Screens, if def.Laps > 1 and view.Route.Closed then T("%d laps", def.Laps) else "🏁", nil, GOLD)
				end
			end
			if stage >= 1 and stage <= 5 then
				local n = tostring(math.max(1, math.ceil(remain)))
				if g.LastN ~= n then
					g.LastN = n
					RaceProps.SetScreen(g.Screens, n, nil, rgb(255, 80, 80))
				end
			end
		end
		local ok, err = pcall(stepAI, view, dt, p)
		if not ok then
			warn("[RaceClient] IA : " .. tostring(err))
			dropView(id)
		end
	end
	-- commissaires (drapeau qui flotte, de près)
	if p then
		for _, g in pairs(gantries) do
			if g.Marshal and (g.Pos - p).Magnitude < RaceClient.FX_RANGE then
				RaceProps.WaveFlag(g.Marshal, clockT)
			end
		end
		pcall(stepShowcase, dt, p)
	end
	local okMine, errMine = pcall(stepMine, dt)
	if not okMine then
		warn("[RaceClient] course : " .. tostring(errMine))
	end
	pcall(stepGridCamera)
	if spectate then
		local okS, errS = pcall(stepSpectate, dt)
		if not okS then
			warn("[RaceClient] spectateur : " .. tostring(errS))
		end
	end
	-- bouton 🏁 au volant (hors course), menu rafraîchi 2 fois / s
	local inRace = joined.Route ~= nil and mine.D ~= nil
	RaceHud.SetRaceButton(isDriving() and not inRace and not spectate)
	menuClock += dt
	if menuClock >= 0.5 then
		menuClock = 0
		refreshMenu()
		pcall(stepSpectateHud)
		local lobby = joined.Route and lobbies[joined.Route]
		if lobby and lobby.Phase == "Lobby" then
			local def = Config.RaceRoutesById[joined.Route]
			RaceHud.SetLobby({
				Text = T("%s %s · %d racers · start in %d s", def.Icon, T(def.Name), lobby.Count or 1, math.max(0, math.ceil((lobby.EndsAt or t) - t))),
			})
		else
			RaceHud.SetLobby(nil)
		end
	end
end

function RaceClient.Stop()
	if not started then
		return
	end
	started = false
	if joined.Route then
		send("leave")
	end
	if spectate then
		stopSpectate()
	end
	for _, c in ipairs(conns) do
		c:Disconnect()
	end
	table.clear(conns)
	for id in pairs(views) do
		dropView(id)
	end
	endMyRace()
	clearFlames()
	destroyHQ()
	for _, g in pairs(gantries) do
		g.Model:Destroy()
		if g.Finish then
			g.Finish:Destroy()
		end
	end
	table.clear(gantries)
	RaceMenu.Destroy()
	RaceHud.Destroy()
	if folder then
		folder:Destroy()
		folder = nil
	end
	joined.Route, joined.RaceId = nil, nil
	table.clear(lobbies)
end

function RaceClient.Debug(): any
	return {
		Views = views,
		Gantries = gantries,
		HQ = hq,
		Joined = joined,
		Mine = mine,
		Gates = gates,
		Chevrons = chevrons,
		Ghost = ghost,
		Flames = flames,
		Lobbies = function()
			return lobbies
		end,
		Board = function()
			return board
		end,
		Me = function()
			return me
		end,
		CamState = function()
			return camState
		end,
		GridCamera = gridCamera,
		Spectate = function()
			return spectate
		end,
		StartSpectate = startSpectate,
		StopSpectate = stopSpectate,
		SpectateTarget = spectateTarget,
		OnEvent = onEvent,
		Stream = stream,
		OpenMenu = openMenu,
		MenuData = menuData,
		Hud = RaceHud,
		Menu = RaceMenu,
		Count = function()
			return count
		end,
	}
end

return RaceClient
