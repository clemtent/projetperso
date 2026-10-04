--[[
	HeistClient (ModuleScript)
	Emplacement : ReplicatedStorage > Client > World > HeistClient

	🕶️ Côté client GÉNÉRIQUE des casses (v11, BANK11) : banque ET convoi du
	train (TRAIN11 n'a rien à faire ici : tout vient de HeistKit). Démarré
	par BankClient. Le serveur décide de tout (HeistKit) ; ici on DESSINE et
	on DEMANDE :
	  - MARQUEURS : point de rendez-vous de chaque casse ouvert (anneau doré
	    au sol + étiquette "E : rejoindre l'équipe"), objectif de l'étape
	    en cours (colonne de lumière + étiquette toujours visible avec la
	    distance), planque (camionnette "Planque" + colonne verte), sacs
	    tombés (à ramasser) ;
	  - INVITES E : rejoindre / lancer, pirater, forcer (pied-de-biche),
	    débloquer la perceuse, remplir son sac (maintenir E), ramasser ;
	  - SACS DE BUTIN sur le dos de TOUS les joueurs qui en portent
	    (attribut "HeistBag" du personnage) ;
	  - HUD "HeistGui" : nom du casse, étape n/N, consigne, chrono (rouge
	    pendant l'alarme), barre de progression, équipe (sacs), boutons
	    Lancer / Quitter / S'enfuir, vignette rouge de l'ALARME ;
	  - MINI-JEUX : PIRATAGE (mémoriser puis recopier un code de symboles
	    sur un ordinateur portable), PIED-DE-BICHE (taper vite), perceuse
	    (barre + "Débloquer !"), RÉSULTAT (carte animée : part du butin,
	    Dopamine, 💎).
	Aucune arme, aucun son, aucune vraie lumière.

	API :
	  HeistClient.Start(options?)  { Toast = fn(text) }
	  HeistClient.Step(dt) ; HeistClient.Stop()
	  HeistClient.List() -> { résumés } ; HeistClient.Summary(id) ; HeistClient.Mine() -> état de MON casse ?
	  HeistClient.ByKind(kind) -> résumé ouvert de ce genre ?
	  HeistClient.OnChanged(fn) : fn(list) à chaque nouvelle liste
	  HeistClient.Debug()
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")

local Client = script.Parent.Parent
local Theme = require(Client.Theme)
local UIUtil = require(Client.UIUtil)
local Config = require(ReplicatedStorage.Shared.Config)
local Locale = require(ReplicatedStorage.Shared.Locale)
local HeistRules = require(ReplicatedStorage.Shared.HeistRules)
local NumberFormatter = require(ReplicatedStorage.Shared.NumberFormatter)

local HeistClient = {}

HeistClient.GUI_NAME = "HeistGui"
HeistClient.FOLDER_NAME = "DopamineHeists"

local rgb = Color3.fromRGB
local M = Enum.Material
local NAVY = rgb(18, 22, 40)
local NAVY2 = rgb(30, 36, 62)
local GOLD = rgb(236, 190, 84)
local WHITE = rgb(255, 255, 255)
local SOFT = rgb(196, 204, 230)
local MINT = rgb(96, 222, 160)
local RED = rgb(240, 70, 80)
local SACK = rgb(150, 112, 66)

local started = false
local opts: { [string]: any } = {}
local conns: { RBXScriptConnection } = {}
local listeners: { (any) -> () } = {}
local folder: Folder? = nil
local gui: ScreenGui? = nil
local ui: { [string]: any } = {}
local list: { any } = {}
local byId: { [string]: any } = {}
local mine: any = nil
local mineAt = 0
local lobbyMarks: { [string]: any } = {}
local target: { [string]: any } = {}
local spotPrompts: { [number]: any } = {}
local droppedMarks: { [number]: any } = {}
local bags: { [Model]: Model } = {}
local hack: any = nil
local taps = 0
local tapClock = 0
local bagClock = 0
local hudClock = 0
local remoteFn: RemoteFunction? = nil
local resultToken = 0

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

local function rootPos(): Vector3?
	local character = Players.LocalPlayer.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if root and root:IsA("BasePart") then
		return root.Position
	end
	return nil
end

-- Demande au serveur -> (ok, message, extra)
local function ask(action: string, id: string?, arg: any): (boolean, any, any)
	local rf = remoteFn
	if not rf then
		return false, nil, nil
	end
	local ok, a, b, c = pcall(function()
		return rf:InvokeServer(action, id, arg)
	end)
	if not ok then
		return false, nil, nil
	end
	if type(b) == "string" and b ~= "" and action ~= "sync" then
		toast(b)
	end
	return a == true, b, c
end

----------------------------------------------------------------------
-- Pièces du monde
----------------------------------------------------------------------

local function part(parent: Instance, name: string, size: Vector3, cf: CFrame, color: Color3, material: Enum.Material?, shape: string?): BasePart
	local p = Instance.new("Part")
	p.Name = name
	if shape == "Cyl" then
		p.Shape = Enum.PartType.Cylinder
	elseif shape == "Ball" then
		p.Shape = Enum.PartType.Ball
	end
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Material = material or M.SmoothPlastic
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Parent = parent
	return p
end

local function billboard(host: BasePart, text: string, color: Color3?, onTop: boolean?, maxDistance: number?, height: number?): TextLabel
	local bb = Instance.new("BillboardGui")
	bb.Name = "Tag"
	bb.Size = UDim2.fromOffset(260, 54)
	bb.StudsOffsetWorldSpace = Vector3.new(0, height or 4, 0)
	bb.AlwaysOnTop = onTop == true
	bb.MaxDistance = maxDistance or 220
	bb.LightInfluence = 0
	bb.Parent = host
	local bg = Instance.new("Frame")
	bg.Name = "Bg"
	bg.BackgroundColor3 = NAVY
	bg.BackgroundTransparency = 0.15
	bg.Size = UDim2.fromScale(1, 1)
	bg.Parent = bb
	UIUtil.Corner(bg, UDim.new(0, 12))
	UIUtil.Stroke(bg, color or GOLD, 2, 0.2)
	local l = Instance.new("TextLabel")
	l.Name = "Text"
	l.BackgroundTransparency = 1
	l.Size = UDim2.new(1, -12, 1, -6)
	l.Position = UDim2.fromOffset(6, 3)
	l.TextScaled = true
	l.Font = Theme.Fonts.Title
	l.TextColor3 = WHITE
	l.Text = text
	l.Parent = bg
	return l
end

local function prompt(host: BasePart, action: string, object: string, hold: number?, range: number?): ProximityPrompt
	local p = Instance.new("ProximityPrompt")
	p.Name = "HeistPrompt"
	p.ActionText = action
	p.ObjectText = object
	p.KeyboardKeyCode = Enum.KeyCode.E
	p.HoldDuration = hold or 0
	p.MaxActivationDistance = range or 10
	p.RequiresLineOfSight = false
	p.Parent = host
	return p
end

-- Colonne de lumière (objectif) : Neon très transparent, sans vraie lumière
local function beacon(parent: Instance, pos: Vector3, color: Color3): BasePart
	local b = part(parent, "Beacon", Vector3.new(60, 1.6, 1.6), CFrame.new(pos + Vector3.new(0, 30, 0)) * CFrame.Angles(0, 0, math.pi / 2), color, M.Neon, "Cyl")
	b.Transparency = 0.72
	return b
end

----------------------------------------------------------------------
-- Sacs sur le dos (tous les joueurs)
----------------------------------------------------------------------

local function buildBag(character: Model, value: number): Model?
	local torso = character:FindFirstChild("UpperTorso") or character:FindFirstChild("Torso")
	if not torso or not torso:IsA("BasePart") then
		return nil
	end
	local m = Instance.new("Model")
	m.Name = "HeistBagModel"
	local size = 1.6 + math.min(value, 6) * 0.12
	local base = torso.CFrame * CFrame.new(0, 0.1, torso.Size.Z / 2 + size * 0.42)
	local sack = part(m, "Sack", Vector3.new(size * 1.1, size * 1.25, size * 0.9), base, SACK, M.Fabric)
	local mesh = Instance.new("SpecialMesh")
	mesh.MeshType = Enum.MeshType.Sphere
	mesh.Parent = sack
	part(m, "Knot", Vector3.new(0.5, 0.5, 0.5), base * CFrame.new(0, size * 0.66, 0), rgb(120, 86, 50), M.Fabric, "Ball")
	part(m, "Tie", Vector3.new(0.9, 0.18, 0.9), base * CFrame.new(0, size * 0.52, 0), rgb(96, 70, 42), M.Fabric)
	local strap = part(m, "Strap", Vector3.new(0.2, 0.2, size * 0.9), base * CFrame.new(0, size * 0.3, -size * 0.45), rgb(96, 70, 42), M.Fabric)
	local _ = strap
	local tag = part(m, "Emblem", Vector3.new(size * 0.7, size * 0.7, 0.05), base * CFrame.new(0, -0.05, size * 0.46), WHITE)
	tag.Transparency = 1
	local sg = Instance.new("SurfaceGui")
	sg.Face = Enum.NormalId.Back
	sg.LightInfluence = 0.6
	sg.CanvasSize = Vector2.new(100, 100)
	sg.Parent = tag
	local l = Instance.new("TextLabel")
	l.BackgroundTransparency = 1
	l.Size = UDim2.fromScale(1, 1)
	l.TextScaled = true
	l.Text = "💎"
	l.Parent = sg
	for _, p in ipairs(m:GetChildren()) do
		if p:IsA("BasePart") then
			p.Anchored = false
			p.Massless = true
			local w = Instance.new("WeldConstraint")
			w.Part0 = torso
			w.Part1 = p
			w.Parent = p
		end
	end
	m.Parent = character
	return m
end

local function stepBags()
	local seen = {}
	for _, p in ipairs(Players:GetPlayers()) do
		local character = p.Character
		if character and character.Parent then
			local v = tonumber(character:GetAttribute("HeistBag")) or 0
			if v > 0 then
				seen[character] = true
				local existing = bags[character]
				if not existing or not existing.Parent or existing:GetAttribute("Value") ~= v then
					if existing then
						existing:Destroy()
					end
					local m = buildBag(character, v)
					if m then
						m:SetAttribute("Value", v)
						bags[character] = m
					end
				end
			end
		end
	end
	for character, m in pairs(bags) do
		if not seen[character] then
			m:Destroy()
			bags[character] = nil
		end
	end
end

----------------------------------------------------------------------
-- HUD
----------------------------------------------------------------------

local function label(props: { [string]: any }): TextLabel
	local l = Instance.new("TextLabel")
	l.BackgroundTransparency = 1
	l.BorderSizePixel = 0
	l.Font = props.Font or Theme.Fonts.Title
	l.TextColor3 = props.Color or WHITE
	l.TextSize = props.TextSize or 18
	l.TextWrapped = props.Wrap == true
	l.TextXAlignment = props.XAlign or Enum.TextXAlignment.Center
	l.Text = props.Text or ""
	l.Name = props.Name or "Label"
	l.Size = props.Size or UDim2.fromScale(1, 1)
	l.Position = props.Position or UDim2.new()
	l.AnchorPoint = props.AnchorPoint or Vector2.zero
	l.ZIndex = props.ZIndex or 3
	if props.Scaled then
		l.TextScaled = true
		UIUtil.Create("UITextSizeConstraint", { MaxTextSize = props.TextSize or 18, MinTextSize = 8, Parent = l })
	end
	l.Parent = props.Parent
	return l
end

local function box(props: { [string]: any }): Frame
	local f = Instance.new("Frame")
	f.BorderSizePixel = 0
	f.Name = props.Name or "Box"
	f.BackgroundColor3 = props.Color or NAVY2
	f.BackgroundTransparency = props.Transparency or 0
	f.Size = props.Size or UDim2.fromScale(1, 1)
	f.Position = props.Position or UDim2.new()
	f.AnchorPoint = props.AnchorPoint or Vector2.zero
	f.ZIndex = props.ZIndex or 2
	f.Visible = props.Visible ~= false
	if props.Radius then
		UIUtil.Corner(f, props.Radius)
	end
	if props.Stroke then
		UIUtil.Stroke(f, props.Stroke, props.StrokeThickness or 2, props.StrokeTransparency)
	end
	f.Parent = props.Parent
	return f
end

local function button(props: { [string]: any }): TextButton
	local b = Instance.new("TextButton")
	b.Name = props.Name or "Button"
	b.AutoButtonColor = true
	b.BorderSizePixel = 0
	b.BackgroundColor3 = props.Color or GOLD
	b.Size = props.Size or UDim2.fromOffset(120, 40)
	b.Position = props.Position or UDim2.new()
	b.AnchorPoint = props.AnchorPoint or Vector2.zero
	b.Font = Theme.Fonts.Title
	b.TextColor3 = props.TextColor or NAVY
	b.TextSize = props.TextSize or 17
	b.TextWrapped = true
	b.Text = props.Text or ""
	b.ZIndex = props.ZIndex or 4
	b.Visible = props.Visible ~= false
	UIUtil.Corner(b, props.Radius or UDim.new(0, 12))
	UIUtil.Stroke(b, WHITE, 2, 0.6)
	b.Parent = props.Parent
	pcall(UIUtil.AnimateButton, b)
	if props.OnClick then
		table.insert(conns, b.Activated:Connect(props.OnClick))
	end
	return b
end

local hideHack: () -> ()
local showCrowbar: (boolean) -> ()

local function buildHud()
	local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")
	local old = playerGui:FindFirstChild(HeistClient.GUI_NAME)
	if old then
		old:Destroy()
	end
	local screen = Instance.new("ScreenGui")
	screen.Name = HeistClient.GUI_NAME
	screen.ResetOnSpawn = false
	screen.ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets
	screen.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	screen.DisplayOrder = 23
	screen.Parent = playerGui
	gui = screen
	local root = UIUtil.Create("Frame", { Name = "Root", BackgroundTransparency = 1, Size = UDim2.fromOffset(1100, 620), Parent = screen })
	ui.Root = root
	ui.Scale = UIUtil.Create("UIScale", { Parent = root })
	-- vignette rouge (alarme)
	local vig = box({ Name = "AlarmVignette", Parent = root, Color = RED, Transparency = 1, Size = UDim2.fromScale(1, 1), ZIndex = 1 })
	vig.Active = false
	local grad = UIUtil.Create("UIGradient", { Parent = vig, Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.2), NumberSequenceKeypoint.new(0.18, 1), NumberSequenceKeypoint.new(0.82, 1), NumberSequenceKeypoint.new(1, 0.2) }) })
	local _ = grad
	ui.Vignette = vig
	-- panneau du casse (haut, centre droit : sous le compteur de Dopamine)
	local panel = box({ Name = "HeistPanel", Parent = root, Color = NAVY, Transparency = 0.06, Size = UDim2.fromOffset(420, 132), AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 118), Radius = UDim.new(0, 16), Stroke = GOLD, StrokeTransparency = 0.35, Visible = false, ZIndex = 5 })
	ui.Panel = panel
	ui.Title = label({ Name = "Title", Parent = panel, Text = "", TextSize = 18, Color = GOLD, XAlign = Enum.TextXAlignment.Left, Size = UDim2.new(1, -120, 0, 24), Position = UDim2.fromOffset(14, 8), ZIndex = 6, Scaled = true })
	ui.Timer = label({ Name = "Timer", Parent = panel, Text = "", TextSize = 24, Color = WHITE, XAlign = Enum.TextXAlignment.Right, Size = UDim2.fromOffset(100, 28), AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -14, 0, 6), ZIndex = 6 })
	ui.Step = label({ Name = "Step", Parent = panel, Text = "", TextSize = 16, Color = WHITE, XAlign = Enum.TextXAlignment.Left, Size = UDim2.new(1, -28, 0, 22), Position = UDim2.fromOffset(14, 34), ZIndex = 6, Scaled = true })
	local bar = box({ Name = "Bar", Parent = panel, Color = NAVY2, Size = UDim2.new(1, -28, 0, 10), Position = UDim2.fromOffset(14, 62), Radius = UDim.new(1, 0), ZIndex = 6 })
	ui.Bar = bar
	ui.BarFill = box({ Name = "Fill", Parent = bar, Color = MINT, Size = UDim2.new(0, 0, 1, 0), Radius = UDim.new(1, 0), ZIndex = 7 })
	ui.Crew = label({ Name = "Crew", Parent = panel, Text = "", TextSize = 14, Color = SOFT, Font = Theme.Fonts.Body, XAlign = Enum.TextXAlignment.Left, Size = UDim2.new(1, -28, 0, 18), Position = UDim2.fromOffset(14, 78), ZIndex = 6, Scaled = true })
	local row = box({ Name = "Buttons", Parent = panel, Transparency = 1, Size = UDim2.new(1, -28, 0, 30), Position = UDim2.fromOffset(14, 98), ZIndex = 6 })
	UIUtil.Create("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 8), HorizontalAlignment = Enum.HorizontalAlignment.Right, Parent = row })
	ui.StartBtn = button({ Name = "StartHeist", Parent = row, Text = "▶ " .. T("Start the heist"), Color = MINT, Size = UDim2.fromOffset(150, 30), TextSize = 14, ZIndex = 7, OnClick = function()
		if mine then
			ask("start", mine.Id, nil)
		end
	end })
	ui.EscapeBtn = button({ Name = "Escape", Parent = row, Text = "🏃 " .. T("Run!"), Color = GOLD, Size = UDim2.fromOffset(110, 30), TextSize = 14, ZIndex = 7, OnClick = function()
		if mine then
			ask("escape", mine.Id, nil)
		end
	end })
	ui.UnjamBtn = button({ Name = "Unjam", Parent = row, Text = "🔧 " .. T("Unjam!"), Color = RED, TextColor = WHITE, Size = UDim2.fromOffset(110, 30), TextSize = 14, ZIndex = 7, OnClick = function()
		if mine then
			ask("unjam", mine.Id, nil)
		end
	end })
	ui.LeaveBtn = button({ Name = "LeaveHeist", Parent = row, Text = T("Leave"), Color = NAVY2, TextColor = WHITE, Size = UDim2.fromOffset(80, 30), TextSize = 14, ZIndex = 7, OnClick = function()
		if mine then
			ask("leave", mine.Id, nil)
			mine = nil
			hideHack()
			showCrowbar(false)
		end
	end })

	-- MINI-JEU : PIRATAGE (ordinateur portable)
	local laptop = box({ Name = "HackLaptop", Parent = root, Color = rgb(44, 48, 60), Size = UDim2.fromOffset(470, 330), AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.55), Radius = UDim.new(0, 18), Stroke = rgb(120, 126, 140), Visible = false, ZIndex = 20 })
	laptop.Active = true
	pcall(UIUtil.SinkClicks, laptop)
	ui.Laptop = laptop
	local screenF = box({ Name = "Screen", Parent = laptop, Color = rgb(10, 22, 18), Size = UDim2.new(1, -28, 1, -72), Position = UDim2.fromOffset(14, 14), Radius = UDim.new(0, 10), ZIndex = 21 })
	label({ Name = "Prompt", Parent = screenF, Text = "> " .. T("HACK THE ALARM BOX"), TextSize = 16, Color = MINT, Font = Enum.Font.Code, XAlign = Enum.TextXAlignment.Left, Size = UDim2.new(1, -20, 0, 22), Position = UDim2.fromOffset(10, 8), ZIndex = 22 })
	ui.HackInfo = label({ Name = "Info", Parent = screenF, Text = "", TextSize = 15, Color = SOFT, Font = Enum.Font.Code, XAlign = Enum.TextXAlignment.Left, Size = UDim2.new(1, -20, 0, 20), Position = UDim2.fromOffset(10, 30), ZIndex = 22 })
	local codeRow = box({ Name = "Code", Parent = screenF, Transparency = 1, Size = UDim2.new(1, -20, 0, 56), Position = UDim2.fromOffset(10, 58), ZIndex = 22 })
	UIUtil.Create("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 8), HorizontalAlignment = Enum.HorizontalAlignment.Center, Parent = codeRow })
	ui.CodeRow = codeRow
	ui.ShowBar = box({ Name = "ShowBar", Parent = screenF, Color = MINT, Size = UDim2.new(1, -20, 0, 6), Position = UDim2.fromOffset(10, 122), Radius = UDim.new(1, 0), ZIndex = 22 })
	local pad = box({ Name = "Pad", Parent = screenF, Transparency = 1, Size = UDim2.new(1, -20, 0, 56), Position = UDim2.fromOffset(10, 140), ZIndex = 22 })
	UIUtil.Create("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 8), HorizontalAlignment = Enum.HorizontalAlignment.Center, Parent = pad })
	ui.Pad = pad
	for i, sym in ipairs(HeistRules.SYMBOLS) do
		local b = button({ Name = "Sym_" .. i, Parent = pad, Text = sym, Color = rgb(30, 60, 50), TextColor = WHITE, TextSize = 28, Size = UDim2.fromOffset(60, 56), ZIndex = 23, OnClick = function()
			if hack and hack.Input then
				table.insert(hack.Entered, i)
				hack.Dirty = true
			end
		end })
		b.LayoutOrder = i
	end
	button({ Name = "HackClear", Parent = laptop, Text = "⌫ " .. T("Clear"), Color = rgb(70, 74, 88), TextColor = WHITE, Size = UDim2.fromOffset(130, 40), Position = UDim2.new(0, 14, 1, -52), TextSize = 15, ZIndex = 22, OnClick = function()
		if hack then
			table.clear(hack.Entered)
			hack.Dirty = true
		end
	end })
	button({ Name = "HackClose", Parent = laptop, Text = T("Close"), Color = rgb(70, 74, 88), TextColor = WHITE, Size = UDim2.fromOffset(110, 40), AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -14, 1, -52), TextSize = 15, ZIndex = 22, OnClick = function()
		hideHack()
	end })

	-- MINI-JEU : PIED-DE-BICHE (taper vite)
	local crow = button({ Name = "CrowbarTap", Parent = root, Text = "💥 " .. T("TAP! (E)"), Color = GOLD, Size = UDim2.fromOffset(220, 90), AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -110), TextSize = 26, Visible = false, ZIndex = 20, OnClick = function()
		taps += 1
	end })
	ui.Crowbar = crow
	ui.CrowScale = UIUtil.Create("UIScale", { Parent = crow })

	-- RÉSULTAT
	local res = box({ Name = "HeistResult", Parent = root, Color = NAVY, Size = UDim2.fromOffset(460, 260), AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.48), Radius = UDim.new(0, 22), Stroke = GOLD, StrokeThickness = 3, Visible = false, ZIndex = 30 })
	ui.Result = res
	ui.ResScale = UIUtil.Create("UIScale", { Parent = res })
	ui.ResTitle = label({ Name = "Title", Parent = res, Text = "", TextSize = 32, Color = GOLD, Size = UDim2.new(1, -20, 0, 44), Position = UDim2.fromOffset(10, 14), ZIndex = 31, Scaled = true })
	ui.ResFill = label({ Name = "Fill", Parent = res, Text = "", TextSize = 18, Color = SOFT, Font = Theme.Fonts.Body, Size = UDim2.new(1, -20, 0, 24), Position = UDim2.fromOffset(10, 64), ZIndex = 31 })
	ui.ResDop = label({ Name = "Dopamine", Parent = res, Text = "", TextSize = 26, Color = rgb(255, 120, 180), Size = UDim2.new(1, -20, 0, 34), Position = UDim2.fromOffset(10, 100), ZIndex = 31, Scaled = true })
	ui.ResDia = label({ Name = "Diamonds", Parent = res, Text = "", TextSize = 26, Color = rgb(150, 230, 255), Size = UDim2.new(1, -20, 0, 34), Position = UDim2.fromOffset(10, 138), ZIndex = 31, Scaled = true })
	ui.ResNote = label({ Name = "Note", Parent = res, Text = "", TextSize = 14, Color = SOFT, Font = Theme.Fonts.Body, Wrap = true, Size = UDim2.new(1, -20, 0, 36), Position = UDim2.fromOffset(10, 176), ZIndex = 31 })
	button({ Name = "ResultOk", Parent = res, Text = T("Great!"), Color = GOLD, Size = UDim2.fromOffset(140, 36), AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -12), ZIndex = 32, OnClick = function()
		res.Visible = false
	end })

	local function layout()
		local size = screen.AbsoluteSize
		if size.X < 10 or size.Y < 10 then
			return
		end
		local scale = math.clamp(math.min(size.X / 1100, size.Y / 620), 0.45, 1.3)
		ui.Scale.Scale = scale
		root.Size = UDim2.fromOffset(size.X / scale, size.Y / scale)
		local touch = UserInputService.TouchEnabled and not UserInputService.MouseEnabled
		local phone = touch and math.min(size.X, size.Y) < 500
		-- téléphone : panneau un peu plus haut, mini-jeux réduits pour tenir
		panel.Position = UDim2.new(0.5, 0, 0, if phone then 92 else 118)
		local rh = size.Y / scale
		local k = math.min(1, (rh - 20) / 360)
		for _, f in ipairs({ laptop }) do
			local s = f:FindFirstChildOfClass("UIScale") or UIUtil.Create("UIScale", { Parent = f })
			s.Scale = k
		end
		ui.ResScale.Scale = math.min(1, (rh - 20) / 280)
	end
	table.insert(conns, screen:GetPropertyChangedSignal("AbsoluteSize"):Connect(layout))
	layout()
end

----------------------------------------------------------------------
-- Mini-jeux
----------------------------------------------------------------------

local function symTile(parent: Instance, sym: string, i: number, color: Color3)
	local f = box({ Name = "Tile", Parent = parent, Color = color, Size = UDim2.fromOffset(56, 56), Radius = UDim.new(0, 10), ZIndex = 23 })
	f.LayoutOrder = i
	label({ Name = "Sym", Parent = f, Text = sym, TextSize = 30, ZIndex = 24 })
end

local function drawHack()
	if not hack or not ui.CodeRow then
		return
	end
	for _, c in ipairs(ui.CodeRow:GetChildren()) do
		if c:IsA("Frame") then
			c:Destroy()
		end
	end
	local n = #hack.Code
	if not hack.Input then
		for i, s in ipairs(hack.Code) do
			symTile(ui.CodeRow, HeistRules.SYMBOLS[s] or "?", i, rgb(30, 90, 70))
		end
		ui.HackInfo.Text = T("Memorise the code…")
	else
		for i = 1, n do
			local s = hack.Entered[i]
			symTile(ui.CodeRow, s and HeistRules.SYMBOLS[s] or "_", i, s and rgb(30, 90, 70) or rgb(20, 40, 34))
		end
		ui.HackInfo.Text = T("Type the code: %d/%d", #hack.Entered, n)
	end
	ui.Pad.Visible = hack.Input
	hack.Dirty = false
end

local function startHack(code: { number }, show: number)
	hack = hack or { Entered = {} }
	hack.Code = code
	hack.Entered = {}
	hack.Input = false
	hack.ShowUntil = os.clock() + (show or 2.6)
	hack.Show = show or 2.6
	hack.Sending = false
	ui.Laptop.Visible = true
	drawHack()
end

hideHack = function()
	hack = nil
	if ui.Laptop then
		ui.Laptop.Visible = false
	end
end

showCrowbar = function(v: boolean)
	if ui.Crowbar then
		ui.Crowbar.Visible = v
	end
end

local function stepHack()
	if not hack then
		return
	end
	if not hack.Input then
		local left = hack.ShowUntil - os.clock()
		ui.ShowBar.Size = UDim2.new(math.clamp(left / hack.Show, 0, 1), -20, 0, 6)
		if left <= 0 then
			hack.Input = true
			drawHack()
		end
		return
	end
	ui.ShowBar.Size = UDim2.new(0, 0, 0, 6)
	if hack.Dirty then
		drawHack()
	end
	if #hack.Entered >= #hack.Code and not hack.Sending and mine then
		hack.Sending = true
		local answer = table.clone(hack.Entered)
		local id = mine.Id
		task.spawn(function()
			local ok, message, extra = ask("hackAnswer", id, answer)
			if ok then
				hideHack()
			elseif type(extra) == "table" and type(extra.Code) == "table" then
				startHack(extra.Code, extra.Show)
			elseif hack then
				-- trop rapide : on renvoie dans un instant
				task.wait(0.6)
				if hack then
					hack.Sending = false
				end
			end
			local _ = message
		end)
	end
end

----------------------------------------------------------------------
-- Marqueurs du monde
----------------------------------------------------------------------

local function clearTarget()
	if target.Model then
		target.Model:Destroy()
	end
	table.clear(target)
	for _, sp in pairs(spotPrompts) do
		if sp.Part then
			sp.Part:Destroy()
		end
	end
	table.clear(spotPrompts)
end

local function clearDropped()
	for _, d in pairs(droppedMarks) do
		d.Part:Destroy()
	end
	table.clear(droppedMarks)
end

-- Van "Planque" (cartoon) à la livraison
local function hideoutVan(parent: Instance, pos: Vector3)
	local cf = CFrame.new(pos) * CFrame.new(-5, 0, 0)
	local body = rgb(40, 44, 54)
	part(parent, "VanBody", Vector3.new(6.4, 5.4, 12), cf * CFrame.new(0, 3.3, 0), body, M.Metal)
	part(parent, "VanCab", Vector3.new(6.2, 2.4, 3.2), cf * CFrame.new(0, 5.2, -4.6), rgb(150, 200, 230), M.Glass).Transparency = 0.3
	for _, x in ipairs({ -2.9, 2.9 }) do
		for _, z in ipairs({ -3.8, 3.8 }) do
			part(parent, "VanWheel", Vector3.new(0.9, 2.2, 2.2), cf * CFrame.new(x, 1.1, z), rgb(30, 30, 34), M.SmoothPlastic, "Cyl")
		end
	end
	local sign = part(parent, "VanSign", Vector3.new(0.1, 1.6, 6), cf * CFrame.new(3.26, 3.8, 0), WHITE)
	sign.Transparency = 1
	local sg = Instance.new("SurfaceGui")
	sg.Face = Enum.NormalId.Right
	sg.CanvasSize = Vector2.new(300, 80)
	sg.LightInfluence = 0.5
	sg.Parent = sign
	local l = Instance.new("TextLabel")
	l.BackgroundTransparency = 1
	l.Size = UDim2.fromScale(1, 1)
	l.TextScaled = true
	l.Font = Theme.Fonts.Title
	l.TextColor3 = GOLD
	l.Text = "🕶️ " .. T("Hideout")
	l.Parent = sg
	-- portes arrière ouvertes + caisses
	part(parent, "VanDoor", Vector3.new(0.2, 4.8, 3), cf * CFrame.new(-3.1, 3.3, 7.4) * CFrame.Angles(0, math.rad(-70), 0), body, M.Metal)
	part(parent, "VanDoor", Vector3.new(0.2, 4.8, 3), cf * CFrame.new(3.1, 3.3, 7.4) * CFrame.Angles(0, math.rad(70), 0), body, M.Metal)
end

local function syncTarget()
	local st = mine
	if not st or st.State ~= "Running" or not st.Step then
		clearTarget()
		return
	end
	local f = folder
	if not f then
		return
	end
	local key = tostring(st.Id) .. ":" .. tostring(st.StepIndex)
	if target.Key ~= key then
		clearTarget()
		target.Key = key
		target.Model = Instance.new("Model")
		target.Model.Name = "HeistTarget"
		target.Model.Parent = f
		local step = st.Step
		local first = st.Targets and st.Targets[1]
		if step.Kind == "Grab" then
			for _, tg in ipairs(st.Targets or {}) do
				if typeof(tg.Pos) == "Vector3" then
					local host = part(target.Model, "GrabSpot", Vector3.new(1, 1, 1), CFrame.new(tg.Pos + Vector3.new(0, 2.6, 0)), WHITE)
					host.Transparency = 1
					local pr = prompt(host, T("Fill your bag"), "💰 " .. T("Loot"), (Config.Bank.Heist.GrabSeconds or 1.5), 8)
					local i = tg.I
					table.insert(conns, pr.PromptButtonHoldBegan:Connect(function()
						if mine then
							ask("grabBegin", mine.Id, i)
						end
					end))
					table.insert(conns, pr.Triggered:Connect(function()
						if mine then
							ask("grabEnd", mine.Id, i)
						end
					end))
					spotPrompts[i] = { Part = host, Prompt = pr }
				end
			end
		elseif first and typeof(first.Pos) == "Vector3" then
			local pos = first.Pos
			local color = step.Kind == "Escape" and MINT or GOLD
			target.Beacon = beacon(target.Model, pos, color)
			local host = part(target.Model, "TargetHost", Vector3.new(1, 1, 1), CFrame.new(pos + Vector3.new(0, 3, 0)), WHITE)
			host.Transparency = 1
			target.Host = host
			target.Tag = billboard(host, "", color, true, 2000, 3)
			if step.Kind == "Escape" then
				hideoutVan(target.Model, pos)
			elseif step.Kind == "Hack" then
				local pr = prompt(host, T("Hack"), "💻 " .. T("Alarm box"), 0, 10)
				table.insert(conns, pr.Triggered:Connect(function()
					if not mine then
						return
					end
					local id = mine.Id
					task.spawn(function()
						local ok, _, extra = ask("hackBegin", id, nil)
						if ok and type(extra) == "table" and type(extra.Code) == "table" then
							startHack(extra.Code, extra.Show)
						end
					end)
				end))
			elseif step.Kind == "Drill" then
				local pr = prompt(host, T("Unjam the drill"), "🔧 " .. T("Drill"), 0, 12)
				pr.Enabled = false
				target.Unjam = pr
				table.insert(conns, pr.Triggered:Connect(function()
					if mine then
						ask("unjam", mine.Id, nil)
					end
				end))
			elseif step.Kind == "Crowbar" then
				local pr = prompt(host, T("Force it open"), "🪛 " .. T("Crowbar"), 0, 10)
				table.insert(conns, pr.Triggered:Connect(function()
					taps += 1
					showCrowbar(true)
				end))
			end
		end
	end
	-- piles déjà prises : invites retirées
	if st.Step.Kind == "Grab" then
		for _, tg in ipairs(st.Targets or {}) do
			local sp = spotPrompts[tg.I]
			if sp and tg.Taken then
				sp.Part:Destroy()
				spotPrompts[tg.I] = nil
			end
		end
	end
	if target.Unjam then
		target.Unjam.Enabled = st.Jammed == true
	end
	-- position mobile (wagon) : l'objectif suit
	local first = st.Targets and st.Targets[1]
	if target.Host and first and typeof(first.Pos) == "Vector3" then
		target.Host.CFrame = CFrame.new(first.Pos + Vector3.new(0, 3, 0))
		if target.Beacon then
			target.Beacon.CFrame = CFrame.new(first.Pos + Vector3.new(0, 30, 0)) * CFrame.Angles(0, 0, math.pi / 2)
		end
	end
end

local function syncDropped()
	local st = mine
	clearDropped()
	if not st or not st.Dropped or not folder then
		return
	end
	for _, d in ipairs(st.Dropped) do
		if typeof(d.Pos) == "Vector3" then
			local m = part(folder :: Folder, "DroppedBag", Vector3.new(1.8, 1.6, 1.6), CFrame.new(d.Pos + Vector3.new(0, -1.6, 0)), SACK, M.Fabric, "Ball")
			local pr = prompt(m, T("Pick up the bag"), "💰 " .. T("Loot"), 0, 9)
			local i = d.I
			table.insert(conns, pr.Triggered:Connect(function()
				if mine then
					ask("pickup", mine.Id, i)
				end
			end))
			droppedMarks[i] = { Part = m }
		end
	end
end

local function syncLobbies()
	local f = folder
	if not f then
		return
	end
	local busy = mine ~= nil and (mine.State == "Lobby" or mine.State == "Running")
	local keep = {}
	for _, s in ipairs(list) do
		if s.State == "Lobby" and typeof(s.Lobby) == "Vector3" then
			keep[s.Id] = true
			local mark = lobbyMarks[s.Id]
			if not mark then
				local m = Instance.new("Model")
				m.Name = "HeistLobby"
				m.Parent = f
				local ring = part(m, "Ring", Vector3.new(0.12, (s.Radius or 12) * 1.2, (s.Radius or 12) * 1.2), CFrame.new(s.Lobby + Vector3.new(0, 0.08, 0)) * CFrame.Angles(0, 0, math.pi / 2), GOLD, M.Neon, "Cyl")
				ring.Transparency = 0.75
				local host = part(m, "Host", Vector3.new(1, 1, 1), CFrame.new(s.Lobby + Vector3.new(0, 3, 0)), WHITE)
				host.Transparency = 1
				local tag = billboard(host, "", GOLD, false, 260, 4.5)
				local pr = prompt(host, T("Join the crew"), (s.Icon or "🕶️") .. " " .. T(s.Name or "Heist"), 0, 12)
				local id = s.Id
				table.insert(conns, pr.Triggered:Connect(function()
					if mine and mine.Id == id and mine.State == "Lobby" then
						ask("start", id, nil)
					else
						ask("join", id, nil)
					end
				end))
				mark = { Model = m, Tag = tag, Prompt = pr, Ring = ring }
				lobbyMarks[s.Id] = mark
			end
			local me = mine and mine.Id == s.Id
			mark.Tag.Text = string.format("%s %s · %d/%d", s.Icon or "🕶️", T(s.Name or "Heist"), s.Crew or 0, s.MaxCrew or 4)
			if me then
				mark.Prompt.ActionText = T("Start the heist")
				mark.Prompt.Enabled = (mine.Leader == Players.LocalPlayer.UserId)
			else
				mark.Prompt.ActionText = T("Join the crew")
				mark.Prompt.Enabled = not busy
			end
		end
	end
	for id, mark in pairs(lobbyMarks) do
		if not keep[id] then
			mark.Model:Destroy()
			lobbyMarks[id] = nil
		end
	end
end

----------------------------------------------------------------------
-- HUD : mise à jour
----------------------------------------------------------------------

local function stepHud(dt: number)
	local st = mine
	if not ui.Panel then
		return
	end
	if not st or (st.State ~= "Lobby" and st.State ~= "Running") then
		ui.Panel.Visible = false
		ui.Vignette.BackgroundTransparency = 1
		showCrowbar(false)
		return
	end
	ui.Panel.Visible = true
	local t = now()
	local me = Players.LocalPlayer.UserId
	local myBag = 0
	local names = {}
	for _, c in ipairs(st.Crew or {}) do
		if c.UserId == me then
			myBag = c.Bag or 0
		end
		local bagsText = (c.Bag and c.Bag > 0) and (" " .. string.rep("💰", math.min(c.Bag, 6))) or ""
		table.insert(names, (c.Leader and "👑 " or "") .. tostring(c.Name) .. bagsText)
	end
	ui.Crew.Text = "👥 " .. table.concat(names, " · ")
	ui.Title.Text = string.format("%s %s", st.Icon or "🕶️", T(st.Name or "Heist"))
	if st.State == "Lobby" then
		local left = math.max(0, (st.LobbyEndsAt or t) - t)
		ui.Step.Text = T("Crew %d/%d · the heist starts in %s", #(st.Crew or {}), st.MaxCrew or 4, HeistRules.Clock(left))
		ui.Timer.Text = HeistRules.Clock(left)
		ui.Timer.TextColor3 = WHITE
		ui.BarFill.Size = UDim2.new(0, 0, 1, 0)
		ui.StartBtn.Visible = st.Leader == me
		ui.EscapeBtn.Visible = false
		ui.UnjamBtn.Visible = false
		ui.Vignette.BackgroundTransparency = 1
		return
	end
	ui.StartBtn.Visible = false
	local step = st.Step or {}
	local left = math.max(0, (st.EndsAt or t) - t)
	ui.Timer.Text = HeistRules.Clock(left)
	ui.Timer.TextColor3 = st.Alarm and RED or WHITE
	local label0 = T(step.Label or "")
	local p = rootPos()
	local first = st.Targets and st.Targets[1]
	if p and first and typeof(first.Pos) == "Vector3" and step.Kind ~= "Grab" then
		local d = math.floor((Vector3.new(first.Pos.X, 0, first.Pos.Z) - Vector3.new(p.X, 0, p.Z)).Magnitude + 0.5)
		label0 = label0 .. string.format(" · %d m", d)
		if target.Tag then
			target.Tag.Text = string.format("📍 %s · %d m", T(step.Label or ""), d)
		end
	end
	if step.Kind == "Grab" then
		label0 = label0 .. " · " .. T("bag %d/%d", myBag, st.Capacity or 3)
	elseif step.Kind == "Escape" then
		label0 = label0 .. " · " .. T("delivered %d/%d", st.Delivered or 0, st.Total or 0)
	end
	ui.Step.Text = T("Step %d/%d: %s", st.StepIndex or 1, st.Steps or 1, label0)
	local prog = tonumber(st.Progress) or 0
	if step.Kind == "Grab" then
		local taken = 0
		for _, tg in ipairs(st.Targets or {}) do
			if tg.Taken then
				taken += 1
			end
		end
		prog = taken / math.max(1, #(st.Targets or {}))
	elseif step.Kind == "Escape" then
		prog = (st.Delivered or 0) / math.max(1, st.Total or 1)
	end
	ui.BarFill.Size = UDim2.new(math.clamp(prog, 0, 1), 0, 1, 0)
	ui.BarFill.BackgroundColor3 = st.Jammed and RED or MINT
	ui.EscapeBtn.Visible = step.Kind == "Grab" and myBag > 0
	ui.UnjamBtn.Visible = step.Kind == "Drill" and st.Jammed == true
	-- vignette rouge qui pulse pendant l'alarme
	if st.Alarm then
		ui.Vignette.BackgroundTransparency = 0.55 + 0.25 * math.abs(math.sin(os.clock() * 3))
	else
		ui.Vignette.BackgroundTransparency = 1
	end
	showCrowbar(step.Kind == "Crowbar" and p ~= nil and first ~= nil and typeof(first.Pos) == "Vector3" and (first.Pos - p).Magnitude < 14)
	if step.Kind ~= "Hack" and hack then
		hideHack()
	end
	local _ = dt
end

local function showResult(r: any)
	if not ui.Result or type(r) ~= "table" then
		return
	end
	resultToken += 1
	local token = resultToken
	ui.ResTitle.Text = if r.Success then ("🎉 " .. T("HEIST DONE!")) else ("🚨 " .. T("HEIST FAILED"))
	ui.ResTitle.TextColor3 = r.Success and GOLD or RED
	ui.ResFill.Text = T("Loot delivered: %d/%d (%d%%) · crew of %d", r.Delivered or 0, r.Total or 0, math.floor((tonumber(r.Fill) or 0) * 100 + 0.5), r.Crew or 1)
	ui.ResDop.Text = if (r.Dopamine or 0) > 0 then ("+" .. NumberFormatter.Format(r.Dopamine) .. " 🧠 Dopamine") else ""
	ui.ResDia.Text = if (r.Diamonds or 0) > 0 then ("+" .. tostring(r.Diamonds) .. " 💎") else ""
	ui.ResNote.Text = if r.Capped then T("Daily limit reached for this heist: come back tomorrow!") elseif not r.Success then T("Too slow: the cartoon police got the loot back. Try again!") else T("Spend your diamonds at the bank's luxury boutique 💎")
	ui.Result.Visible = true
	pcall(UIUtil.Pop, ui.Result, 0.8, 0.25)
	task.delay(9, function()
		if token == resultToken and ui.Result then
			ui.Result.Visible = false
		end
	end)
end

----------------------------------------------------------------------
-- Événements du serveur
----------------------------------------------------------------------

local function setList(l: any)
	if type(l) ~= "table" then
		return
	end
	list = l
	table.clear(byId)
	for _, s in ipairs(list) do
		if type(s) == "table" and type(s.Id) == "string" then
			byId[s.Id] = s
		end
	end
	-- mon casse a disparu de la liste (fini) -> oublié
	if mine and not byId[mine.Id] then
		mine = nil
	end
	pcall(syncLobbies)
	for _, fn in ipairs(listeners) do
		pcall(fn, list)
	end
end

local function onEvent(kind: string, payload: any)
	if kind == "List" then
		setList(payload)
	elseif kind == "State" then
		if type(payload) == "table" then
			local before = mine and mine.Dropped and #mine.Dropped or -1
			mine = payload
			mineAt = os.clock()
			pcall(syncTarget)
			if #(payload.Dropped or {}) ~= before then
				pcall(syncDropped)
			end
			pcall(syncLobbies)
		end
	elseif kind == "Left" then
		mine = nil
		clearTarget()
		clearDropped()
		hideHack()
		pcall(syncLobbies)
	elseif kind == "Result" then
		mine = nil
		clearTarget()
		clearDropped()
		hideHack()
		showResult(payload)
		pcall(syncLobbies)
	elseif kind == "Toast" and type(payload) == "string" then
		toast(payload)
	elseif kind == "Announce" and type(payload) == "table" then
		toast((payload.Icon or "🕶️") .. " " .. T(payload.Text or ""))
	end
end

----------------------------------------------------------------------
-- API
----------------------------------------------------------------------

function HeistClient.Start(options: any?)
	if started then
		HeistClient.Stop()
	end
	started = true
	opts = if type(options) == "table" then options else {}
	local f = Instance.new("Folder")
	f.Name = HeistClient.FOLDER_NAME
	f.Parent = workspace
	folder = f
	buildHud()
	-- touche E répétée pour le pied-de-biche
	table.insert(conns, UserInputService.InputBegan:Connect(function(input: InputObject, processed: boolean)
		if processed then
			return
		end
		if input.KeyCode == Enum.KeyCode.E and ui.Crowbar and ui.Crowbar.Visible then
			taps += 1
		end
	end))
	task.spawn(function()
		local remotes = ReplicatedStorage:WaitForChild("Remotes", 30)
		if not remotes or not started then
			return
		end
		local ev = remotes:WaitForChild("HeistEvent", 30)
		local rf = remotes:WaitForChild("Heist", 30)
		if not started then
			return
		end
		if rf and rf:IsA("RemoteFunction") then
			remoteFn = rf
		end
		if ev and ev:IsA("RemoteEvent") then
			table.insert(conns, ev.OnClientEvent:Connect(function(kind: any, payload: any)
				if type(kind) ~= "string" then
					return
				end
				local ok, err = pcall(onEvent, kind, payload)
				if not ok then
					warn("[HeistClient] " .. kind .. " : " .. tostring(err))
				end
			end))
		end
		local ok, l, m = ask("sync", nil, nil)
		if ok then
			setList(l)
			if type(m) == "table" then
				onEvent("State", m)
			end
		end
	end)
end

function HeistClient.Step(dt: number)
	if not started then
		return
	end
	bagClock += dt
	if bagClock >= 0.5 then
		bagClock = 0
		pcall(stepBags)
	end
	-- coups de pied-de-biche groupés (au plus 6 par envoi)
	tapClock += dt
	if taps > 0 and tapClock >= 0.15 and mine then
		tapClock = 0
		local n = math.min(taps, 6)
		taps = 0
		local id = mine.Id
		task.spawn(ask, "tap", id, n)
		if ui.CrowScale then
			ui.CrowScale.Scale = 1.15
			TweenService:Create(ui.CrowScale, TweenInfo.new(0.12), { Scale = 1 }):Play()
		end
	end
	pcall(stepHack)
	hudClock += dt
	pcall(stepHud, dt)
	-- état du casse trop vieux (serveur muet) : on l'oublie
	if mine and os.clock() - mineAt > 6 then
		mine = nil
		clearTarget()
	end
end

function HeistClient.Stop()
	if not started then
		return
	end
	started = false
	for _, c in ipairs(conns) do
		c:Disconnect()
	end
	table.clear(conns)
	clearTarget()
	clearDropped()
	for _, mark in pairs(lobbyMarks) do
		mark.Model:Destroy()
	end
	table.clear(lobbyMarks)
	for _, m in pairs(bags) do
		m:Destroy()
	end
	table.clear(bags)
	hack = nil
	if folder then
		folder:Destroy()
		folder = nil
	end
	if gui then
		gui:Destroy()
		gui = nil
	end
	table.clear(ui)
	mine = nil
	list = {}
	table.clear(byId)
	remoteFn = nil
end

function HeistClient.List(): { any }
	return list
end

function HeistClient.Summary(id: string): any?
	return byId[id]
end

function HeistClient.ByKind(kind: string): any?
	for _, s in ipairs(list) do
		if s.Kind == kind then
			return s
		end
	end
	return nil
end

function HeistClient.Mine(): any?
	return mine
end

function HeistClient.OnChanged(fn: (any) -> ()): () -> ()
	table.insert(listeners, fn)
	return function()
		local i = table.find(listeners, fn)
		if i then
			table.remove(listeners, i)
		end
	end
end

function HeistClient.Debug(): any
	return {
		OnEvent = onEvent,
		UI = ui,
		Lobbies = lobbyMarks,
		Target = target,
		Spots = spotPrompts,
		Bags = bags,
		Hack = function()
			return hack
		end,
		StartHack = startHack,
		StepBags = stepBags,
		Ask = ask,
		SetRemote = function(rf: any)
			remoteFn = rf
		end,
	}
end

return HeistClient
