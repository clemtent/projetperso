--[[
	BankClient (ModuleScript)
	Emplacement : ReplicatedStorage > Client > World > BankClient

	🏦 Côté client de la Banque Dopamine (v11, BANK11), démarré par
	TownClient en ville (Start / Step / Stop) :
	  - construit la banque EN FLUX (BankBuild) : silhouette lointaine
	    toujours là (~30 pièces), banque complète (intérieur, PNJ) quand la
	    caméra est à moins de FULL_IN studs (retirée au-delà de FULL_OUT) ;
	  - invites E : 4 guichets et 4 distributeurs (compte), bijoutier
	    (boutique de luxe 💎), salle des coffres, "Plan du casse" (quand
	    aucun casse n'est ouvert : prochain casse dans m:ss) ;
	  - écrans vivants : COURS DU DIAMANT (selon TA production), file
	    d'attente "n° appelé -> guichet", tableau bleu du plan du casse
	    (équipe, compte à rebours), boîtier d'alarme ;
	  - CASSE de la banque (d'après HeistClient : liste des casses) : porte
	    du personnel ouverte après le piratage, perceuse sur la porte ronde,
	    porte ronde qui ROULE après le perçage, piles de butin qui
	    disparaissent, alarme (gyrophares, lumière rouge douce) ;
	  - démarre HeistClient (HUD + mini-jeux de TOUS les casses, train
	    compris) et LuxuryWear (objets de luxe portés par tout le monde) ;
	  - interface BankUI (pastille 💎 + fenêtre).
	Remotes : RemoteFunction "Bank" (action, arg) -> (ok, message, état),
	RemoteEvent "BankEvent" (S -> C : "State" | "Toast" | "Heist").

	API : BankClient.Start({ Toast = fn }) ; BankClient.Step(dt) ;
	      BankClient.Stop() ; BankClient.Open(tab?) ; BankClient.Debug()
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Locale = require(ReplicatedStorage.Shared.Locale)
local WorldLayout = require(ReplicatedStorage.Shared.WorldLayout)
local BankLayout = require(ReplicatedStorage.Shared.BankLayout)
local HeistRules = require(ReplicatedStorage.Shared.HeistRules)
local NumberFormatter = require(ReplicatedStorage.Shared.NumberFormatter)
local BankBuild = require(script.Parent.BankBuild)
local BankUI = require(script.Parent.BankUI)
local HeistClient = require(script.Parent.HeistClient)
local LuxuryWear = require(script.Parent.LuxuryWear)

local BankClient = {}

BankClient.FOLDER_NAME = "DopamineBankFolder"
local FULL_IN = 330 -- (studs) banque complète en dessous...
local FULL_OUT = 400 -- ... retirée au-dessus (hystérésis)
local ANIM_R = 170 -- animations (caméras, PNJ, drapeaux) en dessous

local started = false
local opts: { [string]: any } = {}
local conns: { RBXScriptConnection } = {}
local folder: Folder? = nil
local count = 8
local bankCF = CFrame.identity
local low: Model? = nil
local bank: any = nil
local prompts: { ProximityPrompt } = {}
local planPrompt: ProximityPrompt? = nil
local streamClock = 0
local screenClock = 0
local nearClock = 0
local remoteFn: RemoteFunction? = nil
local nextHeistAt = 0
local heistView = { Staff = 0, Vault = 0, StaffGoal = 0, VaultGoal = 0 }
local queueNumber = 41
local queueAt = 0
local unsubscribe: (() -> ())? = nil

local function T(text: string, ...): string
	return Locale.T(text, ...)
end

local function toast(text: string)
	local fn = opts.Toast
	if type(fn) == "function" and type(text) == "string" and text ~= "" then
		pcall(fn, text)
	end
end

local function now(): number
	local ok, t = pcall(function()
		return workspace:GetServerTimeNow()
	end)
	return ok and t or os.clock()
end

local function eye(): Vector3
	local camera = workspace.CurrentCamera
	return camera and camera.CFrame.Position or Vector3.zero
end

local function rootPos(): Vector3?
	local character = Players.LocalPlayer.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if root and root:IsA("BasePart") then
		return root.Position
	end
	return nil
end

-- Demande au serveur -> (ok, message) ; l'état revient avec la réponse
local function ask(action: string, arg: any): (boolean, string?)
	local rf = remoteFn
	if not rf then
		return false, T("Loading...")
	end
	local ok, a, b, c = pcall(function()
		return rf:InvokeServer(action, arg)
	end)
	if not ok then
		return false, nil
	end
	if type(c) == "table" then
		BankUI.SetState(c)
	end
	return a == true, if type(b) == "string" then b else nil
end

----------------------------------------------------------------------
-- Invites
----------------------------------------------------------------------

local function addPrompt(host: BasePart?, action: string, object: string, onTrigger: () -> (), range: number?): ProximityPrompt?
	if not host then
		return nil
	end
	local p = Instance.new("ProximityPrompt")
	p.Name = "BankPrompt"
	p.ActionText = action
	p.ObjectText = object
	p.KeyboardKeyCode = Enum.KeyCode.E
	p.HoldDuration = 0
	p.MaxActivationDistance = range or 9
	p.RequiresLineOfSight = false
	p.Parent = host
	table.insert(conns, p.Triggered:Connect(onTrigger))
	table.insert(prompts, p)
	return p
end

local function wirePrompts(b: any)
	for i, spot in ipairs(b.Spots.Counters or {}) do
		addPrompt(spot, T("My account"), "🏦 " .. T("Counter %d", i), function()
			BankUI.Open("Account")
		end)
	end
	for _, spot in ipairs(b.Spots.ATMs or {}) do
		addPrompt(spot, T("Use the ATM"), "💳 " .. T("ATM"), function()
			BankUI.Open("Account")
		end, 7)
	end
	addPrompt(b.Spots.Luxury, T("Luxury boutique"), "💎 " .. T("Jeweller"), function()
		BankUI.Open("Luxury")
	end)
	addPrompt(b.Spots.Deposit, T("My vault"), "🔒 " .. T("Safe deposit boxes"), function()
		BankUI.Open("Account")
	end)
	planPrompt = addPrompt(b.Spots.Lobby, T("Heist plan"), "🕶️ " .. T("Bank heist"), function()
		local left = math.max(0, nextHeistAt - now())
		if left > 0 then
			toast("🕶️ " .. T("The vault is being refilled: next heist in %s", HeistRules.Clock(left)))
		else
			toast("🕶️ " .. T("The heist opens in a moment…"))
		end
		BankUI.Open("Heists")
	end, 12)
end

----------------------------------------------------------------------
-- Écrans
----------------------------------------------------------------------

local function textIn(parent: Instance, name: string, text: string, x: number, y: number, w: number, h: number, color: Color3, font: Enum.Font?): TextLabel
	local l = parent:FindFirstChild(name) :: TextLabel?
	if not l then
		local nl = Instance.new("TextLabel")
		nl.Name = name
		nl.BackgroundTransparency = 1
		nl.TextScaled = true
		nl.Font = font or Enum.Font.GothamBold
		nl.Position = UDim2.fromScale(x, y)
		nl.Size = UDim2.fromScale(w, h)
		nl.Parent = parent
		l = nl
	end
	local lbl = l :: TextLabel
	lbl.TextColor3 = color
	lbl.Text = text
	return lbl
end

local function drawScreens()
	if not bank then
		return
	end
	local st = BankUI.GetState() or {}
	local gold = Color3.fromRGB(236, 190, 84)
	local white = Color3.fromRGB(240, 244, 255)
	local mint = Color3.fromRGB(96, 222, 160)
	-- cours du diamant (selon la production du joueur) + petit graphique qui bouge
	if bank.Rates then
		textIn(bank.Rates, "Title", "💎 " .. T("DIAMOND RATE"), 0.04, 0.04, 0.92, 0.2, gold, Enum.Font.GothamBlack)
		textIn(bank.Rates, "Rate", T("1 💎 = %s Dopamine", NumberFormatter.Format(tonumber(st.ExchangeRate) or 0)), 0.04, 0.28, 0.92, 0.22, white)
		textIn(bank.Rates, "Left", T("Exchange today: %d 💎 left", tonumber(st.ExchangeLeft) or (Config.Bank.Exchange.DailyMax or 15)), 0.04, 0.52, 0.92, 0.14, mint, Enum.Font.Gotham)
		local spark = bank.Rates:FindFirstChild("Spark")
		if not spark then
			spark = Instance.new("Frame")
			spark.Name = "Spark"
			spark.BackgroundTransparency = 1
			spark.Position = UDim2.fromScale(0.06, 0.7)
			spark.Size = UDim2.fromScale(0.88, 0.24)
			spark.Parent = bank.Rates
			for i = 1, 16 do
				local b = Instance.new("Frame")
				b.Name = "Bar" .. i
				b.BorderSizePixel = 0
				b.BackgroundColor3 = mint
				b.AnchorPoint = Vector2.new(0, 1)
				b.Size = UDim2.fromScale(1 / 16 - 0.012, 0.5)
				b.Position = UDim2.fromScale((i - 1) / 16, 1)
				b.Parent = spark
			end
		end
		local t = os.clock()
		for i = 1, 16 do
			local b = spark:FindFirstChild("Bar" .. i) :: Frame?
			if b then
				local v = 0.35 + 0.3 * math.sin(i * 0.7 + t * 0.6) + 0.2 * math.sin(i * 1.9 + t * 0.25)
				b.Size = UDim2.fromScale(1 / 16 - 0.012, math.clamp(v, 0.08, 1))
			end
		end
	end
	-- file d'attente : n° appelé -> guichet
	if bank.Queue then
		local t = os.clock()
		if t - queueAt > 9 then
			queueAt = t
			queueNumber = queueNumber % 99 + 1
		end
		textIn(bank.Queue, "Title", "🎫 " .. T("NOW SERVING"), 0.04, 0.04, 0.92, 0.2, gold, Enum.Font.GothamBlack)
		textIn(bank.Queue, "Number", string.format("%03d", queueNumber), 0.04, 0.26, 0.5, 0.5, white, Enum.Font.Code)
		textIn(bank.Queue, "Counter", "→ " .. T("Counter %d", queueNumber % BankLayout.COUNTERS + 1), 0.54, 0.34, 0.42, 0.3, mint)
		textIn(bank.Queue, "Hint", T("Press E at a counter to open your account"), 0.04, 0.8, 0.92, 0.14, white, Enum.Font.Gotham)
	end
	-- tableau du plan du casse
	if bank.Board then
		local s = HeistClient.ByKind("Bank")
		local line1, line2
		local t = now()
		if s and s.State == "Lobby" then
			line1 = "🕶️ " .. T("CREW WANTED")
			line2 = if s.LobbyEndsAt then T("%d/%d · start in %s", s.Crew or 0, s.MaxCrew or 4, HeistRules.Clock(s.LobbyEndsAt - t)) else T("Press E to join (%d/%d)", s.Crew or 0, s.MaxCrew or 4)
		elseif s and s.State == "Running" then
			line1 = "🚨 " .. T("HEIST IN PROGRESS")
			line2 = HeistRules.Clock((s.EndsAt or t) - t)
		else
			line1 = "🔒 " .. T("VAULT REFILLING")
			line2 = T("Next heist in %s", HeistRules.Clock(math.max(0, nextHeistAt - t)))
		end
		textIn(bank.Board, "Head", T("HEIST PLAN"), 0.05, 0.03, 0.9, 0.14, Color3.fromRGB(220, 236, 255), Enum.Font.GothamBlack)
		-- schéma de la banque (traits blancs)
		local plan = bank.Board:FindFirstChild("Plan")
		if not plan then
			plan = Instance.new("Frame")
			plan.Name = "Plan"
			plan.BackgroundTransparency = 1
			plan.Position = UDim2.fromScale(0.1, 0.2)
			plan.Size = UDim2.fromScale(0.8, 0.45)
			plan.Parent = bank.Board
			local function line(x: number, y: number, w: number, h: number)
				local f = Instance.new("Frame")
				f.BorderSizePixel = 0
				f.BackgroundColor3 = Color3.fromRGB(220, 236, 255)
				f.Position = UDim2.fromScale(x, y)
				f.Size = UDim2.fromScale(w, h)
				f.Parent = plan
			end
			line(0, 0, 1, 0.03)
			line(0, 0.97, 1, 0.03)
			line(0, 0, 0.02, 1)
			line(0.98, 0, 0.02, 1)
			line(0, 0.62, 0.42, 0.03)
			line(0.58, 0.62, 0.42, 0.03)
			line(0.3, 0.62, 0.02, 0.38)
			line(0.68, 0.62, 0.02, 0.38)
			for i, spec in ipairs({ { "💻", 0.9, 0.45 }, { "🔩", 0.5, 0.62 }, { "💰", 0.5, 0.82 }, { "🏃", 0.08, 0.2 } }) do
				local l = Instance.new("TextLabel")
				l.Name = "Mark" .. i
				l.BackgroundTransparency = 1
				l.TextScaled = true
				l.AnchorPoint = Vector2.new(0.5, 0.5)
				l.Position = UDim2.fromScale(spec[2], spec[3])
				l.Size = UDim2.fromScale(0.16, 0.3)
				l.Text = spec[1]
				l.Parent = plan
			end
		end
		textIn(bank.Board, "Line1", line1, 0.05, 0.68, 0.9, 0.13, Color3.fromRGB(255, 220, 120), Enum.Font.GothamBlack)
		textIn(bank.Board, "Line2", line2, 0.05, 0.83, 0.9, 0.12, Color3.fromRGB(240, 244, 255))
	end
	-- boîtier d'alarme
	if bank.AlarmPanel then
		local s = HeistClient.ByKind("Bank")
		local hacked = false
		for _, id in ipairs(s and s.Done or {}) do
			if id == "hack" then
				hacked = true
			end
		end
		textIn(bank.AlarmPanel, "State", if hacked then "🔓" else "🔒", 0.1, 0.1, 0.8, 0.5, Color3.new(1, 1, 1))
		textIn(bank.AlarmPanel, "Code", if hacked then "ERR" else "****", 0.1, 0.62, 0.8, 0.28, if hacked then Color3.fromRGB(255, 80, 80) else Color3.fromRGB(96, 222, 160), Enum.Font.Code)
	end
	-- texte des distributeurs : solde
	for _, l in ipairs(bank.Screens or {}) do
		l.Text = string.format("💎 %d · 🔒 %d", tonumber(st.Wallet) or 0, tonumber(st.Vault) or 0)
	end
end

----------------------------------------------------------------------
-- Flux (construction / retrait)
----------------------------------------------------------------------

local function destroyFull()
	for _, p in ipairs(prompts) do
		p:Destroy()
	end
	table.clear(prompts)
	planPrompt = nil
	if bank and bank.Model then
		bank.Model:Destroy()
	end
	bank = nil
	if low then
		low.Parent = folder
	end
end

local function buildFull()
	local f = folder
	if not f then
		return
	end
	local ok, result = pcall(BankBuild.Build, f, bankCF)
	if not ok then
		warn("[BankClient] construction : " .. tostring(result))
		return
	end
	bank = result
	wirePrompts(bank)
	if low then
		low.Parent = nil
	end
	-- état du casse appliqué tout de suite (portes, butin)
	heistView.Staff, heistView.Vault = heistView.StaffGoal, heistView.VaultGoal
	BankBuild.SetDoor(bank.StaffDoor, heistView.Staff)
	BankBuild.SetDoor(bank.Vault, heistView.Vault)
	drawScreens()
end

local function stream()
	local d = (eye() - bankCF.Position).Magnitude
	if not bank and d < FULL_IN then
		buildFull()
	elseif bank and d > FULL_OUT then
		destroyFull()
	end
end

----------------------------------------------------------------------
-- Casse de la banque : décor
----------------------------------------------------------------------

local function stepHeist(dt: number)
	local s = HeistClient.ByKind("Bank")
	local done = {}
	for _, id in ipairs(s and s.Done or {}) do
		done[id] = true
	end
	local running = s ~= nil and s.State == "Running"
	local active = running or (s ~= nil and s.State == "Done" and s.Success ~= nil)
	heistView.StaffGoal = (active and done.hack) and 1 or 0
	heistView.VaultGoal = (active and done.drill) and 1 or 0
	if not bank then
		return
	end
	-- portes : ouverture / fermeture douces (3 s la porte ronde)
	local function approach(cur: number, goal: number, speed: number): number
		if cur < goal then
			return math.min(goal, cur + dt * speed)
		end
		return math.max(goal, cur - dt * speed)
	end
	heistView.Staff = approach(heistView.Staff, heistView.StaffGoal, 1.2)
	heistView.Vault = approach(heistView.Vault, heistView.VaultGoal, 0.33)
	BankBuild.SetDoor(bank.StaffDoor, heistView.Staff)
	BankBuild.SetDoor(bank.Vault, heistView.Vault)
	-- perceuse pendant l'étape "drill"
	local drilling = running and s ~= nil and s.Step == "drill"
	local t = os.clock()
	local mine = HeistClient.Mine()
	local progress = if mine and mine.Step and mine.Step.Kind == "Drill" then (tonumber(mine.Progress) or 0) else (drilling and 0.5 or 0)
	BankBuild.SetDrill(bank, drilling, progress, drilling and s ~= nil and s.Jammed == true, t)
	-- butin pris
	local taken = {}
	if active then
		for _, i in ipairs(s and s.Taken or {}) do
			taken[i] = true
		end
	end
	for i = 1, #bank.Piles do
		local want = taken[i] == true
		if bank.PileState == nil then
			bank.PileState = {}
		end
		if bank.PileState[i] ~= want then
			bank.PileState[i] = want
			BankBuild.SetPileTaken(bank, i, want)
		end
	end
	-- alarme
	BankBuild.SetAlarm(bank, running and s ~= nil and s.Alarm == true, t)
	-- invite "plan du casse" : seulement quand aucun casse n'est ouvert
	if planPrompt then
		planPrompt.Enabled = not (s and (s.State == "Lobby" or s.State == "Running"))
	end
end

----------------------------------------------------------------------
-- Événements
----------------------------------------------------------------------

local function onEvent(kind: string, payload: any)
	if kind == "State" then
		BankUI.SetState(payload)
		if type(payload) == "table" and type(payload.NextHeistAt) == "number" then
			nextHeistAt = payload.NextHeistAt
		end
	elseif kind == "Toast" and type(payload) == "string" then
		toast(payload)
	elseif kind == "Heist" and type(payload) == "table" then
		nextHeistAt = tonumber(payload.NextAt) or nextHeistAt
	end
end

----------------------------------------------------------------------
-- API
----------------------------------------------------------------------

function BankClient.Start(options: any?)
	if started then
		BankClient.Stop()
	end
	started = true
	opts = if type(options) == "table" then options else {}
	count = WorldLayout.PlotCount(Players.MaxPlayers)
	bankCF = BankLayout.CFrame(count)
	local f = Instance.new("Folder")
	f.Name = BankClient.FOLDER_NAME
	f.Parent = workspace
	folder = f
	local okLow, m = pcall(BankBuild.BuildLow, f, bankCF)
	if okLow then
		low = m
	end
	BankUI.Build({
		Action = function(action: string, arg: any)
			return ask(action, arg)
		end,
	})
	pcall(HeistClient.Start, { Toast = toast })
	task.spawn(function()
		local remotes = ReplicatedStorage:WaitForChild("Remotes", 30)
		if not remotes or not started then
			return
		end
		local ev = remotes:WaitForChild("BankEvent", 30)
		local rf = remotes:WaitForChild("Bank", 30)
		if not started then
			return
		end
		if rf and rf:IsA("RemoteFunction") then
			remoteFn = rf
		end
		if ev and ev:IsA("RemoteEvent") then
			table.insert(conns, ev.OnClientEvent:Connect(function(kind: any, payload: any)
				if type(kind) == "string" then
					local ok, err = pcall(onEvent, kind, payload)
					if not ok then
						warn("[BankClient] " .. kind .. " : " .. tostring(err))
					end
				end
			end))
		end
		ask("state", nil)
	end)
	stream()
end

function BankClient.Step(dt: number)
	if not started then
		return
	end
	streamClock += dt
	if streamClock >= 0.5 then
		streamClock = 0
		local ok, err = pcall(stream)
		if not ok then
			warn("[BankClient] flux : " .. tostring(err))
		end
	end
	pcall(HeistClient.Step, dt)
	pcall(LuxuryWear.Step, dt)
	local okH, errH = pcall(stepHeist, dt)
	if not okH then
		warn("[BankClient] casse : " .. tostring(errH))
	end
	if bank and (eye() - bankCF.Position).Magnitude < ANIM_R then
		pcall(BankBuild.Animate, bank, os.clock(), dt)
	end
	screenClock += dt
	if screenClock >= 0.5 then
		screenClock = 0
		pcall(drawScreens)
		local left = math.max(0, nextHeistAt - now())
		local s = HeistClient.ByKind("Bank")
		local text
		if s and s.State == "Lobby" then
			text = "🕶️ " .. T("A bank heist is open: meet the crew behind the bank!")
		elseif s and s.State == "Running" then
			text = "🚨 " .. T("A bank heist is in progress!")
		else
			text = "⏳ " .. T("Next bank heist in %s", HeistRules.Clock(left))
		end
		BankUI.SetNextHeist(text)
	end
	nearClock += dt
	if nearClock >= 0.4 then
		nearClock = 0
		local p = rootPos()
		BankUI.SetNear(p ~= nil and BankLayout.Inside(count, p, 10))
	end
end

function BankClient.Stop()
	if not started then
		return
	end
	started = false
	for _, c in ipairs(conns) do
		c:Disconnect()
	end
	table.clear(conns)
	destroyFull()
	if low then
		low:Destroy()
		low = nil
	end
	pcall(HeistClient.Stop)
	pcall(LuxuryWear.Clear)
	BankUI.Destroy()
	if unsubscribe then
		unsubscribe()
		unsubscribe = nil
	end
	if folder then
		folder:Destroy()
		folder = nil
	end
	remoteFn = nil
end

function BankClient.Open(tab: string?)
	BankUI.Open(tab)
end

function BankClient.Debug(): any
	return {
		Bank = function()
			return bank
		end,
		Low = function()
			return low
		end,
		Prompts = prompts,
		Stream = stream,
		OnEvent = onEvent,
		HeistView = heistView,
		StepHeist = stepHeist,
		DrawScreens = drawScreens,
		Ask = ask,
		SetRemote = function(rf: any)
			remoteFn = rf
		end,
		CFrame = function()
			return bankCF
		end,
	}
end

return BankClient
