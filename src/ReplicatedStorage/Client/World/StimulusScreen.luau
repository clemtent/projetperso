--[[
	StimulusScreen (ModuleScript)
	Emplacement : ReplicatedStorage > Client > World > StimulusScreen

	v9.8 🖥️ Les écrans 3D des objets "Dopamine Setup" montrent le VRAI
	contenu du clicker : le module stimulus du clicker (Client > Stimuli) est
	lancé DANS la toile SurfaceGui de l'écran, avec un "ctx" bac à sable :
	  - "Runner" : Stimuli.Runner (même course, mêmes dessins, même animation) ;
	    le cadre "téléphone" déborde de la toile (on ne voit que l'image) ;
	  - "Live"   : Stimuli.LiveStream (la streameuse, le chat, les réactions),
	    centré, avec un fond de page de streaming sur les côtés ;
	  - "DVD"    : Stimuli.DVD (les logos du clicker, mêmes positions que
	    l'écran du clicker : même calcul DVDMath à l'heure du serveur) sur
	    un fond de télé ;
	  - "News"   : plateau du flash info (LiveScreens) + le VRAI bandeau
	    Stimuli.NewsTicker en bas (et ses "ALERTE INFO" par-dessus).
	Bac à sable : AUCUN appel serveur (Interact, ClaimSpawn, Net -> muets),
	AUCUN son (ctx.Sound muet), pas de confettis / flash plein écran, pas
	d'apparitions (dons, bonus). La toile est inerte (SurfaceGui.Active =
	false, posée par LiveProps) : on regarde, on ne clique pas dedans.
	Le rendu est piloté par LiveProps (Step(dt), ≤ 30 images / s, seulement
	les écrans proches : voir LiveProps.REAL_MAX / REAL_DISTANCE).

	API :
	  StimulusScreen.Supports(kind) -> boolean
	  StimulusScreen.Canvas(kind, aspect) -> Vector2        (taille de toile conseillée)
	  StimulusScreen.New(kind, gui, canvas) -> Screen?      (nil : module absent / erreur)
	  screen:Step(dt)   screen:Destroy()   screen.Failed (erreur pendant le rendu)
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local LiveScreens = require(script.Parent.LiveScreens)

local StimulusScreen = {}

local Client = script.Parent.Parent

local rgb = Color3.fromRGB

export type Screen = {
	Kind: string,
	Root: Frame,
	Real: boolean,
	Failed: boolean,
	Step: (self: Screen, dt: number) -> (),
	Destroy: (self: Screen) -> (),
}

----------------------------------------------------------------------
-- Modules du client (chargés à la demande, jamais bloquants)
----------------------------------------------------------------------

local cache: { [string]: any } = {}
local function lazy(key: string, loader: () -> any): any
	local cached = cache[key]
	if cached ~= nil then
		return cached or nil
	end
	local ok, result = pcall(loader)
	cache[key] = (ok and result) or false
	return cache[key] or nil
end

local function clientModule(name: string): any
	return lazy(name, function()
		local module = Client:FindFirstChild(name)
		return module and module:IsA("ModuleScript") and require(module) :: any or nil
	end)
end

local function sharedModule(name: string): any
	return lazy("Shared." .. name, function()
		local module = ReplicatedStorage.Shared:FindFirstChild(name)
		return module and module:IsA("ModuleScript") and require(module) :: any or nil
	end)
end

local function stimulus(name: string): any
	return lazy("Stimuli." .. name, function()
		local folder = Client:FindFirstChild("Stimuli")
		local module = folder and folder:FindFirstChild(name)
		if module and module:IsA("ModuleScript") then
			local loaded = require(module) :: any
			if type(loaded) == "table" and type(loaded.Start) == "function" then
				return loaded
			end
		end
		return nil
	end)
end

----------------------------------------------------------------------
-- Bac à sable : son, réseau et effets plein écran muets
----------------------------------------------------------------------

local function noop(...: any): any
	return nil
end

-- Son muet : toute fonction appelée ne fait rien (jamais de son en plus)
local SILENT = setmetatable({}, {
	__index = function()
		return noop
	end,
})

-- Réseau muet : les écrans 3D n'envoient RIEN au serveur (pas de DVDResize,
-- DVDCorner, Interact...) : l'écran du clicker reste la seule source
local DEAD_REMOTE = {
	FireServer = noop,
	InvokeServer = noop,
	OnClientEvent = { Connect = function()
		return { Connected = false, Disconnect = noop }
	end },
}
local FAKE_NET = setmetatable({
	Event = function()
		return DEAD_REMOTE
	end,
	Function = function()
		return DEAD_REMOTE
	end,
}, {
	__index = function()
		return noop
	end,
})

local function safeEffects(): any
	local effects = clientModule("Effects")
	return setmetatable({
		Burst = effects and effects.Burst or noop,
		FloatingText = effects and effects.FloatingText or noop,
		Pop = effects and effects.Pop or noop,
		AmountStyle = effects and effects.AmountStyle or noop,
		Confetti = noop, -- (plein écran : jamais depuis un écran 3D)
		Flash = noop,
		Shake = noop,
	}, {
		__index = function()
			return noop
		end,
	})
end

local DEAD_CONNECTION = { Connected = false, Disconnect = noop }

type Sandbox = { Ctx: any, Renders: { (dt: number) -> () }, Connections: { any }, Alive: boolean }

local function sandbox(feature: string, module: any, container: Frame, overlay: Frame, design: Vector2): Sandbox
	local ClientState = clientModule("ClientState")
	local box: Sandbox = { Ctx = nil, Renders = {}, Connections = {}, Alive = true }
	local ctx: { [string]: any } = {}
	ctx.Feature = feature
	ctx.Slot = module.Slot
	ctx.Container = container
	ctx.Overlay = overlay
	ctx.State = ClientState
	ctx.Config = sharedModule("Config")
	ctx.Formulas = sharedModule("Formulas")
	ctx.Format = sharedModule("NumberFormatter")
	ctx.DVDMath = sharedModule("DVDMath")
	ctx.Net = FAKE_NET
	ctx.Theme = clientModule("Theme")
	ctx.UIUtil = clientModule("UIUtil")
	ctx.Effects = safeEffects()
	ctx.Sound = SILENT
	ctx.Random = Random.new()
	ctx.World3D = true -- (un stimulus peut savoir qu'il est sur un écran 3D)
	function ctx.IsAlive(): boolean
		return box.Alive
	end
	function ctx.GetSlotScale(): number
		return 1
	end
	function ctx.GetSlotSize(): Vector2
		return design
	end
	ctx.Notify = noop
	function ctx.FloatText(parent: GuiObject, position: UDim2, text: string, color: Color3?, size: number?)
		local effects = ctx.Effects
		pcall(effects.FloatingText, parent, position, text, color, size)
	end
	function ctx.GetLevel(upgradeId: string): number
		local ok, value = pcall(ClientState.GetLevel, upgradeId)
		return ok and tonumber(value) or 0
	end
	function ctx.HasFeature(name: string): boolean
		local ok, value = pcall(ClientState.HasFeature, name)
		return ok and value == true
	end
	function ctx.EffectsEnabled(): boolean
		local data = ClientState and ClientState.Data
		return not (data and data.Settings and data.Settings.Effects == false)
	end
	ctx.ClaimSpawn = noop
	ctx.Interact = noop
	function ctx.Connect(signal: any, callback: (...any) -> ()): any
		if not box.Alive or signal == nil then
			return DEAD_CONNECTION
		end
		local connection = signal:Connect(function(...)
			if box.Alive then
				callback(...)
			end
		end)
		table.insert(box.Connections, connection)
		return connection
	end
	function ctx.OnRender(callback: (dt: number) -> ()): any
		if not box.Alive then
			return DEAD_CONNECTION
		end
		table.insert(box.Renders, callback)
		local connection = { Connected = true }
		function connection.Disconnect(self: any)
			local index = table.find(box.Renders, callback)
			if index then
				table.remove(box.Renders, index)
			end
			if type(self) == "table" then
				self.Connected = false
			end
		end
		return connection
	end
	function ctx.GetVisibility(): string
		return box.Alive and "Visible" or "Hidden"
	end
	function ctx.IsVisible(): boolean
		return box.Alive
	end
	function ctx.OnVisibilityChanged(_callback: any): any
		return DEAD_CONNECTION
	end
	function ctx.OnSpawn(_kind: string, _callback: any): any
		return DEAD_CONNECTION -- (dons, étoiles... : seulement dans le clicker)
	end
	function ctx.OnBonus(_source: string, _callback: any): any
		return DEAD_CONNECTION
	end
	ctx.SetDarkMode = noop
	box.Ctx = ctx
	return box
end

local function killSandbox(box: Sandbox, module: any)
	if not box.Alive then
		return
	end
	box.Alive = false
	for _, connection in ipairs(box.Connections) do
		pcall(function()
			connection:Disconnect()
		end)
	end
	table.clear(box.Connections)
	table.clear(box.Renders)
	if type(module.Stop) == "function" then
		pcall(module.Stop, box.Ctx)
	end
end

----------------------------------------------------------------------
-- Cadres
----------------------------------------------------------------------

local function frame(parent: Instance, name: string, position: UDim2, size: UDim2, color: Color3, z: number?, transparency: number?): Frame
	local f = Instance.new("Frame")
	f.Name = name
	f.BorderSizePixel = 0
	f.Position = position
	f.Size = size
	f.BackgroundColor3 = color
	f.BackgroundTransparency = transparency or 0
	f.ZIndex = z or 1
	f.Parent = parent
	return f
end

local function gradient(parent: GuiObject, a: Color3, b: Color3, rotation: number)
	local g = Instance.new("UIGradient")
	g.Color = ColorSequence.new(a, b)
	g.Rotation = rotation
	g.Parent = parent
end

----------------------------------------------------------------------
-- Tailles
----------------------------------------------------------------------

local RUNNER_H = 200 -- hauteur "design" du coureur (le slot du clicker fait 190)
local RUNNER_MARGIN = 6 -- liseré + cadre "téléphone" du stimulus, hors toile
local LIVE_W, LIVE_H = 384, 268 -- slot L3 du clicker
local DVD_W = 1280 -- l'écran "design" du clicker (logos de 150 x 80)
local TICKER_H = 30 -- slot Ticker

local SUPPORTED = { Runner = "Runner", Live = "LiveStream", DVD = "DVD", News = "NewsTicker" }

function StimulusScreen.Supports(kind: string): boolean
	local name = SUPPORTED[kind]
	return name ~= nil and stimulus(name) ~= nil
end

function StimulusScreen.Canvas(kind: string, aspect: number): Vector2
	local a = math.clamp(aspect, 0.3, 4)
	if kind == "Runner" then
		return Vector2.new(math.floor(RUNNER_H * a + 0.5), RUNNER_H)
	elseif kind == "Live" then
		if a >= LIVE_W / LIVE_H then
			return Vector2.new(math.floor(LIVE_H * a + 0.5), LIVE_H)
		end
		return Vector2.new(LIVE_W, math.floor(LIVE_W / a + 0.5))
	elseif kind == "DVD" then
		return Vector2.new(560, math.floor(560 / a + 0.5))
	end
	return Vector2.new(360, math.floor(360 / a + 0.5))
end

-- Lance le stimulus `name` dans `container` ; renvoie son bac à sable
local function launch(name: string, container: Frame, overlay: Frame, design: Vector2): (Sandbox?, any)
	local module = stimulus(name)
	if not module then
		return nil, nil
	end
	local box = sandbox(name, module, container, overlay, design)
	local ok, err = pcall(module.Start, box.Ctx)
	if not ok then
		warn("[StimulusScreen] " .. name .. ".Start : " .. tostring(err))
		killSandbox(box, module)
		return nil, nil
	end
	return box, module
end

----------------------------------------------------------------------
-- Construction d'un écran
----------------------------------------------------------------------

function StimulusScreen.New(kind: string, gui: SurfaceGui, canvas: Vector2): Screen?
	local name = SUPPORTED[kind]
	if not name or not stimulus(name) then
		return nil
	end
	local W, H = canvas.X, canvas.Y
	local root = frame(gui, "Stimulus_" .. kind, UDim2.fromOffset(0, 0), UDim2.fromOffset(W, H), rgb(8, 8, 16))
	root.ClipsDescendants = true
	local light: LiveScreens.Screen? = nil
	local box: Sandbox?, module: any = nil, nil

	if kind == "Runner" then
		-- le coureur remplit la toile ; son cadre de "téléphone" déborde (coupé)
		local design = Vector2.new(W + RUNNER_MARGIN * 2, H + RUNNER_MARGIN * 2)
		local container = frame(root, "Container", UDim2.fromOffset(-RUNNER_MARGIN, -RUNNER_MARGIN), UDim2.fromOffset(design.X, design.Y), rgb(0, 0, 0), 2, 1)
		box, module = launch(name, container, container, design)
	elseif kind == "Live" then
		-- page de streaming : fond + halo, le live du clicker au centre
		gradient(root, rgb(34, 20, 58), rgb(12, 8, 24), 90)
		local scale = math.min(W / LIVE_W, H / LIVE_H)
		local cw, ch = LIVE_W * scale, LIVE_H * scale
		local halo = frame(root, "Halo", UDim2.fromOffset((W - cw) / 2 - 6, (H - ch) / 2 - 6), UDim2.fromOffset(cw + 12, ch + 12), rgb(170, 90, 255), 1, 0.7)
		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0, 18)
		corner.Parent = halo
		if W - cw > 40 then
			-- bords : pastilles "EN DIRECT" et cœurs qui rappellent l'appli
			for _, side in ipairs({ 0, 1 }) do
				local x = side == 0 and 6 or (W + cw) / 2 + 6
				local w = (W - cw) / 2 - 12
				local stack = frame(root, "Side", UDim2.fromOffset(x, 10), UDim2.fromOffset(w, H - 20), rgb(255, 255, 255), 1, 0.94)
				local stackCorner = Instance.new("UICorner")
				stackCorner.CornerRadius = UDim.new(0, 8)
				stackCorner.Parent = stack
				for k = 0, 3 do
					local dot = frame(stack, "Dot", UDim2.new(0.5, -math.min(8, w / 3), 0, 10 + k * 28), UDim2.fromOffset(math.min(16, w / 1.5), math.min(16, w / 1.5)),
						k == 0 and rgb(236, 50, 80) or rgb(190, 150, 255), 2, k == 0 and 0 or 0.5)
					local dotCorner = Instance.new("UICorner")
					dotCorner.CornerRadius = UDim.new(1, 0)
					dotCorner.Parent = dot
				end
			end
		end
		local holder = frame(root, "Holder", UDim2.fromOffset((W - cw) / 2, (H - ch) / 2), UDim2.fromOffset(LIVE_W, LIVE_H), rgb(0, 0, 0), 2, 1)
		local uiScale = Instance.new("UIScale")
		uiScale.Scale = scale
		uiScale.Parent = holder
		box, module = launch(name, holder, holder, Vector2.new(LIVE_W, LIVE_H))
	elseif kind == "DVD" then
		-- fond de télé (le DVD du clicker est posé sur le fond de l'appli)
		gradient(root, rgb(18, 16, 40), rgb(4, 4, 12), 90)
		local vignette = frame(root, "Vignette", UDim2.fromOffset(0, 0), UDim2.fromScale(1, 1), rgb(0, 0, 0), 2, 0.4)
		local vg = Instance.new("UIGradient")
		vg.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.3),
			NumberSequenceKeypoint.new(0.5, 1),
			NumberSequenceKeypoint.new(1, 0.3),
		})
		vg.Parent = vignette
		local scale = W / DVD_W
		local design = Vector2.new(DVD_W, math.floor(H / scale + 0.5))
		local holder = frame(root, "Holder", UDim2.fromOffset(0, 0), UDim2.fromOffset(design.X, design.Y), rgb(0, 0, 0), 3, 1)
		local uiScale = Instance.new("UIScale")
		uiScale.Scale = scale
		uiScale.Parent = holder
		box, module = launch(name, holder, holder, design)
	elseif kind == "News" then
		-- plateau du flash info (dessiné) + vrai bandeau du clicker
		local ok, screen = pcall(LiveScreens.New, "News", gui, canvas)
		if ok and screen then
			light = screen
			screen.Root.Parent = root
			screen.Root.ZIndex = 1
		end
		local barH = math.floor(H * 0.14 + 0.5)
		local scale = barH / TICKER_H
		local design = Vector2.new(math.floor(W / scale + 0.5), TICKER_H)
		local bar = frame(root, "Ticker", UDim2.fromOffset(0, H - barH), UDim2.fromOffset(design.X, TICKER_H), rgb(20, 16, 34), 20)
		local barScale = Instance.new("UIScale")
		barScale.Scale = scale
		barScale.Parent = bar
		-- "ALERTE INFO" : calque de toute la toile (même échelle que le bandeau)
		local overlay = frame(root, "Overlay", UDim2.fromOffset(0, 0), UDim2.fromOffset(design.X, math.floor(H / scale + 0.5)), rgb(0, 0, 0), 30, 1)
		local overlayScale = Instance.new("UIScale")
		overlayScale.Scale = scale
		overlayScale.Parent = overlay
		box, module = launch(name, bar, overlay, design)
	end

	if not box then
		if light then
			pcall(light.Destroy, light)
		end
		root:Destroy()
		return nil
	end
	local sandboxRef: Sandbox = box
	local screen = {} :: Screen
	screen.Kind = kind
	screen.Root = root
	screen.Real = true
	screen.Failed = false
	function screen.Step(self: Screen, dt: number)
		if self.Failed then
			return
		end
		if light then
			light:Step(dt)
		end
		for _, callback in ipairs(sandboxRef.Renders) do
			local ok, err = pcall(callback, dt)
			if not ok then
				warn("[StimulusScreen] " .. tostring(name) .. " : " .. tostring(err))
				self.Failed = true
				return
			end
		end
	end
	function screen.Destroy(_self: Screen)
		killSandbox(sandboxRef, module)
		if light then
			pcall(light.Destroy, light)
		end
		root:Destroy()
	end
	return screen
end

return StimulusScreen
