--[[
	House3D (ModuleScript)
	Emplacement : ReplicatedStorage > Client > Components > House > House3D

	Vue 3D "maison de poupée" d'une pièce (bouton "🧊 3D" de la vue pièce) :
	une vraie maquette en 3D, construite côté client dans le Workspace, loin
	du monde (House3DScene : studio de ciel pastel, socle fleuri, murs et sol
	avec le papier peint et le sol de la pièce, objets en cartons découpés
	dessinés avec HouseArt), filmée par une caméra Scriptable :
	  - glisser (souris / doigt) = tourner autour (±70°, inclinaison
	    limitée), molette / pincer = zoomer, amorti doux ;
	  - au repos, la caméra se balance doucement toute seule ;
	  - le mur de côté entre la caméra et la pièce se baisse ;
	  - barre d'outils : ↺ ↻ tourner, 🔄 recentrer, 🌙 / ☀️ nuit / jour,
	    ✕ fermer (Échap ferme aussi) ;
	  - pendant la vue, TOUTES les ScreenGui du joueur sont masquées ; à la
	    fermeture on remet EXACTEMENT : les ScreenGui qui étaient visibles,
	    et la caméra (CameraType, CameraSubject, CFrame, FieldOfView, Focus).
	Robuste : double ouverture (la vue précédente est fermée proprement),
	réapparition du personnage, nouvelle caméra, erreurs (un objet cassé
	n'empêche pas les autres de s'afficher). Travail par image = caméra
	seulement (la maquette est construite une fois, sur quelques images).
	Aucun son.

	API :
	  House3D.Open({ Room = pièce, SizeId = taille de la maison, Title = nom de la pièce,
	                 OnClose = function() end }) -> boolean
	  House3D.Close()
	  House3D.IsOpen() -> boolean
	(Room = une pièce de ClientState.Data.House.Rooms, voir HouseCommon.Room)
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local GuiService = game:GetService("GuiService")
local TextService = game:GetService("TextService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Client = script.Parent.Parent.Parent
local Theme = require(Client.Theme)
local Locale = require(ReplicatedStorage.Shared.Locale)
local HouseCommon = require(script.Parent.HouseCommon)
local House3DScene = require(script.Parent.House3DScene)

local House3D = {}

export type Options = {
	Room: any,
	SizeId: string?,
	Title: string?,
	OnClose: (() -> ())?,
}

local RENDER_NAME = "House3DCamera"
local FOV = 40
local PITCH_DEFAULT = math.rad(20)
local PITCH_MIN = math.rad(7)
local PITCH_MAX = math.rad(52)
local YAW_MAX = math.rad(70)
local ZOOM_MIN = 0.55
local ZOOM_MAX = 1.5
local WHEEL_STEP = 0.88
local ROTATE_STEP = math.rad(25)
local DRAG_SPEED = math.rad(0.3) -- par pixel (souris)
local TOUCH_SPEED = math.rad(0.4) -- par pixel (doigt)
local DAMPING = 7
local INTRO_TIME = 1.4
local INTRO_DAMPING = 3.2
local IDLE_TIME = 4 -- (s) sans toucher : la caméra se balance doucement
local AUTO_AMPLITUDE = math.rad(24)
local AUTO_PERIOD = 16
local FRONT_MARGIN = 1.2 -- la caméra reste devant le bord avant de la pièce
local REHIDE_EVERY = 1 -- (s) vérifie que les autres interfaces restent masquées

local WHITE = Color3.new(1, 1, 1)
local C = HouseCommon.Colors

type Saved = {
	CameraType: Enum.CameraType,
	CameraSubject: Instance?,
	CFrame: CFrame,
	FieldOfView: number,
	Focus: CFrame,
}

type Session = {
	Alive: boolean,
	OnClose: (() -> ())?,
	Saved: Saved?,
	Hidden: { ScreenGui },
	Connections: { RBXScriptConnection },
	Bound: boolean,
	Gui: ScreenGui?,
	Scene: House3DScene.Scene?,
	Night: boolean,
	-- caméra (repère : angle autour de la pièce, inclinaison, zoom)
	Yaw: number,
	Pitch: number,
	Zoom: number,
	YawT: number,
	PitchT: number,
	ZoomT: number,
	ZoomMin: number,
	Fit: number,
	Focus: Vector3,
	FrontZ: number,
	Viewport: Vector2,
	Clock: number,
	LastInput: number,
	Auto: boolean,
	AutoPhase: number,
	RehideClock: number,
	-- entrées
	Dragging: boolean,
	DragLast: Vector2,
	Touches: { [any]: Vector2 },
	PinchStart: number?,
	PinchZoom: number,
	-- interface
	NightButton: TextButton?,
	Chip: Frame?,
	ChipBar: Frame?,
	ChipText: TextLabel?,
	TitleCard: Frame?,
	Toolbar: Frame?,
	UiScale: number,
	TopReserve: number, -- (px de maquette) haut de l'écran pris par le titre
	BottomReserve: number, -- bas de l'écran pris par la barre d'outils
}

local session: Session? = nil

----------------------------------------------------------------------
-- Outils
----------------------------------------------------------------------

local function create(className: string, props: { [string]: any }): any
	local instance = Instance.new(className)
	local parent = nil
	for key, value in pairs(props) do
		if key == "Parent" then
			parent = value
		else
			(instance :: any)[key] = value
		end
	end
	if parent then
		instance.Parent = parent
	end
	return instance
end

local function corner(parent: Instance, radius: UDim)
	create("UICorner", { CornerRadius = radius, Parent = parent })
end

local function stroke(parent: Instance, color: Color3, thickness: number, transparency: number)
	create("UIStroke", {
		Color = color,
		Thickness = thickness,
		Transparency = transparency,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
		Parent = parent,
	})
end

local function tween(instance: Instance, duration: number, props: { [string]: any }, style: Enum.EasingStyle?)
	TweenService:Create(instance, TweenInfo.new(duration, style or Enum.EasingStyle.Quad, Enum.EasingDirection.Out), props):Play()
end

local function textWidth(text: string, size: number, font: Enum.Font): number
	local ok, bounds = pcall(function()
		return TextService:GetTextSize(text, size, font, Vector2.new(4000, 200))
	end)
	if ok and typeof(bounds) == "Vector2" then
		return bounds.X
	end
	return (utf8.len(text) or #text) * size * 0.55
end

-- Caméra en orbite autour de `focus` (yaw 0 = face à la pièce)
local function orbitCFrame(focus: Vector3, yaw: number, pitch: number, distance: number): CFrame
	local flat = math.cos(pitch)
	local eye = focus + Vector3.new(math.sin(yaw) * flat, math.sin(pitch), math.cos(yaw) * flat) * distance
	return CFrame.lookAt(eye, focus)
end

local function isTouchDevice(): boolean
	return UserInputService.TouchEnabled and not UserInputService.MouseEnabled
end

----------------------------------------------------------------------
-- Cadrage
----------------------------------------------------------------------

-- Place prise par l'interface (px d'écran) : titre en haut, barre en bas
local function reservedArea(s: Session, viewportH: number): (number, number, number)
	local bottomInset = 0
	local ok, _, bottomRight = pcall(function()
		return GuiService:GetGuiInset()
	end)
	if ok and typeof(bottomRight) == "Vector2" then
		bottomInset = bottomRight.Y
	end
	local scale = s.UiScale
	local top = s.TopReserve * scale
	-- (tactile : marge pour la barre d'accueil des téléphones)
	local bottom = bottomInset + s.BottomReserve * scale + (isTouchDevice() and 12 or 0)
	-- (écran très bas : on garde au moins la moitié de la hauteur pour la pièce)
	local free = viewportH - top - bottom
	if free < viewportH * 0.5 then
		local k = (viewportH * 0.5) / math.max(1, top + bottom)
		top *= k
		bottom *= k
	end
	return top, bottom, 20 * scale
end

-- Distance (et cible) pour voir toute la pièce de face, à l'inclinaison par défaut
local function computeFit(s: Session)
	local scene = s.Scene
	local camera = workspace.CurrentCamera
	if not scene or not camera then
		return
	end
	local viewport = camera.ViewportSize
	local vw, vh = math.max(200, viewport.X), math.max(160, viewport.Y)
	local tanY = math.tan(math.rad(FOV) / 2)
	local tanX = tanY * vw / vh
	local topPx, bottomPx, sidePx = reservedArea(s, vh)
	local limitTop = 1 - 2 * topPx / vh
	local limitBottom = -1 + 2 * bottomPx / vh
	local limitX = 1 - 2 * sidePx / vw
	local lo, hi = scene.BoundsMin, scene.BoundsMax
	local corners = {}
	for _, x in ipairs({ lo.X, hi.X }) do
		for _, y in ipairs({ lo.Y, hi.Y }) do
			for _, z in ipairs({ lo.Z, hi.Z }) do
				table.insert(corners, Vector3.new(x, y, z))
			end
		end
	end
	local function extents(target: Vector3, distance: number): (boolean, number, number, number)
		local cframe = orbitCFrame(target, 0, PITCH_DEFAULT, distance)
		local maxX, minY, maxY = 0, math.huge, -math.huge
		for _, point in ipairs(corners) do
			local v = cframe:PointToObjectSpace(point)
			local depth = -v.Z
			if depth < 0.5 then
				return false, 0, 0, 0
			end
			maxX = math.max(maxX, math.abs(v.X / (depth * tanX)))
			local y = v.Y / (depth * tanY)
			minY = math.min(minY, y)
			maxY = math.max(maxY, y)
		end
		return true, maxX, minY, maxY
	end
	local target = scene.Focus
	local distance = 60
	for _ = 1, 3 do
		local near, far = 4, 800
		for _ = 1, 26 do
			local mid = (near + far) / 2
			local ok, maxX, minY, maxY = extents(target, mid)
			if ok and maxX <= limitX and minY >= limitBottom and maxY <= limitTop then
				far = mid
			else
				near = mid
			end
		end
		distance = far
		local ok, _, minY, maxY = extents(target, distance)
		if ok then
			local shift = (minY + maxY) / 2 - (limitTop + limitBottom) / 2
			target += Vector3.new(0, shift * distance * tanY * 0.9, 0)
		end
	end
	s.Fit = distance
	s.Focus = target
	-- Zoom minimum : on doit toujours pouvoir tourner d'au moins ±25° en restant devant la pièce
	local reach = s.FrontZ + FRONT_MARGIN - target.Z
	local needed = reach / math.cos(math.rad(25)) / math.cos(PITCH_MAX)
	s.ZoomMin = math.clamp(needed / math.max(1, distance), ZOOM_MIN, 1)
end

-- Angle maximal autour de la pièce (la caméra reste devant son bord avant)
local function yawLimit(s: Session, pitch: number, distance: number): number
	local reach = s.FrontZ + FRONT_MARGIN - s.Focus.Z
	local horizontal = distance * math.cos(pitch)
	if horizontal <= reach then
		return 0
	end
	return math.min(YAW_MAX, math.acos(math.clamp(reach / horizontal, -1, 1)))
end

local function clampTargets(s: Session)
	s.PitchT = math.clamp(s.PitchT, PITCH_MIN, PITCH_MAX)
	s.ZoomT = math.clamp(s.ZoomT, s.ZoomMin, ZOOM_MAX)
	local limit = yawLimit(s, s.PitchT, s.Fit * s.ZoomT)
	s.YawT = math.clamp(s.YawT, -limit, limit)
end

local function touched(s: Session)
	s.LastInput = s.Clock
	s.Auto = false
end

----------------------------------------------------------------------
-- Caméra (chaque image)
----------------------------------------------------------------------

local function stepCamera(s: Session, dt: number)
	local camera = workspace.CurrentCamera
	local scene = s.Scene
	if not camera or not scene then
		return
	end
	dt = math.clamp(dt, 0, 0.1)
	s.Clock += dt
	if camera.CameraType ~= Enum.CameraType.Scriptable then
		camera.CameraType = Enum.CameraType.Scriptable
	end
	local viewport = camera.ViewportSize
	if viewport ~= s.Viewport then
		s.Viewport = viewport
		computeFit(s)
	end
	-- Balancement tout seul au repos
	if s.Clock - s.LastInput > IDLE_TIME and not s.Dragging and next(s.Touches) == nil then
		local amplitude = math.min(AUTO_AMPLITUDE, yawLimit(s, s.PitchT, s.Fit * s.ZoomT) * 0.8)
		if amplitude > 0.01 then
			if not s.Auto then
				s.Auto = true
				s.AutoPhase = math.asin(math.clamp(s.Yaw / amplitude, -1, 1))
			end
			s.AutoPhase += dt * math.pi * 2 / AUTO_PERIOD
			s.YawT = amplitude * math.sin(s.AutoPhase)
		end
	end
	clampTargets(s)
	local rate = s.Clock < INTRO_TIME and INTRO_DAMPING or DAMPING
	local alpha = 1 - math.exp(-dt * rate)
	s.Yaw += (s.YawT - s.Yaw) * alpha
	s.Pitch += (s.PitchT - s.Pitch) * alpha
	s.Zoom += (s.ZoomT - s.Zoom) * alpha
	local cframe = orbitCFrame(s.Focus, s.Yaw, s.Pitch, s.Fit * s.Zoom)
	camera.CFrame = cframe
	camera.Focus = CFrame.new(s.Focus)
	if math.abs(camera.FieldOfView - FOV) > 0.01 then
		camera.FieldOfView = FOV
	end
	scene.UpdateWalls(cframe.Position)
	-- Les autres interfaces restent masquées (une ScreenGui réactivée ailleurs)
	s.RehideClock += dt
	if s.RehideClock >= REHIDE_EVERY then
		s.RehideClock = 0
		for _, gui in ipairs(s.Hidden) do
			if gui.Parent and gui.Enabled then
				gui.Enabled = false
			end
		end
	end
end

----------------------------------------------------------------------
-- Commandes
----------------------------------------------------------------------

local function rotateBy(s: Session, delta: number)
	touched(s)
	s.YawT += delta
	clampTargets(s)
end

local function resetView(s: Session)
	touched(s)
	s.YawT = 0
	s.PitchT = PITCH_DEFAULT
	s.ZoomT = 1
end

local function refreshNightButton(s: Session)
	local button = s.NightButton
	if not button then
		return
	end
	local icon = button:FindFirstChild("Icon") :: TextLabel?
	local caption = button:FindFirstChild("Caption") :: TextLabel?
	if icon then
		icon.Text = s.Night and "☀️" or "🌙"
	end
	if caption then
		caption.Text = s.Night and Locale.T("Day") or Locale.T("Night")
	end
end

local function toggleNight(s: Session)
	touched(s)
	s.Night = not s.Night
	local scene = s.Scene
	if scene then
		scene.SetNight(s.Night)
	end
	refreshNightButton(s)
end

----------------------------------------------------------------------
-- Interface (titre, barre d'outils, construction)
----------------------------------------------------------------------

type Metrics = {
	ButtonW: number,
	ButtonH: number,
	IconSize: number,
	CaptionSize: number,
	Pad: number,
	Gap: number,
}

local function toolButton(parent: Instance, m: Metrics, name: string, icon: string, caption: string, order: number, primary: boolean): TextButton
	local button = create("TextButton", {
		Name = name,
		AutoButtonColor = false,
		Text = "",
		Size = UDim2.fromOffset(m.ButtonW, m.ButtonH),
		BackgroundColor3 = primary and C.PinkDeep or C.PinkMist,
		BorderSizePixel = 0,
		LayoutOrder = order,
		Parent = parent,
	}) :: TextButton
	corner(button, UDim.new(0, math.floor(m.ButtonH * 0.28)))
	stroke(button, primary and C.PinkDeep:Lerp(Color3.new(0, 0, 0), 0.15) or C.PinkSoft, 1.5, 0)
	create("UIGradient", {
		Rotation = 90,
		Color = ColorSequence.new(WHITE, Color3.fromRGB(236, 230, 240)),
		Parent = button,
	})
	create("TextLabel", {
		Name = "Icon",
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(0, math.floor(m.ButtonH * 0.08)),
		Size = UDim2.new(1, 0, 0, m.IconSize + 4),
		Font = Theme.Fonts.Title,
		Text = icon,
		TextSize = m.IconSize,
		TextColor3 = primary and WHITE or C.Ink,
		Parent = button,
	})
	local label = create("TextLabel", {
		Name = "Caption",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -math.floor(m.ButtonH * 0.08)),
		Size = UDim2.new(1, -8, 0, m.CaptionSize + 3),
		Font = Theme.Fonts.Title,
		Text = caption,
		TextScaled = true,
		TextColor3 = primary and WHITE or C.Ink,
		Parent = button,
	})
	create("UITextSizeConstraint", { MaxTextSize = m.CaptionSize, MinTextSize = 7, Parent = label })
	-- Petit rebond au survol / à l'appui
	local press = create("UIScale", { Name = "Press", Parent = button }) :: UIScale
	local hovering = false
	button.MouseEnter:Connect(function()
		hovering = true
		tween(press, 0.14, { Scale = 1.07 }, Enum.EasingStyle.Back)
	end)
	button.MouseLeave:Connect(function()
		hovering = false
		tween(press, 0.14, { Scale = 1 })
	end)
	button.MouseButton1Down:Connect(function()
		tween(press, 0.08, { Scale = 0.92 })
	end)
	button.MouseButton1Up:Connect(function()
		tween(press, 0.2, { Scale = hovering and 1.07 or 1 }, Enum.EasingStyle.Back)
	end)
	return button
end

local function separator(parent: Instance, m: Metrics, order: number)
	local holder = create("Frame", {
		Name = "Separator",
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(9, m.ButtonH),
		LayoutOrder = order,
		Parent = parent,
	})
	create("Frame", {
		Name = "Line",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(2, math.floor(m.ButtonH * 0.58)),
		BackgroundColor3 = C.LilacSoft,
		BorderSizePixel = 0,
		Parent = holder,
	})
end

-- Interface de la vue : carte de titre (dans la barre du haut de Roblox, au
-- milieu, qui est libre) + barre d'outils en bas + pastille "construction"
local function buildGui(s: Session, title: string, roomIcon: string): ScreenGui
	local gui = create("ScreenGui", {
		Name = "House3DView",
		ResetOnSpawn = false,
		IgnoreGuiInset = true,
		ScreenInsets = Enum.ScreenInsets.DeviceSafeInsets,
		DisplayOrder = 60,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
	}) :: ScreenGui
	local touch = isTouchDevice()
	local device = "Desktop"
	local okInterface, Interface = pcall(require, Client.Interface)
	if okInterface and type(Interface) == "table" and type(Interface.Device) == "string" then
		device = Interface.Device
	end
	-- Téléphone (paysage, peu de hauteur) : tout est plus compact
	local compact = device == "Phone"
	local scale = compact and 0.82 or 1
	s.UiScale = scale
	local m: Metrics = compact and { ButtonW = 58, ButtonH = 48, IconSize = 20, CaptionSize = 10, Pad = 7, Gap = 5 }
		or { ButtonW = 66, ButtonH = 58, IconSize = 24, CaptionSize = 12, Pad = 8, Gap = 6 }
	local root = create("Frame", {
		Name = "Root",
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		Parent = gui,
	})
	local content = create("Frame", {
		Name = "Content",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.new(1 / scale, 0, 1 / scale, 0),
		Parent = root,
	})
	create("UIScale", { Scale = scale, Parent = content })

	-- Carte de titre : "🛏️ Vue 3D · Chambre" + aide
	local heading = Locale.T("3D view") .. " · " .. title
	local hint = touch and Locale.T("Drag to rotate · Pinch to zoom") or Locale.T("Drag to rotate · Scroll to zoom")
	local cardH = compact and 44 or 54
	local badgeSize = compact and 30 or 38
	local titleSize = compact and 16 or 19
	local hintSize = compact and 11 or 13
	local textLeft = 10 + badgeSize + 10
	local width = math.clamp(math.max(textWidth(heading, titleSize, Theme.Fonts.Title), textWidth(hint, hintSize, Theme.Fonts.Body)) + textLeft + 20, 220, 560)
	local card = create("Frame", {
		Name = "TitleCard",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 6),
		Size = UDim2.fromOffset(width, cardH),
		BackgroundColor3 = WHITE,
		BackgroundTransparency = 0.03,
		BorderSizePixel = 0,
		Parent = content,
	})
	corner(card, UDim.new(0, math.floor(cardH * 0.36)))
	stroke(card, C.PinkSoft, 2, 0)
	create("UIGradient", {
		Rotation = 90,
		Color = ColorSequence.new(WHITE, C.PinkMist),
		Parent = card,
	})
	local badge = create("Frame", {
		Name = "Badge",
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 10, 0.5, 0),
		Size = UDim2.fromOffset(badgeSize, badgeSize),
		BackgroundColor3 = WHITE,
		BorderSizePixel = 0,
		Parent = card,
	})
	corner(badge, UDim.new(1, 0))
	create("UIGradient", {
		Rotation = 45,
		Color = ColorSequence.new(C.Pink, C.Lilac),
		Parent = badge,
	})
	create("TextLabel", {
		Name = "Icon",
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		Font = Theme.Fonts.Title,
		Text = roomIcon,
		TextSize = math.floor(badgeSize * 0.56),
		TextColor3 = WHITE,
		Parent = badge,
	})
	local lineTop = math.floor((cardH - titleSize - hintSize - 6) / 2)
	create("TextLabel", {
		Name = "Title",
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(textLeft, lineTop),
		Size = UDim2.new(1, -textLeft - 12, 0, titleSize + 4),
		Font = Theme.Fonts.Title,
		Text = heading,
		TextSize = titleSize,
		TextColor3 = C.Ink,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextTruncate = Enum.TextTruncate.AtEnd,
		Parent = card,
	})
	create("TextLabel", {
		Name = "Hint",
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(textLeft, lineTop + titleSize + 4),
		Size = UDim2.new(1, -textLeft - 12, 0, hintSize + 4),
		Font = Theme.Fonts.Body,
		Text = hint,
		TextSize = hintSize,
		TextColor3 = C.Ink,
		TextTransparency = 0.3,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextTruncate = Enum.TextTruncate.AtEnd,
		Parent = card,
	})
	s.TitleCard = card
	s.TopReserve = 6 + cardH + 8

	-- Barre d'outils
	local buttons, separators = 5, 2
	local barH = m.ButtonH + m.Pad * 2
	local barWidth = m.Pad * 2 + buttons * m.ButtonW + separators * 9 + (buttons + separators - 1) * m.Gap
	local bar = create("Frame", {
		Name = "Toolbar",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -10),
		Size = UDim2.fromOffset(barWidth, barH),
		BackgroundColor3 = WHITE,
		BackgroundTransparency = 0.03,
		BorderSizePixel = 0,
		Parent = content,
	})
	corner(bar, UDim.new(0, math.floor(barH * 0.36)))
	stroke(bar, C.PinkSoft, 2, 0)
	create("UIGradient", {
		Rotation = 90,
		Color = ColorSequence.new(WHITE, C.PinkMist),
		Parent = bar,
	})
	create("UIPadding", {
		PaddingLeft = UDim.new(0, m.Pad),
		PaddingRight = UDim.new(0, m.Pad),
		PaddingTop = UDim.new(0, m.Pad),
		PaddingBottom = UDim.new(0, m.Pad),
		Parent = bar,
	})
	create("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		VerticalAlignment = Enum.VerticalAlignment.Center,
		SortOrder = Enum.SortOrder.LayoutOrder,
		Padding = UDim.new(0, m.Gap),
		Parent = bar,
	})
	local rotateLeft = toolButton(bar, m, "RotateLeft", "↺", Locale.T("Rotate"), 1, false)
	local rotateRight = toolButton(bar, m, "RotateRight", "↻", Locale.T("Rotate"), 2, false)
	separator(bar, m, 3)
	local reset = toolButton(bar, m, "Reset", "🔄", Locale.T("Reset"), 4, false)
	local nightButton = toolButton(bar, m, "Night", "🌙", Locale.T("Night"), 5, false)
	separator(bar, m, 6)
	local close = toolButton(bar, m, "Close", "✕", Locale.T("Close"), 7, true)
	s.NightButton = nightButton
	s.Toolbar = bar
	s.BottomReserve = 10 + barH + 10
	refreshNightButton(s)
	rotateLeft.Activated:Connect(function()
		rotateBy(s, -ROTATE_STEP)
	end)
	rotateRight.Activated:Connect(function()
		rotateBy(s, ROTATE_STEP)
	end)
	reset.Activated:Connect(function()
		resetView(s)
	end)
	nightButton.Activated:Connect(function()
		toggleNight(s)
	end)
	close.Activated:Connect(function()
		if session == s then
			House3D.Close()
		end
	end)

	-- Pastille "construction" (le temps que les objets arrivent), au-dessus de la barre
	local chip = create("Frame", {
		Name = "Building",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -(10 + barH + 10)),
		Size = UDim2.fromOffset(250, 32),
		BackgroundColor3 = C.Ink,
		BackgroundTransparency = 0.12,
		BorderSizePixel = 0,
		Visible = false,
		Parent = content,
	})
	corner(chip, UDim.new(1, 0))
	local chipText = create("TextLabel", {
		Name = "Text",
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(14, 0),
		Size = UDim2.new(1, -28, 1, -6),
		Font = Theme.Fonts.Title,
		Text = "✨ " .. Locale.T("Building the room…"),
		TextSize = 14,
		TextColor3 = WHITE,
		TextTruncate = Enum.TextTruncate.AtEnd,
		Parent = chip,
	})
	local track = create("Frame", {
		Name = "Track",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -5),
		Size = UDim2.new(1, -28, 0, 3),
		BackgroundColor3 = WHITE,
		BackgroundTransparency = 0.75,
		BorderSizePixel = 0,
		Parent = chip,
	})
	corner(track, UDim.new(1, 0))
	local fill = create("Frame", {
		Name = "Fill",
		Size = UDim2.fromScale(0, 1),
		BackgroundColor3 = C.Pink,
		BorderSizePixel = 0,
		Parent = track,
	})
	corner(fill, UDim.new(1, 0))
	s.Chip = chip
	s.ChipBar = fill
	s.ChipText = chipText
	return gui
end

local function showProgress(s: Session, done: number, total: number)
	local chip = s.Chip
	local bar = s.ChipBar
	if not chip or not bar then
		return
	end
	if total <= 0 or done >= total then
		chip.Visible = false
		return
	end
	chip.Visible = true
	bar.Size = UDim2.fromScale(math.clamp(done / total, 0, 1), 1)
end

----------------------------------------------------------------------
-- Entrées
----------------------------------------------------------------------

local function onInputBegan(s: Session, input: InputObject, processed: boolean)
	local kind = input.UserInputType
	local key = input.KeyCode
	if key == Enum.KeyCode.Escape or key == Enum.KeyCode.ButtonB then
		if session == s then
			House3D.Close()
		end
		return
	end
	if processed then
		return
	end
	if kind == Enum.UserInputType.Keyboard then
		if key == Enum.KeyCode.Left or key == Enum.KeyCode.Q then
			rotateBy(s, -ROTATE_STEP)
		elseif key == Enum.KeyCode.Right or key == Enum.KeyCode.E then
			rotateBy(s, ROTATE_STEP)
		elseif key == Enum.KeyCode.Up then
			touched(s)
			s.PitchT += math.rad(8)
		elseif key == Enum.KeyCode.Down then
			touched(s)
			s.PitchT -= math.rad(8)
		end
	elseif kind == Enum.UserInputType.MouseButton1 or kind == Enum.UserInputType.MouseButton2 then
		s.Dragging = true
		s.DragLast = Vector2.new(input.Position.X, input.Position.Y)
		touched(s)
	elseif kind == Enum.UserInputType.Touch then
		s.Touches[input] = Vector2.new(input.Position.X, input.Position.Y)
		s.PinchStart = nil
		touched(s)
	end
end

local function onInputChanged(s: Session, input: InputObject, processed: boolean)
	local kind = input.UserInputType
	if kind == Enum.UserInputType.MouseMovement then
		if s.Dragging then
			local position = Vector2.new(input.Position.X, input.Position.Y)
			local delta = position - s.DragLast
			s.DragLast = position
			s.YawT -= delta.X * DRAG_SPEED
			s.PitchT += delta.Y * DRAG_SPEED
			touched(s)
		end
	elseif kind == Enum.UserInputType.MouseWheel then
		if processed then
			return
		end
		local wheel = input.Position.Z
		if wheel ~= 0 then
			s.ZoomT *= wheel > 0 and WHEEL_STEP or 1 / WHEEL_STEP
			touched(s)
		end
	elseif kind == Enum.UserInputType.Touch then
		local previous = s.Touches[input]
		if not previous then
			return
		end
		local position = Vector2.new(input.Position.X, input.Position.Y)
		s.Touches[input] = position
		local fingers = {}
		for _, point in pairs(s.Touches) do
			table.insert(fingers, point)
		end
		if #fingers == 1 then
			local delta = position - previous
			s.YawT -= delta.X * TOUCH_SPEED
			s.PitchT += delta.Y * TOUCH_SPEED
		elseif #fingers >= 2 then
			local spread = (fingers[1] - fingers[2]).Magnitude
			local start = s.PinchStart
			if not start then
				s.PinchStart = spread
				s.PinchZoom = s.ZoomT
			else
				s.ZoomT = s.PinchZoom * start / math.max(10, spread)
			end
		end
		touched(s)
	end
end

local function onInputEnded(s: Session, input: InputObject)
	local kind = input.UserInputType
	if kind == Enum.UserInputType.MouseButton1 or kind == Enum.UserInputType.MouseButton2 then
		s.Dragging = false
	elseif kind == Enum.UserInputType.Touch then
		s.Touches[input] = nil
		s.PinchStart = nil
	end
end

----------------------------------------------------------------------
-- Ouverture / fermeture
----------------------------------------------------------------------

local function hideGui(s: Session, child: Instance)
	if child:IsA("ScreenGui") and child ~= s.Gui and child.Enabled then
		child.Enabled = false
		table.insert(s.Hidden, child)
	end
end

local function restoreCamera(s: Session)
	local saved = s.Saved
	local camera = workspace.CurrentCamera
	if not saved or not camera then
		return
	end
	local subject = saved.CameraSubject
	if subject and not subject:IsDescendantOf(game) then
		-- (le personnage a réapparu pendant la vue : on suit le nouveau)
		local player = Players.LocalPlayer
		local character = player and player.Character
		subject = character and character:FindFirstChildOfClass("Humanoid") or nil
	end
	if subject then
		pcall(function()
			camera.CameraSubject = subject
		end)
	end
	pcall(function()
		camera.CameraType = saved.CameraType
	end)
	pcall(function()
		camera.CFrame = saved.CFrame
	end)
	pcall(function()
		camera.Focus = saved.Focus
	end)
	pcall(function()
		camera.FieldOfView = saved.FieldOfView
	end)
end

local function start(s: Session, options: Options)
	local camera = workspace.CurrentCamera
	assert(camera, "pas de caméra")
	s.Saved = {
		CameraType = camera.CameraType,
		CameraSubject = camera.CameraSubject,
		CFrame = camera.CFrame,
		FieldOfView = camera.FieldOfView,
		Focus = camera.Focus,
	}
	local room = options.Room
	local roomType = HouseCommon.GetRoomType(room)
	local title = type(options.Title) == "string" and options.Title ~= "" and options.Title
		or (roomType and Locale.T(roomType.Name) or Locale.T("3D view"))
	local okDark, darkMode = pcall(function()
		return require(Client.ClientState).DarkMode
	end)
	s.Night = okDark and darkMode == true

	-- Interface de la vue (créée avant de masquer les autres)
	local gui = buildGui(s, title, roomType and roomType.Icon or "🏠")
	s.Gui = gui
	local player = Players.LocalPlayer
	local playerGui = player and player:FindFirstChildOfClass("PlayerGui")
	if playerGui then
		for _, child in ipairs(playerGui:GetChildren()) do
			hideGui(s, child)
		end
		table.insert(s.Connections, playerGui.ChildAdded:Connect(function(child: Instance)
			if s.Alive then
				hideGui(s, child)
			end
		end))
	end

	-- Maquette (une ancienne maquette oubliée est enlevée)
	local stale = workspace:FindFirstChild(House3DScene.FOLDER_NAME)
	if stale then
		stale:Destroy()
	end
	local scene = House3DScene.new(room, options.SizeId, s.Night)
	s.Scene = scene
	s.FrontZ = scene.FrontZ
	s.Focus = scene.Focus
	if playerGui then
		gui.Parent = playerGui
	end

	-- Caméra : arrivée en douceur depuis un peu plus loin, de côté
	s.Viewport = camera.ViewportSize
	computeFit(s)
	s.Yaw, s.Pitch, s.Zoom = math.rad(26), math.rad(34), 1.45
	s.YawT, s.PitchT, s.ZoomT = 0, PITCH_DEFAULT, 1
	camera.CameraType = Enum.CameraType.Scriptable
	camera.FieldOfView = FOV
	camera.CFrame = orbitCFrame(s.Focus, s.Yaw, s.Pitch, s.Fit * s.Zoom)
	camera.Focus = CFrame.new(s.Focus)
	RunService:BindToRenderStep(RENDER_NAME, Enum.RenderPriority.Camera.Value + 1, function(dt: number)
		if s.Alive then
			local ok, err = pcall(stepCamera, s, dt)
			if not ok then
				warn("[House3D] Caméra : " .. tostring(err))
			end
		end
	end)
	s.Bound = true

	table.insert(s.Connections, UserInputService.InputBegan:Connect(function(input: InputObject, processed: boolean)
		if s.Alive then
			onInputBegan(s, input, processed)
		end
	end))
	table.insert(s.Connections, UserInputService.InputChanged:Connect(function(input: InputObject, processed: boolean)
		if s.Alive then
			onInputChanged(s, input, processed)
		end
	end))
	table.insert(s.Connections, UserInputService.InputEnded:Connect(function(input: InputObject)
		if s.Alive then
			onInputEnded(s, input)
		end
	end))
	if player then
		-- Réapparition du personnage : la caméra reste la nôtre (voir stepCamera)
		table.insert(s.Connections, player.CharacterAdded:Connect(function()
			if s.Alive then
				s.Viewport = Vector2.zero
			end
		end))
	end

	-- Objets : construits sur quelques images
	showProgress(s, 0, scene.ItemCount * 2)
	task.spawn(function()
		local ok, err = pcall(scene.BuildItems, function(): boolean
			return s.Alive
		end, function(done: number, total: number)
			if s.Alive then
				showProgress(s, done, total)
			end
		end)
		if not ok then
			warn("[House3D] Objets : " .. tostring(err))
		end
		if s.Alive then
			showProgress(s, 1, 1)
		end
	end)
end

function House3D.IsOpen(): boolean
	return session ~= nil
end

function House3D.Close()
	local s = session
	if not s then
		return
	end
	session = nil
	s.Alive = false
	if s.Bound then
		pcall(function()
			RunService:UnbindFromRenderStep(RENDER_NAME)
		end)
	end
	for _, connection in ipairs(s.Connections) do
		pcall(function()
			connection:Disconnect()
		end)
	end
	table.clear(s.Connections)
	restoreCamera(s)
	for _, gui in ipairs(s.Hidden) do
		if gui.Parent then
			pcall(function()
				gui.Enabled = true
			end)
		end
	end
	table.clear(s.Hidden)
	local scene = s.Scene
	if scene then
		pcall(scene.Destroy)
	end
	local gui = s.Gui
	if gui then
		pcall(function()
			gui:Destroy()
		end)
	end
	local callback = s.OnClose
	if callback then
		task.spawn(function()
			local ok, err = pcall(callback)
			if not ok then
				warn("[House3D] OnClose : " .. tostring(err))
			end
		end)
	end
end

function House3D.Open(options: Options?): boolean
	if type(options) ~= "table" or type(options.Room) ~= "table" then
		warn("[House3D] Open : pièce manquante")
		return false
	end
	if session then
		House3D.Close()
	end
	if session then
		-- (rouverte par OnClose de la vue précédente)
		return true
	end
	local s: Session = {
		Alive = true,
		OnClose = type(options.OnClose) == "function" and options.OnClose or nil,
		Saved = nil,
		Hidden = {},
		Connections = {},
		Bound = false,
		Gui = nil,
		Scene = nil,
		Night = false,
		Yaw = 0,
		Pitch = PITCH_DEFAULT,
		Zoom = 1,
		YawT = 0,
		PitchT = PITCH_DEFAULT,
		ZoomT = 1,
		ZoomMin = ZOOM_MIN,
		Fit = 60,
		Focus = House3DScene.ORIGIN,
		FrontZ = House3DScene.ORIGIN.Z,
		Viewport = Vector2.zero,
		Clock = 0,
		LastInput = 0,
		Auto = false,
		AutoPhase = 0,
		RehideClock = 0,
		Dragging = false,
		DragLast = Vector2.zero,
		Touches = {},
		PinchStart = nil,
		PinchZoom = 1,
		NightButton = nil,
		Chip = nil,
		ChipBar = nil,
		ChipText = nil,
		TitleCard = nil,
		Toolbar = nil,
		UiScale = 1,
		TopReserve = 80,
		BottomReserve = 100,
	}
	session = s
	local ok, err = pcall(start, s, options)
	if not ok then
		warn("[House3D] Ouverture : " .. tostring(err))
		if session == s then
			House3D.Close()
		end
		return false
	end
	return true
end

return House3D
