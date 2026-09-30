--[[
	RaceClient (ModuleScript)
	Emplacement : ReplicatedStorage > Client > World > RaceClient

	🏁 Courses de rue, côté client (v10, RACE10). Le serveur (RaceService)
	décide de tout ; ici on MONTRE :
	  - le QG des courses (zone "RaceMeet") en flux : stand, comptoir avec
	    invite E "Courses de rue" (ouvre le menu), tableau des records mis à
	    jour en direct (meilleurs tours du serveur, par parcours) ;
	  - les portiques de départ (feux synchronisés sur l'heure du serveur :
	    5 rouges qui s'allument, puis VERT au GO), cases de grille, arche
	    d'arrivée du sprint, en flux (< 420 studs) ;
	  - les PILOTES IA : voiture CarModels ("Mid" + conducteur NPCModels de
	    près, "Low" plus loin, rien au-delà de 700 studs), roues qui tournent
	    et braquent, caisse qui s'incline, position lissée entre deux
	    instantanés du serveur (5 fois / s) ; boîte de collision SOLIDE
	    (groupe "DopamineCars", étiquette "DopamineMover" + ClientMover pour
	    PHYS10) : on ne traverse pas une IA ;
	  - SA course : arches des 3 prochaines portes (la prochaine brille),
	    HUD (place, tour, chrono, écart, meilleur tour, flèche + distance de
	    la porte, mini-carte), 3-2-1-GO, "mauvais sens", porte franchie,
	    touche F / bouton 🔄 = retour à la dernière porte, 🏳️ abandon ;
	    course de NUIT : la ville passe en nuit pendant la course ;
	  - RÉSULTATS : podium animé + récompense (RaceHud).
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

local LocalPlayer = Players.LocalPlayer

local RaceClient = {}

RaceClient.FOLDER_NAME = "RaceClient"
RaceClient.HQ_IN, RaceClient.HQ_OUT = 450, 520
RaceClient.GANTRY_IN, RaceClient.GANTRY_OUT = 420, 500
RaceClient.AI_MID, RaceClient.AI_FAR = 170, 700
RaceClient.MOVER_TAG = "DopamineMover"
RaceClient.CAR_GROUP = "DopamineCars"

type AICar = {
	Key: string,
	Kind: string,
	Model: Model?,
	Lod: number, -- 2 = Mid (+ pilote), 1 = Low, 0 = rien
	Rig: any?,
	Extra: { BasePart },
	ExtraOff: { CFrame },
	D: number,
	V: number,
	Lane: number,
	Spin: number,
	Steer: number,
	Heading: Vector3?,
	Pitch: number,
	Roll: number,
	Seen: number,
	Name: string,
	Color: string,
	Seed: number,
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
local me: { [string]: any } = { Rewarded = 0, Daily = 8, Best = {} }
local views: { [string]: RaceView } = {}
local hq: { Model: Model?, Parts: any?, Prompt: ProximityPrompt? } = {}
local gantries: { [string]: { Model: Model, Lights: any, Finish: Model? } } = {}
local joined: { Route: string?, RaceId: number? } = {}
local mine: { [string]: any } = {} -- ma course (HUD local)
local gates: { [number]: Model } = {}
local streamClock = 0
local hudClock = 0
local menuClock = 0
local lastCountdown: string? = nil
local nightForced = false
local boardDirty = true
local previews: { [string]: { { number } } } = {}
local resultsShownFor: number? = nil

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

local function isDriving(): boolean
	return myCarRoot() ~= nil
end

local function focus(): Vector3?
	local car = myCarRoot()
	if car then
		return car.Position
	end
	local root = rootPart()
	if root then
		return root.Position
	end
	local camera = workspace.CurrentCamera
	return camera and camera.CFrame.Position or nil
end

local function lineS(route: any, d: number): number
	if route.Closed then
		return d % route.Total
	end
	return route.StartS + d
end

----------------------------------------------------------------------
-- QG des courses : tableau des records
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
	local bg = Instance.new("Frame")
	bg.Name = "Bg"
	bg.BorderSizePixel = 0
	bg.BackgroundColor3 = Color3.fromRGB(22, 20, 38)
	bg.Size = UDim2.fromScale(1, 1)
	bg.Parent = sg
	local function text(parent: Instance, value: string, x: number, y: number, w: number, h: number, color: Color3, font: Enum.Font?, align: Enum.TextXAlignment?): TextLabel
		local l = Instance.new("TextLabel")
		l.BackgroundTransparency = 1
		l.Text = value
		l.TextScaled = true
		l.Font = font or Enum.Font.GothamBold
		l.TextColor3 = color
		l.TextXAlignment = align or Enum.TextXAlignment.Left
		l.Position = UDim2.fromScale(x, y)
		l.Size = UDim2.fromScale(w, h)
		l.Parent = parent
		return l
	end
	text(bg, T("🏆 Best laps on this server"), 0.03, 0.02, 0.94, 0.12, Color3.fromRGB(255, 214, 90), Enum.Font.GothamBlack, Enum.TextXAlignment.Center)
	local list = (Config.Race and Config.Race.Routes) or {}
	for k, def in ipairs(list) do
		local col = (k - 1) % 2
		local row = (k - 1) // 2
		local x0 = 0.03 + col * 0.49
		local y0 = 0.17 + row * 0.41
		local card = Instance.new("Frame")
		card.Name = "Route_" .. def.Id
		card.BorderSizePixel = 0
		card.BackgroundColor3 = Color3.fromRGB(40, 34, 62)
		card.Position = UDim2.fromScale(x0, y0)
		card.Size = UDim2.fromScale(0.46, 0.38)
		card.Parent = bg
		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0, 12)
		corner.Parent = card
		text(card, def.Icon .. " " .. T(def.Name), 0.05, 0.03, 0.9, 0.24, Color3.fromRGB(255, 255, 255), Enum.Font.GothamBlack)
		local rows = board[def.Id] or {}
		for i = 1, 3 do
			local r = rows[i]
			local medal = ({ "🥇", "🥈", "🥉" })[i]
			local y = 0.3 + (i - 1) * 0.22
			if r then
				text(card, medal .. " " .. tostring(r.Name), 0.05, y, 0.58, 0.2, Color3.fromRGB(236, 226, 255))
				text(card, RaceRules.FormatTime(r.Time), 0.62, y, 0.34, 0.2, Color3.fromRGB(130, 236, 190), Enum.Font.GothamBold, Enum.TextXAlignment.Right)
			elseif i == 1 then
				text(card, T("No record yet: be the first!"), 0.05, y, 0.9, 0.2, Color3.fromRGB(190, 176, 214), Enum.Font.Gotham)
			end
		end
	end
	-- état des salles d'attente (écran du comptoir)
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

----------------------------------------------------------------------
-- Menu
----------------------------------------------------------------------

local function statusOf(id: string): (string, Color3, boolean)
	local lobby = lobbies[id]
	if not lobby then
		return T("Open: start a race!"), Color3.fromRGB(130, 236, 190), true
	end
	if lobby.Phase == "Lobby" then
		local left = math.max(0, math.ceil((lobby.EndsAt or 0) - now()))
		return T("%d waiting · starts in %d s", lobby.Count or 0, left), Color3.fromRGB(255, 214, 90), true
	elseif lobby.Phase == "Results" then
		return T("Finishing…"), Color3.fromRGB(214, 196, 236), false
	end
	return T("Race in progress…"), Color3.fromRGB(255, 140, 150), false
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
	for k = 0, n - 1 do
		local x, z = RaceRules.PointAt(line, line.Total * k / n)
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

local function refreshMenu()
	if not RaceHud.IsMenuOpen() then
		return
	end
	local cards = {}
	local can = nearHQ() or isDriving()
	for _, def in ipairs((Config.Race and Config.Race.Routes) or {}) do
		local route = routeOf(def.Id)
		if route then
			local status, color, open = statusOf(def.Id)
			local km = route.RaceDistance * 0.28 / 1000
			local rows = board[def.Id] or {}
			local rec = rows[1]
			local myBest = me.Best and me.Best[def.Id]
			local lapsText = if route.Closed and route.Laps > 1 then T("%d laps", route.Laps) elseif route.Closed then T("1 lap") else T("Sprint")
			local isMine = joined.Route == def.Id
			table.insert(cards, {
				Id = def.Id,
				Icon = def.Icon,
				Name = T(def.Name),
				Info = string.format("%s · %.1f km\n%s", lapsText, km, T(def.Desc or "")),
				Record = if rec then string.format("🏆 %s %s", tostring(rec.Name), RaceRules.FormatTime(rec.Time)) else T("🏆 No record yet"),
				Best = if myBest then T("⏱️ Your best: %s", RaceRules.FormatTime(myBest)) else "",
				Status = if isMine then T("✅ You are signed up!") else status,
				StatusColor = if isMine then Color3.fromRGB(130, 236, 190) else color,
				CanJoin = open and (can or isMine),
				Joined = isMine,
				Preview = preview(route),
				PreviewKey = route.Id .. ":" .. count,
				Closed = route.Closed,
			})
		end
	end
	local r = Config.Race and Config.Race.Rewards or {}
	local secs = r.Seconds or { 120, 80, 55 }
	RaceHud.SetMenu(true, cards, {
		Sub = T("Win Dopamine: 🥇 %d s · 🥈 %d s · 🥉 %d s of production · rewarded today: %d/%d", secs[1], secs[2], secs[3], me.Rewarded or 0, me.Daily or 8),
		Foot = if can then T("AI racers fill the grid. Pass every checkpoint in order, stay on the road. F = back to the last checkpoint.")
			else T("Sign up at the 🏁 Race HQ (on foot, E) or from your car."),
	})
end

local function openMenu(open: boolean)
	if open then
		RaceHud.SetMenu(true, {}, nil)
		refreshMenu()
		send("sync")
	else
		RaceHud.SetMenu(false)
	end
end

----------------------------------------------------------------------
-- Décor en flux : QG + portiques
----------------------------------------------------------------------

local function destroyHQ()
	if hq.Model then
		hq.Model:Destroy()
	end
	hq.Model, hq.Parts, hq.Prompt = nil, nil, nil
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
	fillBoard()
end

local function buildGantry(route: any): { Model: Model, Lights: any, Finish: Model? }
	local f = folder :: Folder
	local cf = RaceRoutes.CFrameAtD(route, 0)
	local model, info = RaceProps.BuildGantry(cf, math.max(route.Width, 16) + 2, route.Def.Icon .. " " .. T(route.Def.Name), false)
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
	return { Model = model, Lights = info.Lights, Finish = finishModel }
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
-- Pilotes IA
----------------------------------------------------------------------

local function destroyAI(ai: AICar)
	if ai.Model then
		ai.Model:Destroy()
	end
	ai.Model = nil
	ai.Rig = nil
	ai.Lod = 0
	table.clear(ai.Extra)
	table.clear(ai.ExtraOff)
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
	if lod >= 2 then
		local okRig, rig = pcall(CarModels.WheelRig, model)
		if okRig then
			ai.Rig = rig
		end
		-- pilote (casque de course : couleur de la voiture)
		local okNpc, npc = pcall(NPCModels.Build, "jogger", { Seed = ai.Seed, Solid = false, Look = false, Name = "Driver" })
		if okNpc and npc then
			local seatCF = model:GetAttribute("SeatCF")
			local seat = if typeof(seatCF) == "CFrame" then seatCF else CFrame.new(-0.9, 1.2, 0.4)
			pcall(NPCModels.SetSeated, npc, 1.05)
			local pivot = CFrame.new(0, -500, 0)
			local npcCF = pivot * seat * CFrame.new(0, -1.05, 0)
			pcall(NPCModels.Place, npc, npcCF)
			pcall(NPCModels.Animate, npc, "sit", 0)
			npc.Parent = model
			for _, d in ipairs(npc:GetDescendants()) do
				if d:IsA("BasePart") then
					d.CanCollide = false
					d.CanQuery = false
					d.CanTouch = false
					table.insert(ai.Extra, d)
					table.insert(ai.ExtraOff, pivot:ToObjectSpace(d.CFrame))
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
	-- braquage + roulis selon le changement de cap
	local turn = math.asin(math.clamp(prev:Cross(heading).Y, -1, 1)) / math.max(dt, 1 / 120)
	ai.Heading = heading
	ai.Steer += (math.clamp(-turn * 0.5, -0.5, 0.5) - ai.Steer) * math.clamp(dt * 6, 0, 1)
	ai.Roll += (math.clamp(turn * ai.V * 0.0025, -0.06, 0.06) - ai.Roll) * math.clamp(dt * 4, 0, 1)
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
	local radius = tonumber(model:GetAttribute("WheelRadius")) or 1
	ai.Spin = (ai.Spin + ai.V * dt / math.max(radius, 0.3)) % (math.pi * 2)
	if ai.Rig then
		local okPose, bparts, frames = pcall(CarModels.PoseRig, ai.Rig, pivot, ai.Spin, ai.Steer, nil)
		if okPose then
			local allParts = table.clone(bparts)
			local allFrames = table.clone(frames)
			for i, part in ipairs(ai.Extra) do
				table.insert(allParts, part)
				table.insert(allFrames, pivot * ai.ExtraOff[i])
			end
			workspace:BulkMoveTo(allParts, allFrames, Enum.BulkMoveMode.FireCFrameChanged)
			return
		end
	end
	model:PivotTo(pivot)
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
					Extra = {},
					ExtraOff = {},
					D = row.D,
					V = row.V,
					Lane = row.L or 0,
					Spin = 0,
					Steer = 0,
					Heading = nil,
					Pitch = 0,
					Roll = 0,
					Seen = t,
					Name = tostring(row.N or ""),
					Color = tostring(row.Col or ""),
					Seed = #tostring(row.K) * 131 + (snap.Id or 1) * 17,
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
			if p then
				local s = lineS(route, ai.D)
				local x, z = RaceRules.PointAt(route.Line, s)
				local world = RaceRoutes.ToWorld(x, z, 0)
				local d = (Vector3.new(world.X - p.X, 0, world.Z - p.Z)).Magnitude
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
			end
		end
	end
	for key, ai in pairs(view.Ai) do
		if not seen[key] then
			destroyAI(ai)
			view.Ai[key] = nil
		end
	end
end

local function dropView(id: string)
	local view = views[id]
	if view then
		for _, ai in pairs(view.Ai) do
			destroyAI(ai)
		end
		views[id] = nil
	end
end

----------------------------------------------------------------------
-- Ma course : portes, HUD
----------------------------------------------------------------------

local function clearGates()
	for _, g in pairs(gates) do
		g:Destroy()
	end
	table.clear(gates)
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

local function endMyRace()
	clearGates()
	table.clear(mine)
	lastCountdown = nil
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
			model:Destroy()
			gates[k] = nil
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
					-- l'arrivée d'une boucle : c'est le portique ; l'arche marque juste la ligne
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

-- Ma progression locale (même calcul que le serveur, pour un HUD fluide)
local function localProgress(route: any): (number?, number, Vector3?)
	local car = myCarRoot()
	if not car then
		return nil, 0, nil
	end
	local o = WorldLayout.Origin()
	local x, z = car.Position.X - o.X, car.Position.Z - o.Z
	local hint = mine.S or lineS(route, mine.D or 0)
	local s, lat = RaceRules.Project(route.Line, x, z, hint, 220)
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
	local _ = lat
	return d, car.AssemblyLinearVelocity.Magnitude, car.CFrame.LookVector
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
			RaceHud.Countdown(T("GO!"), Color3.fromRGB(110, 255, 140))
		else
			RaceHud.Countdown(cd, Color3.fromRGB(255, 90, 90))
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
	if mine.Next and nextIndex > mine.Next and nextIndex - 1 >= 1 then
		local cp = route.Checkpoints[nextIndex - 1]
		if cp and not cp.Finish then
			RaceHud.Flash(T("Checkpoint %d/%d ✓", nextIndex - 1, #route.Checkpoints))
		end
	end
	mine.Next = nextIndex
	if running then
		syncGates(route, nextIndex)
	else
		clearGates()
	end
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
	local place, ahead, behind = 1, nil, nil
	for i, r in ipairs(ranked) do
		if r.Me then
			place = i
			ahead = ranked[i - 1]
			behind = ranked[i + 1]
		end
	end
	local elapsed = if myRow.F and myRow.T then myRow.T elseif snap.Phase == "Racing" then math.max(0, t - (snap.GoAt or t)) else 0
	local gapText = ""
	local refSpeed = math.max(speed, 25)
	if ahead and not myRow.F then
		gapText = T("%s ahead: +%.1f s", tostring(ahead.Row.N), math.max(0, (ahead.Progress - myD) / refSpeed))
	elseif behind and not myRow.F then
		gapText = T("Lead: %.1f s", math.max(0, (myD - behind.Progress) / refSpeed))
	elseif myRow.F then
		gapText = T("🏁 Finished!")
	end
	-- flèche vers la prochaine porte (relative à la caméra)
	local cpText, arrow, dist = nil, 0, 0
	local cp = route.Checkpoints[math.clamp(nextIndex, 1, #route.Checkpoints)]
	local camera = workspace.CurrentCamera
	local car = myCarRoot()
	if running and cp and camera and car then
		local target = RaceRoutes.ToWorld(cp.X, cp.Z, 0)
		local to = Vector3.new(target.X - car.Position.X, 0, target.Z - car.Position.Z)
		dist = to.Magnitude
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
	RaceHud.SetRace({
		Place = place,
		Count = #snap.Racers,
		Lap = math.min(lap, route.Laps),
		Laps = route.Laps,
		Time = RaceRules.FormatTime(elapsed),
		Gap = gapText,
		Best = if myRow.B then T("Best lap: %s", RaceRules.FormatTime(myRow.B)) else "",
		Cp = cpText,
		Arrow = arrow,
		Wrong = wrong,
		Running = running,
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
			local d = r.Progress
			local x, z = RaceRules.PointAt(route.Line, lineS(route, d))
			local color = if r.Me then Color3.fromRGB(255, 214, 90) elseif r.Row.AI then Color3.fromRGB(214, 196, 236) else Color3.fromRGB(90, 220, 240)
			table.insert(dots, { 0.5 + (x - box[1]) / box[3], 0.5 + (z - box[2]) / box[3], color, r.Me })
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
	local others = {}
	for _, row in ipairs(payload.Rows or {}) do
		local timeText = if row.Finished and row.Time then RaceRules.FormatTime(row.Time) elseif row.Dnf then T("Out") else T("Did not finish")
		table.insert(rows, { Place = row.Place, Name = row.Name, UserId = row.UserId, AI = row.AI, TimeText = timeText })
		if (row.Place or 0) > 3 then
			table.insert(others, string.format("%d. %s  %s", row.Place, tostring(row.Name), timeText))
		end
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
	RaceHud.ShowResults({
		Title = (def and def.Icon or "🏁") .. " " .. T("Results") .. " · " .. (if def then T(def.Name) else ""),
		Rows = rows,
		Others = table.concat(others, "   "),
		Mine = mineText,
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
	elseif kind == "Me" then
		if type(payload) == "table" then
			me = payload
		end
		refreshMenu()
	elseif kind == "Joined" then
		joined.Route = payload.Route
		joined.RaceId = payload.RaceId
		table.clear(mine)
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
		RaceHud.SetMenu(false)
		RaceHud.Flash(T("On the grid: slot %d", tonumber(payload.Slot) or 1), Color3.fromRGB(255, 214, 90))
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
	elseif kind == "Finished" then
		RaceHud.Countdown(T("FINISH!"), Color3.fromRGB(255, 214, 90))
		RaceHud.Flash(RaceRules.FormatTime(tonumber(payload.Time) or 0), Color3.fromRGB(130, 236, 190))
	elseif kind == "Result" then
		if resultsShownFor ~= payload.RaceId then
			resultsShownFor = payload.RaceId
			endMyRace()
			joined.Route, joined.RaceId = nil, nil
			pcall(showResults, payload)
		end
	elseif kind == "Reset" then
		mine.D = tonumber(payload.D) or mine.D
		local route = joined.Route and routeOf(joined.Route)
		if route and mine.D then
			mine.S = lineS(route, mine.D)
		end
		RaceHud.Flash(T("Back to the last checkpoint"), Color3.fromRGB(90, 220, 240))
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
		Join = function(routeId: string, isJoined: boolean?)
			if isJoined then
				send("leave")
			else
				send("join", routeId)
			end
		end,
		Leave = function()
			send("leave")
		end,
		Reset = function()
			send("reset")
		end,
		Menu = openMenu,
	})
	table.insert(conns, Net.Event("RaceEvent").OnClientEvent:Connect(function(kind: any, payload: any)
		if type(kind) ~= "string" then
			return
		end
		local ok, err = pcall(onEvent, kind, payload)
		if not ok then
			warn("[RaceClient] " .. kind .. " : " .. tostring(err))
		end
	end))
	-- F = retour à la dernière porte (pendant SA course)
	table.insert(conns, UserInputService.InputBegan:Connect(function(input: InputObject, processed: boolean)
		if processed then
			return
		end
		if input.KeyCode == Enum.KeyCode.F and joined.Route and mine.D ~= nil then
			send("reset")
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
		-- feux du portique (synchronisés sur l'heure du serveur)
		local g = gantries[id]
		if g then
			local remain = (view.Snap.GoAt or 0) - t
			local stage = 0
			if view.Snap.Phase == "Grid" or view.Snap.Phase == "Countdown" or view.Snap.Phase == "Racing" then
				if remain > 3 then
					stage = 0
				elseif remain > 0 then
					stage = math.clamp(math.floor((3 - remain) / 0.6) + 1, 1, 5)
				elseif remain > -4 then
					stage = 6
				end
			end
			if g.Stage ~= stage then
				g.Stage = stage
				RaceProps.SetLights(g.Lights, stage)
			end
		end
		local ok, err = pcall(stepAI, view, dt, p)
		if not ok then
			warn("[RaceClient] IA : " .. tostring(err))
			dropView(id)
		end
	end
	local okMine, errMine = pcall(stepMine, dt)
	if not okMine then
		warn("[RaceClient] course : " .. tostring(errMine))
	end
	-- bouton 🏁 au volant (hors course), menu rafraîchi 2 fois / s
	local inRace = joined.Route ~= nil and mine.D ~= nil
	RaceHud.SetRaceButton(isDriving() and not inRace)
	menuClock += dt
	if menuClock >= 0.5 then
		menuClock = 0
		refreshMenu()
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
	for _, c in ipairs(conns) do
		c:Disconnect()
	end
	table.clear(conns)
	for id in pairs(views) do
		dropView(id)
	end
	endMyRace()
	destroyHQ()
	for _, g in pairs(gantries) do
		g.Model:Destroy()
		if g.Finish then
			g.Finish:Destroy()
		end
	end
	table.clear(gantries)
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
		Lobbies = function()
			return lobbies
		end,
		Board = function()
			return board
		end,
		OnEvent = onEvent,
		Stream = stream,
		OpenMenu = openMenu,
		Hud = RaceHud,
		Count = function()
			return count
		end,
	}
end

return RaceClient
