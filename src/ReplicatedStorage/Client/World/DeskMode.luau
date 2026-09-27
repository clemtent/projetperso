--[[
	DeskMode (ModuleScript)
	Emplacement : ReplicatedStorage > Client > World > DeskMode

	v9.5 🖥️ Mode "bureau" immersif (Dopamine Town) : quand le personnage
	s'assoit à la chaise d'un bureau gamer (Humanoid.Seated sur un siège à
	≤ 3,5 studs de la "SeatPart" du bureau) ou utilise l'invite "🖥️ Utiliser"
	(LiveProps.DeskUsed), la caméra vient doucement cadrer les écrans et le
	clavier posé sur le bureau ; la souris est libre.
	  - les écrans du bureau sont dessinés en priorité (LiveProps.SetDeskFocus)
	    et les clics sur le clavier / la souris du bureau marchent sans
	    condition de distance ;
	  - les vraies touches du joueur (A-Z, 0-9) enfoncent la touche 3D
	    correspondante et cliquent (comme le clavier 2D) ;
	  - on sort avec : saut, Échap, le bouton "⬅ Se lever", ou si le
	    personnage s'éloigne / meurt / disparaît ; la caméra est remise
	    EXACTEMENT (CameraType, CameraSubject, CFrame, FieldOfView) ainsi
	    que MouseBehavior / MouseIconEnabled.
	La caméra est reprise chaque image après les scripts de caméra par défaut
	(BindToRenderStep, priorité Camera + 1) : les émotes / la caméra de
	TownClient ne la déplacent pas pendant le mode.

	API (appelée par TownClient) :
	  DeskMode.Start()          à l'entrée en ville (écoute les sièges / l'invite)
	  DeskMode.Stop()           à la sortie (AVANT que TownClient remette sa caméra)
	  DeskMode.Enter(handle)    handle = LiveProps (bureau) ; renvoie true si c'est fait
	  DeskMode.Exit()
	  DeskMode.IsActive() -> boolean
	  DeskMode.Changed : signal (active: boolean)   (:Connect)
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Locale = require(ReplicatedStorage.Shared.Locale)
local Signal = require(ReplicatedStorage.Shared.Signal)
local NumberFormatter = require(ReplicatedStorage.Shared.NumberFormatter)
local LiveProps = require(script.Parent.LiveProps)

local DeskMode = {}

DeskMode.Changed = Signal.new()

local BIND_NAME = "DopamineDeskMode"
local SEAT_RADIUS = 3.5 -- (studs) siège du serveur -> SeatPart du bureau
local LEAVE_DISTANCE = 12 -- (studs) personnage -> bureau : au-delà on sort
local FOV = 50
local ENTER_TIME = 0.6

local rgb = Color3.fromRGB
local WHITE = Color3.new(1, 1, 1)

type Saved = {
	CameraType: Enum.CameraType,
	Subject: Instance?,
	CFrame: CFrame,
	FOV: number,
	MouseBehavior: Enum.MouseBehavior,
	MouseIcon: boolean,
}

local started = false
local active: any = nil -- handle LiveProps du bureau
local saved: Saved? = nil
local target: CFrame? = nil
local startCF: CFrame? = nil
local blend = 0
local viaSeat = false
local gui: ScreenGui? = nil
local counter: TextLabel? = nil
local counterClock = 0
local connections: { any } = {} -- pendant le mode
local watchers: { any } = {} -- entre Start et Stop
local humanoidConnections: { any } = {}

local function clientState(): any
	local ok, result = pcall(function()
		return require(script.Parent.Parent:WaitForChild("ClientState") :: ModuleScript) :: any
	end)
	return ok and result or nil
end

local function character(): (Model?, Humanoid?, BasePart?)
	local player = Players.LocalPlayer
	local model = player and player.Character
	if not model then
		return nil, nil, nil
	end
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	local root = model:FindFirstChild("HumanoidRootPart")
	return model, humanoid, (root and root:IsA("BasePart")) and root or nil
end

local function disconnectAll(list: { any })
	for _, connection in ipairs(list) do
		pcall(function()
			connection:Disconnect()
		end)
	end
	table.clear(list)
end

----------------------------------------------------------------------
-- Cadrage : les écrans en haut, le clavier en bas de l'image
----------------------------------------------------------------------

local function framing(handle: any): CFrame?
	local model: Model = handle.Model
	local root: BasePart = handle.Ref
	local front = root.CFrame.LookVector -- devant du bureau (vers la chaise)
	local up = Vector3.new(0, 1, 0)
	local right = front:Cross(up)
	if right.Magnitude < 0.01 then
		return nil
	end
	right = right.Unit
	local sum = Vector3.zero
	local count = 0
	local minX, maxX, maxY = math.huge, -math.huge, -math.huge
	local base = root.Position
	for _, rec in ipairs(handle.Screens) do
		local part: BasePart = rec.Part
		local p = part.Position
		sum += p
		count += 1
		local halfW = part.Size.X / 2
		local along = (p - base):Dot(right)
		minX = math.min(minX, along - halfW)
		maxX = math.max(maxX, along + halfW)
		maxY = math.max(maxY, p.Y + part.Size.Y / 2)
	end
	if count == 0 then
		return nil
	end
	local center = sum / count
	-- clavier sur le bureau : on l'inclut en bas de l'image
	local low = center.Y - 1.2
	local keyboardAt: Vector3? = nil
	for _, other in ipairs(LiveProps.Peripherals(handle)) do
		if other.Kind == "Keyboard" then
			keyboardAt = other.Ref.Position
		end
	end
	local topHeight = tonumber(model:GetAttribute("TopHeight")) or 2.5
	if keyboardAt then
		low = keyboardAt.Y
	else
		low = base.Y + topHeight
	end
	local width = math.max(2, maxX - minX)
	local height = math.max(1.5, maxY - low)
	local lookAt = base + right * ((minX + maxX) / 2) + up * (low + height * 0.52 - base.Y)
	local vfov = math.rad(FOV)
	local camera = workspace.CurrentCamera
	local viewport = camera and camera.ViewportSize or Vector2.new(1280, 720)
	local aspect = viewport.X / math.max(1, viewport.Y)
	local hfov = 2 * math.atan(math.tan(vfov / 2) * aspect)
	local distance = math.max((width * 0.56) / math.tan(hfov / 2), (height * 0.62) / math.tan(vfov / 2))
	distance = math.clamp(distance, 2.2, 14)
	-- l'œil : devant le bureau, un peu au-dessus du clavier, regard légèrement plongeant
	local eye = lookAt + front * distance + up * (distance * 0.22)
	return CFrame.lookAt(eye, lookAt)
end

----------------------------------------------------------------------
-- Interface (bouton "Se lever", aide, compteur)
----------------------------------------------------------------------

local function buildGui()
	local player = Players.LocalPlayer
	local parent = player and player:FindFirstChildOfClass("PlayerGui")
	if not parent then
		return
	end
	local screen = Instance.new("ScreenGui")
	screen.Name = "DeskModeGui"
	screen.ResetOnSpawn = false
	screen.IgnoreGuiInset = false
	screen.DisplayOrder = 40
	screen.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	local bar = Instance.new("Frame")
	bar.Name = "Bar"
	bar.AnchorPoint = Vector2.new(0.5, 1)
	bar.Position = UDim2.new(0.5, 0, 1, -14)
	bar.Size = UDim2.fromOffset(460, 56)
	bar.BackgroundColor3 = rgb(34, 26, 52)
	bar.BackgroundTransparency = 0.15
	bar.BorderSizePixel = 0
	bar.Parent = screen
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 16)
	corner.Parent = bar
	local strokeLine = Instance.new("UIStroke")
	strokeLine.Color = rgb(255, 120, 200)
	strokeLine.Thickness = 2
	strokeLine.Transparency = 0.2
	strokeLine.Parent = bar
	local sizeLimit = Instance.new("UISizeConstraint")
	sizeLimit.MaxSize = Vector2.new(460, 56)
	sizeLimit.Parent = bar
	local scale = Instance.new("UIScale")
	scale.Name = "Fit"
	local camera = workspace.CurrentCamera
	local viewport = camera and camera.ViewportSize or Vector2.new(1280, 720)
	scale.Scale = math.clamp((viewport.X - 24) / 460, 0.6, 1)
	scale.Parent = bar
	local button = Instance.new("TextButton")
	button.Name = "GetUp"
	button.AutoButtonColor = true
	button.Position = UDim2.fromOffset(8, 8)
	button.Size = UDim2.fromOffset(140, 40)
	button.BackgroundColor3 = rgb(255, 110, 170)
	button.BorderSizePixel = 0
	button.Font = Enum.Font.GothamBlack
	button.TextSize = 17
	button.TextColor3 = WHITE
	button.Text = Locale.T("⬅ Get up")
	button.Parent = bar
	local buttonCorner = Instance.new("UICorner")
	buttonCorner.CornerRadius = UDim.new(0, 12)
	buttonCorner.Parent = button
	local hint = Instance.new("TextLabel")
	hint.Name = "Hint"
	hint.BackgroundTransparency = 1
	hint.Position = UDim2.fromOffset(158, 6)
	hint.Size = UDim2.fromOffset(292, 22)
	hint.Font = Enum.Font.GothamBold
	hint.TextSize = 14
	hint.TextXAlignment = Enum.TextXAlignment.Left
	hint.TextColor3 = rgb(236, 226, 255)
	hint.Text = UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled and Locale.T("👆 Tap the keys and the mouse to click!")
		or Locale.T("⌨️ Type or click the keys · 🖱️ click the mouse")
	hint.TextTruncate = Enum.TextTruncate.AtEnd
	hint.Parent = bar
	local count = Instance.new("TextLabel")
	count.Name = "Counter"
	count.BackgroundTransparency = 1
	count.Position = UDim2.fromOffset(158, 28)
	count.Size = UDim2.fromOffset(292, 22)
	count.Font = Enum.Font.GothamBlack
	count.TextSize = 16
	count.TextXAlignment = Enum.TextXAlignment.Left
	count.TextColor3 = rgb(255, 214, 90)
	count.Text = ""
	count.Parent = bar
	table.insert(connections, button.Activated:Connect(function()
		DeskMode.Exit(true)
	end))
	screen.Parent = parent
	gui = screen
	counter = count
end

local function refreshCounter()
	local label = counter
	if not label then
		return
	end
	local state = clientState()
	if state and type(state.GetDisplayDopamine) == "function" then
		local ok, value = pcall(state.GetDisplayDopamine)
		if ok and type(value) == "number" then
			label.Text = "🧠 " .. NumberFormatter.Format(value)
		end
	end
end

----------------------------------------------------------------------
-- Entrée / sortie
----------------------------------------------------------------------

local KEY_NAMES: { [Enum.KeyCode]: string } = {}
do
	for _, letter in ipairs({ "A", "B", "C", "D", "E", "F", "G", "H", "I", "J", "K", "L", "M", "N", "O", "P", "Q", "R", "S", "T", "U", "V", "W", "X", "Y", "Z" }) do
		local ok, code = pcall(function()
			return (Enum.KeyCode :: any)[letter]
		end)
		if ok and code then
			KEY_NAMES[code] = "Key_" .. letter
		end
	end
	local digits = { "Zero", "One", "Two", "Three", "Four", "Five", "Six", "Seven", "Eight", "Nine" }
	for index, word in ipairs(digits) do
		local ok, code = pcall(function()
			return (Enum.KeyCode :: any)[word]
		end)
		if ok and code then
			KEY_NAMES[code] = "Key_" .. tostring(index - 1)
		end
	end
end

local function onRender(dt: number)
	local camera = workspace.CurrentCamera
	local handle = active
	if not camera or not handle then
		return
	end
	if not handle.Alive or not handle.Model.Parent then
		DeskMode.Exit(false)
		return
	end
	local goal = framing(handle) or target
	target = goal
	if not goal then
		return
	end
	blend = math.min(1, blend + dt / ENTER_TIME)
	local t = 1 - (1 - blend) ^ 3
	local from = startCF or goal
	if camera.CameraType ~= Enum.CameraType.Scriptable then
		camera.CameraType = Enum.CameraType.Scriptable
	end
	camera.CFrame = from:Lerp(goal, t)
	camera.FieldOfView = (saved and saved.FOV or 70) + (FOV - (saved and saved.FOV or 70)) * t
	if UserInputService.MouseBehavior ~= Enum.MouseBehavior.Default then
		UserInputService.MouseBehavior = Enum.MouseBehavior.Default
	end
	counterClock += dt
	if counterClock >= 0.1 then
		counterClock = 0
		refreshCounter()
		-- personnage trop loin du bureau (il a marché) : on sort
		local _, _, root = character()
		if root and (root.Position - handle.Ref.Position).Magnitude > LEAVE_DISTANCE then
			DeskMode.Exit(false)
		end
	end
end

function DeskMode.IsActive(): boolean
	return active ~= nil
end

function DeskMode.Enter(handle: any): boolean
	if type(handle) ~= "table" or not handle.Alive or handle.Kind ~= "Desk" then
		return false
	end
	if active == handle then
		return true
	end
	if active then
		DeskMode.Exit(false)
	end
	local camera = workspace.CurrentCamera
	if not camera then
		return false
	end
	saved = {
		CameraType = camera.CameraType,
		Subject = camera.CameraSubject,
		CFrame = camera.CFrame,
		FOV = camera.FieldOfView,
		MouseBehavior = UserInputService.MouseBehavior,
		MouseIcon = UserInputService.MouseIconEnabled,
	}
	active = handle
	startCF = camera.CFrame
	blend = 0
	target = framing(handle)
	LiveProps.SetDeskFocus(handle)
	UserInputService.MouseIconEnabled = true
	buildGui()
	refreshCounter()
	local ok = pcall(function()
		RunService:BindToRenderStep(BIND_NAME, Enum.RenderPriority.Camera.Value + 1, onRender)
	end)
	if not ok then
		table.insert(connections, RunService.RenderStepped:Connect(onRender))
	end
	-- sorties : saut, Échap, touches du clavier -> touches 3D
	table.insert(connections, UserInputService.InputBegan:Connect(function(input: InputObject, processed: boolean)
		if input.KeyCode == Enum.KeyCode.Escape then
			DeskMode.Exit(true)
			return
		end
		if processed or input.UserInputType ~= Enum.UserInputType.Keyboard then
			return
		end
		local keyName = KEY_NAMES[input.KeyCode]
		if keyName and active then
			for _, other in ipairs(LiveProps.Peripherals(active)) do
				if other.Kind == "Keyboard" then
					LiveProps.Press(other, keyName)
					break
				end
			end
		end
	end))
	table.insert(connections, UserInputService.JumpRequest:Connect(function()
		if active and blend > 0.3 then
			DeskMode.Exit(false)
		end
	end))
	local _, humanoid = character()
	if humanoid then
		table.insert(connections, humanoid.Died:Connect(function()
			DeskMode.Exit(false)
		end))
	end
	local player = Players.LocalPlayer
	if player then
		table.insert(connections, player.CharacterRemoving:Connect(function()
			DeskMode.Exit(false)
		end))
	end
	DeskMode.Changed:Fire(true)
	return true
end

-- `standUp` = vrai : on relève le personnage s'il est assis (bouton, Échap)
function DeskMode.Exit(standUp: boolean?)
	if not active then
		return
	end
	active = nil
	pcall(function()
		RunService:UnbindFromRenderStep(BIND_NAME)
	end)
	disconnectAll(connections)
	LiveProps.SetDeskFocus(nil)
	if gui then
		gui:Destroy()
		gui = nil
		counter = nil
	end
	local camera = workspace.CurrentCamera
	local s = saved
	saved = nil
	if camera and s then
		camera.CameraType = s.CameraType
		camera.CameraSubject = s.Subject
		camera.CFrame = s.CFrame
		camera.FieldOfView = s.FOV
	end
	if s then
		UserInputService.MouseBehavior = s.MouseBehavior
		UserInputService.MouseIconEnabled = s.MouseIcon
	end
	if standUp and viaSeat then
		local _, humanoid = character()
		if humanoid and humanoid.SeatPart then
			humanoid.Sit = false
			humanoid.Jump = true
		end
	end
	viaSeat = false
	target = nil
	startCF = nil
	DeskMode.Changed:Fire(false)
end

----------------------------------------------------------------------
-- Écoute (ville) : sièges du bureau, invite "🖥️ Utiliser"
----------------------------------------------------------------------

local function watchHumanoid(humanoid: Humanoid)
	disconnectAll(humanoidConnections)
	table.insert(humanoidConnections, humanoid.Seated:Connect(function(isSeated: boolean, seatPart: BasePart?)
		if isSeated and seatPart then
			local desk = LiveProps.DeskNear(seatPart.Position, SEAT_RADIUS)
			if desk and desk.Interactive then
				if DeskMode.Enter(desk) then
					viaSeat = true
				end
			end
		elseif not isSeated and viaSeat and active then
			DeskMode.Exit(false)
		end
	end))
end

function DeskMode.Start()
	if started then
		return
	end
	started = true
	table.insert(watchers, LiveProps.DeskUsed:Connect(function(handle: any)
		if started and handle and handle.Interactive then
			DeskMode.Enter(handle)
		end
	end))
	local player = Players.LocalPlayer
	if player then
		table.insert(watchers, player.CharacterAdded:Connect(function(model: Model)
			local humanoid = model:WaitForChild("Humanoid", 10)
			if humanoid and humanoid:IsA("Humanoid") and started then
				watchHumanoid(humanoid)
			end
		end))
		local _, humanoid = character()
		if humanoid then
			watchHumanoid(humanoid)
		end
	end
end

function DeskMode.Stop()
	DeskMode.Exit(false)
	started = false
	disconnectAll(watchers)
	disconnectAll(humanoidConnections)
end

-- (tests) état interne
function DeskMode.Debug(): { [string]: any }
	return { Active = active, Target = target, Blend = blend, Started = started, ViaSeat = viaSeat }
end

return DeskMode
