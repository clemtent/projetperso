--[[
	LiveProps (ModuleScript)
	Emplacement : ReplicatedStorage > Client > World > LiveProps

	v9.5 🖥️ "Dopamine Setup" : donne VIE aux modèles 3D des objets Setup
	(House3DSetup) dans la maison de la ville ET dans l'aperçu 3D du panneau
	Maison :
	  - écrans (SurfaceGui dans le PlayerGui, Adornee = la pièce "Screen",
	    Face = Front, MaxDistance 120) : mini coureur, mini live, logo DVD,
	    flash info, LCD de la chaîne (LiveScreens) ; au plus MAX_GUIS écrans
	    dessinés en même temps (les plus proches ; le bureau du mode bureau
	    d'abord), les autres brillent d'une couleur unie ;
	  - clavier : les touches s'enfoncent, son de touche (GearClick /
	    SoundManager.PlayKeySound), VRAI clic (ClientState.Click, même chemin
	    que le gros bouton) ; souris : boutons, son du clic, vrai clic ;
	  - papier bulle : les bulles éclatent (Interact "Bubble", son "Pop",
	    limite de 12 / s comme en 2D) puis regonflent ;
	  - moulin : les ailes tournent (plus vite quand on souffle : Interact
	    "Spin", recharge de Config.Interactions.Spin) ;
	  - presse : le piston descend et écrase canard / canette / pastèque qui
	    repoussent ; gros bouton rouge = Interact "Press" (Feature PressStart,
	    recharge 3 s) ;
	  - hi-fi : vinyle / CD / bobines qui tournent, membranes et VU-mètres qui
	    battent quand la musique joue ; ▶ = musique on/off (même chemin que
	    le lecteur des ⚙️ Réglages), ⏭ = morceau suivant (SoundManager) ;
	  - écran d'infos : clic = Interact "Headline" ; coin live : voyant REC,
	    ON AIR ; plantes qui se balancent ; bandes "RGB" arc-en-ciel.
	Clics 3D : rayon depuis la caméra (souris / toucher), seulement sur les
	objets "Interactive" et à ≤ 14 studs du personnage (sauf en mode bureau).
	Les récompenses du serveur ("Bonus" Spin / Press / Headline) s'envolent
	en "+X" au-dessus de l'objet.
	Performance : UNE boucle Heartbeat pour tous les objets, animations à
	30 images / s, en pause au-delà de ~60 studs du point de focus (SetFocus
	ou la caméra) ; aucune création d'instance par image (bulles "+X" en
	réserve, tableaux réutilisés).

	API :
	  LiveProps.Attach(model, itemId, context) -> handle?
	    context = { Interactive: boolean, IsOwner: boolean?, Player: Player?, OwnerId: number?,
	                PauseDistance: number?, ScreenDistance: number? }
	    (Interactive = false : aperçu 3D, pause à 250 studs, écrans visibles à 300)
	  LiveProps.Detach(handle)
	  LiveProps.AttachAll(models, context) -> { handle }   (ignore les objets non Setup)
	  LiveProps.BindHouseBuilder(HouseBuilder)             (crochets OnItemAttach / OnItemDetach : la ville)
	  LiveProps.HandleOf(model) -> handle?
	  LiveProps.DetachAll(handles)
	  LiveProps.SetFocus(position?)        (nil = la caméra)
	  LiveProps.IsLive(itemId) -> boolean
	  LiveProps.DeskNear(position, radius?) -> handle?     (bureau le plus proche)
	  LiveProps.Peripherals(deskHandle) -> { handle }       (clavier / souris posés dessus)
	  LiveProps.SetDeskFocus(handle?)      (mode bureau : écrans prioritaires, clics sans distance)
	  LiveProps.DeskUsed : Signal (handle) (invite "🖥️ Utiliser" / clic sur un écran de bureau)
	  LiveProps.Press(handle, partName)    (appui programmé : touche, bouton... pour DeskMode)
	  LiveProps.Count() -> number
	v9.8 (DESK98) :
	  - écrans : le VRAI contenu du clicker (World/StimulusScreen : Runner,
	    LiveStream, DVD, NewsTicker) sur les REAL_MAX écrans les plus proches
	    (≤ REAL_DISTANCE studs, bureau du mode bureau d'abord) ; les autres
	    gardent le dessin léger (LiveScreens) ; toiles inertes (Active = false) ;
	  - télés : clic sur l'écran = chaîne suivante (Live, DVD, Infos, Coureur) ;
	  - clavier : légendes des touches (une toile par rangée, seulement sur le
	    clavier le plus proche) ; appui "visuel" (jeu du bureau, sans clic) ;
	  - presse : tapis roulant qui amène l'objet, écrasement, éjection vers le
	    bac, manomètres, afficheur, éclats, couleurs du palier du clicker.
	  LiveProps.MainScreen(deskHandle) -> ScreenRec?    (le plus grand écran du bureau)
	  LiveProps.SetOverride(rec, override?)             (override = { Canvas(aspect), Build(gui, canvas) -> Screen })
	  LiveProps.PressVisual(handle, partName) -> boolean (touche / bouton qui s'enfonce, sans clic ni son)
	  LiveProps.SetChannel(rec, kind)
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Config = require(ReplicatedStorage.Shared.Config)
local Locale = require(ReplicatedStorage.Shared.Locale)
local Signal = require(ReplicatedStorage.Shared.Signal)
local NumberFormatter = require(ReplicatedStorage.Shared.NumberFormatter)
local LiveScreens = require(script.Parent.LiveScreens)
local StimulusScreen = require(script.Parent.StimulusScreen)

local Client = script.Parent.Parent

local LiveProps = {}

LiveProps.MAX_GUIS = 8 -- écrans dessinés en même temps (tous objets confondus)
LiveProps.REAL_MAX = 3 -- écrans avec le VRAI stimulus du clicker (les plus proches)
LiveProps.REAL_DISTANCE = 40 -- (studs) au-delà : dessin léger
LiveProps.LEGEND_DISTANCE = 22 -- (studs) légendes du clavier le plus proche
LiveProps.PAUSE_DISTANCE = 45 -- (studs) au-delà : animations en pause (v9.8 : 60 -> 45)
LiveProps.SCREEN_DISTANCE = 120 -- MaxDistance des SurfaceGui
LiveProps.CLICK_DISTANCE = 14 -- (studs) personnage -> objet pour cliquer

local ANIM_STEP = 1 / 30
local MANAGE_STEP = 0.5
local HOVER_STEP = 0.1
local RGB_STEP = 1 / 15

local rgb = Color3.fromRGB
local WHITE = Color3.new(1, 1, 1)
local CYAN_SOFT = rgb(120, 200, 255)

LiveProps.DeskUsed = Signal.new()

----------------------------------------------------------------------
-- Modules du client (chargés à la demande, jamais bloquants)
----------------------------------------------------------------------

local cache: { [string]: any } = {}
local function lazy(name: string, path: { string }): any
	local cached = cache[name]
	if cached ~= nil then
		return cached or nil
	end
	local ok, result = pcall(function()
		local node: Instance = Client
		for _, step in ipairs(path) do
			local child = node:FindFirstChild(step)
			if not child then
				return nil
			end
			node = child
		end
		if node:IsA("ModuleScript") then
			return require(node) :: any
		end
		return nil
	end)
	cache[name] = (ok and result) or false
	return cache[name] or nil
end
local function clientState(): any
	return lazy("ClientState", { "ClientState" })
end
local function soundManager(): any
	return lazy("SoundManager", { "SoundManager" })
end
local function gearClick(): any
	return lazy("GearClick", { "Stimuli", "Gear", "GearClick" })
end
local function setupModule(): any
	return lazy("House3DSetup", { "Components", "House", "House3DSetup" })
end
local function settingsPanel(): any
	return lazy("Settings", { "Components", "Panels", "Settings" })
end
local function net(): any
	local cached = cache.Net
	if cached == nil then
		local ok, result = pcall(require, ReplicatedStorage.Shared.Net)
		cached = ok and result or false
		cache.Net = cached
	end
	return cached or nil
end

local function playSound(name: string, pitch: number?)
	local manager = soundManager()
	if manager and type(manager.Play) == "function" then
		pcall(manager.Play, name, pitch)
	end
end

local function hasFeature(name: string): boolean
	local state = clientState()
	if not state or type(state.HasFeature) ~= "function" then
		return false
	end
	local ok, value = pcall(state.HasFeature, name)
	return ok and value == true
end

local function levelOf(upgradeId: string): number
	local state = clientState()
	if not state or type(state.GetLevel) ~= "function" then
		return 0
	end
	local ok, value = pcall(state.GetLevel, upgradeId)
	return ok and tonumber(value) or 0
end

local function interact(kind: string, arg: any?)
	local module = net()
	if not module then
		return
	end
	pcall(function()
		module.Event("Interact"):FireServer(kind, arg)
	end)
end

local function upgradeName(upgradeId: string): string
	for _, upgrade in ipairs(Config.Upgrades or {}) do
		if upgrade.Id == upgradeId then
			return Locale.T(upgrade.Name)
		end
	end
	return upgradeId
end

----------------------------------------------------------------------
-- Types
----------------------------------------------------------------------

type Mover = { Part: BasePart, Offset: CFrame, Size: Vector3 }
type Spinner = { Pivot: BasePart, Parts: { BasePart }, Offsets: { CFrame }, CFrames: { CFrame }, Axis: string, Angle: number, Speed: number, Target: number }
type Press = { Part: BasePart, Offset: CFrame, Base: Color3, Material: Enum.Material, T: number, Depth: number }
export type Override = {
	Canvas: (aspect: number) -> Vector2,
	Build: (gui: SurfaceGui, canvas: Vector2) -> any,
}
export type ScreenRec = {
	Part: BasePart,
	Kind: string,
	Index: number,
	Handle: any,
	Gui: SurfaceGui?,
	Screen: any?, -- LiveScreens.Screen | StimulusScreen.Screen | écran d'un override
	Real: boolean, -- vrai stimulus du clicker dessiné
	RealBroken: boolean, -- le vrai stimulus a planté : dessin léger pour de bon
	Override: Override?, -- (jeu du bureau) prend l'écran
	Wings: { BasePart },
	BaseColor: Color3,
	BaseMaterial: Enum.Material,
}

export type Handle = {
	Model: Model,
	ItemId: string,
	Kind: string,
	Setup: { [string]: any },
	Interactive: boolean,
	IsOwner: boolean,
	Alive: boolean,
	Ref: BasePart,
	Paused: boolean,
	Distance: number,
	PauseDistance: number,
	ScreenDistance: number,
	Clock: number,
	Screens: { ScreenRec },
	Clickables: { BasePart },
	Roles: { [BasePart]: string },
	RGB: { BasePart },
	Movers: { [BasePart]: Mover },
	Presses: { Press },
	Spinners: { Spinner },
	State: { [string]: any },
	Connections: { any },
	Prompt: ProximityPrompt?,
	Step: ((h: Handle, dt: number) -> ())?,
	Click: ((h: Handle, part: BasePart, role: string, point: Vector3) -> ())?,
	Visual: ((h: Handle, part: BasePart) -> ())?, -- (v9.8) appui sans clic ni son
}

local handles: { Handle } = {}
local byModel: { [Model]: Handle } = {}
local screens: { ScreenRec } = {}
local focusPoint: Vector3? = nil
local focusAt = 0
local deskFocus: Handle? = nil
local heartbeat: RBXScriptConnection? = nil
local inputConnections: { RBXScriptConnection } = {}
local notifyConnection: any = nil
local clickList: { BasePart } = {}
local random = Random.new()

----------------------------------------------------------------------
-- Outils
----------------------------------------------------------------------

local function refCF(h: Handle): CFrame
	return h.Ref.CFrame
end

-- Mémorise la pose de repos d'une pièce (repère du modèle)
local function mover(h: Handle, part: BasePart): Mover
	local existing = h.Movers[part]
	if existing then
		return existing
	end
	local m: Mover = { Part = part, Offset = refCF(h):ToObjectSpace(part.CFrame), Size = part.Size }
	h.Movers[part] = m
	return m
end

local function newSpinner(pivotPart: BasePart, parts: { BasePart }, axis: string, speed: number): Spinner
	local offsets = table.create(#parts)
	local cframes = table.create(#parts)
	for index, part in ipairs(parts) do
		offsets[index] = pivotPart.CFrame:ToObjectSpace(part.CFrame)
		cframes[index] = part.CFrame
	end
	return { Pivot = pivotPart, Parts = parts, Offsets = offsets, CFrames = cframes, Axis = axis, Angle = 0, Speed = speed, Target = speed }
end

local function stepSpinner(spinner: Spinner, dt: number)
	spinner.Speed += (spinner.Target - spinner.Speed) * math.min(1, dt * 1.5)
	spinner.Angle = (spinner.Angle + spinner.Speed * dt) % (math.pi * 2)
	local a = spinner.Angle
	local rotation = spinner.Axis == "Y" and CFrame.Angles(0, a, 0) or (spinner.Axis == "X" and CFrame.Angles(a, 0, 0) or CFrame.Angles(0, 0, a))
	local base = spinner.Pivot.CFrame * rotation
	local cframes = spinner.CFrames
	for index, offset in ipairs(spinner.Offsets) do
		cframes[index] = base * offset
	end
	workspace:BulkMoveTo(spinner.Parts, cframes, Enum.BulkMoveMode.FireCFrameChanged)
end

-- Balancement (plantes) : petit angle autour du pivot
local function swaySpinner(spinner: Spinner, clock: number, amount: number)
	local base = spinner.Pivot.CFrame * CFrame.Angles(math.sin(clock * 1.3) * amount * 0.6, 0, math.sin(clock * 0.9) * amount)
	local cframes = spinner.CFrames
	for index, offset in ipairs(spinner.Offsets) do
		cframes[index] = base * offset
	end
	workspace:BulkMoveTo(spinner.Parts, cframes, Enum.BulkMoveMode.FireCFrameChanged)
end

local function findPart(model: Model, name: string): BasePart?
	local found = model:FindFirstChild(name, true)
	if found and found:IsA("BasePart") then
		return found
	end
	return nil
end

local function partsNamed(model: Model, name: string): { BasePart }
	local list = {}
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") and d.Name == name then
			table.insert(list, d)
		end
	end
	return list
end

-- Appui (touche, bouton) : la pièce s'enfonce puis remonte (v9.8 : l'éclair
-- de couleur n'est plus du Neon ; la légende de la touche s'estompe)
local function press(h: Handle, part: BasePart, depth: number?, flash: Color3?)
	local m = mover(h, part)
	for _, p in ipairs(h.Presses) do
		if p.Part == part then
			p.T = 0
			return
		end
	end
	table.insert(h.Presses, { Part = part, Offset = m.Offset, Base = part.Color, Material = part.Material, T = 0, Depth = depth or m.Size.Y * 0.55 })
	if flash then
		part.Color = flash
	end
end

local function stepPresses(h: Handle, dt: number)
	local list = h.Presses
	if #list == 0 then
		return
	end
	local ref = refCF(h)
	local legends: { [BasePart]: TextLabel }? = h.State.LegendLabels
	for index = #list, 1, -1 do
		local p = list[index]
		p.T += dt
		local t = p.T
		local down
		if t < 0.04 then
			down = t / 0.04
		elseif t < 0.12 then
			down = 1
		else
			down = math.max(0, 1 - (t - 0.12) / 0.12)
		end
		p.Part.CFrame = ref * p.Offset * CFrame.new(0, -p.Depth * down, 0)
		local label = legends and legends[p.Part]
		if label then
			label.TextTransparency = 0.05 + 0.6 * down
		end
		if t >= 0.24 then
			p.Part.CFrame = ref * p.Offset
			p.Part.Color = p.Base
			p.Part.Material = p.Material
			if label then
				label.TextTransparency = 0.05
			end
			table.remove(list, index)
		end
	end
end

----------------------------------------------------------------------
-- "+X" et petits messages flottants (réserve de BillboardGui)
----------------------------------------------------------------------

type Floater = { Gui: BillboardGui, Label: TextLabel, T: number, Busy: boolean, Offset: Vector3 }
local floaters: { Floater } = {}
local FLOATERS = 6

local function playerGui(): Instance?
	local player = Players.LocalPlayer
	return player and player:FindFirstChildOfClass("PlayerGui") or nil
end

local function floater(): Floater?
	for _, f in ipairs(floaters) do
		if not f.Busy then
			return f
		end
	end
	if #floaters >= FLOATERS then
		-- la plus ancienne est recyclée
		local oldest = floaters[1]
		for _, f in ipairs(floaters) do
			if f.T > oldest.T then
				oldest = f
			end
		end
		return oldest
	end
	local parent = playerGui()
	if not parent then
		return nil
	end
	local gui = Instance.new("BillboardGui")
	gui.Name = "LivePropsPop"
	gui.Size = UDim2.fromOffset(160, 34)
	gui.AlwaysOnTop = true
	gui.LightInfluence = 0
	gui.MaxDistance = 80
	gui.ResetOnSpawn = false
	gui.Enabled = false
	gui.Parent = parent
	local text = Instance.new("TextLabel")
	text.Name = "Text"
	text.BackgroundTransparency = 1
	text.Size = UDim2.fromScale(1, 1)
	text.Font = Enum.Font.GothamBlack
	text.TextSize = 24
	text.TextColor3 = rgb(255, 230, 90)
	text.TextStrokeColor3 = rgb(120, 40, 100)
	text.TextStrokeTransparency = 0
	text.Text = ""
	text.Parent = gui
	local f: Floater = { Gui = gui, Label = text, T = 0, Busy = false, Offset = Vector3.zero }
	table.insert(floaters, f)
	return f
end

local function popText(part: BasePart, point: Vector3, text: string, color: Color3?, size: number?)
	local f = floater()
	if not f then
		return
	end
	f.Busy = true
	f.T = 0
	f.Offset = point - part.Position
	f.Gui.Adornee = part
	f.Gui.StudsOffsetWorldSpace = f.Offset
	f.Gui.Enabled = true
	f.Label.Text = text
	f.Label.TextColor3 = color or rgb(255, 230, 90)
	f.Label.TextSize = size or 24
	f.Label.TextTransparency = 0
	f.Label.TextStrokeTransparency = 0
end

local function stepFloaters(dt: number)
	for _, f in ipairs(floaters) do
		if f.Busy then
			f.T += dt
			local t = f.T / 0.9
			if t >= 1 then
				f.Busy = false
				f.Gui.Enabled = false
				f.Gui.Adornee = nil
			else
				f.Gui.StudsOffsetWorldSpace = f.Offset + Vector3.new(0, 0.4 + t * 1.6, 0)
				f.Label.TextTransparency = math.max(0, t - 0.55) / 0.45
				f.Label.TextStrokeTransparency = f.Label.TextTransparency
			end
		end
	end
end

local function formatGain(value: number): string
	if value >= 1e6 then
		return NumberFormatter.Format(value)
	end
	if value < 10 and value % 1 ~= 0 then
		return NumberFormatter.Format(value)
	end
	return NumberFormatter.WithSpaces(value)
end

----------------------------------------------------------------------
-- Écrans (SurfaceGui dans le PlayerGui)
----------------------------------------------------------------------

local function screenOff(rec: ScreenRec)
	local tint = LiveScreens.Tints[rec.Kind] or rgb(40, 40, 70)
	-- (v9.6 : écran en veille = verre sombre mat, plus une dalle Neon)
	rec.Part.Material = Enum.Material.SmoothPlastic
	rec.Part.Color = tint:Lerp(Color3.new(0, 0, 0), 0.7)
end

local function releaseGui(rec: ScreenRec)
	local screen = rec.Screen
	if screen then
		rec.Screen = nil
		pcall(screen.Destroy, screen)
	end
	local gui = rec.Gui
	if gui then
		rec.Gui = nil
		gui:Destroy()
	end
	rec.Real = false
	if rec.Part.Parent then
		screenOff(rec)
	end
end

-- Dessine l'écran : override (jeu du bureau), vrai stimulus du clicker
-- (`real`) ou dessin léger (LiveScreens)
local function claimGui(rec: ScreenRec, real: boolean)
	if rec.Gui then
		return
	end
	local part = rec.Part
	local size = part.Size
	local aspect = size.X / math.max(0.05, size.Y)
	local override = rec.Override
	local useReal = real and not override and not rec.RealBroken and StimulusScreen.Supports(rec.Kind)
	local canvas: Vector2
	if override then
		local ok, value = pcall(override.Canvas, aspect)
		canvas = (ok and typeof(value) == "Vector2") and value or Vector2.new(400, math.floor(400 / aspect + 0.5))
	elseif useReal then
		canvas = StimulusScreen.Canvas(rec.Kind, aspect)
	else
		local width = rec.Kind == "Music" and 256 or 320
		canvas = Vector2.new(width, math.max(40, math.floor(width / aspect + 0.5)))
	end
	local gui = Instance.new("SurfaceGui")
	gui.Name = "LiveScreen_" .. rec.Kind
	gui.Face = Enum.NormalId.Front
	gui.SizingMode = Enum.SurfaceGuiSizingMode.FixedSize
	gui.CanvasSize = canvas
	gui.LightInfluence = 0
	gui.Brightness = 1 -- (v9.6 : 1.2 -> 1, écrans pas éblouissants)
	gui.MaxDistance = rec.Handle.ScreenDistance
	gui.AlwaysOnTop = false
	gui.ClipsDescendants = true
	gui.ResetOnSpawn = false
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.Active = false -- (v9.8 : toile inerte, les clics 3D passent au travers)
	gui.Adornee = part
	local screen: any = nil
	if override then
		local ok, result = pcall(override.Build, gui, canvas)
		if ok then
			screen = result
		else
			warn("[LiveProps] Écran du jeu : " .. tostring(result))
		end
	elseif useReal then
		local ok, result = pcall(StimulusScreen.New, rec.Kind, gui, canvas)
		if ok and result then
			screen = result
		else
			if not ok then
				warn("[LiveProps] Vrai écran " .. tostring(rec.Kind) .. " : " .. tostring(result))
			end
			rec.RealBroken = true
			gui:ClearAllChildren()
			local width = 320
			canvas = Vector2.new(width, math.max(40, math.floor(width / aspect + 0.5)))
			gui.CanvasSize = canvas
		end
	end
	if not screen then
		local ok, result = pcall(LiveScreens.New, rec.Kind, gui, canvas)
		if not ok then
			warn("[LiveProps] Écran " .. tostring(rec.Kind) .. " : " .. tostring(result))
			gui:Destroy()
			return
		end
		screen = result
	end
	gui.Parent = playerGui() or part
	rec.Gui = gui
	rec.Screen = screen
	rec.Real = useReal and type(screen) == "table" and screen.Real == true
	part.Material = Enum.Material.SmoothPlastic
	part.Color = Color3.new(0, 0, 0)
end

-- Qui a droit à un écran dessiné ? (les plus proches, le bureau actif et le
-- jeu du bureau d'abord) ; qui a droit au VRAI stimulus du clicker ?
local ranked: { ScreenRec } = {}
local rankDistance: { [ScreenRec]: number } = {}
local function manageScreens(focus: Vector3)
	table.clear(ranked)
	table.clear(rankDistance)
	for _, rec in ipairs(screens) do
		local h = rec.Handle
		if h.Alive and rec.Part.Parent then
			local distance = (rec.Part.Position - focus).Magnitude
			if rec.Override then
				distance = -2
			elseif h == deskFocus then
				distance = -1
			elseif h.Paused or distance > h.ScreenDistance then
				distance = math.huge
			end
			rankDistance[rec] = distance
			table.insert(ranked, rec)
		end
	end
	table.sort(ranked, function(a, b)
		return rankDistance[a] < rankDistance[b]
	end)
	-- écran planté : on repasse au dessin léger
	for _, rec in ipairs(ranked) do
		local screen = rec.Screen
		if screen and type(screen) == "table" and screen.Failed == true then
			rec.RealBroken = true
			releaseGui(rec)
		end
	end
	local wanted: { [ScreenRec]: boolean } = {}
	local wantReal: { [ScreenRec]: boolean } = {}
	local realCount = 0
	for index, rec in ipairs(ranked) do
		local distance = rankDistance[rec]
		local want = index <= LiveProps.MAX_GUIS and distance < math.huge
		wanted[rec] = want
		if want and not rec.Override and not rec.RealBroken and realCount < LiveProps.REAL_MAX and distance <= LiveProps.REAL_DISTANCE
			and rec.Handle.Interactive and StimulusScreen.Supports(rec.Kind) then
			realCount += 1
			wantReal[rec] = true
		end
	end
	for _, rec in ipairs(ranked) do
		if rec.Gui and (not wanted[rec] or (not rec.Override and rec.Real ~= (wantReal[rec] == true))) then
			releaseGui(rec)
		end
	end
	-- (au plus un vrai stimulus construit par passage : le coût est étalé)
	local built = false
	for _, rec in ipairs(ranked) do
		if wanted[rec] and not rec.Gui then
			local real = wantReal[rec] == true
			if real and built then
				real = false -- (dessin léger en attendant le prochain passage)
			end
			claimGui(rec, real)
			if rec.Real then
				built = true
			end
		end
	end
end

----------------------------------------------------------------------
-- Comportements par famille
----------------------------------------------------------------------

local BEHAVIOURS: { [string]: (h: Handle) -> () } = {}

-- 🖥️ Bureau : chaise tournée vers les écrans, invite "Utiliser", clic écran
BEHAVIOURS.Desk = function(h: Handle)
	local seat = h.Model:FindFirstChild("SeatPart")
	if seat and seat:IsA("BasePart") and seat:GetAttribute("FacesDesk") ~= true then
		-- (BuildModel oriente les places assises vers l'avant du modèle ; la
		-- chaise d'un bureau regarde les écrans, vers l'arrière)
		seat.CFrame = seat.CFrame * CFrame.Angles(0, math.pi, 0)
		seat:SetAttribute("FacesDesk", true)
	end
	if h.Interactive then
		for _, rec in ipairs(h.Screens) do
			table.insert(h.Clickables, rec.Part)
			h.Roles[rec.Part] = "Desk"
		end
		local anchor = h.Screens[math.max(1, math.ceil(#h.Screens / 2))]
		if anchor then
			local prompt = Instance.new("ProximityPrompt")
			prompt.Name = "UsePrompt"
			prompt.ActionText = Locale.T("🖥️ Use")
			local item = Config.HouseItemsById and Config.HouseItemsById[h.ItemId]
			prompt.ObjectText = item and Locale.T(item.Name) or ""
			prompt.KeyboardKeyCode = Enum.KeyCode.F
			prompt.GamepadKeyCode = Enum.KeyCode.ButtonY
			prompt.MaxActivationDistance = 9
			prompt.RequiresLineOfSight = false
			prompt.HoldDuration = 0
			prompt.UIOffset = Vector2.new(0, 40)
			prompt.Parent = anchor.Part
			h.Prompt = prompt
			table.insert(h.Connections, prompt.Triggered:Connect(function()
				if h.Alive then
					LiveProps.DeskUsed:Fire(h)
				end
			end))
		end
	end
	h.Click = function(_h, _part, role, _point)
		if role == "Desk" then
			LiveProps.DeskUsed:Fire(h)
		end
	end
end

-- ⌨️ Clavier : touches -> vrais clics (v9.8 : légendes, éclair doux)
local KEY_FLASH = rgb(255, 120, 220)
local LEGEND_PPS = 320 -- pixels de toile par stud (légendes)
local LEGEND_DARK = rgb(58, 54, 80)

-- Légendes : une plaque invisible par rangée, juste au-dessus des touches,
-- avec une SurfaceGui (face Top) et un texte par touche
local function buildLegends(h: Handle)
	if h.State.LegendPlates then
		return
	end
	local keys: { BasePart } = h.State.Keys or {}
	if #keys == 0 then
		return
	end
	local ref = refCF(h)
	local rows: { [string]: { BasePart } } = {}
	local order: { string } = {}
	for _, key in ipairs(keys) do
		local rel = ref:PointToObjectSpace(h.Movers[key] and (ref * h.Movers[key].Offset).Position or key.Position)
		local rowKey = string.format("%.2f", rel.Z * 20)
		if not rows[rowKey] then
			rows[rowKey] = {}
			table.insert(order, rowKey)
		end
		table.insert(rows[rowKey], key)
	end
	local plates: { BasePart } = {}
	local labels: { [BasePart]: TextLabel } = {}
	for _, rowKey in ipairs(order) do
		local list = rows[rowKey]
		local first = list[1]
		local rotation = (ref * h.Movers[first].Offset).Rotation
		local minX, maxX, top, depth = math.huge, -math.huge, -math.huge, 0
		local frameCF = CFrame.new((ref * h.Movers[first].Offset).Position) * rotation
		for _, key in ipairs(list) do
			local rest = ref * h.Movers[key].Offset
			local rel = frameCF:PointToObjectSpace(rest.Position)
			minX = math.min(minX, rel.X - key.Size.X / 2)
			maxX = math.max(maxX, rel.X + key.Size.X / 2)
			top = math.max(top, rel.Y + key.Size.Y / 2)
			depth = math.max(depth, key.Size.Z)
		end
		local width = maxX - minX
		local plate = Instance.new("Part")
		plate.Name = "KeyLegends"
		plate.Anchored = true
		plate.CanCollide = false
		plate.CanQuery = false
		plate.CanTouch = false
		plate.CastShadow = false
		plate.Transparency = 1
		plate.Size = Vector3.new(math.max(0.05, width), 0.01, math.max(0.05, depth))
		plate.CFrame = frameCF * CFrame.new((minX + maxX) / 2, top + 0.006, 0)
		local canvas = Vector2.new(math.max(16, math.floor(width * LEGEND_PPS + 0.5)), math.max(8, math.floor(depth * LEGEND_PPS + 0.5)))
		local gui = Instance.new("SurfaceGui")
		gui.Name = "Legends"
		gui.Face = Enum.NormalId.Top
		gui.SizingMode = Enum.SurfaceGuiSizingMode.FixedSize
		gui.CanvasSize = canvas
		gui.LightInfluence = 1
		gui.Brightness = 1
		gui.MaxDistance = LiveProps.LEGEND_DISTANCE + 10
		gui.ClipsDescendants = true
		gui.Active = false
		gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
		gui.Parent = plate
		for _, key in ipairs(list) do
			local legend = key:GetAttribute("Legend")
			if type(legend) == "string" and legend ~= "" then
				local rel = plate.CFrame:PointToObjectSpace((ref * h.Movers[key].Offset).Position)
				local w = key.Size.X * LEGEND_PPS
				local d = key.Size.Z * LEGEND_PPS
				local label = Instance.new("TextLabel")
				label.Name = key.Name
				label.BackgroundTransparency = 1
				label.AnchorPoint = Vector2.new(0.5, 0.5)
				label.Position = UDim2.fromOffset((rel.X / plate.Size.X + 0.5) * canvas.X, (rel.Z / plate.Size.Z + 0.5) * canvas.Y)
				label.Size = UDim2.fromOffset(w, d)
				label.Font = Enum.Font.GothamBold
				label.TextSize = math.max(6, math.floor(d * (utf8.len(legend) == 1 and 0.62 or 0.36)))
				label.TextColor3 = key:GetAttribute("KeyStyle") == "A" and LEGEND_DARK or WHITE
				label.TextTransparency = 0.05
				label.Text = legend
				label.Parent = gui
				labels[key] = label
			end
		end
		plate.Parent = h.Model
		table.insert(plates, plate)
	end
	h.State.LegendPlates = plates
	h.State.LegendLabels = labels
end

local function dropLegends(h: Handle)
	local plates = h.State.LegendPlates
	if not plates then
		return
	end
	h.State.LegendPlates = nil
	h.State.LegendLabels = nil
	for _, plate in ipairs(plates) do
		plate:Destroy()
	end
end

BEHAVIOURS.Keyboard = function(h: Handle)
	local keys: { BasePart } = {}
	local byName: { [string]: BasePart } = {}
	for _, d in ipairs(h.Model:GetDescendants()) do
		if d:IsA("BasePart") and string.sub(d.Name, 1, 4) == "Key_" then
			table.insert(keys, d)
			byName[d.Name] = d
			h.Roles[d] = "Key"
			table.insert(h.Clickables, d)
			mover(h, d)
		end
	end
	h.State.Keys = keys
	h.State.KeysByName = byName
	local base = findPart(h.Model, "KeyboardBase")
	if base then
		h.Roles[base] = "AnyKey"
		table.insert(h.Clickables, base)
	end
	local function flashFor(key: BasePart): Color3
		return key.Color:Lerp(KEY_FLASH, 0.55)
	end
	h.Visual = function(_h, part)
		press(h, part, nil, flashFor(part))
	end
	h.Click = function(_h, part, role, point)
		local key = part
		if role ~= "Key" then
			-- clic entre les touches : la touche la plus proche
			local best, bestDistance = nil, math.huge
			for _, k in ipairs(keys) do
				local distance = (k.Position - point).Magnitude
				if distance < bestDistance then
					best, bestDistance = k, distance
				end
			end
			if not best then
				return
			end
			key = best
		end
		press(h, key, nil, flashFor(key):Lerp(WHITE, random:NextNumber(0, 0.3)))
		local gear = gearClick()
		if gear then
			pcall(gear.PlayKeySound, math.max(1, levelOf("Keyboard")), 1, 0)
			local okClick, gain = pcall(gear.Click, "SetupKeyboard", nil)
			if okClick and type(gain) == "number" then
				popText(key, key.Position + Vector3.new(0, 0.2, 0), "+" .. formatGain(gain), nil, 22)
			end
		end
	end
end

-- 🖱️ Souris : boutons -> vrais clics
BEHAVIOURS.Mouse = function(h: Handle)
	for _, d in ipairs(h.Model:GetDescendants()) do
		if d:IsA("BasePart") and d.Name ~= "Root" and d.Name ~= "Hitbox" then
			table.insert(h.Clickables, d)
			h.Roles[d] = d.Name
		end
	end
	local left = findPart(h.Model, "MouseLeft")
	local right = findPart(h.Model, "MouseRight")
	h.Visual = function(_h, part)
		press(h, part, part.Size.Y * 0.5, rgb(120, 220, 255))
	end
	h.Click = function(_h, part, role, _point)
		local button = (role == "MouseRight" and right) or left
		if button then
			press(h, button, button.Size.Y * 0.5, rgb(120, 220, 255))
		end
		local gear = gearClick()
		if gear then
			pcall(gear.PlayClickSound)
			local okClick, gain = pcall(gear.Click, "SetupMouse", nil)
			if okClick and type(gain) == "number" then
				popText(button or part, (button or part).Position + Vector3.new(0, 0.3, 0), "+" .. formatGain(gain), rgb(140, 230, 255), 22)
			end
		end
	end
end

-- 🔘 Papier bulle : éclate / regonfle
BEHAVIOURS.BubbleWrap = function(h: Handle)
	local bubbles: { { Part: BasePart, Popped: boolean, Timer: number, Grow: number, Transparency: number } } = {}
	for _, d in ipairs(h.Model:GetDescendants()) do
		if d:IsA("BasePart") and string.sub(d.Name, 1, 7) == "Bubble_" then
			mover(h, d)
			table.insert(bubbles, { Part = d, Popped = false, Timer = 0, Grow = 1, Transparency = d.Transparency })
			h.Roles[d] = "Bubble"
			table.insert(h.Clickables, d)
		end
	end
	local settings = (Config.Interactions and Config.Interactions.Bubble) or {}
	local maxPerSecond = tonumber(settings.MaxPerSecond) or 12
	local tokens = maxPerSecond
	local lastRefill = os.clock()
	local function setBubble(bubble, grow: number)
		local m = h.Movers[bubble.Part]
		local s = 0.2 + 0.8 * grow
		local size = Vector3.new(m.Size.X * (1.1 - 0.1 * grow), m.Size.Y * s, m.Size.Z * (1.1 - 0.1 * grow))
		bubble.Part.Size = size
		bubble.Part.CFrame = refCF(h) * m.Offset * CFrame.new(0, -(m.Size.Y - size.Y) / 2, 0)
		bubble.Part.Transparency = bubble.Transparency + (1 - grow) * 0.45
	end
	h.Step = function(_h, dt)
		for _, bubble in ipairs(bubbles) do
			if bubble.Popped then
				bubble.Timer -= dt
				if bubble.Timer <= 0 then
					bubble.Grow = math.min(1, bubble.Grow + dt * 2.5)
					setBubble(bubble, bubble.Grow)
					if bubble.Grow >= 1 then
						bubble.Popped = false
					end
				end
			end
		end
	end
	h.Click = function(_h, part, _role, point)
		for _, bubble in ipairs(bubbles) do
			if bubble.Part == part then
				if bubble.Popped then
					return
				end
				local now = os.clock()
				tokens = math.min(maxPerSecond, tokens + (now - lastRefill) * maxPerSecond)
				lastRefill = now
				if tokens < 1 then
					return -- trop vite : la bulle résiste
				end
				tokens -= 1
				bubble.Popped = true
				bubble.Grow = 0
				bubble.Timer = random:NextNumber(5, 9)
				setBubble(bubble, 0)
				playSound("Pop", random:NextNumber(0.9, 1.35))
				if hasFeature("BubbleWrap") then
					interact("Bubble")
					local state = clientState()
					local data = state and state.Data
					local gain = (tonumber(data and data.ClickValue) or 0) * (tonumber(settings.ClickFraction) or 0.5)
					if gain > 0 then
						popText(part, point, "+" .. formatGain(gain), rgb(170, 230, 255), 20)
					end
				else
					popText(part, point, "POP!", rgb(170, 230, 255), 20)
				end
				return
			end
		end
	end
end

-- 🌀 Moulin : les ailes tournent ; souffler = Interact("Spin")
BEHAVIOURS.Windmill = function(h: Handle)
	local pivotPart = findPart(h.Model, "Pivot_Blades")
	local parts = partsNamed(h.Model, "Blade")
	for _, hub in ipairs(partsNamed(h.Model, "Blades")) do
		table.insert(parts, hub)
	end
	local spinner = pivotPart and #parts > 0 and newSpinner(pivotPart, parts, "Z", 1.1) or nil
	if spinner then
		table.insert(h.Spinners, spinner)
	end
	if h.Interactive then
		for _, d in ipairs(h.Model:GetDescendants()) do
			if d:IsA("BasePart") and d.Transparency < 1 and d.Name ~= "Hitbox" then
				table.insert(h.Clickables, d)
				h.Roles[d] = "Spin"
			end
		end
	end
	local settings = (Config.Interactions and Config.Interactions.Spin) or {}
	local cooldown = tonumber(settings.Cooldown) or 2
	local last = -math.huge
	h.Step = function(_h, dt)
		if spinner and spinner.Target > 1.1 then
			spinner.Target = math.max(1.1, spinner.Target - dt * 1.2)
		end
	end
	h.Click = function(_h, part, _role, point)
		if spinner then
			spinner.Target = math.min(9, spinner.Target + 3)
			spinner.Speed = math.max(spinner.Speed, spinner.Target * 0.7)
		end
		playSound("Open", random:NextNumber(1.1, 1.4))
		popText(part, point, "💨", WHITE, 26)
		local now = os.clock()
		if now - last >= cooldown and hasFeature("Pinwheel") then
			last = now
			interact("Spin")
			h.State.BonusSource = "Spin"
			h.State.BonusAt = now
		end
	end
end

-- 🗜️ Presse (v9.8) : le tapis amène l'objet sous la presse, descente,
-- écrasement (éclats, vapeur), remontée, la galette part au bac ; manomètres,
-- voyants, afficheur, gyrophare ; couleurs du palier de la presse du clicker
-- (niveau "Presse hydraulique" du propriétaire). Gros bouton = Interact("Press").
type Crush = { Part: BasePart, Offset: CFrame, Size: Vector3, Axis: Vector3, Transparency: number, Variant: number }
local PRESS_DURATIONS = { Load = 1.3, Settle = 0.35, Descend = 0.9, Squeeze = 0.45, Hold = 0.35, Rise = 0.8, Eject = 0.9 }
local PRESS_NEXT = { Load = "Settle", Settle = "Descend", Descend = "Squeeze", Squeeze = "Hold", Hold = "Rise", Rise = "Eject", Eject = "Load" }
local TINT_ROLES = { Frame = "Frame", FrameDark = "Dark", AccentA = "AccentA", AccentB = "AccentB", Chrome = "Chrome", Hose = "Hose", Bolt = "Bolt" }
BEHAVIOURS.Press = function(h: Handle)
	local model = h.Model
	local ramPivot = findPart(model, "Pivot_Ram")
	local anvil = findPart(model, "Pivot_Anvil")
	local footprint = model:GetAttribute("Footprint")
	local k = typeof(footprint) == "Vector3" and footprint.X / 100 or 0.05 -- studs par unité
	local ramParts = partsNamed(model, "PressRam")
	local ramOffsets = {}
	local ramCFrames = {}
	if ramPivot then
		for index, part in ipairs(ramParts) do
			ramOffsets[index] = ramPivot.CFrame:ToObjectSpace(part.CFrame)
			ramCFrames[index] = part.CFrame
		end
	end
	-- objets (une variante visible à la fois), repère de l'enclume
	local crushables: { Crush } = {}
	local variants = 0
	if anvil then
		local up = anvil.CFrame.UpVector
		for _, part in ipairs(partsNamed(model, "Crushable")) do
			local cf = part.CFrame
			local dots = { math.abs(cf.RightVector:Dot(up)), math.abs(cf.UpVector:Dot(up)), math.abs(cf.LookVector:Dot(up)) }
			local axis = Vector3.new(0, 1, 0)
			if dots[1] >= dots[2] and dots[1] >= dots[3] then
				axis = Vector3.new(1, 0, 0)
			elseif dots[3] >= dots[2] then
				axis = Vector3.new(0, 0, 1)
			end
			local variant = tonumber(part:GetAttribute("Variant")) or 1
			variants = math.max(variants, variant)
			local offset = anvil.CFrame:ToObjectSpace(cf)
			table.insert(crushables, { Part = part, Offset = offset, Size = part.Size, Axis = axis, Transparency = part.Transparency, Variant = variant })
		end
	end
	-- trajets (studs, repère de l'enclume : +X = vers le tapis)
	local slats = partsNamed(model, "BeltSlat")
	local slatOffsets: { CFrame } = {}
	local slatCFrames: { CFrame } = {}
	local beltMin, beltMax = math.huge, -math.huge
	if anvil then
		for index, slat in ipairs(slats) do
			local offset = anvil.CFrame:ToObjectSpace(slat.CFrame)
			slatOffsets[index] = offset
			slatCFrames[index] = slat.CFrame
			beltMin = math.min(beltMin, offset.X)
			beltMax = math.max(beltMax, offset.X)
		end
	end
	-- (objet en miroir : le tapis est de l'autre côté)
	local beltSide = (#slats == 0 or (beltMin + beltMax) / 2 >= 0) and 1 or -1
	local range = beltMax > beltMin and beltMax - beltMin or 0
	local loadDX = #slats > 0 and (beltSide > 0 and beltMax + range * 0.1 or beltMin - range * 0.1) or 40 * k
	local binDX = -33 * k * beltSide
	local binDY = -16 * k
	local slatGap = #slats > 1 and (beltMax - beltMin) / (#slats - 1) or 1
	local slatShift = 0
	-- course du coulisseau : jusqu'à la hauteur d'une galette au-dessus de l'enclume
	local travel = 0
	if ramPivot and anvil then
		local plateBottom = math.huge
		for _, part in ipairs(ramParts) do
			local rel = anvil.CFrame:PointToObjectSpace(part.Position)
			plateBottom = math.min(plateBottom, rel.Y - part.Size.Y / 2)
		end
		travel = math.max(0, plateBottom - 3 * k)
	end
	local beacon = findPart(model, "PressBeacon")
	local display = findPart(model, "PressDisplay")
	local lamps = { findPart(model, "Lamp1"), findPart(model, "Lamp2"), findPart(model, "Lamp3") }
	type Needle = { Part: BasePart, Dial: BasePart, Rel: CFrame, Value: number }
	local needles: { Needle } = {}
	for index = 1, 2 do
		local needle = findPart(model, "Gauge" .. index)
		local dial = findPart(model, "GaugeDial" .. index)
		if needle and dial then
			mover(h, needle)
			table.insert(needles, { Part = needle, Dial = dial, Rel = dial.CFrame:ToObjectSpace(needle.CFrame), Value = 0 })
		end
	end
	-- couleurs du palier (propriétaire : son niveau ; visiteur : palier par défaut)
	local tinted: { BasePart } = {}
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") and type(d:GetAttribute("Tint")) == "string" then
			table.insert(tinted, d)
		end
	end
	local style: any = nil
	local function applyTier()
		local module = setupModule()
		local tiers = module and module.PressTiers
		if type(tiers) ~= "table" then
			return
		end
		local level = h.IsOwner and levelOf("Press") or 0
		local tier = level > 0 and math.clamp(math.floor(level), 1, #tiers) or (tonumber(module.PRESS_DEFAULT_TIER) or 5)
		if h.State.Tier == tier then
			return
		end
		h.State.Tier = tier
		style = tiers[tier]
		for _, part in ipairs(tinted) do
			local key = TINT_ROLES[part:GetAttribute("Tint")]
			local color = key and style[key]
			if typeof(color) == "Color3" then
				part.Color = color
				local role = part:GetAttribute("Tint")
				if role == "Frame" or role == "FrameDark" then
					part.Material = (style.Wood and role == "Frame") and Enum.Material.Wood or (style.Crystal and Enum.Material.Glass or Enum.Material.Metal)
				end
			end
		end
	end
	applyTier()
	-- éclats + vapeur (seulement dans la ville)
	local debris: ParticleEmitter? = nil
	local steam: ParticleEmitter? = nil
	if h.Interactive and anvil then
		for _, name in ipairs({ "PressDebris", "PressSteam" }) do
			local old = anvil:FindFirstChild(name)
			if old then
				old:Destroy()
			end
		end
		local s = math.max(0.3, k * 18)
		local emitter = Instance.new("ParticleEmitter")
		emitter.Name = "PressDebris"
		emitter.Rate = 0
		emitter.Lifetime = NumberRange.new(0.35, 0.75)
		emitter.Speed = NumberRange.new(4 * s, 9 * s)
		emitter.SpreadAngle = Vector2.new(75, 75)
		emitter.Acceleration = Vector3.new(0, -35 * s, 0)
		emitter.Drag = 1.5
		emitter.Size = NumberSequence.new(0.22 * s, 0.05 * s)
		emitter.Rotation = NumberRange.new(0, 360)
		emitter.RotSpeed = NumberRange.new(-240, 240)
		emitter.LightEmission = 0
		emitter.EmissionDirection = Enum.NormalId.Top
		emitter.Parent = anvil
		debris = emitter
		local puff = Instance.new("ParticleEmitter")
		puff.Name = "PressSteam"
		puff.Rate = 0
		puff.Lifetime = NumberRange.new(0.8, 1.4)
		puff.Speed = NumberRange.new(1.5 * s, 3 * s)
		puff.SpreadAngle = Vector2.new(35, 35)
		puff.Acceleration = Vector3.new(0, 2 * s, 0)
		puff.Size = NumberSequence.new(0.5 * s, 1.4 * s)
		puff.Transparency = NumberSequence.new(0.45, 1)
		puff.Color = ColorSequence.new(rgb(245, 245, 250))
		puff.LightEmission = 0
		puff.EmissionDirection = Enum.NormalId.Top
		puff.Parent = anvil
		steam = puff
	end
	-- afficheur (compteur d'écrasements)
	local counter: TextLabel? = nil
	local crushes = 0
	if h.Interactive and display then
		local state = clientState()
		local stats = state and state.Data and state.Data.Stats
		crushes = h.IsOwner and tonumber(stats and stats.PressCrushes) or 0
		local old = display:FindFirstChild("PressCounter")
		if old then
			old:Destroy()
		end
		local gui = Instance.new("SurfaceGui")
		gui.Name = "PressCounter"
		gui.Face = Enum.NormalId.Top
		gui.SizingMode = Enum.SurfaceGuiSizingMode.FixedSize
		gui.CanvasSize = Vector2.new(200, 100)
		gui.LightInfluence = 0
		gui.Brightness = 1
		gui.MaxDistance = 40
		gui.Active = false
		gui.Parent = display
		local text = Instance.new("TextLabel")
		text.BackgroundTransparency = 1
		text.Size = UDim2.fromScale(1, 1)
		text.Font = Enum.Font.Code
		text.TextSize = 40
		text.TextColor3 = rgb(110, 255, 150)
		text.Text = ""
		text.Parent = gui
		counter = text
	end
	local function showCount()
		if counter then
			counter.Text = string.format("💥%06d", math.floor(crushes) % 1000000)
		end
	end
	showCount()

	local current = 1
	local phase = "Load"
	local phaseTime = random:NextNumber(0, 1)
	local turbo = false
	local pendingTurbo = false
	local cooldownEnd = 0
	local tierClock = 0
	local settings = (Config.Interactions and Config.Interactions.Press) or {}
	local cooldown = tonumber(settings.Cooldown) or 3
	local function showVariant(variant: number, transparency: number?)
		for _, c in ipairs(crushables) do
			c.Part.Transparency = c.Variant == variant and math.max(c.Transparency, transparency or 0) or 1
		end
	end
	-- pose de l'objet : écrasement `s` (1 = intact), décalage (repère de l'enclume)
	local function placeItem(s: number, slide: Vector3)
		if not anvil then
			return
		end
		local g = math.min(1.9, 1 / math.sqrt(math.max(0.15, s)))
		local base = anvil.CFrame * CFrame.new(slide)
		for _, c in ipairs(crushables) do
			if c.Variant == current then
				local o = c.Offset
				local sx = c.Axis.X > 0.5 and s or g
				local sy = c.Axis.Y > 0.5 and s or g
				local sz = c.Axis.Z > 0.5 and s or g
				c.Part.Size = Vector3.new(c.Size.X * sx, c.Size.Y * sy, c.Size.Z * sz)
				c.Part.CFrame = base * CFrame.new(o.X * g, o.Y * s, o.Z * g) * o.Rotation
			end
		end
	end
	local function setRam(drop: number)
		if not ramPivot then
			return
		end
		local base = ramPivot.CFrame * CFrame.new(0, -drop, 0)
		for index, offset in ipairs(ramOffsets) do
			ramCFrames[index] = base * offset
		end
		workspace:BulkMoveTo(ramParts, ramCFrames, Enum.BulkMoveMode.FireCFrameChanged)
	end
	local function moveBelt(dx: number)
		if not anvil or #slats == 0 then
			return
		end
		local span = slatGap * #slats
		slatShift = (slatShift + dx) % span
		local base = anvil.CFrame
		local lo = beltMin - slatGap * 0.5
		for index, offset in ipairs(slatOffsets) do
			-- (les lamelles avancent vers l'enclume et reviennent au bout du tapis)
			local x = lo + ((offset.X - beltSide * slatShift - lo) % span)
			slatCFrames[index] = base * CFrame.new(x - offset.X, 0, 0) * offset
		end
		workspace:BulkMoveTo(slats, slatCFrames, Enum.BulkMoveMode.FireCFrameChanged)
	end
	local function setLamps(on: number)
		for index, lamp in ipairs(lamps) do
			if lamp then
				lamp.Transparency = index == on and 0 or 0.72
			end
		end
	end
	local squash = 1
	showVariant(current)
	placeItem(1, Vector3.new(loadDX, 0, 0))
	h.Step = function(_h, dt)
		tierClock += dt
		if tierClock > 3 then
			tierClock = 0
			applyTier()
		end
		local speed = (turbo and 3.2 or 1) * (1 + ((h.State.Tier or 5) - 1) * 0.05)
		phaseTime += dt * speed
		local duration = PRESS_DURATIONS[phase] or 1
		local t = math.clamp(phaseTime / duration, 0, 1)
		local pressure = 0
		if phase == "Load" then
			-- le tapis amène l'objet jusqu'à l'enclume
			local eased = 1 - (1 - t) ^ 2
			placeItem(1, Vector3.new(loadDX * (1 - eased), 0, 0))
			moveBelt(dt * speed * math.abs(loadDX) / duration * (1 - t * 0.6))
			setRam(0)
			setLamps(1)
		elseif phase == "Settle" then
			placeItem(1, Vector3.zero)
			setLamps(1)
			if pendingTurbo then
				t = 1
			end
		elseif phase == "Descend" then
			local drop = travel * (t * t)
			setRam(drop)
			pressure = t * 0.7
			-- le coulisseau touche l'objet vers 60 % de la course, puis l'écrase
			local touch = 0.6
			if t > touch then
				squash = 1 - (t - touch) / (1 - touch) * 0.85
				placeItem(squash, Vector3.zero)
				pressure = 0.7 + (t - touch) / (1 - touch) * 0.3
			end
			setLamps(3)
		elseif phase == "Squeeze" then
			setRam(travel + math.sin(t * math.pi * 7) * 0.012)
			pressure = 1
			setLamps(3)
		elseif phase == "Hold" then
			setRam(travel)
			pressure = 1 - t * 0.2
			setLamps(3)
		elseif phase == "Rise" then
			setRam(travel * (1 - t) ^ 2)
			pressure = 0.8 * (1 - t)
			setLamps(2)
		elseif phase == "Eject" then
			-- la galette glisse vers le bac, tombe et s'efface
			local fall = math.max(0, t - 0.55) / 0.45
			placeItem(0.15, Vector3.new(binDX * math.min(1, t / 0.7), binDY * fall * fall, 0))
			showVariant(current, math.clamp((t - 0.7) / 0.3, 0, 1))
			moveBelt(dt * speed * math.abs(loadDX) / PRESS_DURATIONS.Load * 0.5)
			setLamps(2)
		end
		-- manomètres (aiguilles qui suivent la pression, un peu de retard / tremblement)
		for index, needle in ipairs(needles) do
			local target = pressure * (index == 1 and 1 or 0.82) + (pressure > 0.95 and math.sin(h.Clock * 40) * 0.03 or 0)
			needle.Value += (target - needle.Value) * math.min(1, dt * (index == 1 and 9 or 5))
			needle.Part.CFrame = needle.Dial.CFrame * CFrame.Angles(needle.Value * 2.4, 0, 0) * needle.Rel
		end
		if beacon then
			local active = phase == "Descend" or phase == "Squeeze" or phase == "Hold"
			beacon.Transparency = active and ((math.floor(h.Clock * 6) % 2 == 0) and 0 or 0.55) or 0.25
		end
		if t >= 1 then
			local nextPhase = PRESS_NEXT[phase] or "Load"
			if phase == "Descend" then
				-- CRUNCH : éclats de la couleur du palier (+ l'objet) et son (si clic)
				squash = 0.15
				placeItem(squash, Vector3.zero)
				if debris then
					local first = style and style.Debris and style.Debris[1] or rgb(200, 205, 215)
					local itemColor = first
					for _, c in ipairs(crushables) do
						if c.Variant == current then
							itemColor = c.Part.Color
							break
						end
					end
					debris.Color = ColorSequence.new(itemColor, first)
					debris:Emit(18)
				end
				crushes += 1
				showCount()
				if h.State.Loud then
					h.State.Loud = false
					playSound("Crush", random:NextNumber(0.85, 1.15) * (turbo and 0.85 or 1))
				end
			elseif phase == "Rise" and steam and style and style.Steam then
				steam:Emit(6)
			elseif phase == "Eject" then
				-- objet suivant, remis intact au bout du tapis
				current = variants > 0 and (current % variants + 1) or 1
				squash = 1
				turbo = false
				showVariant(current)
				placeItem(1, Vector3.new(loadDX, 0, 0))
			elseif phase == "Settle" then
				turbo = pendingTurbo or turbo
				pendingTurbo = false
			end
			phase, phaseTime = nextPhase, 0
		end
	end
	if h.Interactive then
		for _, d in ipairs(model:GetDescendants()) do
			if d:IsA("BasePart") and d.Transparency < 1 and d.Name ~= "Hitbox" then
				table.insert(h.Clickables, d)
				h.Roles[d] = d.Name == "PressButton" and "PressButton" or "Press"
			end
		end
	end
	h.Click = function(_h, part, role, point)
		local button = role == "PressButton" and part or findPart(model, "PressButton")
		if button then
			press(h, button, button.Size.X * 0.4, nil)
		end
		if not hasFeature("PressStart") then
			-- sans "Turbo Press" : l'écrasement démarre quand même, sans bonus
			pendingTurbo = true
			popText(part, point, Locale.T("🔒 Unlocks with %s", upgradeName("PressStart")), rgb(230, 230, 240), 16)
			return
		end
		local now = os.clock()
		if now < cooldownEnd then
			playSound("Error", 1)
			return
		end
		cooldownEnd = now + cooldown
		interact("Press")
		playSound("Click", 0.7)
		h.State.Loud = true
		h.State.BonusSource = "Press"
		h.State.BonusAt = now
		if phase == "Descend" or phase == "Squeeze" or phase == "Hold" then
			turbo = true
		else
			pendingTurbo = true
			turbo = true
		end
	end
end

-- 🎧 Hi-fi : disque / bobines, membranes, VU ; ▶ et ⏭
BEHAVIOURS.HiFi = function(h: Handle)
	local vinylPivot = findPart(h.Model, "Pivot_Vinyl")
	local vinyl = partsNamed(h.Model, "Vinyl")
	local disc = vinylPivot and #vinyl > 0 and newSpinner(vinylPivot, vinyl, "Y", 3.5) or nil
	if disc then
		table.insert(h.Spinners, disc)
	end
	local spools = {}
	for index = 1, 2 do
		local p = findPart(h.Model, "Pivot_Spool" .. index)
		local list = partsNamed(h.Model, "Spool" .. index)
		if p and #list > 0 then
			local spinner = newSpinner(p, list, "Z", 4)
			table.insert(spools, spinner)
			table.insert(h.Spinners, spinner)
		end
	end
	local cones = partsNamed(h.Model, "SpeakerCone")
	for _, cone in ipairs(cones) do
		mover(h, cone)
	end
	local bars = {}
	for index = 1, 12 do
		local bar = findPart(h.Model, "VU_" .. index)
		if not bar then
			break
		end
		mover(h, bar)
		table.insert(bars, { Part = bar, Level = 0.3 })
	end
	local playButton = findPart(h.Model, "PlayButton")
	local nextButton = findPart(h.Model, "NextButton")
	local playing = true
	local checkTimer = 0
	local function musicPlaying(): boolean
		if not h.Interactive then
			return true -- aperçu : toujours en musique
		end
		local manager = soundManager()
		if manager and type(manager.IsMusicPlaying) == "function" then
			local ok, value = pcall(manager.IsMusicPlaying)
			if ok and value == true then
				return true
			end
			-- pas de musique dans la playlist : le disque tourne quand même doucement
			local okList, hasList = pcall(manager.HasPlaylist)
			return okList and hasList == false
		end
		return true
	end
	h.Step = function(_h, dt)
		checkTimer -= dt
		if checkTimer <= 0 then
			checkTimer = 0.5
			playing = musicPlaying()
			local speed = playing and 3.5 or 0
			if disc then
				disc.Target = speed
			end
			for _, spool in ipairs(spools) do
				spool.Target = playing and 4 or 0
			end
		end
		local clock = h.Clock
		local beat = playing and math.max(0, math.sin(clock * 8.4)) ^ 3 or 0
		local ref = refCF(h)
		for _, cone in ipairs(cones) do
			local m = h.Movers[cone]
			local s = 1 + beat * 0.1
			cone.Size = Vector3.new(m.Size.X * (1 + beat * 0.8), m.Size.Y * s, m.Size.Z * s)
		end
		for index, bar in ipairs(bars) do
			local target = playing and (0.2 + 0.8 * math.abs(math.sin(clock * (2.2 + index * 0.41) + index * 1.7)) * (0.6 + beat * 0.4)) or 0.08
			bar.Level += (target - bar.Level) * math.min(1, dt * 14)
			local m = h.Movers[bar.Part]
			local height = math.max(0.02, m.Size.Y * bar.Level)
			bar.Part.Size = Vector3.new(m.Size.X, height, m.Size.Z)
			bar.Part.CFrame = ref * m.Offset * CFrame.new(0, -(m.Size.Y - height) / 2, 0)
		end
	end
	if h.Interactive then
		for _, d in ipairs(h.Model:GetDescendants()) do
			if d:IsA("BasePart") and d.Transparency < 1 and d.Name ~= "Hitbox" then
				table.insert(h.Clickables, d)
				h.Roles[d] = (d.Name == "NextButton" and "Next") or "Play"
			end
		end
	end
	h.Click = function(_h, part, role, point)
		local manager = soundManager()
		if not hasFeature("Lofi") then
			popText(part, point, Locale.T("🔒 Unlocks with 🎧 %s", Locale.T("Lofi Beats")), rgb(220, 200, 255), 16)
			return
		end
		if role == "Next" then
			if nextButton then
				press(h, nextButton, nextButton.Size.Y * 0.5, rgb(200, 230, 255))
			end
			if manager and type(manager.NextTrack) == "function" then
				local ok, changed = pcall(manager.NextTrack)
				if ok and changed then
					playSound("Open", 1.25)
					popText(part, point, "⏭", WHITE, 24)
					for _, spinner in ipairs(h.Spinners) do
						spinner.Speed = 12 -- petit coup de disque
					end
				end
			end
			return
		end
		if playButton then
			press(h, playButton, playButton.Size.Y * 0.5, rgb(200, 255, 220))
		end
		-- ▶ / ❚❚ : même chemin que le lecteur des ⚙️ Réglages
		local settings = settingsPanel()
		if settings and type(settings.Get) == "function" and type(settings.Apply) == "function" then
			local okGet, current = pcall(settings.Get, "Music")
			local newValue = not (okGet and current ~= false)
			pcall(settings.Apply, "Music", newValue)
			playSound("Open", newValue and 1.3 or 0.8)
			popText(part, point, newValue and "▶" or "❚❚", WHITE, 24)
			checkTimer = 0
			task.spawn(function()
				local module = net()
				if module then
					pcall(function()
						module.Function("SetSetting"):InvokeServer("Music", newValue)
					end)
				end
			end)
		end
	end
end

-- 📰 Écran d'infos : clic = Interact("Headline")
BEHAVIOURS.NewsTV = function(h: Handle)
	local lamp = findPart(h.Model, "OnAir")
	h.Step = function(_h, _dt)
		if lamp then
			lamp.Transparency = (math.floor(h.Clock * 1.5) % 2 == 0) and 0 or 0.45
		end
	end
	if h.Interactive then
		for _, rec in ipairs(h.Screens) do
			table.insert(h.Clickables, rec.Part)
			h.Roles[rec.Part] = "Headline"
		end
	end
	local settings = (Config.Interactions and Config.Interactions.Headline) or {}
	local cooldown = tonumber(settings.Cooldown) or 8
	local last = -math.huge
	h.Click = function(_h, part, _role, point)
		local now = os.clock()
		if now - last < cooldown then
			popText(part, point, "📰", WHITE, 22)
			return
		end
		last = now
		playSound("Click", 1)
		if hasFeature("NewsTicker") then
			interact("Headline")
			h.State.BonusSource = "Headline"
			h.State.BonusAt = now
		end
		popText(part, point, "📰 !", WHITE, 22)
	end
end

-- 🎥 Coin live : voyant REC, ON AIR, anneau qui respire
BEHAVIOURS.LiveStudio = function(h: Handle)
	local rec = findPart(h.Model, "RecLight")
	local onAir = findPart(h.Model, "OnAir")
	local ring = partsNamed(h.Model, "RingLight")
	h.Step = function(_h, _dt)
		local clock = h.Clock
		if rec then
			rec.Transparency = (math.floor(clock * 1.2) % 2 == 0) and 0 or 0.7
		end
		if onAir then
			onAir.Transparency = 0.1 + (math.sin(clock * 2.5) + 1) * 0.12
		end
		local warm = rgb(255, 246, 236):Lerp(rgb(255, 214, 236), (math.sin(clock * 0.8) + 1) / 2)
		for _, part in ipairs(ring) do
			part.Color = warm
		end
	end
end

-- 📺 Télé : clic sur l'écran = chaîne suivante (v9.8) ; halo doux ("ambilight")
-- de la couleur de la chaîne
local CHANNELS = { "Live", "DVD", "News", "Runner" }
local CHANNEL_NAMES = { Live = "🔴 Live", DVD = "📀 DVD", News = "📰 News", Runner = "🏃 Runner" }
local HALO_COLORS = { Live = rgb(220, 120, 255), DVD = rgb(90, 200, 255), News = rgb(90, 140, 255), Runner = rgb(255, 190, 120) }
BEHAVIOURS.TV = function(h: Handle)
	local halo = findPart(h.Model, "Ambilight")
	local rec = h.Screens[1]
	if halo then
		h.Step = function(_h, _dt)
			local base = HALO_COLORS[rec and rec.Kind or "DVD"] or CYAN_SOFT
			halo.Color = base:Lerp(WHITE, 0.25 + 0.15 * math.sin(h.Clock * 0.9))
		end
	end
	if h.Interactive and rec then
		table.insert(h.Clickables, rec.Part)
		h.Roles[rec.Part] = "Channel"
	end
	local last = -math.huge
	h.Click = function(_h, part, role, point)
		if role ~= "Channel" or not rec then
			return
		end
		local now = os.clock()
		if now - last < 0.35 then
			return
		end
		last = now
		local index = table.find(CHANNELS, rec.Kind) or 0
		local kind = CHANNELS[index % #CHANNELS + 1]
		;(LiveProps :: any).SetChannel(rec, kind)
		popText(part, point, "📺 " .. Locale.T(CHANNEL_NAMES[kind] or kind), WHITE, 20)
	end
end

-- 🌼 Plante : la fleur se balance ; le lotus scintille
BEHAVIOURS.Plant = function(h: Handle)
	local pivotPart = findPart(h.Model, "Pivot_Flower")
	local parts = partsNamed(h.Model, "Flower")
	local sway = pivotPart and #parts > 0 and newSpinner(pivotPart, parts, "Z", 0) or nil
	local sparkles = partsNamed(h.Model, "Sparkle")
	for _, spark in ipairs(sparkles) do
		mover(h, spark)
	end
	local phase = random:NextNumber(0, 6)
	h.Step = function(_h, _dt)
		local clock = h.Clock + phase
		if sway then
			swaySpinner(sway, clock, 0.05)
		end
		local ref = refCF(h)
		for index, spark in ipairs(sparkles) do
			local m = h.Movers[spark]
			spark.CFrame = ref * m.Offset * CFrame.new(0, math.sin(clock * 1.6 + index) * m.Size.Y * 1.5, 0)
			spark.Transparency = 0.2 + (math.sin(clock * 3 + index * 1.3) + 1) * 0.3
		end
	end
end

----------------------------------------------------------------------
-- Boucle
----------------------------------------------------------------------

local function currentFocus(): Vector3
	if focusPoint and os.clock() - focusAt < 2 then
		return focusPoint
	end
	local camera = workspace.CurrentCamera
	if camera then
		return camera.CFrame.Position
	end
	return Vector3.zero
end

local function characterPosition(): Vector3?
	local player = Players.LocalPlayer
	local character = player and player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if root and root:IsA("BasePart") then
		return root.Position
	end
	return nil
end

local function rebuildClickList()
	table.clear(clickList)
	for _, h in ipairs(handles) do
		if h.Alive and h.Interactive and (h.Distance < 40 or h == deskFocus) then
			for _, part in ipairs(h.Clickables) do
				table.insert(clickList, part)
			end
		end
	end
end

local animClock, manageClock, hoverClock, rgbClock = 0, 0, 0, 0
local hover: SelectionBox? = nil
local pointer: Vector2? = nil

local function handleOf(part: Instance): Handle?
	local node: Instance? = part
	while node and node ~= workspace do
		if node:IsA("Model") then
			local h = byModel[node]
			if h then
				return h
			end
		end
		node = node.Parent
	end
	return nil
end

local function raycast(position: Vector2): (BasePart?, Vector3?, Handle?)
	if #clickList == 0 then
		return nil, nil, nil
	end
	local camera = workspace.CurrentCamera
	if not camera then
		return nil, nil, nil
	end
	local ray = camera:ScreenPointToRay(position.X, position.Y)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = clickList
	local result = workspace:Raycast(ray.Origin, ray.Direction * 200, params)
	if not result then
		return nil, nil, nil
	end
	local part = result.Instance
	if not part:IsA("BasePart") then
		return nil, nil, nil
	end
	return part, result.Position, handleOf(part)
end

local function tryClick(position: Vector2): boolean
	local part, point, h = raycast(position)
	if not part or not point or not h or not h.Alive or not h.Interactive then
		return false
	end
	local near = h == deskFocus
	if not near and deskFocus then
		-- clavier / souris posés sur le bureau du mode bureau
		for _, other in ipairs(LiveProps.Peripherals(deskFocus)) do
			if other == h then
				near = true
			end
		end
	end
	if not near then
		local character = characterPosition()
		near = character ~= nil and (character - point).Magnitude <= LiveProps.CLICK_DISTANCE
	end
	if not near then
		popText(part, point, Locale.T("Get closer 👣"), WHITE, 18)
		return true
	end
	local role = h.Roles[part] or "Any"
	local click = h.Click
	if click then
		local ok, err = pcall(click, h, part, role, point)
		if not ok then
			warn("[LiveProps] Clic " .. h.ItemId .. " : " .. tostring(err))
		end
	end
	return true
end

local function stepHover()
	if not UserInputService.MouseEnabled or not pointer then
		return
	end
	local part, point, h = raycast(pointer :: Vector2)
	local target: BasePart? = nil
	if part and h and point then
		local character = characterPosition()
		if h == deskFocus or (character and (character - point).Magnitude <= LiveProps.CLICK_DISTANCE) then
			target = part
		end
	end
	if target then
		local box = hover
		if not box then
			local newBox = Instance.new("SelectionBox")
			newBox.Name = "LivePropsHover"
			newBox.LineThickness = 0.02
			newBox.Color3 = rgb(255, 120, 200)
			newBox.SurfaceTransparency = 1
			newBox.Parent = playerGui() or workspace
			hover = newBox
			box = newBox
		end
		if box then
			box.Adornee = target
			box.Visible = true
		end
	elseif hover then
		hover.Adornee = nil
		hover.Visible = false
	end
end

local function manage()
	local focus = currentFocus()
	for index = #handles, 1, -1 do
		local h = handles[index]
		if not h.Model.Parent or not h.Ref.Parent then
			-- modèle retiré sans Detach (reconstruction de la pièce) : on nettoie
			LiveProps.Detach(h)
		else
			h.Distance = (h.Ref.Position - focus).Magnitude
			h.Paused = h ~= deskFocus and h.Distance > h.PauseDistance
		end
	end
	manageScreens(focus)
	rebuildClickList()
	-- légendes : seulement le clavier le plus proche (ou celui du mode bureau)
	local best: Handle? = nil
	local bestDistance = LiveProps.LEGEND_DISTANCE
	local deskKeyboards: { [Handle]: boolean } = {}
	if deskFocus then
		for _, other in ipairs(LiveProps.Peripherals(deskFocus)) do
			deskKeyboards[other] = true
		end
	end
	for _, h in ipairs(handles) do
		if h.Alive and h.Kind == "Keyboard" and h.Interactive then
			local distance = deskKeyboards[h] and -1 or h.Distance
			if distance < bestDistance then
				best, bestDistance = h, distance
			end
		end
	end
	for _, h in ipairs(handles) do
		if h.Kind == "Keyboard" then
			if h == best then
				local ok, err = pcall(buildLegends, h)
				if not ok then
					warn("[LiveProps] Légendes : " .. tostring(err))
					h.State.LegendPlates = h.State.LegendPlates or {}
				end
			else
				dropLegends(h)
			end
		end
	end
end

-- Une image d'animation d'un objet (appelée dans un pcall, sans fermeture)
local function stepHandle(h: Handle, step: number, doRGB: boolean)
	for _, spinner in ipairs(h.Spinners) do
		if spinner.Speed ~= 0 or spinner.Target ~= 0 then
			stepSpinner(spinner, step)
		end
	end
	stepPresses(h, step)
	local custom = h.Step
	if custom then
		custom(h, step)
	end
	if doRGB and #h.RGB > 0 then
		for index, part in ipairs(h.RGB) do
			part.Color = Color3.fromHSV((h.Clock * 0.12 + index * 0.07) % 1, 0.72, 1)
		end
	end
	for _, rec in ipairs(h.Screens) do
		local screen = rec.Screen
		if screen then
			screen:Step(step)
		end
	end
end

local function onHeartbeat(dt: number)
	dt = math.min(dt, 0.1)
	manageClock += dt
	if manageClock >= MANAGE_STEP then
		manageClock = 0
		manage()
	end
	animClock += dt
	if animClock < ANIM_STEP then
		stepFloaters(dt)
		return
	end
	local step = animClock
	animClock = 0
	stepFloaters(step)
	rgbClock += step
	local doRGB = rgbClock >= RGB_STEP
	if doRGB then
		rgbClock = 0
	end
	for _, h in ipairs(handles) do
		if h.Alive and not h.Paused then
			h.Clock += step
			local ok, err = pcall(stepHandle, h, step, doRGB)
			if not ok then
				warn("[LiveProps] " .. h.ItemId .. " : " .. tostring(err))
				h.Paused = true
			end
		end
	end
	hoverClock += step
	if hoverClock >= HOVER_STEP then
		hoverClock = 0
		stepHover()
	end
end

local function ensureLoop()
	if not heartbeat then
		heartbeat = RunService.Heartbeat:Connect(onHeartbeat)
	end
	if #inputConnections == 0 then
		table.insert(inputConnections, UserInputService.InputBegan:Connect(function(input: InputObject, processed: boolean)
			if processed then
				return
			end
			local kind = input.UserInputType
			if kind == Enum.UserInputType.MouseButton1 or kind == Enum.UserInputType.Touch then
				tryClick(Vector2.new(input.Position.X, input.Position.Y))
			end
		end))
		table.insert(inputConnections, UserInputService.InputChanged:Connect(function(input: InputObject)
			if input.UserInputType == Enum.UserInputType.MouseMovement then
				pointer = Vector2.new(input.Position.X, input.Position.Y)
			end
		end))
	end
	if not notifyConnection then
		local state = clientState()
		if state and state.NotifyReceived and type(state.NotifyReceived.Connect) == "function" then
			-- bonus du serveur (Spin / Press / Headline) : "+X" au-dessus de l'objet
			notifyConnection = state.NotifyReceived:Connect(function(payload: any)
				if type(payload) ~= "table" or payload.Type ~= "Bonus" then
					return
				end
				local amount = tonumber(payload.Amount)
				if not amount then
					return
				end
				local now = os.clock()
				for _, h in ipairs(handles) do
					if h.Alive and h.State.BonusSource == payload.Source and now - (h.State.BonusAt or 0) < 4 then
						h.State.BonusSource = nil
						local anchor = h.Ref
						local top = h.Model:GetAttribute("Footprint")
						local lift = typeof(top) == "Vector3" and top.Y or 3
						popText(anchor, anchor.Position + Vector3.new(0, lift + 0.5, 0), "+" .. formatGain(amount), rgb(255, 214, 80), 28)
						return
					end
				end
			end)
		end
	end
end

local function stopLoop()
	if heartbeat then
		heartbeat:Disconnect()
		heartbeat = nil
	end
	for _, connection in ipairs(inputConnections) do
		connection:Disconnect()
	end
	table.clear(inputConnections)
	if notifyConnection then
		pcall(function()
			notifyConnection:Disconnect()
		end)
		notifyConnection = nil
	end
	if hover then
		hover:Destroy()
		hover = nil
	end
	for _, f in ipairs(floaters) do
		f.Gui:Destroy()
	end
	table.clear(floaters)
	table.clear(clickList)
end

----------------------------------------------------------------------
-- API
----------------------------------------------------------------------

function LiveProps.IsLive(itemId: string): boolean
	local module = setupModule()
	if module and type(module.KindOf) == "function" then
		local ok, kind = pcall(module.KindOf, itemId)
		return ok and kind ~= nil
	end
	local item = Config.HouseItemsById and Config.HouseItemsById[itemId]
	return type(item) == "table" and type(item.Setup) == "table"
end

local function setupOf(itemId: string): { [string]: any }?
	local module = setupModule()
	if module and type(module.SetupOf) == "function" then
		local ok, setup = pcall(module.SetupOf, itemId)
		if ok and type(setup) == "table" then
			return setup
		end
	end
	local item = Config.HouseItemsById and Config.HouseItemsById[itemId]
	if type(item) == "table" and type(item.Setup) == "table" then
		return item.Setup
	end
	return nil
end

function LiveProps.Attach(model: Model, itemId: string?, context: { [string]: any }?): Handle?
	if typeof(model) ~= "Instance" or not model:IsA("Model") then
		return nil
	end
	if byModel[model] then
		return byModel[model]
	end
	local id = tostring(itemId or model:GetAttribute("ItemId") or "")
	local setup = setupOf(id)
	if not setup then
		return nil
	end
	local ctx = type(context) == "table" and context or {}
	local ref = model.PrimaryPart or model:FindFirstChild("Root")
	if not ref or not ref:IsA("BasePart") then
		ref = model:FindFirstChildWhichIsA("BasePart", true)
	end
	if not ref then
		return nil
	end
	local h: Handle = {
		Model = model,
		ItemId = id,
		Kind = tostring(setup.Kind or ""),
		Setup = setup,
		Interactive = ctx.Interactive == true,
		IsOwner = ctx.IsOwner == true,
		Alive = true,
		Ref = ref :: BasePart,
		Paused = false,
		Distance = 0,
		-- (aperçu 3D du panneau : caméra en orbite plus loin, jamais en pause)
		PauseDistance = tonumber(ctx.PauseDistance) or (ctx.Interactive == true and LiveProps.PAUSE_DISTANCE or 250),
		ScreenDistance = tonumber(ctx.ScreenDistance) or (ctx.Interactive == true and LiveProps.SCREEN_DISTANCE or 300),
		Clock = random:NextNumber(0, 10),
		Screens = {},
		Clickables = {},
		Roles = {},
		RGB = {},
		Movers = {},
		Presses = {},
		Spinners = {},
		State = {},
		Connections = {},
		Prompt = nil,
		Step = nil,
		Click = nil,
		Visual = nil,
	}
	-- écrans + bandes RGB (toutes familles)
	local wings: { [number]: { BasePart } } = {}
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") then
			if d.Name == "Screen" then
				local rec: ScreenRec = {
					Part = d,
					Kind = tostring(d:GetAttribute("ScreenKind") or "DVD"),
					Index = tonumber(d:GetAttribute("ScreenIndex")) or (#h.Screens + 1),
					Handle = h,
					Gui = nil,
					Screen = nil,
					Real = false,
					RealBroken = false,
					Override = nil,
					Wings = {},
					BaseColor = d.Color,
					BaseMaterial = d.Material,
				}
				table.insert(h.Screens, rec)
				table.insert(screens, rec)
				screenOff(rec)
			elseif d.Name == "ScreenWing" then
				local index = tonumber(d:GetAttribute("ScreenIndex")) or 0
				wings[index] = wings[index] or {}
				table.insert(wings[index], d)
			elseif d.Name == "RGB" then
				table.insert(h.RGB, d)
			end
		end
	end
	for _, rec in ipairs(h.Screens) do
		rec.Wings = wings[rec.Index] or {}
		local tint = LiveScreens.Tints[rec.Kind]
		for _, wing in ipairs(rec.Wings) do
			if tint then
				wing.Color = tint
			end
		end
	end
	local behaviour = BEHAVIOURS[h.Kind]
	if behaviour then
		local ok, err = pcall(behaviour, h)
		if not ok then
			warn("[LiveProps] " .. id .. " : " .. tostring(err))
		end
	end
	if not h.Interactive then
		table.clear(h.Clickables)
		h.Click = nil
	end
	-- nettoyage automatique si le modèle est détruit sans Detach
	table.insert(h.Connections, model.AncestryChanged:Connect(function(_, parent)
		if parent == nil and h.Alive then
			task.defer(function()
				if h.Alive and model.Parent == nil then
					LiveProps.Detach(h)
				end
			end)
		end
	end))
	table.insert(handles, h)
	byModel[model] = h
	ensureLoop()
	manageClock = MANAGE_STEP -- écrans attribués dès la prochaine image
	return h
end

function LiveProps.Detach(handle: Handle?)
	local h = handle
	if type(h) ~= "table" or not h.Alive then
		return
	end
	h.Alive = false
	for _, connection in ipairs(h.Connections) do
		pcall(function()
			connection:Disconnect()
		end)
	end
	table.clear(h.Connections)
	if h.Prompt then
		h.Prompt:Destroy()
		h.Prompt = nil
	end
	for _, rec in ipairs(h.Screens) do
		releaseGui(rec)
		local index = table.find(screens, rec)
		if index then
			table.remove(screens, index)
		end
	end
	-- pièces remises au repos (le modèle peut rester dans le monde)
	if h.Model.Parent and h.Ref.Parent then
		local ref = refCF(h)
		for part, m in pairs(h.Movers) do
			if part.Parent then
				part.Size = m.Size
				part.CFrame = ref * m.Offset
			end
		end
		for _, p in ipairs(h.Presses) do
			if p.Part.Parent then
				p.Part.Color = p.Base
				p.Part.Material = p.Material
			end
		end
	end
	table.clear(h.Presses)
	pcall(dropLegends, h)
	for _, rec in ipairs(h.Screens) do
		rec.Override = nil
	end
	if deskFocus == h then
		deskFocus = nil
	end
	local index = table.find(handles, h)
	if index then
		table.remove(handles, index)
	end
	if byModel[h.Model] == h then
		byModel[h.Model] = nil
	end
	if #handles == 0 then
		stopLoop()
	end
end

function LiveProps.AttachAll(models: { Instance }, context: { [string]: any }?): { Handle }
	local list = {}
	if type(models) ~= "table" then
		return list
	end
	for _, model in ipairs(models) do
		if typeof(model) == "Instance" and model:IsA("Model") then
			local id = model:GetAttribute("ItemId")
			if type(id) == "string" and LiveProps.IsLive(id) then
				local ok, h = pcall(LiveProps.Attach, model, id, context)
				if ok and h then
					table.insert(list, h)
				elseif not ok then
					warn("[LiveProps] " .. tostring(id) .. " : " .. tostring(h))
				end
			end
		end
	end
	return list
end

function LiveProps.DetachAll(list: { Handle }?)
	if type(list) ~= "table" then
		return
	end
	for _, h in ipairs(list) do
		pcall(LiveProps.Detach, h)
	end
end

function LiveProps.SetFocus(position: Vector3?)
	if typeof(position) == "Vector3" then
		focusPoint = position
		focusAt = os.clock()
	else
		focusPoint = nil
	end
end

function LiveProps.SetDeskFocus(handle: Handle?)
	deskFocus = (type(handle) == "table" and handle.Alive) and handle or nil
	manageClock = MANAGE_STEP
end

function LiveProps.GetDeskFocus(): Handle?
	return deskFocus
end

function LiveProps.Count(): number
	return #handles
end

function LiveProps.Handles(): { Handle }
	return table.clone(handles)
end

-- Bureau le plus proche d'un point (siège, personnage)
function LiveProps.DeskNear(position: Vector3, radius: number?): Handle?
	local best, bestDistance = nil, radius or 4
	for _, h in ipairs(handles) do
		if h.Alive and h.Kind == "Desk" then
			local seat = h.Model:FindFirstChild("SeatPart")
			local at = (seat and seat:IsA("BasePart")) and seat.Position or h.Ref.Position
			local distance = (at - position).Magnitude
			if distance < bestDistance then
				best, bestDistance = h, distance
			end
		end
	end
	return best
end

-- Clavier / souris (et autres objets Setup) posés sur le dessus d'un bureau
function LiveProps.Peripherals(desk: Handle?): { Handle }
	local list = {}
	if type(desk) ~= "table" or not desk.Alive then
		return list
	end
	local footprint = desk.Model:GetAttribute("Footprint")
	local width = typeof(footprint) == "Vector3" and footprint.X or 6
	local center = desk.Ref.CFrame
	local topCenter = desk.Model:GetAttribute("TopCenter")
	if typeof(topCenter) == "Vector3" then
		center = center * CFrame.new(topCenter)
	end
	for _, h in ipairs(handles) do
		if h ~= desk and h.Alive and (h.Kind == "Keyboard" or h.Kind == "Mouse") then
			local rel = center:PointToObjectSpace(h.Ref.Position)
			if math.abs(rel.X) <= width / 2 + 0.5 and math.abs(rel.Z) <= 3 and math.abs(rel.Y) <= 1.5 then
				table.insert(list, h)
			end
		end
	end
	return list
end

-- Handle d'un modèle (nil si le modèle n'est pas vivant)
function LiveProps.HandleOf(model: Instance?): Handle?
	if typeof(model) ~= "Instance" or not model:IsA("Model") then
		return nil
	end
	return byModel[model]
end

-- Branche LiveProps sur les crochets de HouseBuilder (OnItemAttach /
-- OnItemDetach, v9.5) : chaque objet Setup construit dans une maison de la
-- ville devient vivant et cliquable ; retiré = détaché. Idempotent ; les
-- crochets déjà posés par quelqu'un d'autre sont appelés aussi.
local boundBuilders: { [any]: boolean } = setmetatable({}, { __mode = "k" }) :: any
function LiveProps.BindHouseBuilder(builder: any)
	if type(builder) ~= "table" or boundBuilders[builder] then
		return
	end
	boundBuilders[builder] = true
	local previousAttach = builder.OnItemAttach
	local previousDetach = builder.OnItemDetach
	builder.OnItemAttach = function(house: any, slot: number, model: Model, entry: any, itemId: string)
		if type(previousAttach) == "function" then
			pcall(previousAttach, house, slot, model, entry, itemId)
		end
		if LiveProps.IsLive(itemId) then
			local player = Players.LocalPlayer
			local owner = type(house) == "table" and tonumber(house.UserId) or 0
			LiveProps.Attach(model, itemId, { Interactive = true, IsOwner = player ~= nil and owner == player.UserId, OwnerId = owner })
		end
	end
	builder.OnItemDetach = function(house: any, slot: number, model: Model, entry: any, itemId: string)
		if type(previousDetach) == "function" then
			pcall(previousDetach, house, slot, model, entry, itemId)
		end
		local h = LiveProps.HandleOf(model)
		if h then
			LiveProps.Detach(h)
		end
	end
end

-- (v9.8) Le plus grand écran d'un bureau (celui du jeu)
function LiveProps.MainScreen(desk: Handle?): ScreenRec?
	if type(desk) ~= "table" or not desk.Alive then
		return nil
	end
	local best: ScreenRec? = nil
	local bestArea = -1
	for _, rec in ipairs(desk.Screens) do
		local area = rec.Part.Size.X * rec.Part.Size.Y
		if area > bestArea + 1e-4 then
			best, bestArea = rec, area
		end
	end
	return best
end

-- (v9.8) Un écran pris par un autre contenu (jeu du bureau) ; nil = rendu
function LiveProps.SetOverride(rec: ScreenRec?, override: Override?)
	if type(rec) ~= "table" then
		return
	end
	if rec.Override == override then
		return
	end
	rec.Override = override
	releaseGui(rec)
	manageClock = MANAGE_STEP -- (redessiné à la prochaine image)
end

-- (v9.8) Chaîne d'un écran (télé) : redessiné tout de suite
function LiveProps.SetChannel(rec: ScreenRec?, kind: string)
	if type(rec) ~= "table" or type(kind) ~= "string" or rec.Kind == kind then
		return
	end
	rec.Kind = kind
	rec.RealBroken = false
	releaseGui(rec)
	manageClock = MANAGE_STEP
end

-- (v9.8) Appui visuel (jeu du bureau) : la touche / le bouton s'enfonce, sans
-- clic ni son
function LiveProps.PressVisual(handle: Handle?, partName: string): boolean
	local h = handle
	if type(h) ~= "table" or not h.Alive or not h.Visual then
		return false
	end
	local byName = h.State.KeysByName
	local part = (byName and byName[partName]) or findPart(h.Model, partName)
	if not part then
		return false
	end
	local ok = pcall(h.Visual :: any, h, part)
	return ok
end

-- Appui programmé (DeskMode : vraies touches du clavier du joueur)
function LiveProps.Press(handle: Handle?, partName: string): boolean
	local h = handle
	if type(h) ~= "table" or not h.Alive or not h.Click then
		return false
	end
	local part = findPart(h.Model, partName)
	if not part then
		return false
	end
	local ok = pcall(h.Click :: any, h, part, h.Roles[part] or "Any", part.Position)
	return ok
end

return LiveProps
