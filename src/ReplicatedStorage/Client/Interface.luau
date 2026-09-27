--[[
	Interface (ModuleScript)
	Emplacement : ReplicatedStorage > Client > Interface

	Crée la ScreenGui et la "toile virtuelle" responsive :
	  - toute l'interface est pensée pour un écran de 1280x720 ;
	  - un UIScale agrandit / réduit l'ensemble selon l'écran réel
	    (PC, mobile, tablette) ;
	  - le cadre "Root" s'étire pour toujours couvrir toute la zone sûre
	    (hors encoche et barre Roblox ; sa taille en pixels "design" est
	    donc >= 1280x720 dans un sens) ;
	  - une ScreenGui de fond séparée remplit tout l'écran (couleurs du
	    thème équipé, ou fond sombre du mode néon).

	Calques (du plus bas au plus haut), tous plein écran, transparents et
	non "Active" (les clics passent à travers) :
	  Background < Slots < Main < Overlay < Panels < Toasts < Effects < Cinematic

	v5 : profil d'appareil (Interface.Device = "Phone" | "Tablet" | "Desktop",
	signal Interface.DeviceChanged). Sur téléphone / tablette, la toile de
	référence est plus petite (Theme.DeviceResolutions : 960x540, 1120x630) :
	tout est donc affiché plus gros. Les composants s'adaptent (colonne
	centrale, fenêtres, bandeaux) et les emplacements des stimuli rétrécissent
	si besoin (voir Slots). Sur PC rien ne change (toile 1280x720).

	v9.1 (plein écran) : les deux ScreenGui couvrent TOUT l'écran
	(ScreenInsets = None, SafeAreaCompatibility = None, ClipToDeviceSafeArea
	= false : sinon Roblox découpe le fond à l'encoche et laisse des bandes).
	La toile "Root" est placée par nous dans l'écran :
	  - PC / tablette : exactement la zone sûre "CoreUI" (comme avant) ;
	  - téléphone : la zone sûre de l'appareil un peu rognée (on garde juste
	    de quoi éviter l'encoche et la barre d'accueil), et le haut de la toile
	    remonte DANS la barre Roblox : la rangée du bandeau d'actualités
	    (30 px "design") occupe la partie libre de la barre, à droite des
	    boutons Roblox (GuiService.TopbarInset), le reste commence sous eux.
	Les zones sûres sont MESURÉES (ScreenGui-sondes en DeviceSafeInsets /
	CoreUISafeInsets) : aucune valeur d'appareil n'est devinée.
	Interface.Bleed = marges (pixels "design") entre la toile et les bords de
	l'écran : le calque Background les recouvre (fond de bord à bord) et
	Interface.ApplyBleed(objet) étend n'importe quel cadre "plein écran" (voiles
	sombres des fenêtres : les "Dimmer" des calques Panels / Toasts / Overlay
	sont étendus automatiquement). Interface.TickerInsets = { Left, Right } :
	partie de la rangée du bandeau cachée par les boutons Roblox (voir Slots).
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local GuiService = game:GetService("GuiService")

local Theme = require(script.Parent.Theme)
local UIUtil = require(script.Parent.UIUtil)
local Signal = require(ReplicatedStorage.Shared.Signal)
local Config = require(ReplicatedStorage.Shared.Config)
local ClientState = require(script.Parent.ClientState)

local Interface = {}

Interface.ScreenGui = nil :: ScreenGui?
Interface.Root = nil :: Frame?
Interface.Layers = {} :: { [string]: Frame }
Interface.Scale = 1
Interface.CanvasSize = Theme.DesignResolution -- taille de la toile en pixels "design"
Interface.ScaleChanged = Signal.new() -- (scale, canvasSize)
Interface.Device = "Desktop" -- "Phone" | "Tablet" | "Desktop"
Interface.DeviceChanged = Signal.new() -- (device)
Interface.DesignResolution = Theme.DesignResolution -- toile de référence de l'appareil
-- Marges (pixels "design") entre la toile et les bords de l'écran (zones non sûres)
Interface.Bleed = { Left = 0, Top = 0, Right = 0, Bottom = 0 }
-- Rangée du bandeau (y ∈ [0, 30] de la toile) : largeur cachée par les boutons Roblox
Interface.TickerInsets = { Left = 0, Right = 0 }
-- Hauteur (pixels "design") en haut de la toile qui passe sous la barre Roblox
-- (téléphone : la rangée du bandeau ; 0 ailleurs). Les calques Panels et
-- Toasts commencent dessous : fenêtres et popups restent hors des boutons Roblox.
Interface.SafeTop = 0

-- Forçage du profil (tests dans Studio) : nil = détection automatique
local deviceOverride: string? = nil
local updateScaleFn: (() -> ())? = nil

-- Profil d'appareil : téléphone = tactile ET petit écran (< 500 px de côté),
-- tablette = tactile et plus grand, sinon PC (un PC tactile avec souris reste "Desktop")
local function detectDevice(): string
	if deviceOverride then
		return deviceOverride
	end
	local touch = UserInputService.TouchEnabled and not UserInputService.MouseEnabled
	if not touch then
		return "Desktop"
	end
	local camera = workspace.CurrentCamera
	local viewport = camera and camera.ViewportSize or Vector2.new(1280, 720)
	if math.min(viewport.X, viewport.Y) < 500 then
		return "Phone"
	end
	return "Tablet"
end

Interface.LayerOrder = { "Background", "Slots", "Main", "Overlay", "Panels", "Toasts", "Effects", "Cinematic" }

-- Téléphone : part des marges de l'appareil (encoche, barre d'accueil) que la
-- toile garde. L'encoche ne fait qu'une trentaine de pixels de profondeur au
-- milieu d'un bord et iOS annonce la même marge des DEUX côtés : on en garde
-- ~45 % (jamais moins que marge - 26 px) ; en bas ~30 % (le trait d'accueil
-- ne gêne que les glissements, pas les touchers).
local function phoneSide(inset: number): number
	if inset <= 0 then
		return 0
	end
	return math.max(math.floor(inset * 0.45 + 0.5), inset - 26)
end
local function phoneBottom(inset: number): number
	if inset <= 0 then
		return 0
	end
	return math.floor(inset * 0.3 + 0.5)
end
-- Rangée du bandeau d'actualités en haut de la toile (pixels "design", = Slots)
local TICKER_ROW = 30
-- Le contenu sous le bandeau commence à (bas de la barre Roblox - 4 px) :
-- les boutons Roblox (44 px) s'arrêtent ~7 px au-dessus du bas de la barre
local TOPBAR_OVERLAP = 4
-- Largeur libre minimale (pixels écran) dans la barre pour y mettre le bandeau
local MIN_TOPBAR_ROOM = 240

-- ScreenGui "plein écran" réglée explicitement (ordre des propriétés : sans
-- effet de bord de IgnoreGuiInset sur ScreenInsets)
local function makeScreenGui(name: string, insets: Enum.ScreenInsets, displayOrder: number, parent: Instance): ScreenGui
	local gui = Instance.new("ScreenGui")
	gui.Name = name
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = insets == Enum.ScreenInsets.None
	gui.ScreenInsets = insets
	gui.SafeAreaCompatibility = Enum.SafeAreaCompatibility.None
	gui.ClipToDeviceSafeArea = false
	gui.DisplayOrder = displayOrder
	gui.Parent = parent
	return gui
end

-- Marges (pixels écran) d'une ScreenGui-sonde par rapport à l'écran entier
local function probeInsets(probe: ScreenGui, full: Vector2): (number, number, number, number)
	local position = probe.AbsolutePosition
	local size = probe.AbsoluteSize
	if size.X < 1 or size.Y < 1 then
		return 0, 0, 0, 0
	end
	local left = math.max(0, position.X)
	local top = math.max(0, position.Y)
	return left, top, math.max(0, full.X - left - size.X), math.max(0, full.Y - top - size.Y)
end

-- Zone libre de la barre Roblox (pixels écran) : minX, maxX, bas ; nil si inconnue
local function topbarFree(): (number?, number?, number?)
	local ok, rect = pcall(function()
		return GuiService.TopbarInset
	end)
	if not ok or typeof(rect) ~= "Rect" and type(rect) ~= "table" then
		return nil, nil, nil
	end
	local r = rect :: any
	local height = r.Height
	if type(height) ~= "number" or height <= 0 or type(r.Width) ~= "number" or r.Width <= 0 then
		return nil, nil, nil
	end
	return r.Min.X, r.Max.X, r.Max.Y
end

-- Cadres étendus jusqu'aux bords de l'écran (voir Interface.ApplyBleed)
local bleedTargets: { [GuiObject]: boolean } = setmetatable({}, { __mode = "k" }) :: any
local BLEED_NAMES = { Dimmer = true, MailDimmer = true }
-- Calques qui commencent sous Interface.SafeTop
local SHIFTED_LAYERS = { "Panels", "Toasts" }

local function applyBleedTo(object: GuiObject)
	local b = Interface.Bleed
	-- Dans un calque décalé (Panels / Toasts), le parent commence SafeTop plus bas
	local shift = 0
	for _, name in ipairs(SHIFTED_LAYERS) do
		local layer = Interface.Layers[name]
		if layer and object ~= layer and object:IsDescendantOf(layer) then
			shift = Interface.SafeTop
		end
	end
	object.AnchorPoint = Vector2.zero
	object.Position = UDim2.fromOffset(-b.Left, -(b.Top + shift))
	object.Size = UDim2.new(1, b.Left + b.Right, 1, b.Top + b.Bottom + shift)
end

function Interface.Build(): ScreenGui
	local player = Players.LocalPlayer
	local playerGui = player:WaitForChild("PlayerGui") :: PlayerGui
	-- Le jeu se joue en paysage sur mobile
	playerGui.ScreenOrientation = Enum.ScreenOrientation.LandscapeSensor

	for _, name in ipairs({ "DopamineGui", "DopamineBackdrop", "DopamineSafeProbe", "DopamineCoreProbe" }) do
		local old = playerGui:FindFirstChild(name)
		if old then
			old:Destroy()
		end
	end

	-- Fond plein écran (sous l'encoche / la barre Roblox) : simple couleur,
	-- pour ne jamais voir le monde 3D autour de la zone sûre
	-- (ClipToDeviceSafeArea = false : sinon Roblox coupe le fond à l'encoche)
	local backdropGui = makeScreenGui("DopamineBackdrop", Enum.ScreenInsets.None, 0, playerGui)
	local backdrop = UIUtil.Create("Frame", {
		Name = "Backdrop",
		BackgroundColor3 = Color3.new(1, 1, 1),
		BorderSizePixel = 0,
		Active = false,
		Size = UDim2.fromScale(1, 1),
		Parent = backdropGui,
	})
	local backdropGradient = UIUtil.Gradient(backdrop, ColorSequence.new(Theme.Colors.Background, Theme.Colors.BackgroundBottom), 90)
	local lastKey = ""
	local function applyBackdrop()
		local data = ClientState.Data
		local themeId = (data and type(data.Themes) == "table" and data.Themes.Equipped) or "Classic"
		local theme = Config.ThemesById[themeId]
		local dark = ClientState.DarkMode
		-- Mode sombre du joueur : seul le thème Classique passe en fond sombre
		-- (les autres thèmes gardent leur fond ; le néon reste presque noir)
		local userDarkClassic = ClientState.HasDarkSource("User") and themeId == "Classic"
		local neonDark = dark and not userDarkClassic and (ClientState.HasDarkSource("Stimuli") or ClientState.HasDarkSource("Main"))
		local key = tostring(themeId) .. (dark and ":dark" or ":light") .. (userDarkClassic and ":user" or "") .. (neonDark and ":neon" or "")
		if key == lastKey then
			return
		end
		lastKey = key
		if userDarkClassic and not neonDark then
			backdrop.BackgroundColor3 = Color3.new(1, 1, 1)
			backdropGradient.Color = ColorSequence.new(Theme.DarkUI.Background, Theme.DarkUI.BackgroundBottom)
			backdropGradient.Enabled = true
		elseif theme and (theme.Dark or not neonDark) then
			-- Couleurs du thème (sombre ou clair)
			backdrop.BackgroundColor3 = Color3.new(1, 1, 1)
			backdropGradient.Color = ColorSequence.new(theme.Top, theme.Bottom)
			backdropGradient.Enabled = true
		elseif dark then
			-- Mode néon sur un thème clair : fond presque noir
			backdrop.BackgroundColor3 = Theme.DarkColors.Background
			backdropGradient.Enabled = false
		else
			backdrop.BackgroundColor3 = Color3.new(1, 1, 1)
			backdropGradient.Color = ColorSequence.new(Theme.Colors.Background, Theme.Colors.BackgroundBottom)
			backdropGradient.Enabled = true
		end
	end
	ClientState.DarkModeChanged:Connect(applyBackdrop)
	ClientState.DarkSourcesChanged:Connect(applyBackdrop)
	ClientState.Changed:Connect(applyBackdrop)
	applyBackdrop()

	-- L'interface couvre tout l'écran ; la toile (Root) est placée par
	-- updateScale selon les zones sûres mesurées par deux sondes vides
	local screenGui = makeScreenGui("DopamineGui", Enum.ScreenInsets.None, 1, playerGui)
	screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	local safeProbe = makeScreenGui("DopamineSafeProbe", Enum.ScreenInsets.DeviceSafeInsets, -1, playerGui)
	local coreProbe = makeScreenGui("DopamineCoreProbe", Enum.ScreenInsets.CoreUISafeInsets, -1, playerGui)

	-- Toile virtuelle mise à l'échelle
	local root = UIUtil.Create("Frame", {
		Name = "Root",
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(Theme.DesignResolution.X, Theme.DesignResolution.Y),
		ZIndex = 2,
		Parent = screenGui,
	})
	local uiScale = UIUtil.Create("UIScale", { Parent = root })

	for index, name in ipairs(Interface.LayerOrder) do
		Interface.Layers[name] = UIUtil.Create("Frame", {
			Name = name,
			BackgroundTransparency = 1,
			Active = false,
			Size = UDim2.fromScale(1, 1),
			ZIndex = index,
			Parent = root,
		})
	end
	-- Le calque Background déborde jusqu'aux bords de l'écran (fond de bord à
	-- bord) ; Slots.Create y recale les cadres des stimuli sur la toile
	local backgroundLayer = Interface.Layers.Background
	bleedTargets[backgroundLayer] = true
	-- Cinématiques (ex. "Ocean") : leurs cadres plein-calque couvrent tout l'écran
	Interface.Layers.Cinematic.ChildAdded:Connect(function(child)
		if child:IsA("GuiObject") and child.Size == UDim2.fromScale(1, 1) then
			Interface.ApplyBleed(child)
		end
	end)
	-- Voiles sombres des fenêtres / popups ("Dimmer") : tout l'écran aussi
	for _, name in ipairs({ "Overlay", "Panels", "Toasts" }) do
		Interface.Layers[name].DescendantAdded:Connect(function(object)
			if BLEED_NAMES[object.Name] and object:IsA("GuiObject") then
				Interface.ApplyBleed(object)
			end
		end)
	end

	-- Recalcule l'échelle et la place de la toile quand l'écran, les zones
	-- sûres ou la barre Roblox changent
	local function updateScale()
		local full = screenGui.AbsoluteSize
		if full.X < 1 or full.Y < 1 then
			return
		end
		local device = detectDevice()
		local design = Theme.DeviceResolutions[device] or Theme.DesignResolution
		local dl, dt, dr, db = probeInsets(safeProbe, full)
		local cl, ct, cr, cb = probeInsets(coreProbe, full)
		local tbMin, tbMax, tbBottom = topbarFree()

		local left, top, right, bottom = cl, ct, cr, cb
		local tickerLeft, tickerRight = 0, 0
		local scale
		local reclaim = false
		if device == "Phone" then
			left, right, bottom = phoneSide(dl), phoneSide(dr), phoneBottom(db)
			top = dt
			local barBottom = tbBottom or math.max(ct, dt)
			-- Bandeau dans la partie libre de la barre Roblox (s'il y a la place)
			reclaim = tbMin ~= nil and tbMax ~= nil and tbBottom ~= nil and (tbMax :: number) - (tbMin :: number) >= MIN_TOPBAR_ROOM
			if reclaim then
				-- haut de la toile = bas de la barre - overlap - bandeau (x échelle)
				local k = math.min((full.X - left - right) / design.X, (full.Y - bottom - barBottom + TOPBAR_OVERLAP) / (design.Y - TICKER_ROW))
				scale = math.clamp(k, Theme.MinScale, Theme.MaxScale)
				top = math.max(dt, barBottom - TOPBAR_OVERLAP - TICKER_ROW * scale)
			else
				top = math.max(dt, barBottom)
			end
		end
		local available = Vector2.new(full.X - left - right, full.Y - top - bottom)
		if available.X < 1 or available.Y < 1 then
			return
		end
		if not scale then
			scale = math.clamp(math.min(available.X / design.X, available.Y / design.Y), Theme.MinScale, Theme.MaxScale)
		end
		local canvas = Vector2.new(available.X / scale, available.Y / scale)
		if reclaim then
			-- Partie de la rangée du bandeau cachée par les boutons Roblox
			tickerLeft = math.max(0, ((tbMin :: number) + 6 - left) / scale)
			if (tbMax :: number) < full.X - dr - 20 then
				tickerRight = math.max(0, (left + available.X - (tbMax :: number) + 6) / scale)
			end
			if canvas.X - tickerLeft - tickerRight < 420 then
				tickerLeft, tickerRight = 0, 0
			end
		end
		local deviceChanged = device ~= Interface.Device
		Interface.Device = device
		Interface.DesignResolution = design
		Interface.Scale = scale
		Interface.CanvasSize = canvas
		Interface.Bleed = {
			Left = left / scale,
			Top = top / scale,
			Right = right / scale,
			Bottom = bottom / scale,
		}
		Interface.TickerInsets = { Left = tickerLeft, Right = tickerRight }
		local safeTop = reclaim and TICKER_ROW or 0
		Interface.SafeTop = safeTop
		for _, name in ipairs(SHIFTED_LAYERS) do
			local layer = Interface.Layers[name]
			layer.Position = UDim2.fromOffset(0, safeTop)
			layer.Size = UDim2.new(1, 0, 1, -safeTop)
		end
		uiScale.Scale = scale
		-- Root fait (zone utile / échelle) pour la couvrir exactement une fois agrandi
		root.Position = UDim2.fromOffset(left, top)
		root.Size = UDim2.fromOffset(canvas.X, canvas.Y)
		for object in pairs(bleedTargets) do
			if object.Parent then
				applyBleedTo(object)
			end
		end
		if deviceChanged then
			Interface.DeviceChanged:Fire(device)
		end
		Interface.ScaleChanged:Fire(scale, canvas)
	end
	updateScaleFn = updateScale

	screenGui:GetPropertyChangedSignal("AbsoluteSize"):Connect(updateScale)
	for _, probe in ipairs({ safeProbe, coreProbe }) do
		probe:GetPropertyChangedSignal("AbsoluteSize"):Connect(updateScale)
		probe:GetPropertyChangedSignal("AbsolutePosition"):Connect(updateScale)
	end
	pcall(function()
		GuiService:GetPropertyChangedSignal("TopbarInset"):Connect(updateScale)
	end)
	-- Tactile / souris qui apparaissent (tablette + clavier...) : on revérifie le profil
	UserInputService.LastInputTypeChanged:Connect(function()
		if detectDevice() ~= Interface.Device then
			updateScale()
		end
	end)
	Interface.Device = detectDevice()
	updateScale()

	Interface.ScreenGui = screenGui
	Interface.Root = root
	return screenGui
end

-- Étend un cadre "plein écran" (Size 1,1 dans un parent qui couvre la toile,
-- ex. un voile sombre) jusqu'aux bords réels de l'écran, et le tient à jour.
function Interface.ApplyBleed(object: GuiObject)
	bleedTargets[object] = true
	applyBleedTo(object)
end

-- Vrai sur téléphone (interface compacte : une seule ligne de menus, etc.)
function Interface.IsPhone(): boolean
	return Interface.Device == "Phone"
end

-- Vrai sur téléphone ou tablette (écran tactile sans souris)
function Interface.IsTouch(): boolean
	return Interface.Device ~= "Desktop"
end

-- Force un profil ("Phone" | "Tablet" | "Desktop") pour tester dans Studio ; nil = auto
function Interface.SetDeviceOverride(device: string?)
	if device ~= nil and Theme.DeviceResolutions[device] == nil then
		return
	end
	deviceOverride = device
	local update = updateScaleFn
	if update then
		update()
	end
end

-- Convertit une position écran (pixels réels, ex. AbsolutePosition) en
-- position sur la toile (pixels "design").
function Interface.ScreenToCanvas(point: Vector2): Vector2
	local root = Interface.Root
	if not root then
		return point
	end
	return (point - root.AbsolutePosition) / Interface.Scale
end

-- Centre d'un élément, en coordonnées de la toile (pour placer des effets
-- dans un calque plein écran, ex. Effects.Burst(layer, UDim2.fromOffset(...)))
function Interface.GetCanvasCenter(guiObject: GuiObject): Vector2
	return Interface.ScreenToCanvas(guiObject.AbsolutePosition + guiObject.AbsoluteSize / 2)
end

-- Même chose, mais sous forme de UDim2 prête à l'emploi
function Interface.CanvasPosition(guiObject: GuiObject, offset: Vector2?): UDim2
	local center = Interface.GetCanvasCenter(guiObject) + (offset or Vector2.zero)
	return UDim2.fromOffset(center.X, center.Y)
end

return Interface
